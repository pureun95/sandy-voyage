class_name GravityDrain
extends RefCounted
## Collection for the gravity rule ("hybrid", approved 2026-11-14).
##
## Intake: a block cell on board row 0 exposes its top face to the landscape's bottom row;
## those sand pixels are the block's intake. Collection only starts when an intake pixel
## holds a grain of the block's color (direct contact). From there, grains 4-connected to
## the intake through the same color are pulled in. Other colors are never crossed, never
## collected, and diagonal links do not count.
##
## Order: farthest first along the connected path. Moving every grain of a same-color path
## one cell toward the intake and absorbing the one at the intake is, cell for cell, the
## same as emptying the farthest cell; so the data change is exact (one emptied cell per
## collected grain) and the remaining cluster always stays connected to the intake.
## `last_paths` holds, per collected grain, the cell path to the intake for the animation.
## Emptied cells wake the gravity simulation, so the picture collapses into them.

const EMPTY := SandMap.EMPTY

var map: SandMap
var board: PuzzleBoard
var sim: SandSim
var px_per_col := 16
var changes := 0
## For the last step() call: one PackedInt32Array per collected grain, from the emptied
## cell to the intake pixel (inclusive), in collection order.
var last_paths: Array[PackedInt32Array] = []

var _collected_last := {}  # block id -> grains collected in its last step
var _parent := PackedInt32Array()
var _seen := PackedByteArray()


func _init(p_map: SandMap, p_board: PuzzleBoard, p_sim: SandSim) -> void:
	map = p_map
	board = p_board
	sim = p_sim
	@warning_ignore("integer_division")
	px_per_col = map.width / board.cols
	_parent.resize(map.width * map.height)
	_seen.resize(map.width * map.height)


## Intake pixels (landscape bottom row) above the block's row-0 cells.
func intake_pixels(block: SandBlock, at: Vector2i = block.pos) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := (map.height - 1) * map.width
	for col in block.contact_columns(at):
		for x in range(col * px_per_col, (col + 1) * px_per_col):
			out.append(row + x)
	return out


func reset_session(block: SandBlock) -> void:
	_collected_last.erase(block.id)


func reset_all() -> void:
	_collected_last.clear()


func is_collecting(block: SandBlock) -> bool:
	return int(_collected_last.get(block.id, 0)) > 0


## Per board column, a bitmask of colors currently touching that column's intake face.
func contact_masks() -> PackedInt32Array:
	var masks := PackedInt32Array()
	masks.resize(board.cols)
	var row := (map.height - 1) * map.width
	for x in map.width:
		var v := map.cells[row + x]
		if v != EMPTY:
			@warning_ignore("integer_division")
			masks[x / px_per_col] |= 1 << v
	return masks


## Collects up to `budget` grains for `block`. Returns the emptied cell indices.
func step(block: SandBlock, budget: int, _max_visits := 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	last_paths.clear()
	_collected_last[block.id] = 0
	if block.removed or block.is_full() or budget <= 0:
		return out
	var color := block.color_id
	var w := map.width
	var size := w * map.height
	var cells := map.cells
	var order := PackedInt32Array()
	var parent := _parent
	_parent = PackedInt32Array()
	var seen := _seen
	_seen = PackedByteArray()
	for i in intake_pixels(block):
		if cells[i] == color:  # direct contact only
			parent[i] = -1
			seen[i] = 1
			order.append(i)
	if order.is_empty():
		_parent = parent
		_seen = seen
		return out
	var head := 0
	while head < order.size():
		var j := order[head]
		head += 1
		var jx := j % w
		var n := j - 1
		if jx > 0 and cells[n] == color and seen[n] == 0:
			seen[n] = 1; parent[n] = j; order.append(n)
		n = j + 1
		if jx < w - 1 and cells[n] == color and seen[n] == 0:
			seen[n] = 1; parent[n] = j; order.append(n)
		n = j - w
		if n >= 0 and cells[n] == color and seen[n] == 0:
			seen[n] = 1; parent[n] = j; order.append(n)
		n = j + w
		if n < size and cells[n] == color and seen[n] == 0:
			seen[n] = 1; parent[n] = j; order.append(n)
	for i in order:
		seen[i] = 0  # reset only what this call touched
	_seen = seen
	var take := mini(mini(budget, block.room()), order.size())
	for k in take:
		var i := order[order.size() - 1 - k]  # farthest first (BFS order is by distance)
		var path := PackedInt32Array()
		var p := i
		while p != -1:
			path.append(p)
			p = parent[p]
		last_paths.append(path)
		out.append(i)
	_parent = parent
	map.cells = PackedByteArray()  # sole ownership for writes
	for i in out:
		cells[i] = EMPTY
		sim.wake(i)
	map.cells = cells
	block.collected += out.size()
	changes += out.size()
	_collected_last[block.id] = out.size()
	return out
