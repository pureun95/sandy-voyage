class_name MapView
extends Control
## Pastel pixel world map. The land mask (assets/ui/world_land_480x180.png, made by
## tools/make_world_mask.py) is equirectangular: 0.75 degrees per cell, x = 0 at lon -30,
## y = 0 at lat 78N. A view is a rectangle of cells at a coarseness (1 = 0.75 deg, 2 = 1.5 deg)
## drawn with `cell_px` screen pixels per cell. Pins and a dotted route are drawn on top;
## labels are child Labels placed by the screens.

const MASK_PATH := "res://assets/ui/world_land_480x180.png"
const DEG := 0.75
const LON0 := -30.0
const LAT0 := 78.0

const PAL := {"sea": "#cfe7e3", "shore": "#bfdfd9", "wave": "#bddbd5", "land": "#f5e2c4",
	"land2": "#eed7b3", "coast": "#e3c39b"}
const PAL_FAINT := {"sea": "#fff6ec", "shore": "#fff6ec", "wave": "#fff6ec", "land": "#f9ebdb",
	"land2": "#f9ebdb", "coast": "#f5e0cb"}

static var _mask := PackedByteArray()
static var _mw := 0
static var _mh := 0
static var _tex_cache := {}

var view := Rect2i()      # in cells of `coarse`
var coarse := 1
var cell_px := 4.0
var palette: Dictionary = PAL
var pins: Array = []      # {lat, lon, style: done|current|open|unbuilt|premium, big: bool}
var route: Array = []     # [Vector2(lat, lon) ...] drawn as a dotted flight line
var route_next: Array = []
var _tex: Texture2D


static func _load_mask() -> void:
	if not _mask.is_empty():
		return
	var tex := load(MASK_PATH) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	_mw = img.get_width()
	_mh = img.get_height()
	_mask = img.get_data()


static func land(x: int, y: int, c: int) -> bool:
	_load_mask()
	if c <= 1:
		return x >= 0 and y >= 0 and x < _mw and y < _mh and _mask[y * _mw + x] > 127
	var n := 0
	for dy in c:
		for dx in c:
			if land(x * c + dx, y * c + dy, 1):
				n += 1
	return n * 2 >= c * c


## Mask cell (0.75 deg units, fractional) of a coordinate.
static func to_cell(lat: float, lon: float) -> Vector2:
	return Vector2(fposmod(lon - LON0, 360.0) / DEG, (LAT0 - lat) / DEG)


static func world(px_width := 720.0) -> MapView:
	var m := MapView.new()
	m.coarse = 2
	m.cell_px = px_width / 240.0
	m.view = Rect2i(0, 3, 240, 83)
	m._apply()
	return m


## A continent map from the catalog's {lon, lat, scale} centred in a `size_px` rectangle.
static func region(spec: Dictionary, size_px: Vector2) -> MapView:
	var m := MapView.new()
	m.coarse = 1
	m.cell_px = float(spec.get("scale", 4))
	var cells := Vector2i(ceili(size_px.x / m.cell_px), ceili(size_px.y / m.cell_px))
	var c := to_cell(float(spec.lat), float(spec.lon))
	m.view = Rect2i(Vector2i(roundi(c.x - cells.x * 0.5), roundi(c.y - cells.y * 0.5)), cells)
	m._apply()
	m.size = size_px
	m.custom_minimum_size = size_px
	return m


func _apply() -> void:
	size = Vector2(view.size) * cell_px
	custom_minimum_size = size
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_palette(p: Dictionary) -> void:
	palette = p
	_tex = null
	queue_redraw()


## Local position of a coordinate on this map.
func point(lat: float, lon: float) -> Vector2:
	var c := to_cell(lat, lon) / float(coarse)
	return (c - Vector2(view.position)) * cell_px


func contains(lat: float, lon: float, margin := 8.0) -> bool:
	return Rect2(Vector2.ZERO, size).grow(-margin).has_point(point(lat, lon))


func _texture() -> Texture2D:
	var key := "%s|%d|%s" % [view, coarse, palette.get("sea", "")]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(view.size.x, view.size.y, false, Image.FORMAT_RGBA8)
	var col := {}
	for k in palette:
		col[k] = Color.html(palette[k])
	for y in view.size.y:
		for x in view.size.x:
			var mx := view.position.x + x
			var my := view.position.y + y
			var c: Color
			if land(mx, my, coarse):
				var coast := not land(mx + 1, my, coarse) or not land(mx - 1, my, coarse) \
					or not land(mx, my + 1, coarse) or not land(mx, my - 1, coarse)
				c = col.coast if coast else (col.land2 if (mx * 7 + my * 13) % 23 == 0 else col.land)
			elif land(mx, my - 1, coarse) or land(mx - 1, my, coarse) or land(mx + 1, my, coarse):
				c = col.shore
			elif posmod(mx, 11) < 2 and posmod(my, 6) == 3:
				c = col.wave
			else:
				c = col.sea
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


func _draw() -> void:
	if _tex == null:
		_tex = _texture()
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(view.size) * cell_px), false)
	_dotted(route, UiKit.ACCENT_DARK, 5.0, 12.0)
	_dotted(route_next, Color("#c9a48f"), 4.0, 10.0)
	for p in pins:
		var at := point(float(p.lat), float(p.lon))
		var big: bool = p.get("big", false)
		var r := 9.0 if big else 5.0
		match str(p.style):
			"current":
				draw_rect(Rect2(at - Vector2(18, 18), Vector2(36, 36)), Color(UiKit.ACCENT, 0.33))
				_pin(at, r, UiKit.TEXT, UiKit.ACCENT)
			"done":
				_pin(at, r, UiKit.TEXT, UiKit.MINT)
			"open":
				_pin(at, r, UiKit.TEXT, Color.WHITE)
			"unbuilt":
				_pin(at, r, UiKit.TEXT_SOFT, Color("#efe5da"))
			_:
				_pin(at, r, UiKit.LOCKED, Color("#efe5da"))


func _pin(at: Vector2, r: float, rim: Color, fill: Color) -> void:
	draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), rim)
	draw_rect(Rect2(at - Vector2(r - 3, r - 3), Vector2(r - 3, r - 3) * 2.0), fill)


func _dotted(pts_ll: Array, color: Color, dot: float, gap: float) -> void:
	for i in range(pts_ll.size() - 1):
		var a := point(pts_ll[i].x, pts_ll[i].y)
		var b := point(pts_ll[i + 1].x, pts_ll[i + 1].y)
		var dist := a.distance_to(b)
		var mid := (a + b) * 0.5 - Vector2(0, dist * 0.18)
		var n := maxi(2, int(dist * 1.15 / gap))
		for k in range(1, n):
			var t := float(k) / n
			var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
			draw_rect(Rect2((p - Vector2(dot, dot) * 0.5).round(), Vector2(dot, dot)), color)
