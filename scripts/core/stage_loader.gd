class_name StageLoader
extends RefCounted
## Loads data-driven destinations and stages and builds SandGame instances.
## Image data (paths, palettes) lives in data/destinations.json; puzzle layouts in
## data/stages.json. Swapping in improved art only requires editing the JSON.

const DESTINATIONS_PATH := "res://data/destinations.json"
const STAGES_PATH := "res://data/stages.json"
const CONFIG_PATH := "res://data/game_config.json"

static var _dest_cache := {}
static var _stage_cache := []
static var _config_cache := {}
static var _stage_dest_cache := {}
static var _asset_dir := ""


static func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("StageLoader: cannot read %s" % path)
		return null
	return JSON.parse_string(text)


static func config() -> Dictionary:
	if _config_cache.is_empty():
		var c: Variant = _read_json(CONFIG_PATH)
		_config_cache = c if c is Dictionary else {}
	return _config_cache


## id -> destination dict. Adds "palette_colors" (Array[Color]) and "palette_keys".
static func destinations() -> Dictionary:
	if _dest_cache.is_empty():
		var cfg: Dictionary = _read_json(DESTINATIONS_PATH)
		_asset_dir = cfg.asset_dir
		for d in cfg.destinations:
			var dest: Dictionary = d.duplicate(true)
			dest.album_path = cfg.asset_dir + "/" + d.album
			var paths := {}
			for res in d.puzzle:
				paths[res] = cfg.asset_dir + "/" + d.puzzle[res]
			dest.puzzle_paths = paths
			var colors: Array[Color] = []
			var keys: Array[String] = []
			for p in d.palette:
				keys.append(p.key)
				colors.append(Color.html(p.color))
			dest.palette_colors = colors
			dest.palette_keys = keys
			_dest_cache[d.id] = dest
	return _dest_cache


static func destination_order() -> Array:
	var cfg: Dictionary = _read_json(DESTINATIONS_PATH)
	var out := []
	for d in cfg.destinations:
		out.append(d.id)
	return out


static func stages() -> Array:
	if _stage_cache.is_empty():
		var s: Dictionary = _read_json(STAGES_PATH)
		_stage_cache = s.stages
	return _stage_cache


static func get_stage(stage_id: String) -> Dictionary:
	for s in stages():
		if s.id == stage_id:
			return s
	return {}


## Art + palette used by `stage`: its destination, with the stage's optional own landscape
## laid over it. A stage without "landscape" gets the destination dict itself (unchanged
## behaviour for the existing stages). Optional stage key (paths relative to asset_dir or res://):
##   "landscape": { "puzzle": {"64": "...", "128": "..."}, "album": "...",
##                  "palette": [ {"key", "name_ko", "color"} ... ] }
## Missing parts fall back to the destination's. Returns {} for an unknown destination.
static func stage_destination(stage: Dictionary) -> Dictionary:
	var dest: Dictionary = destinations().get(stage.get("destination", ""), {})
	if dest.is_empty() or not stage.has("landscape"):
		return dest
	var sid := str(stage.get("id", ""))
	if _stage_dest_cache.has(sid):
		return _stage_dest_cache[sid]
	var ls: Dictionary = stage.landscape
	var out := dest.duplicate(true)
	if ls.has("puzzle"):
		var paths := {}
		for res in ls.puzzle:
			paths[res] = _asset_path(str(ls.puzzle[res]))
		out.puzzle_paths = paths
	if ls.has("album"):
		out.album_path = _asset_path(str(ls.album))
	if ls.has("palette"):
		out.palette = ls.palette
		var colors: Array[Color] = []
		var keys: Array[String] = []
		for p in ls.palette:
			keys.append(p.key)
			colors.append(Color.html(p.color))
		out.palette_colors = colors
		out.palette_keys = keys
	_stage_dest_cache[sid] = out
	return out


static func _asset_path(p: String) -> String:
	return p if p.begins_with("res://") else _asset_dir + "/" + p


## Clears cached JSON (tests that swap stage data).
static func clear_cache() -> void:
	_dest_cache = {}
	_stage_cache = []
	_stage_dest_cache = {}


## Strict: loads exactly the `resolution` image (no fallback). Null + error when it is missing.
static func load_map(dest: Dictionary, resolution: int) -> SandMap:
	var path: String = dest.puzzle_paths.get(str(resolution), "")
	if path.is_empty():
		push_error("StageLoader: %s has no %d puzzle image" % [dest.id, resolution])
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("StageLoader: %s %d puzzle image cannot be loaded: %s" % [dest.id, resolution, path])
		return null
	return SandMap.from_image_with_palette(tex.get_image(), dest.palette_colors)


## New landscapes ship a 128 puzzle image only.
const FALLBACK_RESOLUTION := 128


## Resolution whose image `build` loads for a `requested` one: the requested image when the
## stage has it (existing 64/128 stages unchanged), else 128 when only 128 exists. When 128 is
## missing too, `requested` is returned so the missing image is reported, never hidden.
static func puzzle_resolution(dest: Dictionary, requested: int) -> int:
	var paths: Dictionary = dest.get("puzzle_paths", {})
	if paths.has(str(requested)):
		return requested
	if paths.has(str(FALLBACK_RESOLUTION)):
		return FALLBACK_RESOLUTION
	return requested


