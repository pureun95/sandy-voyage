extends Node
## Debug autopilot. Drives the real UI: drags and button clicks are injected as mouse
## events into the viewport (same path as a finger or mouse). Moves come from LevelSolver.
## Uses an isolated save file (user://autoplay_save.json); the player's save is untouched.
##
##   godot --path . -- --autoplay=hawaii_01 [--res=128] [--shots=DIR]   one stage
##   godot --path . -- --autoplay=all [--res=128] [--shots=DIR]         every stage in order: home ->
##        "여행 시작하기", "다음 스테이지" inside a destination, the destination sheet's "출발!" for
##        the next destination; then home / world map / album
##   godot --path . -- --autoplay=verify-save                           new process: check saved progress
##   godot --path . -- --autoplay=ui-shots --shots=DIR                  screenshots of every travel screen
##        (fresh save, then a seeded mid-journey save; isolated save file)
##   ... --extra-stages=res://tests/fixtures/gyeongju_test_stages.json   test-only stages, injected in
##        memory (data/*.json untouched; save is the isolated autoplay file as always)
##   ... --probe --shots=DIR   sand render probe (single stage): every frame checks the uploaded sand
##        texture against SandMap.cells; every `probe_every` frames hides the grain fx for one frame
##        and compares the rendered screen (cell centres) with the cells; saves the landscape+board
##        area every `frame_every` frames to DIR/frames/ (for a GIF/video). Report: DIR/probe.json

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
var probe := false
var probe_every := 30
var frame_every := 4
var _probe := {}
var _orig := PackedByteArray()
var _frame_no := 0
var _taken := {}   # cell index -> frame it was collected (refill tracking)


func _ready() -> void:
	var res := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--res="):
			res = int(a.substr(6))
		elif a.begins_with("--extra-stages="):
			print("AUTOPLAY extra stages: ", load("res://tests/stage_fixture.gd").inject(a.substr(15)))
		elif a == "--probe":
			probe = true
		elif a.begins_with("--probe-every="):
			probe_every = int(a.substr(14))
		elif a.begins_with("--frame-every="):
			frame_every = int(a.substr(14))
	if probe and shots_dir == "":
		push_error("autoplay: --probe needs --shots=DIR (frames, diffs and probe.json go there)")
		probe = false
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
	elif stage_id == "ui-shots":
		_run_ui_shots.call_deferred()
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
	main.show_home()
	await _frames_wait(20)
	await _shot("00_home")
	_gs = main.show_game(stage_id)
	await _frames_wait(30)
	await _shot("01_start")
	if probe:
		_probe_begin()
		await _probe_screen("start")
	var t0 := Time.get_ticks_msec()
	await _play_current(true)
	var play_s := (Time.get_ticks_msec() - t0) / 1000.0
	await _frames_wait(90)
	await _shot("10_clear")
	print("AUTOPLAY RESULT stage=%s res=%d cleared=%s drags=%d drag_mismatch=%d play_time=%.1fs remaining=%d saved_album=%s" % [
		stage_id, _gs.game.map.width, _gs.game.cleared, _drags, _drag_mismatch, play_s, _gs.game.remaining,
		App.save.is_unlocked(_gs.game.destination.id)])
	_report()
	if probe:
		_probe_report()
	var ok := _gs.game.cleared and _failures.is_empty()
	main.show_album()
	await _frames_wait(20)
	await _shot("11_album")
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------- all stages via UI

