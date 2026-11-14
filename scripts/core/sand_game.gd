class_name SandGame
extends RefCounted
## One running stage: sand data + board + collection rules. No nodes, no rendering,
## so the same object drives the game screen, tests, the solver and benchmarks.
##
## physics "channel" (default): fixed landscape, SandCollector (open-channel rule).
## physics "gravity": SandSim falling sand + GravityDrain (contact-started cluster pull).

signal grains_collected(block: SandBlock, indices: PackedInt32Array)
signal block_filled(block: SandBlock)
signal stage_cleared

var stage := {}
var destination := {}
var resolution := 128
var map: SandMap
var board: PuzzleBoard
## SandCollector (channel) or GravityDrain (gravity); both expose step/is_collecting/
## reset_session/reset_all/contact_masks.
var collector: RefCounted
var physics := "channel"
var sim: SandSim
var grains_per_second := 800.0
var fall_steps_per_second := 60.0
var max_fall_steps_per_frame := 4
## Increments whenever any cell changes (collection or falling); renderers watch it.
var sand_version := 0
var collected_last_tick := 0
var max_visits_per_tick := 2000
var total := 0
var remaining := 0
var cleared := false

var _held := {}   # block id -> true while dragged/animating (does not collect)
var _carry := {}  # block id -> fractional grain budget
var _fall_carry := 0.0


func setup(p_map: SandMap, p_board: PuzzleBoard, p_physics := "channel") -> void:
	map = p_map
	board = p_board
	physics = p_physics
	if physics == "gravity":
		sim = SandSim.new(map)
		collector = GravityDrain.new(map, board, sim)
	else:
		collector = SandCollector.new(map, board)
	total = map.remaining()
	remaining = total
	cleared = remaining == 0


func set_held(block: SandBlock, held: bool) -> void:
	if held:
		_held[block.id] = true
		collector.reset_session(block)
	else:
		_held.erase(block.id)


func is_held(block: SandBlock) -> bool:
	return _held.has(block.id)


func try_move(block: SandBlock, dir: Vector2i, steps: int) -> bool:
	var ok := board.move(block, dir, steps)
	if ok:
		collector.reset_session(block)
	return ok


func sand_progress() -> float:
	return 0.0 if total == 0 else 1.0 - float(remaining) / total


func is_cleared() -> bool:
	return remaining == 0


func is_gravity() -> bool:
	return physics == "gravity"


## Per board column: bitmask of colors a block there could start collecting right now.
func contact_masks() -> PackedInt32Array:
	return collector.contact_masks()


## Nothing is being collected and (gravity) no grain is falling.
func is_idle() -> bool:
	return collected_last_tick == 0 and (sim == null or not sim.is_active())


## Advances collection by `dt` seconds for every resting block in contact.
func tick(dt: float) -> void:
	if cleared:
		return
	collected_last_tick = 0
	for b in board.blocks:
		if b.removed or _held.has(b.id):
			continue
		if b.contact_columns().is_empty():
			_carry.erase(b.id)
			continue
		var want: float = grains_per_second * dt + float(_carry.get(b.id, 0.0))
		var n := int(want)
		var got: PackedInt32Array = collector.step(b, n, max_visits_per_tick) if n > 0 else PackedInt32Array()
		_carry[b.id] = (want - n) if got.size() == n else 0.0
		if got.size() > 0:
			remaining -= got.size()
			collected_last_tick += got.size()
			sand_version += 1
			grains_collected.emit(b, got)
		if b.is_full():
			board.remove_block(b)
			collector.reset_session(b)
			_carry.erase(b.id)
			block_filled.emit(b)
	if sim != null:
		_fall_carry += fall_steps_per_second * dt
		var n_steps := mini(int(_fall_carry), max_fall_steps_per_frame)
		_fall_carry = minf(_fall_carry - n_steps, 1.0)
		for k in n_steps:
			if sim.step() > 0:
				sand_version += 1
	if remaining == 0:
		cleared = true
		stage_cleared.emit()


## Collects everything currently reachable for every resting block (no animation pacing).
## Used by tests/solver; returns number of grains collected.
func collect_all_now() -> int:
	var before := remaining
	var progressed := true
	while progressed and remaining > 0:
		progressed = false
		if sim != null and sim.is_active():
			sim.settle()
			sand_version += 1
		for b in board.blocks:
			if b.removed or _held.has(b.id) or b.contact_columns().is_empty():
				continue
			var got: PackedInt32Array = collector.step(b, 1 << 30)
			if got.size() > 0:
				progressed = true
				remaining -= got.size()
				grains_collected.emit(b, got)
			if b.is_full():
				board.remove_block(b)
				collector.reset_session(b)
				block_filled.emit(b)
	if remaining == 0 and not cleared:
		cleared = true
		stage_cleared.emit()
	return before - remaining
