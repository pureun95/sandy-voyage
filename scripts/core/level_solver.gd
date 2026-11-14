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
static func find_next(board: PuzzleBoard, collector: SandCollector, max_states := 100000) -> Dictionary:
	var masks := collector.column_reach()
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
		var got := game.collector.step(target, 1 << 30)
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
