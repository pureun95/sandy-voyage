class_name PostcardImage
extends Control
## A picture that fills its rect (cover crop). The texture comes from App.thumbs and is only
## requested while the control is on or near the screen; far off-screen it lets go of it, so
## long scrolling lists hold only nearby thumbnails. Without a picture it draws a blank
## postcard placeholder with `placeholder` text (never a generated landscape).

var path := ""
var placeholder := ""
var dim := false          # grey-out (locked / not yet collected)
var full_res := false     # load the original (single large view) instead of a thumbnail
var _tex: Texture2D
var _check := 0.0


static func create(p_path: String, min_size: Vector2, p_placeholder := "", p_dim := false) -> PostcardImage:
	var p := PostcardImage.new()
	p.path = p_path
	p.placeholder = p_placeholder
	p.dim = p_dim
	p.custom_minimum_size = min_size
	p.size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	return p


func _ready() -> void:
	if full_res and path != "":
		_tex = load(path)
	elif path != "":
		App.thumbs.thumb_ready.connect(_on_ready)
		_refresh()
	if placeholder != "" and path == "":
		var l := UiKit.label(placeholder, 18, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		l.offset_left = 10
		l.offset_right = -10
		add_child(l)


func _process(delta: float) -> void:
	if full_res or path == "":
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		_refresh()


func _refresh() -> void:
	var vis := get_viewport_rect()
	var r := get_global_rect()
	var near := is_visible_in_tree() and r.intersects(vis.grow(vis.size.y))
	var far := not is_visible_in_tree() or not r.intersects(vis.grow(vis.size.y * 2.0))
	if near and _tex == null:
		_tex = App.thumbs.get_thumb(path)
		if _tex != null:
			queue_redraw()
	elif far and _tex != null:
		_tex = null
		queue_redraw()


func _on_ready(p: String) -> void:
	if p == path and _tex == null:
		_check = 0.0


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _tex == null:
		draw_rect(r, UiKit.PIP_OFF.lightened(0.45))
		# Blank postcard: stamp box and two address lines.
		draw_rect(Rect2(size.x - 34, 10, 24, 28), UiKit.PIP_OFF, false, 3.0)
		if placeholder == "":
			return
		draw_rect(Rect2(14, size.y - 22, size.x * 0.45, 3), UiKit.PIP_OFF)
		return
	var ts := _tex.get_size()
	var k := maxf(size.x / ts.x, size.y / ts.y)
	var src := Rect2((ts - size / k) * 0.5, size / k)
	draw_texture_rect_region(_tex, r, src, Color(1, 1, 1, 0.42) if dim else Color.WHITE)
	if dim:
		draw_rect(r, Color(UiKit.PIP_OFF, 0.35))
