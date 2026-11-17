class_name PixelBox
extends StyleBox
## Pixel-art panel/button background: two-step stepped corners, optional rim, a flat drop
## shadow below the box and an optional darker lip along the bottom (pressable buttons).

var bg := Color.WHITE
var rim := Color.TRANSPARENT
var rim_width := 4.0
var step := 4.0
var shadow := Color.TRANSPARENT
var shadow_y := 6.0
var lip := Color.TRANSPARENT
var lip_h := 0.0


static func make(p_bg: Color, p_rim := Color.TRANSPARENT, p_shadow := Color.TRANSPARENT,
		p_lip := Color.TRANSPARENT, p_lip_h := 0.0, margin := 12.0) -> PixelBox:
	var b := PixelBox.new()
	b.bg = p_bg
	b.rim = p_rim
	b.shadow = p_shadow
	b.lip = p_lip
	b.lip_h = p_lip_h
	b.content_margin_left = margin + 4
	b.content_margin_right = margin + 4
	b.content_margin_top = margin
	b.content_margin_bottom = margin + p_lip_h * 0.5
	return b


func _draw(ci: RID, r: Rect2) -> void:
	if shadow.a > 0.0:
		_shape(ci, Rect2(r.position + Vector2(0, shadow_y), r.size), shadow)
	var inner := r
	if rim.a > 0.0 and rim_width > 0.0:
		_shape(ci, r, rim)
		inner = r.grow(-rim_width)
	if lip.a > 0.0 and lip_h > 0.0:
		_shape(ci, inner, lip)
		_shape(ci, Rect2(inner.position, inner.size - Vector2(0, lip_h)), bg)
	else:
		_shape(ci, inner, bg)


func _shape(ci: RID, r: Rect2, c: Color) -> void:
	var s := minf(step, minf(r.size.x, r.size.y) / 4.0)
	if s <= 0.0:
		return
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, r.position.y + 2 * s, r.size.x, r.size.y - 4 * s), c)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x + s, r.position.y + s, r.size.x - 2 * s, r.size.y - 2 * s), c)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x + 2 * s, r.position.y, r.size.x - 4 * s, r.size.y), c)
