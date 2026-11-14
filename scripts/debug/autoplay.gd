extends Node
## Debug autopilot. Drives the real UI: drags and button clicks are injected as mouse
## events into the viewport (same path as a finger or mouse). Moves come from LevelSolver.
## Uses an isolated save file (user://autoplay_save.json); the player's save is untouched.
##
##   godot --path . -- --autoplay=hawaii_01 [--res=128] [--shots=DIR]   one stage
##   godot --path . -- --autoplay=all [--res=128] [--shots=DIR]         every stage in order via
##                                                                      "다음 스테이지", then list + album
##   godot --path . -- --autoplay=verify-save                           new process: check saved progress

const SAVE_PATH := "user://autoplay_save.json"

var main: Node
var stage_id := ""
var shots_dir := ""
var _frames := PackedFloat32Array()   # frame delta (ms)
var _ticks := PackedFloat32Array()    # game.tick cost (ms)
var _gs: GameScreen
var _recording := false
var _drags := 0
var _drag_mismatch := 0
var _failures := PackedStringArray()


func _ready() -> void:
	var res := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--res="):
			res = int(a.substr(6))
	if stage_id == "verify-save":
		_verify_save.call_deferred()
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	App.save = SaveStore.new(SAVE_PATH)
	App.save.load_data()
	if res > 0:
		App.save.data.settings.resolution = res
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	if stage_id == "all":
		_run_all.call_deferred()
	else:
		_run_one.call_deferred()


func _process(delta: float) -> void:
	if _recording and is_instance_valid(_gs):
		_frames.append(delta * 1000.0)
		_ticks.append(_gs.last_tick_usec / 1000.0)


func _frames_wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join(shot_name + ".png"))


func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("AUTOPLAY FAIL: ", msg)


# ---------------------------------------------------------------- single stage

func _run_one() -> void:
	main.show_stage_select()
	await _frames_wait(20)
	await _shot("00_stage_select")
	_gs = main.show_game(stage_id)
	await _frames_wait(30)
	await _shot("01_start")
	var t0 := Time.get_ticks_msec()
	await _play_current(true)
	var play_s := (Time.get_ticks_msec() - t0) / 1000.0
	await _frames_wait(90)
	await _shot("10_clear")
	print("AUTOPLAY RESULT stage=%s res=%d cleared=%s drags=%d drag_mismatch=%d play_time=%.1fs remaining=%d saved_album=%s" % [
		stage_id, _gs.game.map.width, _gs.game.cleared, _drags, _drag_mismatch, play_s, _gs.game.remaining,
		App.save.is_unlocked(_gs.game.destination.id)])
	_report()
	var ok := _gs.game.cleared and _failures.is_empty()
	main.show_album()
	await _frames_wait(20)
	await _shot("11_album")
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- all stages via UI

func _run_all() -> void:
	var stages := StageLoader.stages()
	main.show_stage_select()
	await _frames_wait(20)
	await _shot("00_stage_select")
	if not await _click_button(main, str(stages[0].name_ko)):
		_fail("first stage button not found")
	for i in stages.size():
		await _frames_wait(20)
		_gs = main._screen as GameScreen
		if _gs == null or _gs.stage_id != stages[i].id:
			_fail("expected game screen for %s, got %s" % [stages[i].id, _gs.stage_id if _gs else "none"])
			break
		var drags_before := _drags
		var t0 := Time.get_ticks_msec()
		await _play_current(false)
		var play_s := (Time.get_ticks_msec() - t0) / 1000.0
		# Wait for the clear overlay.
		var w := 0
		while not is_instance_valid(_gs._overlay) and w < 300:
			await get_tree().process_frame
			w += 1
		await _frames_wait(10)
		await _shot("%02d_%s_clear" % [i + 1, stages[i].id])
		print("STAGE %d %s cleared=%s drags=%d play=%.1fs saved=%s album[%s]=%s" % [i + 1, stages[i].id,
			_gs.game.cleared, _drags - drags_before, play_s, App.save.is_cleared(stages[i].id),
			stages[i].destination, App.save.is_unlocked(stages[i].destination)])
		if not _gs.game.cleared or not App.save.is_cleared(stages[i].id):
			_fail("stage %s not cleared/saved" % stages[i].id)
			break
		var label := "다음 스테이지" if i + 1 < stages.size() else "스테이지 목록"
		if not await _click_button(_gs, label):
			_fail("button '%s' not found after %s" % [label, stages[i].id])
			break
	await _frames_wait(20)
	await _shot("20_stage_select_after")
	var checks := _count_buttons_with(main, "✓")
	print("STAGE LIST: %d stage buttons show ✓" % checks)
	if checks != stages.size():
		_fail("stage list shows %d cleared marks, expected %d" % [checks, stages.size()])
	if not await _click_button(main, "여행 앨범"):
		_fail("album button not found")
	await _frames_wait(20)
	await _shot("21_album")
	var fresh := SaveStore.new(SAVE_PATH)
	fresh.load_data()
	var unlocked := []
	for d in StageLoader.destination_order():
		if fresh.is_unlocked(d):
			unlocked.append(d)
	print("SAVE ON DISK: cleared=%d unlocked=%s" % [fresh.data.cleared.size(), unlocked])
	print("AUTOPLAY ALL: stages=%d drags=%d drag_mismatch=%d failures=%d" % [stages.size(), _drags, _drag_mismatch, _failures.size()])
	_report()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify_save() -> void:
	var s := SaveStore.new(SAVE_PATH)
	s.load_data()
	App.save = s
	main.show_album()
	await _frames_wait(20)
	var unlocked := []
	for d in StageLoader.destination_order():
		if s.is_unlocked(d):
			unlocked.append(d)
	print("VERIFY SAVE (new process): cleared=%s unlocked=%s resolution=%s" % [
		s.data.cleared.keys(), unlocked, s.get_setting("resolution")])
	await _shot("30_album_after_restart")
	get_tree().quit()


