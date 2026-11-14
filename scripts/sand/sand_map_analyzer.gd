class_name SandMapAnalyzer
extends RefCounted
## Puzzle-suitability metrics for a SandMap (connectivity, fragmentation).


## Returns one Dictionary per palette color:
## { color, pixels, components, largest, tiny_components (<= tiny_max px), tiny_pixels }
static func color_stats(map: SandMap, tiny_max := 3) -> Array:
	var w := map.width
	var h := map.height
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var stats := []
	for c in map.palette.size():
		stats.append({"color": map.palette[c], "pixels": 0, "components": 0,
			"largest": 0, "tiny_components": 0, "tiny_pixels": 0})
	var stack := PackedInt32Array()
	var next_label := 0
	for start in w * h:
		var cid := map.cells[start]
		if cid == SandMap.EMPTY or label[start] >= 0:
			continue
		var size := 0
		stack.clear()
		stack.append(start)
		label[start] = next_label
		while stack.size() > 0:
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			var x := i % w
			@warning_ignore("integer_division")
			var y := i / w
			for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1,
					i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if n >= 0 and label[n] < 0 and map.cells[n] == cid:
					label[n] = next_label
					stack.append(n)
		next_label += 1
		var s: Dictionary = stats[cid]
		s.pixels += size
		s.components += 1
		s.largest = maxi(s.largest, size)
		if size <= tiny_max:
			s.tiny_components += 1
			s.tiny_pixels += size
	return stats


## Fraction of 4-neighbour pairs whose colors differ (higher = noisier image).
static func edge_ratio(map: SandMap) -> float:
	var diff := 0
	var total := 0
	for y in map.height:
		for x in map.width:
			var a := map.get_id(x, y)
			if x + 1 < map.width:
				total += 1
				if map.get_id(x + 1, y) != a:
					diff += 1
			if y + 1 < map.height:
				total += 1
				if map.get_id(x, y + 1) != a:
					diff += 1
	return float(diff) / maxf(total, 1)
