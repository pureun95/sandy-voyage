extends SceneTree
## Headless CPU benchmark of game logic, 64 vs 128 (same stage, same pacing in seconds).
##   godot --headless --path . -s res://tests/bench_collect.gd [-- --stage=hawaii_01]
## Measures SandGame.tick() per 60fps frame and column_reach() (drag hint) cost.
## Rendering cost is NOT measured here (see autoplay stats).


func _init() -> void:
	var stage_id := "hawaii_01"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage_id = a.substr(8)
	for res in [128, 64]:
		var g: SandGame = StageLoader.build(StageLoader.get_stage(stage_id), res).game
		var ticks := PackedFloat32Array()
		var reach := PackedFloat32Array()
		var frames := 0
		var guard := 0
		while not g.cleared and guard < 300:
			guard += 1
			var r := LevelSolver.find_next(g.board, g.collector)
			if r.status != "found":
				break
			for m in r.moves:
				g.try_move(g.board.get_block(m.id), m.dir, m.steps)
			g.collector._reach_changes = -1  # measure uncached cost
			var t0 := Time.get_ticks_usec()
			g.collector.column_reach()
			reach.append((Time.get_ticks_usec() - t0) / 1000.0)
			var rem_before := g.remaining
			var idle := 0
			while idle < 30 and not g.cleared:
				var before := g.remaining
				var t1 := Time.get_ticks_usec()
				g.tick(1.0 / 60.0)
				ticks.append((Time.get_ticks_usec() - t1) / 1000.0)
				frames += 1
				idle = idle + 1 if g.remaining == before else 0
			if g.remaining == rem_before:
				print("  STALL: planned contact collected nothing (block %s)" % r.block_id)
				break
		print("[%s @%d] cleared=%s grains=%d frames=%d (%.1fs collecting)  tick ms: %s  column_reach ms: %s" % [
			stage_id, res, g.cleared, g.total, frames, frames / 60.0, _stats(ticks), _stats(reach)])
	quit()


static func _stats(a: PackedFloat32Array) -> String:
	if a.is_empty():
		return "-"
	var s := Array(a)
	s.sort()
	var sum := 0.0
	for x in s:
		sum += x
	@warning_ignore("integer_division")
	return "avg %.3f p50 %.3f p99 %.3f max %.3f" % [sum / s.size(), s[s.size() / 2], s[int(s.size() * 0.99)], s[-1]]
