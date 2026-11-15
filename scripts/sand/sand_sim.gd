class_name SandSim
extends RefCounted
## Falling-sand cellular automaton over SandMap.cells (game approximation, not physics):
## each step a grain moves at most one cell: straight down if empty, otherwise diagonally
## down-left/down-right if empty. The landscape's bottom row rests on the board top, which
## is solid floor (grains are only removed there by a drain, never fall into the board).
## No momentum, friction or pressure; repose angle is 45 degrees.
##
## `diagonal_needs_side_gap` (stage/config "diagonal_needs_side_gap"): a diagonal move also
## needs the side cell at the grain's own height to be empty. Grains still slide down open
## slopes, but no longer squeeze through a diagonal gap inside the pile. That squeezing (a
## hole opened by a neighbor column falling in the same pass, taken diagonally) is what made
## neighbor columns zip together and the picture dissolve into speckles.
##
## Only "active" 8x8 chunks are scanned. A chunk wakes when a grain in or next to it moves
## or a cell in it is emptied. A fully packed picture has no empty cells, so nothing moves
## until collection makes a hole: the start is stable by construction.

const EMPTY := SandMap.EMPTY
const CHUNK := 8

var map: SandMap
## false: original rule (diagonal cell empty). true: the side cell must be empty too.
var diagonal_needs_side_gap := false
## Stage/config "column_wake": a removed grain wakes the whole column above it (see wake()).
var column_wake := false
var steps := 0
var last_moves := 0
var _cw := 0
var _ch := 0
var _active := PackedByteArray()


func _init(p_map: SandMap) -> void:
	map = p_map
	_cw = ceili(float(map.width) / CHUNK)
	_ch = ceili(float(map.height) / CHUNK)
	_active.resize(_cw * _ch)


func is_active() -> bool:
	return _active.has(1)


func active_chunks() -> int:
	return _active.count(1)


## Mark the chunk holding `index` (and the chunks that could fall into it) for simulation.
## With `column_wake`, every chunk above it in its chunk column and the two neighbor chunk
## columns is marked too, so the whole column above a removed grain drops in one pass.
## Without it the column above wakes one chunk per step, and the hole climbs as a visible
## gap line (8 cells per frame) before it closes.
func wake(index: int) -> void:
	var x := index % map.width
	@warning_ignore("integer_division")
	var cx := x / CHUNK
	@warning_ignore("integer_division")
	var cy := index / map.width / CHUNK
	if not column_wake:
		_mark(_active, cx, cy)
		return
	for y in range(cy, -1, -1):
		for dx in [-1, 0, 1]:
			var xx: int = cx + dx
			if xx >= 0 and xx < _cw:
				_active[y * _cw + xx] = 1


func _mark(a: PackedByteArray, cx: int, cy: int) -> void:
	for dy in [-1, 0]:
		var y: int = cy + dy
		if y < 0:
			continue
		for dx in [-1, 0, 1]:
			var x: int = cx + dx
			if x >= 0 and x < _cw:
				a[y * _cw + x] = 1


## One simulation step. Returns the number of grains that moved.
func step() -> int:
	steps += 1
	if not is_active():
		last_moves = 0
		return 0
	var w := map.width
	var h := map.height
	var cells := map.cells
	map.cells = PackedByteArray()
	var next := PackedByteArray()
	next.resize(_cw * _ch)
	var moves := 0
	var flip := steps & 1
	for y in range(h - 2, -1, -1):
		@warning_ignore("integer_division")
		var cy := y / CHUNK
		for cxi in _cw:
			var cx := cxi if flip == 0 else _cw - 1 - cxi
			if _active[cy * _cw + cx] == 0:
				continue
			var x0 := cx * CHUNK
			var x1 := mini(x0 + CHUNK, w)
			for k in x1 - x0:
				var x := x0 + k if flip == 0 else x1 - 1 - k
				var i := y * w + x
				var v := cells[i]
				if v == EMPTY:
					continue
				var b := i + w
				var t := -1
				if cells[b] == EMPTY:
					t = b
				else:
					# Alternate which diagonal is tried first so piles stay symmetric.
					var left_first := ((x + y + steps) & 1) == 0
					var l := b - 1 if x > 0 else -1
					var r := b + 1 if x < w - 1 else -1
					var a := l if left_first else r
					var c := r if left_first else l
					var gap := diagonal_needs_side_gap
					# (a - b) is -1 or +1: the side cell next to the grain toward that diagonal.
					if a >= 0 and cells[a] == EMPTY and (not gap or cells[i + a - b] == EMPTY):
						t = a
					elif c >= 0 and cells[c] == EMPTY and (not gap or cells[i + c - b] == EMPTY):
						t = c
				if t < 0:
					continue
				cells[t] = v
				cells[i] = EMPTY
				moves += 1
				var tx := t % w
				@warning_ignore("integer_division")
				_mark(next, tx / CHUNK, (y + 1) / CHUNK)
				_mark(next, cx, cy)
	map.cells = cells
	_active = next
	last_moves = moves
	return moves


## Runs until nothing moves (or `max_steps`). Returns steps taken.
func settle(max_steps := 2000) -> int:
	var n := 0
	while is_active() and n < max_steps:
		step()
		n += 1
	return n
