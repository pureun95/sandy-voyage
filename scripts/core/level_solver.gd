class_name LevelSolver
extends RefCounted
## Decides whether a stage can be cleared using the real movement and collection rules.
##
## Why a greedy search is complete here:
##  * Sliding moves are reversible, so the set of reachable block layouts never shrinks
##    except that removing a full block only frees space.
##  * Collecting sand only turns sand into open channel; it never blocks anything.
##  * Per color, total block capacity equals the sand count, so any grain a block of
##    that color takes is a grain that had to be taken anyway.
## So no collection can make a stage worse, and "repeat: reach any layout where some
## non-full block touches its own color, collect" either clears the stage or proves it
## stuck. Layout search is breadth-first over single-cell moves of every block, bounded
## by `max_states`; hitting the bound reports "unknown", never "solvable".


## Finds the nearest layout (fewest single-cell moves) where some non-full block can
## collect its color. Does not modify the board.
## Returns { status: "found"|"none"|"limit", block_id, moves: [{id, dir, steps}], unit_moves, states }.
static func find_next(board: PuzzleBoard, collector: RefCounted, max_states := 100000) -> Dictionary:
	var masks: PackedInt32Array = collector.contact_masks()
	var blocks := board.active_blocks()
	var n := blocks.size()
	var cols := board.cols
	var rows := board.rows
	var base := PackedByteArray()
	base.resize(cols * rows)
	for wpos in board.walls:
		base[wpos.y * cols + wpos.x] = 1

	var start := PackedInt32Array()
	for b in blocks:
		start.append(b.pos.y * cols + b.pos.x)
	var queue: Array[PackedInt32Array] = [start]
	var parent := {str(start): []}
	var head := 0
	while head < queue.size():
		var st := queue[head]
		head += 1
		for k in n:
			var b := blocks[k]
			if b.is_full():
				continue
			@warning_ignore("integer_division")
			var at := Vector2i(st[k] % cols, st[k] / cols)
			if (SandCollector.reach_at(b, at, masks) >> b.color_id) & 1:
				var moves := _path(parent, st, blocks, cols)
				return {"status": "found", "block_id": b.id, "moves": _compress(moves),
					"unit_moves": moves.size(), "states": queue.size()}
		if queue.size() >= max_states:
			return {"status": "limit", "states": queue.size()}
		var occ := base.duplicate()
		for k in n:
			var px := st[k] % cols
			@warning_ignore("integer_division")
			var py := st[k] / cols
			for c in blocks[k].cells:
				occ[(py + c.y) * cols + px + c.x] = k + 2
		for k in n:
			var px := st[k] % cols
			@warning_ignore("integer_division")
			var py := st[k] / cols
			for dir in PuzzleBoard.DIRS:
				var ok := true
				for c in blocks[k].cells:
					var x := px + c.x + dir.x
					var y := py + c.y + dir.y
					if x < 0 or y < 0 or x >= cols or y >= rows:
						ok = false
						break
					var o := occ[y * cols + x]
					if o != 0 and o != k + 2:
						ok = false
						break
				if not ok:
					continue
				var ns := st.duplicate()
				ns[k] = (py + dir.y) * cols + px + dir.x
				var key := str(ns)
				if not parent.has(key):
					parent[key] = [str(st), k, dir, st]
					queue.append(ns)
	return {"status": "none", "states": queue.size()}


## Cheaper search for open boards (used by the gravity policy). Tier 1: move one block
## alone (others fixed). Tier 2: first slide one other block out of the way, then tier 1.
## Falls back to the full layout BFS of find_next(). Not guaranteed to be the fewest moves.
static func find_next_tiered(board: PuzzleBoard, collector: RefCounted, max_states := 100000) -> Dictionary:
	var masks: PackedInt32Array = collector.contact_masks()
	var blocks := board.active_blocks()
	var best := {}
	for b in blocks:
		if b.is_full():
			continue
		var r := _solo_path(board, b, masks)
		if not r.is_empty() and (best.is_empty() or r.size() < best.moves_unit.size()):
			best = {"block": b, "moves_unit": r}
	if not best.is_empty():
		return {"status": "found", "block_id": best.block.id, "moves": _compress(best.moves_unit),
			"unit_moves": best.moves_unit.size(), "states": 0}
	for c in blocks:
		var start := c.pos
		for spot in _solo_reachable(board, c):
			c.pos = spot.pos
			for b in blocks:
				if b == c or b.is_full():
					continue
				var r := _solo_path(board, b, masks)
				if not r.is_empty():
					var cost: int = spot.path.size() + r.size()
					if best.is_empty() or cost < best.cost:
						best = {"block": b, "moves_unit": spot.path + r, "cost": cost}
			c.pos = start
	if not best.is_empty():
		return {"status": "found", "block_id": best.block.id, "moves": _compress(best.moves_unit),
			"unit_moves": best.moves_unit.size(), "states": 0}
	var cleared := _clear_path_plan(board, blocks, masks)
	if not cleared.is_empty():
		return {"status": "found", "block_id": cleared.block_id, "moves": _compress(cleared.moves),
			"unit_moves": cleared.moves.size(), "states": 0}
	return find_next(board, collector, max_states)