# ---------------------------------------------------------------- helpers

func _play_current(take_shots: bool) -> void:
	_recording = true
	var shot_n := 2
	var next_shot_t := 0.0
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while not _gs.game.cleared and guard < 5000:
		guard += 1
		var r := LevelSolver.find_next_tiered(_gs.game.board, _gs.game.collector) if _gs.game.is_gravity() 			else LevelSolver.find_next(_gs.game.board, _gs.game.collector)
		if r.status != "found":
			_fail("%s: no further collectible layout (%s); remaining=%d" % [_gs.stage_id, r.status, _gs.game.remaining])
			break
		for m in r.moves:
			await _drag(m)
		var idle := 0
		while idle < 25 and not _gs.game.cleared:
			await get_tree().process_frame
			var busy := _gs.fx.count() > 0 or not _gs.game.is_idle()
			idle = 0 if busy else idle + 1
			var t := (Time.get_ticks_msec() - t0) / 1000.0
			if take_shots and busy and t >= next_shot_t and shot_n < 9:
				await _shot("%02d_play" % shot_n)
				shot_n += 1
				next_shot_t = t + 3.0
	_recording = false


func _drag(m: Dictionary) -> void:
	var bv := _gs.board_view
	var w := 0
	while not bv._settle.is_empty() and w < 120:
		await get_tree().process_frame
		w += 1
	var b := _gs.game.board.get_block(m.id)
	var expected: Vector2i = b.pos + m.dir * int(m.steps)
	var start := bv.global_position + (Vector2(b.pos + b.cells[0]) + Vector2(0.5, 0.5)) * bv.cell
	var delta: Vector2 = Vector2(m.dir * int(m.steps)) * bv.cell
	_mouse_button(start, true)
	await get_tree().process_frame
	var n: int = 6 + int(m.steps) * 3
	for i in range(1, n + 1):
		_mouse_motion(start + delta * (float(i) / n))
		await get_tree().process_frame
	_mouse_button(start + delta, false)
	await get_tree().process_frame
	_drags += 1
	if b.pos != expected:
		_drag_mismatch += 1
		_fail("%s: drag of %s ended at %s, expected %s" % [_gs.stage_id, m.id, b.pos, expected])


func _find_button(root: Node, prefix: String) -> Button:
	for c in root.get_children():
		if c is Button and c.is_visible_in_tree() and (c as Button).text.begins_with(prefix):
			return c
		var f := _find_button(c, prefix)
		if f:
			return f
	return null


func _count_buttons_with(root: Node, needle: String) -> int:
	var n := 0
	for c in root.get_children():
		if c is Button and (c as Button).text.contains(needle):
			n += 1
		n += _count_buttons_with(c, needle)
	return n


func _click_button(root: Node, prefix: String) -> bool:
	var b := _find_button(root, prefix)
	if b == null:
		return false
	var p := b.get_global_rect().get_center()
	_mouse_motion(p, false)
	await get_tree().process_frame
	_mouse_button(p, true)
	await get_tree().process_frame
	_mouse_button(p, false)
	await get_tree().process_frame
	return true


func _mouse_button(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	e.global_position = p
	if pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)


func _mouse_motion(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e, true)


static func _stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s := Array(a)
	s.sort()
	var sum := 0.0
	for x in s:
		sum += x
	@warning_ignore("integer_division")
	return {"avg": sum / s.size(), "p50": s[s.size() / 2], "p99": s[int(s.size() * 0.99)], "max": s[-1], "n": s.size()}


func _report() -> void:
	var over := 0
	for f in _frames:
		if f > 17.5:
			over += 1
	var rep := {"stage": stage_id, "frame_ms": _stats(_frames), "tick_ms": _stats(_ticks),
		"frames_over_17_5ms": over, "drags": _drags, "drag_mismatch": _drag_mismatch, "failures": _failures}
	print("AUTOPLAY STATS ", JSON.stringify(rep))
	if shots_dir != "":
		var f := FileAccess.open(shots_dir.path_join("stats.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "\t"))
