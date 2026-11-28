extends SceneTree
## Level validation tool.
##   godot --headless --path . -s res://tests/validate_levels.gd [-- --res=128 --stage=hawaii_01 --plan]
##   ... -- --extra=res://tests/fixtures/gyeongju_test_stages.json   also test-only stages (memory only)
## Exit code 1 when any stage fails.


func _init() -> void:
	var res_list := [128, 64]
	var only := ""
	var show_plan := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--res="):
			res_list = [int(a.substr(6))]
		elif a.begins_with("--stage="):
			only = a.substr(8)
		elif a == "--plan":
			show_plan = true
		elif a.begins_with("--extra="):
			print("extra stages: ", load("res://tests/stage_fixture.gd").inject(a.substr(8)))
	var bad := 0
	for stage in StageLoader.stages():
		if only != "" and stage.id != only:
			continue
		# Stages with only a 128 image (new landscapes) are still validated at every requested
		# resolution: a 64 request builds the 128 image (StageLoader fallback) and is shown as such.
		var dest := StageLoader.stage_destination(stage)
		if not dest.is_empty() and not dest.get("puzzle_paths", {}).has("128"):
			print("[%s] FAIL  no 128 puzzle image (required for every stage)" % stage.id)
			bad += 1
		for res in res_list:
			var r := LevelValidator.validate(stage, res, 150000)
			var loaded := int(r.get("loaded_resolution", res))
			var tag := "@%d" % res if loaded == res else "@%d->%d fallback" % [res, loaded]
			print("[%s %s] %s  status=%s  blocks=%s free=%s  drags=%s unit_moves=%s collections=%s states_max=%s  %sms" % [
				r.stage, tag, "OK" if r.ok else "FAIL", r.get("status"), r.get("blocks"), r.get("free_cells"),
				r.get("drags"), r.get("unit_moves"), r.get("collections"), r.get("states_max"), r.get("solve_ms")])
			for e in r.errors:
				print("    ERROR ", e)
			for w in r.warnings:
				print("    WARN  ", w)
			if show_plan and r.has("plan"):
				for m in r.plan:
					print("    move %s %s x%d" % [m.id, m.dir, m.steps])
			if not r.ok:
				bad += 1
	print("STAGES FAILED: %d" % bad)
	quit(1 if bad > 0 else 0)