func _run_all() -> void:
	var stages := StageLoader.stages()
	main.show_home()
	await _frames_wait(20)
	await _shot("00_home")
	if not await _click_button(main, "여행 시작하기"):
		_fail("home start button not found")
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
		print("STAGE %d %s cleared=%s drags=%d play=%.1fs saved=%s album[%s]=%s last_played=%s" % [i + 1, stages[i].id,
			_gs.game.cleared, _drags - drags_before, play_s, App.save.is_cleared(stages[i].id),
			stages[i].destination, App.save.is_unlocked(stages[i].destination), App.save.last_played()])
		if not _gs.game.cleared or not App.save.is_cleared(stages[i].id):
			_fail("stage %s not cleared/saved" % stages[i].id)
			break
		if i + 1 >= stages.size():
			break
		if stages[i + 1].destination == stages[i].destination:
			if not await _click_button(_gs, "다음 스테이지"):
				_fail("'다음 스테이지' not found after %s" % stages[i].id)
				break
			continue
		# Last stage of a destination: no cross-destination "next"; go back to the sheet,
		# then open the next destination and start it from its sheet.
		if _find_button(_gs, "다음 스테이지") != null:
			_fail("'다음 스테이지' offered across destinations after %s" % stages[i].id)
		if not await _click_button(_gs, "여행지로 돌아가기"):
			_fail("'여행지로 돌아가기' not found after %s" % stages[i].id)
			break
		await _frames_wait(20)
		await _shot("%02d_%s_sheet" % [i + 1, stages[i].destination])
		main.show_destination(str(stages[i + 1].destination))
		await _frames_wait(20)
		if not await _click_button(main, "출발!"):
			_fail("'출발!' not found on %s sheet" % stages[i + 1].destination)
			break
	await _frames_wait(20)
	main.show_home()
	await _frames_wait(30)
	await _shot("20_home_after")
	var stamps := TravelCatalog.total_stamps(App.save)
	var cards := TravelCatalog.total_postcards(App.save)
	print("TRAVEL: stamps=%d postcards=%d continue=%s" % [stamps, cards, TravelCatalog.continue_stage(App.save, App.entitlements)])
	var built_dests := {}
	for st in stages:
		built_dests[st.destination] = true
	if stamps != built_dests.size() or cards != stages.size():
		_fail("expected %d stamps / %d postcards, got %d / %d" % [built_dests.size(), stages.size(), stamps, cards])
	if not await _click_button(main, "세계 지도"):
		_fail("world map button not found")
	await _frames_wait(30)
	await _shot("21_world_map")
	main.show_home()
	await _frames_wait(20)
	if not await _click_button(main, "여행 앨범"):
		_fail("album button not found")
	await _frames_wait(40)
	await _shot("22_album")
	var fresh := SaveStore.new(SAVE_PATH)
	fresh.load_data()
	var unlocked := []
	for d in StageLoader.destination_order():
		if fresh.is_unlocked(d):
			unlocked.append(d)
	print("SAVE ON DISK: cleared=%d unlocked=%s last_played=%s" % [fresh.data.cleared.size(), unlocked, fresh.last_played()])
	print("AUTOPLAY ALL: stages=%d drags=%d drag_mismatch=%d failures=%d" % [stages.size(), _drags, _drag_mismatch, _failures.size()])
	_report()
	get_tree().quit(0 if _failures.is_empty() else 1)


## Screenshots of the travel screens: fresh save first, then a seeded mid-journey save
## (Hawaii 3/3, Fuji 3/3, London 1/3, last played london_01). Writes only SAVE_PATH.
func _run_ui_shots() -> void:
	main.show_home()
	await _frames_wait(30)
	await _shot("01_home_fresh")
	var s := App.save
	var t := int(Time.get_unix_time_from_system()) - 86400 * 3
	for sid in ["hawaii_01", "hawaii_02", "hawaii_03", "fuji_01", "fuji_02", "fuji_03", "london_01"]:
		t += 3600
		s.data.cleared[sid] = {"at": t}
		var dest: String = TravelCatalog.split_stage_id(sid).destination
		if not s.data.album.has(dest):
			s.data.album[dest] = {"at": t, "first_stage": sid}
	s.data.last_played = "london_01"
	s.save_data()
	var steps := [
		["02_home", func(): main.show_home()],
		["03_world_map", func(): main.show_world_map()],
		["04_continent_europe", func(): main.show_continent("europe")],
		["05_sheet_london", func(): main.show_destination("london")],
		["06_sheet_paris_unbuilt_free", func(): main.show_destination("paris")],
		["07_sheet_edinburgh_premium", func(): main.show_destination("edinburgh")],
		["09_continent_asia", func(): main.show_continent("asia")],
		["10_sheet_fuji_visited", func(): main.show_destination("fuji")],
		["11_continent_north_america", func(): main.show_continent("north_america")],
		["12_continent_south_america", func(): main.show_continent("south_america")],
		["13_continent_africa", func(): main.show_continent("africa")],
		["14_continent_oceania", func(): main.show_continent("oceania")],
		["15_album_europe", func(): main.show_album("europe")],
		["17_album_asia", func(): main.show_album("asia")],
	]
	for st in steps:
		st[1].call()
		await _frames_wait(45)
		await _shot(st[0])
		if st[0] == "07_sheet_edinburgh_premium":
			if not await _click_button(main, "여행 패스 안내"):
				_fail("pass info button not found")
			await _frames_wait(10)
			await _shot("08_pass_info")
		if st[0] == "15_album_europe":
			var a := main._screen as AlbumScreen
			a._full(TravelCatalog.destination("london"), 1)
			await _frames_wait(20)
			await _shot("16_album_full_view")
		if st[0] == "05_sheet_london":
			_gs = main.show_game("london_02")
			await _frames_wait(30)
			await _shot("05b_game_london_02")
	print("UI SHOTS: thumbs cached=%d failures=%d" % [App.thumbs.cached_count(), _failures.size()])
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
			if probe:
				await _probe_frame()
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
		if probe:
			await _probe_frame()
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