## Builds a stage. Returns { game: SandGame or null, errors: PackedStringArray }.
## Pass `map` to reuse an already-loaded SandMap (it is copied). Without `map`, a request for a
## resolution the stage has no image for falls back to 128 (see puzzle_resolution);
## game.resolution is then 128 and game.requested_resolution the original request.
static func build(stage: Dictionary, resolution := 128, map: SandMap = null) -> Dictionary:
	var errors := PackedStringArray()
	var dest := stage_destination(stage)
	if dest.is_empty():
		errors.append("unknown destination '%s'" % stage.get("destination", ""))
		return {"game": null, "errors": errors}
	var loaded := resolution if map != null else puzzle_resolution(dest, resolution)
	var m := map.duplicate_map() if map != null else load_map(dest, loaded)
	if m == null:
		errors.append("puzzle image for %s @%d could not be converted to sand%s" % [dest.id, loaded,
			"" if loaded == resolution else " (fallback for @%d)" % resolution])
		return {"game": null, "errors": errors}
	if map == null and (m.width != loaded or m.height != loaded):
		errors.append("puzzle image for %s @%d is %dx%d, expected %dx%d" % [dest.id, loaded, m.width,
			m.height, loaded, loaded])

	var board := PuzzleBoard.new()
	board.cols = int(stage.board.cols)
	board.rows = int(stage.board.rows)
	if m.width % board.cols != 0:
		errors.append("sand width %d is not divisible by %d board columns" % [m.width, board.cols])
	for wpos in stage.get("walls", []):
		board.walls[Vector2i(int(wpos[0]), int(wpos[1]))] = true

	var keys: Array[String] = dest.palette_keys
	for bd in stage.blocks:
		var color := keys.find(str(bd.color))
		if color < 0:
			errors.append("block '%s' uses unknown color '%s'" % [bd.id, bd.color])
			color = 0
		var cells: Array = bd.cells if bd.has("cells") else SandBlock.shape_cells(str(bd.get("shape", "")))
		if cells.is_empty():
			errors.append("block '%s' has unknown shape '%s'" % [bd.id, bd.get("shape", "")])
		var b := SandBlock.create(str(bd.id), color, cells, Vector2i(int(bd.pos[0]), int(bd.pos[1])))
		b.capacity = int(bd.capacity) if bd.has("capacity") and not (bd.capacity is String) else -1
		board.blocks.append(b)
	_assign_capacities(board, m, stage)

	var game := SandGame.new()
	game.stage = stage
	game.destination = dest
	game.resolution = m.width if map == null else resolution
	game.requested_resolution = resolution
	game.setup(m, board, str(stage.get("physics", "channel")), str(stage.get("collect", "drain")))
	var cfg := config()
	var base: float = float(cfg.get("grains_per_second_at_128", 800.0))
	game.grains_per_second = base * float(m.width * m.height) / 16384.0
	game.max_visits_per_tick = int(cfg.get("max_visits_per_tick", 2000))
	if game.is_gravity():
		var gc: Dictionary = cfg.get("gravity", {})
		var area := float(m.width * m.height) / 16384.0
		game.grains_per_second = float(gc.get("collect_per_second_at_128", 600.0)) * area
		# Same on-screen fall speed at any resolution: cells per second scale with width.
		game.fall_steps_per_second = float(gc.get("fall_cells_per_second_at_128", 60.0)) * m.width / 128.0
		game.max_fall_steps_per_frame = int(gc.get("max_fall_steps_per_frame", 4))
		# Diagonal slide rule: stage value wins, else the gravity default (false = original rule).
		game.sim.diagonal_needs_side_gap = bool(stage.get("diagonal_needs_side_gap",
			gc.get("diagonal_needs_side_gap", false)))
		# Wake the whole column above a removed grain: stage value wins, else the gravity default.
		game.sim.column_wake = bool(stage.get("column_wake", gc.get("column_wake", false)))
		if game.is_suction():
			_configure_suction(game, gc.get("suction", {}), m, area)
	return {"game": game, "errors": errors}


## Rule B-2 settings. Distances are given in cells of the 128x128 sand grid and scaled by
## width/128 here (64x64: link 3 -> 2 (rounded, min 1), reach 48 -> 24).
static func _configure_suction(game: SandGame, sc: Dictionary, m: SandMap, area: float) -> void:
	var d: SuctionDrain = game.collector
	var scale := float(m.width) / 128.0
	d.link = maxi(1, roundi(float(sc.get("link_cells_at_128", 3)) * scale))
	d.reach = float(sc.get("reach_cells_at_128", 48)) * scale
	d.finish_at = float(sc.get("finish_at", 0.9))
	d.finish_speed_scale = float(sc.get("finish_speed_scale", 3.0))
	d.scan_visits_per_frame = int(sc.get("scan_visits_per_frame", 15000))
	if sc.has("collect_per_second_at_128"):
		game.grains_per_second = float(sc.collect_per_second_at_128) * area


## Capacity "auto" (or absent): each color's sand count is split across that color's
## blocks in proportion to their weight (default = cell count). Explicit integer
## capacities are kept as-is and checked by the validator.
static func _assign_capacities(board: PuzzleBoard, map: SandMap, stage: Dictionary) -> void:
	var counts := map.count_by_color()
	var by_color := {}
	for i in board.blocks.size():
		var b := board.blocks[i]
		if b.capacity < 0:
			if not by_color.has(b.color_id):
				by_color[b.color_id] = []
			by_color[b.color_id].append(i)
	for color in by_color:
		var idxs: Array = by_color[color]
		var fixed := 0
		for b in board.blocks:
			if b.color_id == color and b.capacity >= 0:
				fixed += b.capacity
		var pool := maxi(0, counts[color] - fixed)
		var weights := []
		var wsum := 0.0
		for i in idxs:
			var bd: Dictionary = stage.blocks[i]
			var wgt := float(bd.get("weight", board.blocks[i].cells.size()))
			weights.append(wgt)
			wsum += wgt
		var given := 0
		for k in idxs.size():
			var cap := int(floor(pool * weights[k] / wsum))
			board.blocks[idxs[k]].capacity = cap
			given += cap
		board.blocks[idxs[0]].capacity += pool - given
