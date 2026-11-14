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


static func load_map(dest: Dictionary, resolution: int) -> SandMap:
	var path: String = dest.puzzle_paths.get(str(resolution), "")
	if path.is_empty():
		push_error("StageLoader: %s has no %d puzzle image" % [dest.id, resolution])
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	return SandMap.from_image_with_palette(tex.get_image(), dest.palette_colors)


## Builds a stage. Returns { game: SandGame or null, errors: PackedStringArray }.
## Pass `map` to reuse an already-loaded SandMap (it is copied).
static func build(stage: Dictionary, resolution := 128, map: SandMap = null) -> Dictionary:
	var errors := PackedStringArray()
	var dest: Dictionary = destinations().get(stage.get("destination", ""), {})
	if dest.is_empty():
		errors.append("unknown destination '%s'" % stage.get("destination", ""))
		return {"game": null, "errors": errors}
	var m := map.duplicate_map() if map != null else load_map(dest, resolution)
	if m == null:
		errors.append("puzzle image for %s @%d could not be converted to sand" % [dest.id, resolution])
		return {"game": null, "errors": errors}

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
	game.resolution = resolution
	game.setup(m, board)
	var cfg := config()
	var base: float = float(cfg.get("grains_per_second_at_128", 800.0))
	game.grains_per_second = base * float(m.width * m.height) / 16384.0
	game.max_visits_per_tick = int(cfg.get("max_visits_per_tick", 2000))
	return {"game": game, "errors": errors}


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
