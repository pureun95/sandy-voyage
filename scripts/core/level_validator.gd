class_name LevelValidator
extends RefCounted
## Checks a stage for: capacity/sand mismatch per color, blocks outside the board,
## initial overlaps, unknown colors/shapes, and real clearability (LevelSolver).


static func validate(stage: Dictionary, resolution := 128, max_states := 100000) -> Dictionary:
	var built := StageLoader.build(stage, resolution)
	var errors := PackedStringArray(built.errors)
	var warnings := PackedStringArray()
	var game: SandGame = built.game
	var report := {"stage": stage.get("id", "?"), "resolution": resolution}
	if game == null:
		report.merge({"ok": false, "errors": errors, "warnings": warnings, "status": "not_built"})
		return report

	errors.append_array(game.board.validate())

	var keys: Array = game.destination.palette_keys
	var counts := game.map.count_by_color()
	var caps := PackedInt32Array()
	caps.resize(counts.size())
	for b in game.board.blocks:
		if b.capacity <= 0:
			errors.append("block '%s' has capacity %d" % [b.id, b.capacity])
		caps[b.color_id] += b.capacity
	for i in counts.size():
		if counts[i] != caps[i]:
			errors.append("color '%s': sand %d != block capacity %d" % [keys[i], counts[i], caps[i]])

	# Cheap necessary condition: even with every other block gone, each block must be
	# able to slide (walls/edges only) to some position touching board row 0.
	for b in game.board.blocks:
		if not _can_reach_intake_alone(game.board, b):
			errors.append("block '%s' (%s) can never reach the intake row: walls/edges block its shape" % [
				b.id, keys[b.color_id]])

	# Gravity: sand can come to rest over any column (it piles against the edges), so every
	# block must be able to bring an intake cell under every column.
	if game.is_gravity():
		for b in game.board.blocks:
			var missing := _unreachable_intake_columns(game.board, b)
			if not missing.is_empty():
				errors.append("block '%s' (%s, shape cells %s) can never put an intake under column(s) %s; sand of its color can settle there" % [
					b.id, keys[b.color_id], b.cells, missing])

	var free := game.board.cols * game.board.rows - game.board.walls.size()
	for b in game.board.blocks:
		free -= b.cells.size()
	if free <= 0:
		errors.append("no free cell to move into")

	var start_contact := []
	var masks := game.contact_masks()
	for b in game.board.blocks:
		if not b.contact_columns().is_empty() and (SandCollector.reach_at(b, b.pos, masks) >> b.color_id) & 1:
			start_contact.append(b.id)
	if not start_contact.is_empty():
		warnings.append("blocks collect immediately at start: %s" % ", ".join(start_contact))

	report.merge({"free_cells": free, "blocks": game.board.blocks.size(),
		"sand": game.total, "capacities": caps})
	if not errors.is_empty():
		report.merge({"ok": false, "errors": errors, "warnings": warnings, "status": "invalid"})
		return report

	var t0 := Time.get_ticks_msec()
	if game.is_gravity():
		# Gravity stages are checked by playing them with paced ticks; success shows a way
		# exists, failure only shows this policy found none.
		var played := LevelSolver.play_gravity(game, max_states)
		report.merge(played)
		report.solve_ms = Time.get_ticks_msec() - t0
		report.physics = "gravity"
		if played.status == "cleared":
			report.status = "solvable"
		else:
			errors.append("gravity play policy did not clear (%s): %d grains left %s; blocks %s" % [
				played.status, played.get("remaining", -1), played.get("remaining_by_color", {}), played.get("stuck_blocks", [])])
		report.merge({"ok": errors.is_empty(), "errors": errors, "warnings": warnings})
		return report
	var sol := LevelSolver.solve(game, max_states)
	report.merge(sol)
	report.solve_ms = Time.get_ticks_msec() - t0
	if sol.status == "unsolvable":
		errors.append("not clearable: %d grains left %s; blocks left %s" % [
			sol.remaining, sol.remaining_by_color, sol.stuck_blocks])
	elif sol.status == "unknown":
		errors.append("clearability unknown: layout search exceeded %d states" % max_states)
	elif sol.status != "solvable":
		errors.append("solver error")
	report.merge({"ok": errors.is_empty(), "errors": errors, "warnings": warnings})
	return report


## Columns no position of `b` (walls/edges only) can put an intake cell under.
static func _unreachable_intake_columns(board: PuzzleBoard, b: SandBlock) -> Array:
	var solo := PuzzleBoard.new()
	solo.cols = board.cols
	solo.rows = board.rows
	solo.walls = board.walls
	var probe := SandBlock.create(b.id, b.color_id, b.cells, b.pos)
	solo.blocks.append(probe)
	var covered := {}
	var seen := {b.pos: true}
	var queue: Array[Vector2i] = [b.pos]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for col in probe.contact_columns(p):
			covered[col] = true
		for d in PuzzleBoard.DIRS:
			var n := p + d
			if not seen.has(n) and solo.can_place(probe, n):
				seen[n] = true
				queue.append(n)
	var missing := []
	for c in board.cols:
		if not covered.has(c):
			missing.append(c)
	return missing


static func _can_reach_intake_alone(board: PuzzleBoard, b: SandBlock) -> bool:
	var solo := PuzzleBoard.new()
	solo.cols = board.cols
	solo.rows = board.rows
	solo.walls = board.walls
	var probe := SandBlock.create(b.id, b.color_id, b.cells, b.pos)
	solo.blocks.append(probe)
	var seen := {b.pos: true}
	var queue: Array[Vector2i] = [b.pos]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if not probe.contact_columns(p).is_empty():
			return true
		for d in PuzzleBoard.DIRS:
			var n := p + d
			if not seen.has(n) and solo.can_place(probe, n):
				seen[n] = true
				queue.append(n)
	return false
