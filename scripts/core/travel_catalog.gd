class_name TravelCatalog
extends RefCounted
## The confirmed 100-destination list (data/travel_catalog.json) joined with what is actually
## built in the project. Pure logic: no nodes, so screens and tests share it.
##
## Three independent states per destination / stage:
##  - built:   the stage exists in data/stages.json and its art (puzzle image for every
##             resolution it declares + album image) exists. Catalog entries alone are never playable.
##  - access:  free, or premium + the "travel_pass" entitlement. Entitlements come from the store
##             later (App.entitlements); they are not part of the save file.
##  - unlock:  inside a destination, stage n opens when stage n-1 is cleared (stage 1 is always
##             open). A stage cleared earlier stays open, so old progress never gets locked.
## Stage ids are "<destination>_<nn>" (hawaii_01 ...), the same ids the save file uses.

const PATH := "res://data/travel_catalog.json"

static var _data := {}
static var _by_id := {}
static var _built := {}  # stage id -> bool


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"continents": [], "destinations": [], "free_order": []}
		for d in _data.destinations:
			_by_id[d.id] = d
	return _data


static func reload() -> void:
	_data = {}
	_by_id = {}
	_built = {}


static func stages_per_destination() -> int:
	return int(data().get("stages_per_destination", 3))


static func continents() -> Array:
	return data().continents


static func continent(cid: String) -> Dictionary:
	for c in continents():
		if c.id == cid:
			return c
	return {}


static func destinations() -> Array:
	return data().destinations


static func destination(dest_id: String) -> Dictionary:
	data()
	return _by_id.get(dest_id, {})


static func in_continent(cid: String) -> Array:
	return destinations().filter(func(d): return d.continent == cid)


static func free_order() -> Array:
	return data().get("free_order", [])


static func is_premium(dest_id: String) -> bool:
	return str(destination(dest_id).get("access", "premium")) != "free"


static func has_access(dest_id: String, entitlements: Dictionary) -> bool:
	return not is_premium(dest_id) or bool(entitlements.get("travel_pass", false))


static func stage_id(dest_id: String, n: int) -> String:
	return "%s_%02d" % [dest_id, n]


## Destination id and 1-based slot of a stage id, or {} when the id has no "_<nn>" suffix.
static func split_stage_id(sid: String) -> Dictionary:
	var at := sid.rfind("_")
	if at <= 0 or not sid.substr(at + 1).is_valid_int():
		return {}
	return {"destination": sid.substr(0, at), "n": int(sid.substr(at + 1))}


static func is_stage_built(sid: String) -> bool:
	if _built.has(sid):
		return _built[sid]
	var ok := false
	var stage := StageLoader.get_stage(sid)
	if not stage.is_empty():
		var art := StageLoader.stage_destination(stage)
		ok = not art.is_empty() and not art.puzzle_paths.is_empty() and ResourceLoader.exists(art.album_path)
		for res in art.get("puzzle_paths", {}):
			ok = ok and ResourceLoader.exists(art.puzzle_paths[res])
	_built[sid] = ok
	return ok


static func built_stage_count(dest_id: String) -> int:
	var n := 0
	for i in range(1, stages_per_destination() + 1):
		if is_stage_built(stage_id(dest_id, i)):
			n += 1
	return n


## Playable at all (its first stage is built). Access is checked separately.
static func is_built(dest_id: String) -> bool:
	return is_stage_built(stage_id(dest_id, 1))


static func cleared_count(save: SaveStore, dest_id: String) -> int:
	var n := 0
	for i in range(1, stages_per_destination() + 1):
		if save.is_cleared(stage_id(dest_id, i)):
			n += 1
	return n


## Visit stamp: every stage of the destination cleared.
static func is_visited(save: SaveStore, dest_id: String) -> bool:
	return cleared_count(save, dest_id) >= stages_per_destination()


