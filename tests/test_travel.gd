extends SceneTree
## Travel catalog / progress tests: godot --headless --path . -s res://tests/test_travel.gd
## Confirmed 100-destination list, content readiness vs access vs unlock, per-stage landscape
## fallback, save compatibility (old saves, last_played), postcards and visit stamps.

var failures := 0
var passes := 0
var _tmp: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _init() -> void:
	test_catalog()
	test_built_and_access()
	test_stage_unlock()
	test_landscape_fallback()
	test_save_compat()
	test_progress_and_continue()
	for p in _tmp:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("PASSED %d  FAILURES %d" % [passes, failures])
	quit(1 if failures > 0 else 0)


func fresh_save() -> SaveStore:
	var path := "user://test_travel_%d.json" % Time.get_ticks_usec()
	_tmp.append(path)
	var s := SaveStore.new(path)
	s.load_data()
	return s


func test_catalog() -> void:
	print("[catalog]")
	var list := TravelCatalog.destinations()
	check(list.size() == 100, "100 destinations (%d)" % list.size())
	var ids := {}
	for d in list:
		ids[d.id] = true
	check(ids.size() == 100, "ids unique")
	var free := list.filter(func(d): return d.access == "free").map(func(d): return d.id)
	var want := ["hawaii", "fuji", "london", "paris", "seoul", "giza", "sydney", "venice", "machu_picchu", "new_york"]
	check(free.size() == 10 and want.all(func(i): return free.has(i)), "free = the 10 confirmed destinations %s" % [free])
	check(TravelCatalog.free_order() == want, "free order follows the confirmed list")
	var counts := {}
	for c in TravelCatalog.continents():
		counts[c.id] = TravelCatalog.in_continent(c.id).size()
	check(counts == {"asia": 30, "europe": 25, "north_america": 17, "south_america": 12, "africa": 10, "oceania": 6},
		"continent counts 30/25/17/12/10/6 %s" % [counts])
	check(TravelCatalog.destination("hawaii").continent == "north_america", "Hawaii is in North America (confirmed list)")
	check(TravelCatalog.destination("gyeongju").name_ko == "경주" and TravelCatalog.destination("seoul").access == "free",
		"Korea: Seoul (free), Gyeongju listed")
	for id in ["hawaii", "fuji", "london"]:
		var d := TravelCatalog.destination(id)
		check(d.name_ko == StageLoader.destinations()[id].name_ko, "existing destination '%s' keeps its id and name" % id)
	var bad := list.filter(func(d): return absf(d.lat) > 78.0 or absf(d.lon) > 180.0)
	check(bad.is_empty(), "coordinates in range")


func test_built_and_access() -> void:
	print("[built / access]")
	var built := TravelCatalog.destinations().filter(func(d): return TravelCatalog.is_built(d.id)).map(func(d): return d.id)
	check(built == ["fuji", "london", "hawaii"], "only destinations with art + stages are built: %s" % [built])
	for sid in ["hawaii_01", "hawaii_02", "hawaii_03", "fuji_01", "fuji_02", "fuji_03", "london_01", "london_02", "london_03"]:
		check(TravelCatalog.is_stage_built(sid), "%s built" % sid)
	check(not TravelCatalog.is_stage_built("paris_01") and not TravelCatalog.is_stage_built("hawaii_04"), "catalog-only stages are not built")
	var s := fresh_save()
	var none := {"travel_pass": false}
	var with_pass := {"travel_pass": true}
	check(TravelCatalog.stage_state(s, "paris", 1, none) == "unbuilt", "free but not built -> unbuilt (not playable)")
	check(TravelCatalog.stage_state(s, "edinburgh", 1, with_pass) == "unbuilt", "premium + pass but not built -> still unbuilt")
	check(TravelCatalog.is_premium("edinburgh") and not TravelCatalog.has_access("edinburgh", none), "premium needs the pass")
	check(TravelCatalog.has_access("edinburgh", with_pass) and TravelCatalog.has_access("paris", none), "pass grants premium; free always accessible")
	check(not TravelCatalog.can_play(s, "edinburgh_01", with_pass) and not TravelCatalog.can_play(s, "paris_01", none), "can_play false for unbuilt")


func test_stage_unlock() -> void:
	print("[stage unlock 1 -> 2 -> 3]")
	var s := fresh_save()
	var e := {}
	check(TravelCatalog.stage_state(s, "fuji", 1, e) == "open", "stage 1 open on a fresh save")
	check(TravelCatalog.stage_state(s, "fuji", 2, e) == "locked" and TravelCatalog.stage_state(s, "fuji", 3, e) == "locked", "2 and 3 locked")
	s.mark_cleared("fuji_01", "fuji")
	check(TravelCatalog.stage_state(s, "fuji", 1, e) == "cleared" and TravelCatalog.stage_state(s, "fuji", 2, e) == "open", "clearing 1 opens 2")
	check(TravelCatalog.stage_state(s, "fuji", 3, e) == "locked", "3 still locked")
	check(TravelCatalog.next_open_stage(s, "fuji", e) == "fuji_02", "next open stage is fuji_02")
	# Old progress (no locks before): london_03 cleared without london_02 stays playable.
	var old := fresh_save()
	old.mark_cleared("london_03", "london")
	check(TravelCatalog.stage_state(old, "london", 3, e) == "cleared", "previously cleared stage 3 stays open (cleared)")
	check(TravelCatalog.stage_state(old, "london", 2, e) == "locked" and TravelCatalog.stage_state(old, "london", 1, e) == "open",
		"its earlier stages follow the normal rule")
	check(TravelCatalog.can_play(old, "london_03", e) and not TravelCatalog.can_play(old, "london_02", e), "can_play matches the states")