## Tier 3: route a block as if only walls existed, then slide every block standing on that
## route out of it (each by its own nearest free spot), then move the block. Board state is
## restored before returning; the returned moves replay the plan from the current layout.
static func _clear_path_plan(board: PuzzleBoard, blocks: Array[SandBlock], masks: PackedInt32Array) -> Dictionary:
	var saved := {}
	for b in blocks:
		saved[b] = b.pos
	var result := {}
	for b in blocks:
		if b.is_full() or not result.is_empty():
			continue
		for route in _wall_only_routes(board, b, masks, 6):
			var lane := {}
			for p in route:
				for c in b.cells:
					lane[p + c] = true
			var moves := []
			var ok := true
			for o in blocks:
				if o == b:
					continue
				var blocking := false
				for c in o.cells:
					if lane.has(o.pos + c):
						blocking = true
				if not blocking:
					continue
				var moved := false
				for spot in _solo_reachable(board, o):
					var clear := true
					for c in o.cells:
						if lane.has(spot.pos + c):
							clear = false
					if clear:
						moves.append_array(spot.path)
						o.pos = spot.pos
						moved = true
						break
				if not moved:
					ok = false
					break
			if ok:
				var r := _solo_path(board, b, masks)
				if not r.is_empty():
					moves.append_array(r)
					result = {"block_id": b.id, "moves": moves}
			for o in blocks:
				o.pos = saved[o]
			if not result.is_empty():
				break
	return result


## Up to `limit` routes (lists of positions) for `b` to spots touching its color, ignoring
## other blocks (walls and edges only), nearest first.
static func _wall_only_routes(board: PuzzleBoard, b: SandBlock, masks: PackedInt32Array, limit: int) -> Array:
	var solo := PuzzleBoard.new()
	solo.cols = board.cols
	solo.rows = board.rows
	solo.walls = board.walls
	var probe := SandBlock.create(b.id, b.color_id, b.cells, b.pos)
	solo.blocks.append(probe)
	var routes := []
	var prev := {b.pos: null}
	var queue: Array[Vector2i] = [b.pos]
	var head := 0
	while head < queue.size() and routes.size() < limit:
		var p := queue[head]
		head += 1
		if (SandCollector.reach_at(probe, p, masks) >> b.color_id) & 1:
			var route := []
			var q: Variant = p
			while q != null:
				route.push_front(q)
				q = prev[q]
			routes.append(route)
		for d in PuzzleBoard.DIRS:
			var n := p + d
			if not prev.has(n) and solo.can_place(probe, n):
				prev[n] = p
				queue.append(n)
	return routes


## BFS over positions of `b` alone (others fixed) to the nearest spot touching its color.
static func _solo_path(board: PuzzleBoard, b: SandBlock, masks: PackedInt32Array) -> Array:
	for spot in _solo_reachable(board, b):
		if (SandCollector.reach_at(b, spot.pos, masks) >> b.color_id) & 1:
			return spot.path
	return []


## All positions `b` can reach alone, nearest first: [{pos, path:[{id,dir,steps}]}].
static func _solo_reachable(board: PuzzleBoard, b: SandBlock) -> Array:
	var start := b.pos
	var out := [{"pos": start, "path": []}]
	var seen := {start: true}
	var head := 0
	while head < out.size():
		var cur: Dictionary = out[head]
		head += 1
		for d in PuzzleBoard.DIRS:
			var n: Vector2i = cur.pos + d
			if seen.has(n) or not board.can_place(b, n):
				continue
			seen[n] = true
			var p: Array = cur.path.duplicate()
			p.append({"id": b.id, "dir": d, "steps": 1})
			out.append({"pos": n, "path": p})
	return out


static func _path(parent: Dictionary, goal: PackedInt32Array, blocks: Array[SandBlock], _cols: int) -> Array:
	var out := []
	var key := str(goal)
	while true:
		var p: Array = parent[key]
		if p.is_empty():
			break
		out.push_front({"id": blocks[p[1]].id, "dir": p[2], "steps": 1})
		key = p[0]
	return out


