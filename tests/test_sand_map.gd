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
	for d in cfg.destinations:
		for res in ["64", "128"]:
			var path: String = dir + "/" + d.puzzle[res]
			print("[%s %s] %s" % [d.id, res, path])
			var tex := load(path) as Texture2D
			check(tex != null, "texture loads")
			if tex == null:
				continue
			var img := tex.get_image()
			var map := SandMap.from_image(img)
			check(map != null, "sand map built")
			if map == null:
				continue
			var n := int(res)
			check(map.width == n and map.height == n, "size %dx%d" % [map.width, map.height])
			check(map.palette.size() == int(d.expected_colors),
				"palette size %d == expected %d" % [map.palette.size(), d.expected_colors])
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
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