## "cleared" | "open" | "locked" (previous stage not cleared) | "unbuilt" | "pass" (no access).
static func stage_state(save: SaveStore, dest_id: String, n: int, entitlements: Dictionary) -> String:
	var sid := stage_id(dest_id, n)
	if not is_stage_built(sid):
		return "unbuilt"
	if not has_access(dest_id, entitlements):
		return "pass"
	if save.is_cleared(sid):
		return "cleared"
	if n == 1 or save.is_cleared(stage_id(dest_id, n - 1)):
		return "open"
	return "locked"


static func can_play(save: SaveStore, sid: String, entitlements: Dictionary) -> bool:
	var p := split_stage_id(sid)
	if p.is_empty():
		return false
	return stage_state(save, p.destination, p.n, entitlements) in ["open", "cleared"]


## First stage of `dest_id` the player should play next ("" when none is open).
static func next_open_stage(save: SaveStore, dest_id: String, entitlements: Dictionary) -> String:
	for i in range(1, stages_per_destination() + 1):
		if stage_state(save, dest_id, i, entitlements) == "open":
			return stage_id(dest_id, i)
	return ""


## The destination the player is travelling in: the last played stage's destination, if valid.
static func current_destination(save: SaveStore) -> String:
	var p := split_stage_id(save.last_played())
	if p.is_empty() or destination(p.destination).is_empty() or not is_stage_built(save.last_played()):
		return ""
	return p.destination


## Stage for "continue": next open stage of the current destination, else of the first
## destination in the free order (then any accessible built destination). "" = nothing left.
static func continue_stage(save: SaveStore, entitlements: Dictionary) -> String:
	var order: Array = []
	var cur := current_destination(save)
	if cur != "":
		order.append(cur)
	order.append_array(free_order())
	for d in destinations():
		order.append(d.id)
	for dest_id in order:
		if is_built(dest_id) and has_access(dest_id, entitlements):
			var sid := next_open_stage(save, dest_id, entitlements)
			if sid != "":
				return sid
	return ""


static func continent_progress(save: SaveStore, cid: String) -> Dictionary:
	var list := in_continent(cid)
	var out := {"total": list.size(), "free": 0, "built": 0, "stamps": 0, "postcards": 0}
	for d in list:
		if d.access == "free":
			out.free += 1
		if is_built(d.id):
			out.built += 1
		var c := cleared_count(save, d.id)
		out.postcards += c
		if c >= stages_per_destination():
			out.stamps += 1
	return out


static func total_stamps(save: SaveStore) -> int:
	var n := 0
	for d in destinations():
		if is_visited(save, d.id):
			n += 1
	return n


static func total_postcards(save: SaveStore) -> int:
	var n := 0
	for d in destinations():
		n += cleared_count(save, d.id)
	return n


## Destinations in the order of their first clear (the travel route drawn on the map).
static func visit_route(save: SaveStore) -> Array:
	var ids: Array = save.data.album.keys().filter(func(i): return not destination(i).is_empty())
	ids.sort_custom(func(a, b): return int(save.data.album[a].get("at", 0)) < int(save.data.album[b].get("at", 0)))
	return ids


## Album image of a stage's postcard (stage landscape, else the destination's). "" when none.
static func postcard_path(dest_id: String, n: int) -> String:
	var stage := StageLoader.get_stage(stage_id(dest_id, n))
	if not stage.is_empty():
		var p := str(StageLoader.stage_destination(stage).get("album_path", ""))
		if ResourceLoader.exists(p):
			return p
	var d: Dictionary = StageLoader.destinations().get(dest_id, {})
	var p2 := str(d.get("album_path", ""))
	return p2 if ResourceLoader.exists(p2) else ""


## Cover picture of a destination (stage 1 postcard, else any of its postcards).
static func cover_path(dest_id: String) -> String:
	for i in range(1, stages_per_destination() + 1):
		var p := postcard_path(dest_id, i)
		if p != "":
			return p
	return ""


## Short stage title: "하와이 1 · 첫 해변" -> "첫 해변".
static func stage_title(sid: String) -> String:
	var name := str(StageLoader.get_stage(sid).get("name_ko", ""))
	var at := name.rfind("·")
	return name.substr(at + 1).strip_edges() if at >= 0 else name