static func _compress(moves: Array) -> Array:
	var out := []
	for m in moves:
		if not out.is_empty() and out[-1].id == m.id and out[-1].dir == m.dir:
			out[-1].steps += 1
		else:
			out.append(m.duplicate())
	return out


## Plays `game` to the end with the greedy strategy. Mutates `game` (pass a fresh one).
## Returns { status: "solvable"|"unsolvable"|"unknown", drags, unit_moves, collections,
##           states_max, remaining, remaining_by_color, stuck_blocks, plan }.
static func solve(game: SandGame, max_states := 100000) -> Dictionary:
	var drags := 0
	var unit := 0
	var collections := 0
	var states_max := 0
	var plan := []
	while game.remaining > 0:
		var r := find_next(game.board, game.collector, max_states)
		states_max = maxi(states_max, int(r.states))
		if r.status != "found":
			var res := _summary(game, "unknown" if r.status == "limit" else "unsolvable")
			res.merge({"drags": drags, "unit_moves": unit, "collections": collections,
				"states_max": states_max, "plan": plan})
			return res
		for m in r.moves:
			var b := game.board.get_block(m.id)
			if not game.try_move(b, m.dir, m.steps):
				push_error("LevelSolver: planned move failed %s" % m)
				return {"status": "error"}
		drags += r.moves.size()
		unit += int(r.unit_moves)
		plan.append_array(r.moves)
		var target := game.board.get_block(r.block_id)
		game.collector.reset_all()
		var got: PackedInt32Array = game.collector.step(target, 1 << 30)
		if got.is_empty():
			push_error("LevelSolver: reach mask promised sand but none collected")
			return {"status": "error"}
		game.remaining -= got.size()
		collections += 1
		if target.is_full():
			game.board.remove_block(target)
	var done := _summary(game, "solvable")
	done.merge({"drags": drags, "unit_moves": unit, "collections": collections,
		"states_max": states_max, "plan": plan})
	return done


## Gravity stages: plays `game` with real paced ticks and a simple policy (repeat: wait until
## nothing falls or is collected, then move to the nearest layout where some non-full block
## touches its own color). Mutates `game`. Unlike solve(), this is NOT a proof: "cleared"
## means this policy found a way; "stuck" means this policy found none, not that none exists.
## Returns { status: "cleared"|"stuck"|"unknown"|"timeout", drags, unit_moves, collections,
##           ticks, sim_seconds, states_max, remaining, remaining_by_color, stuck_blocks, plan }.
static func play_gravity(game: SandGame, max_states := 100000, max_ticks := 400000, dt := 1.0 / 60.0) -> Dictionary:
	var drags := 0
	var unit := 0
	var collections := 0
	var ticks := 0
	var states_max := 0
	var plan := []
	var status := "cleared"
	while game.remaining > 0:
		while game.remaining > 0 and ticks < max_ticks:
			game.tick(dt)
			ticks += 1
			if game.is_idle():
				break
		if game.remaining == 0:
			break
		if ticks >= max_ticks:
			status = "timeout"
			break
		var r := find_next_tiered(game.board, game.collector, max_states)
		states_max = maxi(states_max, int(r.states))
		if r.status != "found":
			status = "unknown" if r.status == "limit" else "stuck"
			break
		for m in r.moves:
			if not game.try_move(game.board.get_block(m.id), m.dir, m.steps):
				push_error("LevelSolver: planned move failed %s" % m)
				return {"status": "error"}
		drags += r.moves.size()
		unit += int(r.unit_moves)
		plan.append_array(r.moves)
		collections += 1
		game.tick(dt)
		ticks += 1
		if game.collected_last_tick == 0:
			push_error("LevelSolver: contact mask promised sand but none collected")
			return {"status": "error"}
	var res := _summary(game, status)
	res.merge({"drags": drags, "unit_moves": unit, "collections": collections, "ticks": ticks,
		"sim_seconds": ticks * dt, "states_max": states_max, "plan": plan})
	return res


static func _summary(game: SandGame, status: String) -> Dictionary:
	var by_color := {}
	var counts := game.map.count_by_color()
	var keys: Array = game.destination.get("palette_keys", [])
	for i in counts.size():
		if counts[i] > 0:
			by_color[keys[i] if i < keys.size() else str(i)] = counts[i]
	var stuck := []
	for b in game.board.active_blocks():
		stuck.append("%s(%s %d/%d @%s)" % [b.id, keys[b.color_id] if b.color_id < keys.size() else b.color_id,
			b.collected, b.capacity, b.pos])
	return {"status": status, "remaining": game.remaining, "remaining_by_color": by_color,
		"stuck_blocks": stuck}
