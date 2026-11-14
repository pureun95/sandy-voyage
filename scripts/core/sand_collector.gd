class_name SandCollector
extends RefCounted
## Contact-based sand collection. Pure logic over SandMap + PuzzleBoard.
##
## Geometry: the board sits directly below the landscape. Board column c covers sand
## pixel columns [c*px_per_col, (c+1)*px_per_col). A block cell on board row 0 touches,
## with its top face, the sand pixels of the landscape's bottom row above it.
## Diagonal adjacency never counts.
##
## Spread: collection starts at the touched pixels and expands breadth-first (nearest
## first) through same-colored sand and through EMPTY cells (sand already collected,
## i.e. open channels connected to the board). Sand of any other color stops the
## spread, so regions that are not reachable through the contact face are never taken.

const EMPTY := SandMap.EMPTY
## Sessions that ran dry while other blocks were changing the sand re-scan at most
## once every this many calls (bounds per-frame cost on mobile).
const RESCAN_INTERVAL := 12

var map: SandMap
var board: PuzzleBoard
var px_per_col := 16
## Total grains removed by any block; used to detect sand changes made by others.
var changes := 0

var _sessions := {}  # block id -> _Session
var _reach_cache := PackedInt32Array()
var _reach_changes := -1


class _Session:
	var key := Vector2i(-999, -999)
	var queue := PackedInt32Array()
	var visited := PackedByteArray()
	var head := 0
	var changes_seen := 0
	var foreign_change := false
	var idle_calls := 0
	var last_collected := 0


func _init(p_map: SandMap, p_board: PuzzleBoard) -> void:
	map = p_map
	board = p_board
	@warning_ignore("integer_division")
	px_per_col = map.width / board.cols


## Sand pixel indices touched by the top face of `block` at `at` (bottom landscape row).
func contact_seeds(block: SandBlock, at: Vector2i = block.pos) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := (map.height - 1) * map.width
	for col in block.contact_columns(at):
		for x in range(col * px_per_col, (col + 1) * px_per_col):
			out.append(row + x)
	return out


func reset_session(block: SandBlock) -> void:
	_sessions.erase(block.id)


func reset_all() -> void:
	_sessions.clear()


## True when `block` collected grains in its most recent step.
func is_collecting(block: SandBlock) -> bool:
	var s: _Session = _sessions.get(block.id)
	return s != null and s.last_collected > 0


## Collects up to `budget` grains of the block's color reachable from its contact face.
## Returns the collected pixel indices in collection order (nearest first).
## `max_visits` bounds the BFS work done in this call.
func step(block: SandBlock, budget: int, max_visits := 1 << 30) -> PackedInt32Array:
	var out := PackedInt32Array()
	if block.removed or block.is_full() or budget <= 0:
		return out
	var s: _Session = _sessions.get(block.id)
	if s != null and s.changes_seen != changes:
		# Another block removed sand since this session last ran. Cells this session
		# already skipped as "other color" may now be open channel.
		s.foreign_change = true
	if s == null or s.key != block.pos:
		var seeds := contact_seeds(block)
		if seeds.is_empty():
			_sessions.erase(block.id)
			return out
		s = _new_session(block, seeds)
	elif s.head >= s.queue.size() and s.foreign_change:
		# Ran dry, but the sand changed under it; re-scan (throttled for frame cost).
		s.idle_calls += 1
		if s.idle_calls >= RESCAN_INTERVAL or max_visits >= (1 << 30):
			s = _new_session(block, contact_seeds(block))
	if s.head >= s.queue.size():
		s.last_collected = 0
		return out

	# Take sole ownership of the packed arrays so writes don't trigger copy-on-write.
	var cells := map.cells
	map.cells = PackedByteArray()
	var queue := s.queue
	s.queue = PackedInt32Array()
	var visited := s.visited
	s.visited = PackedByteArray()

	var w := map.width
	var size := w * map.height
	var color := block.color_id
	var limit := mini(budget, block.room())
	var head := s.head
	var visits := 0
	while out.size() < limit and head < queue.size() and visits < max_visits:
		var i := queue[head]
		head += 1
		visits += 1
		var v := cells[i]
		if v == color:
			cells[i] = EMPTY
			out.append(i)
		elif v != EMPTY:
			continue
		var x := i % w
		if x > 0 and visited[i - 1] == 0:
			visited[i - 1] = 1
			queue.append(i - 1)
		if x < w - 1 and visited[i + 1] == 0:
			visited[i + 1] = 1
			queue.append(i + 1)
		if i >= w and visited[i - w] == 0:
			visited[i - w] = 1
			queue.append(i - w)
		if i + w < size and visited[i + w] == 0:
			visited[i + w] = 1
			queue.append(i + w)

	map.cells = cells
	s.queue = queue
	s.visited = visited
	s.head = head
	block.collected += out.size()
	changes += out.size()
	s.changes_seen = changes
	s.last_collected = out.size()
	return out


func _new_session(block: SandBlock, seeds: PackedInt32Array) -> _Session:
	var s := _Session.new()
	s.key = block.pos
	s.visited.resize(map.width * map.height)
	for i in seeds:
		s.visited[i] = 1
		s.queue.append(i)
	s.changes_seen = changes
	_sessions[block.id] = s
	return s


## For each board column, a bitmask of sand colors reachable from that column's
## contact face right now (directly touching, or through open channels).
## Cached until sand changes (`changes`), so repeated calls (drag hints, solver) are free.
func column_reach() -> PackedInt32Array:
	if _reach_changes == changes and _reach_cache.size() == board.cols:
		return _reach_cache
	var w := map.width
	var size := w * map.height
	var cells := map.cells
	var label := PackedInt32Array()
	label.resize(size)
	label.fill(-1)
	var comp_mask := PackedInt32Array()
	var queue := PackedInt32Array()
	queue.resize(size)
	var masks := PackedInt32Array()
	masks.resize(board.cols)
	var row := size - w
	for x in w:
		var i := row + x
		var v := cells[i]
		var m := 0
		if v != EMPTY:
			m = 1 << v
		else:
			if label[i] < 0:
				# Flood one open-channel component; collect colors on its border.
				var comp := comp_mask.size()
				var cm := 0
				label[i] = comp
				queue[0] = i
				var head := 0
				var tail := 1
				while head < tail:
					var j := queue[head]
					head += 1
					var jx := j % w
					var n := j - 1
					if jx > 0:
						if cells[n] != EMPTY: cm |= 1 << cells[n]
						elif label[n] < 0: label[n] = comp; queue[tail] = n; tail += 1
					n = j + 1
					if jx < w - 1:
						if cells[n] != EMPTY: cm |= 1 << cells[n]
						elif label[n] < 0: label[n] = comp; queue[tail] = n; tail += 1
					n = j - w
					if n >= 0:
						if cells[n] != EMPTY: cm |= 1 << cells[n]
						elif label[n] < 0: label[n] = comp; queue[tail] = n; tail += 1
					n = j + w
					if n < size:
						if cells[n] != EMPTY: cm |= 1 << cells[n]
						elif label[n] < 0: label[n] = comp; queue[tail] = n; tail += 1
				comp_mask.append(cm)
			m = comp_mask[label[i]]
		@warning_ignore("integer_division")
		masks[x / px_per_col] |= m
	_reach_cache = masks
	_reach_changes = changes
	return masks


## Colors (bitmask) `block` could collect if it stood at `at`, given `masks` from column_reach().
static func reach_at(block: SandBlock, at: Vector2i, masks: PackedInt32Array) -> int:
	var m := 0
	for col in block.contact_columns(at):
		m |= masks[col]
	return m