# ---------------------------------------------------------------- sand render probe

func _probe_begin() -> void:
	var g := _gs.game
	_orig = g.map.cells.duplicate()
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir.path_join("probe"))
		FileAccess.open(shots_dir.path_join("probe/cells_00000.bin"), FileAccess.WRITE).store_buffer(_orig)
	_frame_no = 0
	_probe = {"stage": stage_id, "res": g.map.width, "frames": 0, "tex_checks": 0, "tex_mismatch_frames": 0,
		"tex_mismatch_cells_max": 0, "screen_checks": 0, "screen_mismatch_max": 0, "screen_mismatch_total": 0,
		"screen_ghost_total": 0, "screen_hole_total": 0, "float_idle_frames": 0, "float_idle_max": 0,
		"timeline": [], "taken": 0, "taken_buried": 0, "refill_within_5f": 0, "refill_within_30f": 0,
		"still_empty_after_30f": 0}
	g.grains_collected.connect(_on_probe_grains)
	DirAccess.make_dir_recursive_absolute(shots_dir.path_join("frames"))
	DirAccess.make_dir_recursive_absolute(shots_dir.path_join("probe"))


## Called right after process_frame: last frame's tick + texture upload are both done, so the
## uploaded texture must equal map.cells exactly.
func _probe_frame() -> void:
	var g := _gs.game
	_frame_no += 1
	_probe.frames += 1
	var tex_cells := _gs.sand_view.texture.get_image().get_data()
	_probe.tex_checks += 1
	if tex_cells != g.map.cells:
		var diff := 0
		for i in tex_cells.size():
			if tex_cells[i] != g.map.cells[i]:
				diff += 1
		_probe.tex_mismatch_frames += 1
		_probe.tex_mismatch_cells_max = maxi(_probe.tex_mismatch_cells_max, diff)
	# Grains resting on an empty cell while the simulation is asleep would be stuck in the air.
	if g.sim != null and not g.sim.is_active():
		var fl := _floating(g)
		if fl > 0:
			_probe.float_idle_frames += 1
			_probe.float_idle_max = maxi(_probe.float_idle_max, fl)
	_track_refill(g)
	if _frame_no % 10 == 0:
		_probe.timeline.append(_timeline_row(g))
	if _frame_no % 60 == 0 and shots_dir != "":
		var f := FileAccess.open(shots_dir.path_join("probe/cells_%05d.bin" % _frame_no), FileAccess.WRITE)
		f.store_buffer(g.map.cells)
	if _frame_no % probe_every == 0:
		await _probe_screen("f%05d" % _frame_no)
	elif shots_dir != "" and _frame_no % frame_every == 0:
		await RenderingServer.frame_post_draw
		_save_frame()


## Grains the simulation rule would still move (empty below, or an empty diagonal-below cell
## that the stage's slide rule allows) - should be 0 whenever the simulation is asleep.
func _floating(g: SandGame) -> int:
	var w := g.map.width
	var c := g.map.cells
	var gap := g.sim.diagonal_needs_side_gap
	var n := 0
	for i in range(0, c.size() - w):
		if c[i] == SandMap.EMPTY:
			continue
		var b := i + w
		if c[b] == SandMap.EMPTY:
			n += 1
			continue
		var x := i % w
		if x > 0 and c[b - 1] == SandMap.EMPTY and (not gap or c[i - 1] == SandMap.EMPTY):
			n += 1
		elif x < w - 1 and c[b + 1] == SandMap.EMPTY and (not gap or c[i + 1] == SandMap.EMPTY):
			n += 1
	return n


## A collected grain was "buried" when the cell above it still held sand at that moment: the
## column above then drops into the hole, so the spot looks full again while the grain flies off.
func _on_probe_grains(_b: SandBlock, indices: PackedInt32Array) -> void:
	var g := _gs.game
	var w := g.map.width
	for i in indices:
		_probe.taken += 1
		if i >= w and g.map.cells[i - w] != SandMap.EMPTY:
			_probe.taken_buried += 1
		_taken[i] = _frame_no


func _track_refill(g: SandGame) -> void:
	var done := []
	for i in _taken:
		var age: int = _frame_no - int(_taken[i])
		if g.map.cells[i] != SandMap.EMPTY:
			if age <= 5:
				_probe.refill_within_5f += 1
			if age <= 30:
				_probe.refill_within_30f += 1
			done.append(i)
		elif age > 30:
			_probe.still_empty_after_30f += 1
			done.append(i)
	for i in done:
		_taken.erase(i)


