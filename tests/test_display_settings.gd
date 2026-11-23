extends SceneTree
## Headless test: godot --headless --path . -s res://tests/test_display_settings.gd
## Postcard pre-scaling (256 px art only), the debug-only 64/128 resolution switch and the
## release 128 resolution rule (App.effective_resolution) with saves left untouched.
## Uses a temporary save file; the player's save is never written. UI scripts use the App autoload,
## which is not a known identifier while a -s script compiles, so they are load()ed after one frame.

var failures := 0
var passed := 0
var Postcard: GDScript
var Settings: GDScript

const ALBUM_1024 := "res://assets/destinations/Sandy_Voyage_Assets_v2/london_album_1024.png"
const ALBUM_256 := "res://assets/destinations/gyeongju/gyeongju_s1_v2_album256.png"


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _init() -> void:
	await process_frame
	Postcard = load("res://scripts/ui/postcard_image.gd")
	Settings = load("res://scripts/ui/settings_panel.gd")
	test_display_texture()
	await process_frame
	await test_settings_panel()
	test_resolution_setting()
	print("PASSED %d  FAILURES %d" % [passed, failures])
	quit(1 if failures > 0 else 0)


func test_display_texture() -> void:
	print("[postcard display texture]")
	check(Postcard.display_texture(null) == null, "null stays null")
	for d in StageLoader.destinations().values():
		var t := load(d.album_path) as Texture2D
		check(Postcard.display_texture(t) == t,
			"%s %dpx album returned unchanged (same LINEAR path as before)" % [d.id, t.get_width()])
	var small := load(ALBUM_256) as Texture2D
	if small == null:
		print("  (skip 256 checks: %s not present)" % ALBUM_256)
		return
	var big: Texture2D = Postcard.display_texture(small)
	check(big != small and big.get_width() == 1024 and big.get_height() == 1024, "256 album -> 1024 texture")
	var src := small.get_image()
	var dst := big.get_image()
	var bad := 0
	for y in range(0, 256, 5):
		for x in range(0, 256, 3):
			var c := src.get_pixel(x, y)
			for k in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
				if not dst.get_pixel(x * 4 + k.x, y * 4 + k.y).is_equal_approx(c):
					bad += 1
	check(bad == 0, "each 256 px pixel becomes an exact 4x4 block (nearest, mismatches=%d)" % bad)
	check(small.get_image().get_width() == 256, "source image is not resized in place")
	var again: Texture2D = Postcard.display_texture(small)
	check(again.get_width() == 1024, "opening the same postcard again still gives 1024 (no repeated x4)")
	check(load(ALBUM_256) == small, "source texture itself is not modified (resource cache intact)")


func test_settings_panel() -> void:
	print("[settings panel]")
	var app := root.get_node_or_null("App")
	check(app != null, "App autoload available")
	if app == null:
		return
	var path := "user://test_settings_%d.json" % Time.get_ticks_usec()
	var real_save = app.save
	var s := SaveStore.new(path)
	s.load_data()
	s.set_setting("resolution", 64)   # a player who switched to 64 in an earlier build
	app.save = s
	var hidden: Control = Settings.create(Callable(), false)
	root.add_child(hidden)
	check(hidden.find_child("ResolutionSwitch", true, false) == null, "release UI: no resolution switch")
	var sound: Button = null
	for b in hidden.find_children("*", "Button", true, false):
		if str(b.text).begins_with("소리"):
			sound = b
	check(sound != null, "release UI: sound switch still shown")
	if sound != null:
		sound.pressed.emit()   # refresh must not touch the missing switch
		check(s.get_setting("sound") == false, "sound toggles without the resolution switch")
	check(int(s.get_setting("resolution")) == 64, "saved resolution value left untouched (not reset)")
	hidden.queue_free()
	var shown: Control = Settings.create(Callable(), true)
	root.add_child(shown)
	check(shown.find_child("ResolutionSwitch", true, false) != null, "debug UI: resolution switch present")
	shown.queue_free()
	check(Settings.resolution_switch_visible() == OS.is_debug_build(), "visibility follows build type")
	await process_frame
	app.save = real_save
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_resolution_setting() -> void:
	print("[resolution setting: release forces 128, saves untouched]")
	var AppScript: GDScript = load("res://scripts/autoload/app.gd")
	# 4. Release build: 128 whatever was saved.
	for saved in [64, 128, "64", null, 32]:
		check(AppScript.effective_resolution(saved, false) == 128, "release: saved %s -> 128" % [saved])
	# Debug build keeps the 64/128 comparison.
	check(AppScript.effective_resolution(64, true) == 64, "debug: saved 64 -> 64")
	check(AppScript.effective_resolution(128, true) == 128, "debug: saved 128 -> 128")
	check(AppScript.effective_resolution(64.0, true) == 64, "debug: saved 64.0 (JSON number) -> 64")
	check(AppScript.effective_resolution(null, true) == 128 and AppScript.effective_resolution(32, true) == 128,
		"debug: missing/invalid -> 128")

	# 3. A player whose save says 64 (switched in an earlier build), with progress.
	var app := root.get_node_or_null("App")
	if app == null:
		check(false, "App autoload available")
		return
	var path := "user://test_res_save_%d.json" % Time.get_ticks_usec()
	var s := SaveStore.new(path)
	s.load_data()
	s.mark_cleared("hawaii_01", "hawaii")
	s.set_setting("sound", false)
	s.set_setting("resolution", 64)
	var before := FileAccess.get_file_as_string(path)
	var real_save = app.save
	var loaded := SaveStore.new(path)
	loaded.load_data()
	app.save = loaded
	var r: int = app.resolution()
	check(r == (64 if OS.is_debug_build() else 128), "App.resolution() = %d in this %s build" % [
		r, "debug" if OS.is_debug_build() else "release"])
	check(AppScript.effective_resolution(loaded.get_setting("resolution"), false) == 128,
		"the same save in a release build runs 128")
	# 5. That setting on a 128-only stage: fallback to the 128 image.
	var stage: Dictionary = StageLoader.get_stage("hawaii_02").duplicate(true)
	stage.id = "__test_settings_only128"
	stage.landscape = {"puzzle": {"128": StageLoader.destinations().hawaii.puzzle_paths["128"]}}
	var b := StageLoader.build(stage, r)
	check(b.game != null and b.errors.is_empty() and b.game.resolution == 128,
		"128-only stage with this setting builds at 128 (requested %d)" % r)
	# Nothing above writes the save: file bytes and data are unchanged.
	check(FileAccess.get_file_as_string(path) == before, "save file unchanged (bytes)")
	var again := SaveStore.new(path)
	again.load_data()
	check(again.is_cleared("hawaii_01") and again.is_unlocked("hawaii"), "clear record and album kept")
	check(again.get_setting("sound") == false and int(again.get_setting("resolution")) == 64,
		"other settings and the saved resolution kept")
	app.save = real_save
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