func test_landscape_fallback() -> void:
	print("[per-stage landscape]")
	var stage := StageLoader.get_stage("hawaii_02")
	var art := StageLoader.stage_destination(stage)
	check(art == StageLoader.destinations().hawaii, "no landscape key -> destination art (unchanged)")
	check(TravelCatalog.postcard_path("hawaii", 2) == StageLoader.destinations().hawaii.album_path, "postcard falls back to destination album")
	var own := stage.duplicate(true)
	own.id = "hawaii_test_own"
	own.landscape = {"album": "res://assets/destinations/Sandy_Voyage_Assets_v2/fuji_album_1024.png",
		"puzzle": {"128": "hawaii_puzzle_128_5colors.png"}}
	var a2 := StageLoader.stage_destination(own)
	check(a2.album_path.ends_with("fuji_album_1024.png") and a2.puzzle_paths.size() == 1
		and str(a2.puzzle_paths["128"]).ends_with("Sandy_Voyage_Assets_v2/hawaii_puzzle_128_5colors.png"),
		"stage landscape overrides album/puzzle (relative paths resolve to asset_dir)")
	check(a2.palette_keys == StageLoader.destinations().hawaii.palette_keys, "palette falls back to the destination's")
	check(StageLoader.destinations().hawaii.album_path.ends_with("hawaii_album_1024.png"), "destination dict itself not modified")
	var built := StageLoader.build(own, 128)
	check(built.game != null and built.errors.is_empty(), "stage with its own landscape builds")
	check(built.game.destination.album_path.ends_with("fuji_album_1024.png"), "game uses the stage's postcard")
	var orig := StageLoader.build(stage, 128)
	check(orig.game.total == 16384 and orig.game.destination.id == "hawaii", "existing stage builds as before")


func test_save_compat() -> void:
	print("[save compatibility]")
	var path := "user://test_travel_old_%d.json" % Time.get_ticks_usec()
	_tmp.append(path)
	# A version-1 save written by the previous build (no last_played key).
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1,
		"cleared": {"hawaii_01": {"at": 1000}, "hawaii_02": {"at": 2000}, "hawaii_03": {"at": 3000}, "london_02": {"at": 4000}},
		"album": {"hawaii": {"at": 1000, "first_stage": "hawaii_01"}, "london": {"at": 4000, "first_stage": "london_02"}},
		"settings": {"resolution": 64, "sound": false}}))
	f.close()
	var s := SaveStore.new(path)
	s.load_data()
	check(s.is_cleared("hawaii_03") and s.is_cleared("london_02") and s.is_unlocked("london"), "old cleared/album records load")
	check(s.last_played() == "" and int(s.get_setting("resolution")) == 64, "missing last_played -> default, settings kept")
	check(TravelCatalog.cleared_count(s, "hawaii") == 3 and TravelCatalog.is_visited(s, "hawaii"), "postcards/stamp derived from old clears")
	check(TravelCatalog.cleared_count(s, "london") == 1 and not TravelCatalog.is_visited(s, "london"), "partial destination: 1/3, no stamp")
	s.set_last_played("london_02")
	s.mark_cleared("fuji_01", "fuji")
	var s2 := SaveStore.new(path)
	s2.load_data()
	check(s2.last_played() == "london_02", "last_played persists")
	check(s2.data.album.fuji.first_stage == "fuji_01" and s2.data.album.hawaii.at == 1000, "album first-clear record kept as before")
	check(s2.data.cleared.size() == 5 and s2.clear_time("hawaii_02") == 2000, "clear records and times intact")


func test_progress_and_continue() -> void:
	print("[progress / continue]")
	var s := fresh_save()
	var e := {}
	check(TravelCatalog.continue_stage(s, e) == "hawaii_01", "fresh save continues at hawaii_01 (first in free order)")
	check(TravelCatalog.current_destination(s) == "", "no current destination yet")
	s.set_last_played("london_01")
	s.mark_cleared("london_01", "london")
	check(TravelCatalog.current_destination(s) == "london" and TravelCatalog.continue_stage(s, e) == "london_02",
		"continue = next open stage of the last played destination")
	s.mark_cleared("london_02", "london")
	s.mark_cleared("london_03", "london")
	check(TravelCatalog.continue_stage(s, e) == "hawaii_01", "destination done -> next destination in free order")
	check(TravelCatalog.total_stamps(s) == 1 and TravelCatalog.total_postcards(s) == 3, "1 stamp, 3 postcards")
	var eu := TravelCatalog.continent_progress(s, "europe")
	check(eu.total == 25 and eu.free == 3 and eu.built == 1 and eu.stamps == 1 and eu.postcards == 3, "europe progress %s" % [eu])
	s.data.cleared["hawaii_01"] = {"at": 1}
	s.data.album["hawaii"] = {"at": 1, "first_stage": "hawaii_01"}
	check(TravelCatalog.visit_route(s) == ["hawaii", "london"], "route follows first-clear time")
	s.set_last_played("nowhere_01")
	check(TravelCatalog.current_destination(s) == "", "unknown last_played is ignored")
	for sid in ["hawaii_02", "hawaii_03", "fuji_01", "fuji_02", "fuji_03"]:
		s.mark_cleared(sid, TravelCatalog.split_stage_id(sid).destination)
	check(TravelCatalog.continue_stage(s, e) == "", "all built stages cleared -> nothing to continue")
	check(TravelCatalog.stage_title("london_02") == "빨간 버스", "short stage title")
	check(TravelCatalog.split_stage_id("machu_picchu_02") == {"destination": "machu_picchu", "n": 2}, "stage id split with underscores in the id")
