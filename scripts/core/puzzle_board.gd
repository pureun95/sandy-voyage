class_name PuzzleBoard
extends RefCounted
## Grid board under the sand landscape. Board row 0 is directly adjacent to the
## landscape's bottom pixel row. Movement is grid based, cardinal only, no rotation.

const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var cols := 8
var rows := 5
var walls := {}  # Vector2i -> true (fixed obstacle cells)
var blocks: Array[SandBlock] = []


func is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


static func is_cardinal(dir: Vector2i) -> bool:
	return absi(dir.x) + absi(dir.y) == 1


func get_block(block_id: String) -> SandBlock:
	for b in blocks:
		if b.id == block_id:
			return b
	return null


func active_blocks() -> Array[SandBlock]:
	var out: Array[SandBlock] = []
	for b in blocks:
		if not b.removed:
			out.append(b)
	return out


func block_at(cell: Vector2i) -> SandBlock:
	for b in blocks:
		if b.removed:
			continue
		for c in b.cells:
			if b.pos + c == cell:
				return b
	return null


func can_place(block: SandBlock, at: Vector2i) -> bool:
	for c in block.cells:
		var p := at + c
		if not is_inside(p) or walls.has(p):
			return false
		var other := block_at(p)
		if other != null and other != block:
			return false
	return true


## How many whole cells `block` can slide in `dir` before hitting a wall, edge or block.
func max_steps(block: SandBlock, dir: Vector2i) -> int:
	if block.removed or not is_cardinal(dir):
		return 0
	var n := 0
	while can_place(block, block.pos + dir * (n + 1)):
		n += 1
	return n


## Slides `block` `steps` cells along a cardinal `dir`. Rejects diagonal moves and
## any move that would pass through an obstacle. Returns true when the block moved.
func move(block: SandBlock, dir: Vector2i, steps := 1) -> bool:
	if block == null or block.removed or steps <= 0 or not is_cardinal(dir):
		return false
	if steps > max_steps(block, dir):
		return false
	block.pos += dir * steps
	return true


func remove_block(block: SandBlock) -> void:
	block.removed = true


## Static layout errors: out-of-bounds blocks, overlaps, duplicate ids.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var ids := {}
	for w in walls:
		if not is_inside(w):
			errors.append("wall %s is outside the board" % w)
	for b in blocks:
		if ids.has(b.id):
			errors.append("duplicate block id '%s'" % b.id)
		ids[b.id] = true
		if b.cells.is_empty():
			errors.append("block '%s' has no cells" % b.id)
		for p in b.occupied():
			if not is_inside(p):
				errors.append("block '%s' cell %s is outside the %dx%d board" % [b.id, p, cols, rows])
			elif walls.has(p):
				errors.append("block '%s' overlaps wall at %s" % [b.id, p])
			elif seen.has(p):
				errors.append("block '%s' overlaps block '%s' at %s" % [b.id, seen[p], p])
			seen[p] = b.id
	return errors
