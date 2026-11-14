class_name SandMap
extends RefCounted
## Sand grain data built from the actual pixels of a puzzle image.
## One pixel = one sand grain. Each grain stores a color id (index into `palette`).
## EMPTY marks a cell with no sand (collected or never filled).

const EMPTY := 255

var width := 0
var height := 0
var palette: Array[Color] = []
## Row-major color ids, size width*height. Values are palette indices or EMPTY.
var cells := PackedByteArray()


static func from_image(image: Image, max_colors := 16) -> SandMap:
	var map := SandMap.new()
	if image == null or image.is_empty():
		push_error("SandMap.from_image: empty image")
		return null
	var img := image
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	map.width = img.get_width()
	map.height = img.get_height()
	map.cells.resize(map.width * map.height)

	# Exact-color palette, ordered by first appearance; then re-sorted by frequency.
	var index_of := {}
	var counts: Array[int] = []
	var raw_ids := PackedInt32Array()
	raw_ids.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				raw_ids[y * map.width + x] = -1
				continue
			var key := c.to_rgba32() | 0xFF  # ignore alpha detail once opaque
			if not index_of.has(key):
				index_of[key] = counts.size()
				counts.append(0)
			var id: int = index_of[key]
			counts[id] += 1
			raw_ids[y * map.width + x] = id

	if counts.size() > max_colors:
		push_error("SandMap.from_image: %d colors exceeds max %d (image is not quantized?)" % [counts.size(), max_colors])
		return null

	var order: Array = range(counts.size())
	order.sort_custom(func(a, b): return counts[a] > counts[b])
	var id_remap := PackedInt32Array()
	id_remap.resize(counts.size())
	var keys := index_of.keys()
	var key_for_id := {}
	for k in keys:
		key_for_id[index_of[k]] = k
	for new_id in order.size():
		var old_id: int = order[new_id]
		id_remap[old_id] = new_id
		map.palette.append(Color.hex(key_for_id[old_id]))
	for i in raw_ids.size():
		map.cells[i] = EMPTY if raw_ids[i] < 0 else id_remap[raw_ids[i]]
	return map


## Builds a map whose color ids are indices into `canonical` (the destination's named palette).
## Each exact image color is mapped to its nearest canonical color. The render palette keeps the
## image's own exact colors, so a 64px and a 128px quantization share ids but keep their pixels.
## Returns null when a color is farther than `max_dist` from every canonical color, or when two
## image colors would collapse onto the same canonical color.
static func from_image_with_palette(image: Image, canonical: Array[Color], max_dist := 0.12) -> SandMap:
	var map := from_image(image, canonical.size())
	if map == null:
		return null
	var id_remap := PackedInt32Array()
	id_remap.resize(map.palette.size())
	var used := {}
	for i in map.palette.size():
		var best := -1
		var best_d := INF
		for j in canonical.size():
			var d := color_distance(map.palette[i], canonical[j])
			if d < best_d:
				best_d = d
				best = j
		if best_d > max_dist:
			push_error("SandMap: color %s is %.3f from nearest palette color" % [map.palette[i].to_html(false), best_d])
			return null
		if used.has(best):
			push_error("SandMap: two image colors map to palette index %d" % best)
			return null
		used[best] = true
		id_remap[i] = best
	var render: Array[Color] = canonical.duplicate()
	for i in map.palette.size():
		render[id_remap[i]] = map.palette[i]
	map.palette = render
	for k in map.cells.size():
		if map.cells[k] != EMPTY:
			map.cells[k] = id_remap[map.cells[k]]
	return map


static func color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func duplicate_map() -> SandMap:
	var m := SandMap.new()
	m.width = width
	m.height = height
	m.palette = palette.duplicate()
	m.cells = cells.duplicate()
	return m


static func from_texture_path(path: String, max_colors := 16) -> SandMap:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("SandMap: cannot load %s" % path)
		return null
	return from_image(tex.get_image(), max_colors)


func get_id(x: int, y: int) -> int:
	return cells[y * width + x]


func set_id(x: int, y: int, id: int) -> void:
	cells[y * width + x] = id


func count_by_color() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(palette.size())
	for v in cells:
		if v != EMPTY:
			out[v] += 1
	return out


func remaining() -> int:
	var n := 0
	for v in cells:
		if v != EMPTY:
			n += 1
	return n


func to_image() -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var id := get_id(x, y)
			img.set_pixel(x, y, Color(0, 0, 0, 0) if id == EMPTY else palette[id])
	return img
