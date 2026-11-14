class_name SandGame
extends RefCounted
## One running stage: sand data + board + collection rules. No nodes, no rendering,
## so the same object drives the game screen, tests, the solver and benchmarks.

signal grains_collected(block: SandBlock, indices: PackedInt32Array)
signal block_filled(block: SandBlock)
signal stage_cleared

var stage := {}
var destination := {}
var resolution := 128
var map: SandMap
var board: PuzzleBoard
var collector: SandCollector
var grains_per_second := 800.0
var max_visits_per_tick := 2000
var total := 0
var remaining := 0
var cleared := false

var _held := {}   # block id -> true while dragged/animating (does not collect)
var _carry := {}  # block id -> fractional grain budget


func setup(p_map: SandMap, p_board: PuzzleBoard) -> void:
	map = p_map
	board = p_board
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


## Advances collection by `dt` seconds for every resting block in contact.
func tick(dt: float) -> void:
	if cleared:
		return
	for b in board.blocks:
		if b.removed or _held.has(b.id):
			continue
		if b.contact_columns().is_empty():
			_carry.erase(b.id)
			continue
		var want: float = grains_per_second * dt + float(_carry.get(b.id, 0.0))
		var n := int(want)
		var got := collector.step(b, n, max_visits_per_tick) if n > 0 else PackedInt32Array()
		_carry[b.id] = (want - n) if got.size() == n else 0.0
		if got.size() > 0:
			remaining -= got.size()
			grains_collected.emit(b, got)
		if b.is_full():
			board.remove_block(b)
			collector.reset_session(b)
			_carry.erase(b.id)
			block_filled.emit(b)
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
		for b in board.blocks:
			if b.removed or _held.has(b.id) or b.contact_columns().is_empty():
				continue
			var got := collector.step(b, 1 << 30)
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
