extends SceneTree
## Checks a candidate landscape (album + puzzle PNG) against the game's real loading code,
## without touching data/*.json. Run --import first after adding images.
##   godot --headless --path . -s res://tests/check_landscape_candidate.gd -- \
##       res://assets/destinations/gyeongju/gyeongju_s1_puzzle128.png \
##       res://assets/destinations/gyeongju/gyeongju_s1_album256.png

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <puzzle.png> <album.png> [expected_album_size]")
		quit(2)
		return
	var puzzle_path := args[0]
	var album_path := args[1]
	var album_size := int(args[2]) if args.size() > 2 else 256

	print("[album] ", album_path)
	var atex := load(album_path) as Texture2D
	check(atex != null, "album loads as Texture2D")
	if atex != null:
		check(atex.get_width() == album_size and atex.get_height() == album_size,
			"album size %dx%d" % [atex.get_width(), atex.get_height()])

	print("[puzzle] ", puzzle_path)
	var tex := load(puzzle_path) as Texture2D
	check(tex != null, "puzzle loads as Texture2D")
	if tex == null:
		quit(1)
		return
	var img := tex.get_image()
	var n := img.get_width()
	check(n == 128 and img.get_height() == 128, "puzzle size %dx%d" % [n, img.get_height()])
	var map := SandMap.from_image(img, 8)
	check(map != null, "SandMap.from_image (max 8 colors)")
	if map == null:
		quit(1)
		return
	check(map.remaining() == n * n, "every pixel is a grain (%d)" % map.remaining())
	var mismatches := 0
	for y in n:
		for x in n:
			if map.palette[map.get_id(x, y)].to_rgba32() != (img.get_pixel(x, y).to_rgba32() | 0xFF):
				mismatches += 1
	check(mismatches == 0, "grain colors == source pixels (mismatches=%d)" % mismatches)

	# Same path the game uses: a stage "landscape" override (in memory only) -> load_map.
	var entries := []
	for i in map.palette.size():
		entries.append({"key": "c%d" % i, "name_ko": "c%d" % i, "color": "#" + map.palette[i].to_html(false)})
	var stage := {"id": "__candidate_check", "destination": StageLoader.destination_order()[0],
		"landscape": {"puzzle": {"128": puzzle_path}, "album": album_path, "palette": entries}}
	var dest := StageLoader.stage_destination(stage)
	check(dest.get("album_path", "") == album_path, "stage_destination resolves res:// album path")
	var m2 := StageLoader.load_map(dest, 128)
	check(m2 != null, "StageLoader.load_map with palette (from_image_with_palette)")

	var counts := map.count_by_color()
	var stats := SandMapAnalyzer.color_stats(map, 3)
	var min_pair := INF
	for i in map.palette.size():
		for j in range(i + 1, map.palette.size()):
			min_pair = minf(min_pair, SandMap.color_distance(map.palette[i], map.palette[j]))
	for i in stats.size():
		var s: Dictionary = stats[i]
		print("    #%s px=%d (%.1f%%) comps=%d largest=%d tiny=%d" % [s.color.to_html(false), s.pixels,
			100.0 * s.pixels / (n * n), s.components, s.largest, s.tiny_components])
		check(s.pixels == counts[i], "analyzer count matches color %d" % i)
	print("    colors %d, edge ratio %.1f%%, min RGB distance %.3f (from_image_with_palette max_dist 0.12)" % [
		map.palette.size(), SandMapAnalyzer.edge_ratio(map) * 100.0, min_pair])
	# Game rule: from_image_with_palette accepts an image color within 0.12 of a palette color,
	# so palette colors closer than that could swallow each other. (Existing hawaii/fuji/london
	# closest pairs: 0.213 / 0.221 / 0.206. Perceptual dE2000 is checked by tools/landscape_pipeline.py.)
	check(min_pair > 0.12, "sand colors farther apart than max_dist 0.12 (closest %.3f)" % min_pair)
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