func _timeline_row(g: SandGame) -> Dictionary:
	var c := g.map.cells
	var same := 0
	var empty := 0
	for i in c.size():
		if c[i] == SandMap.EMPTY:
			empty += 1
		elif c[i] == _orig[i]:
			same += 1
	return {"frame": _frame_no, "remaining": g.remaining, "empty": empty,
		"same_as_original": same, "sim_active_chunks": g.sim.active_chunks() if g.sim else 0,
		"fx": _gs.fx.count()}


func _land_rect_px() -> Dictionary:
	var sv := _gs.sand_view
	var xf := get_viewport().get_final_transform() * sv.get_global_transform_with_canvas()
	return {"xf": xf, "size": sv.size}


func _save_frame() -> void:
	var img := get_viewport().get_texture().get_image()
	var r := _land_rect_px()
	var xf: Transform2D = r.xf
	var bv := _gs.board_view
	var p0: Vector2 = xf * Vector2.ZERO
	var p1: Vector2 = xf * Vector2(r.size.x, r.size.y + bv.size.y)
	var rect := Rect2i(Vector2i(p0), Vector2i(p1 - p0)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(rect).save_png(shots_dir.path_join("frames/%05d.png" % _frame_no))


## Hides the flying grains for one frame, then compares every cell centre on screen with
## map.cells: "ghost" = screen shows sand where the cell is empty, "hole" = screen shows empty
## where there is sand, "wrong" = another sand color.
func _probe_screen(tag: String) -> void:
	var g := _gs.game
	_gs.fx.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_gs.fx.visible = true
	var r := _land_rect_px()
	var xf: Transform2D = r.xf
	var w := g.map.width
	var gs: float = r.size.x / w
	var pal: Array[Color] = g.map.palette
	var empty_col := UiKit.EMPTY_SAND
	var ghost := 0
	var hole := 0
	var wrong := 0
	var cells := g.map.cells
	var diff := Image.create(w, g.map.height, false, Image.FORMAT_RGBA8)
	for y in g.map.height:
		for x in w:
			var p: Vector2 = xf * Vector2((x + 0.5) * gs, (y + 0.5) * gs)
			var c := img.get_pixelv(Vector2i(p))
			var best := -1
			var bd := SandMap.color_distance(c, empty_col)
			for k in pal.size():
				var d := SandMap.color_distance(c, pal[k])
				if d < bd:
					bd = d
					best = k
			var want := int(cells[y * w + x])
			var want_id := -1 if want == SandMap.EMPTY else want
			if best == want_id:
				diff.set_pixel(x, y, Color(pal[want_id], 0.35) if want_id >= 0 else Color(0, 0, 0, 0))
				continue
			if want_id < 0:
				ghost += 1
				diff.set_pixel(x, y, Color.RED)
			elif best < 0:
				hole += 1
				diff.set_pixel(x, y, Color.BLUE)
			else:
				wrong += 1
				diff.set_pixel(x, y, Color.MAGENTA)
	var total := ghost + hole + wrong
	_probe.screen_checks += 1
	_probe.screen_mismatch_max = maxi(_probe.screen_mismatch_max, total)
	_probe.screen_mismatch_total += total
	_probe.screen_ghost_total += ghost
	_probe.screen_hole_total += hole
	if total > 0 or tag == "start" or _probe.screen_checks % 10 == 0:
		diff.save_png(shots_dir.path_join("probe/%s_diff_%d.png" % [tag, total]))
		img.save_png(shots_dir.path_join("probe/%s_screen.png" % tag))
	if total > 0:
		printerr("PROBE %s: screen != cells: ghost=%d hole=%d wrong=%d" % [tag, ghost, hole, wrong])


func _probe_report() -> void:
	_probe.viewport = str(get_viewport().get_texture().get_size())
	print("PROBE ", JSON.stringify({"frames": _probe.frames, "tex_mismatch_frames": _probe.tex_mismatch_frames,
		"screen_checks": _probe.screen_checks, "screen_mismatch_total": _probe.screen_mismatch_total,
		"screen_mismatch_max": _probe.screen_mismatch_max, "float_idle_frames": _probe.float_idle_frames,
		"float_idle_max": _probe.float_idle_max, "taken": _probe.taken, "taken_buried": _probe.taken_buried,
		"refill_within_5f": _probe.refill_within_5f, "refill_within_30f": _probe.refill_within_30f,
		"still_empty_after_30f": _probe.still_empty_after_30f}))
	var f := FileAccess.open(shots_dir.path_join("probe.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_probe, "\t"))
