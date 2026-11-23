extends SceneTree
## Headless test: godot --headless --path . -s res://tests/test_sand_map.gd
## Verifies sand data is generated from real image pixels (not a background image).

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _init() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/destinations.json"))
	var dir: String = cfg.asset_dir
	# Every puzzle image a destination lists is checked (existing ones: 64 and 128). 128 is
	# required; 64 is optional (new landscapes ship 128 only, StageLoader falls back to it).
	for d in cfg.destinations:
		check(d.puzzle.has("128"), "%s has a 128 puzzle image" % d.id)
		for res in d.puzzle:
			check_image("%s %s" % [d.id, res], dir + "/" + d.puzzle[res], int(res), int(d.expected_colors))
	# Per-stage landscapes (data/stages.json "landscape"), same rules.
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stages.json"))
	var n_landscapes := 0
	for s in st.stages:
		if not s.has("landscape") or not s.landscape.has("puzzle"):
			continue
		n_landscapes += 1
		var ls: Dictionary = s.landscape
		check(ls.puzzle.has("128"), "%s landscape has a 128 puzzle image" % s.id)
		var expected := -1
		if ls.has("palette"):
			expected = ls.palette.size()
		for res in ls.puzzle:
			var p := str(ls.puzzle[res])
			check_image("%s landscape %s" % [s.id, res], p if p.begins_with("res://") else dir + "/" + p,
				int(res), expected)
	print("stage landscapes checked: %d" % n_landscapes)
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


## expected_colors < 0: not checked (a landscape without its own palette uses the destination's).
func check_image(label: String, path: String, n: int, expected_colors: int) -> void:
	print("[%s] %s" % [label, path])
	var tex := load(path) as Texture2D
	check(tex != null, "texture loads")
	if tex == null:
		return
	var img := tex.get_image()
	var map := SandMap.from_image(img)
	check(map != null, "sand map built")
	if map == null:
		return
	check(map.width == n and map.height == n, "size %dx%d" % [map.width, map.height])
	if expected_colors >= 0:
		check(map.palette.size() == expected_colors,
			"palette size %d == expected %d" % [map.palette.size(), expected_colors])
	check(map.remaining() == n * n, "every pixel became a grain (%d)" % map.remaining())
	# Round trip: every grain's color equals the source pixel exactly.
	var mismatches := 0
	for y in n:
		for x in n:
			var src := img.get_pixel(x, y).to_rgba32() | 0xFF
			if map.palette[map.get_id(x, y)].to_rgba32() != src:
				mismatches += 1
	check(mismatches == 0, "grain colors match source pixels (mismatches=%d)" % mismatches)
	var counts := map.count_by_color()
	var stats := SandMapAnalyzer.color_stats(map, 3)
	for i in stats.size():
		var s: Dictionary = stats[i]
		print("    #%s px=%d comps=%d largest=%d tiny=%d" % [
			s.color.to_html(false), s.pixels, s.components, s.largest, s.tiny_components])
		check(s.pixels == counts[i], "analyzer count matches for color %d" % i)
	print("    edge ratio %.1f%%" % (SandMapAnalyzer.edge_ratio(map) * 100.0))
