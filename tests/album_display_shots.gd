extends SceneTree
## Renders the album full view (PostcardImage, full_res, LINEAR, 680x680 like AlbumScreen._full)
## at a 1.5x device scale (1080p phone) and saves the frame. Needs a window (not --headless).
##   godot --path . -s res://tests/album_display_shots.gd -- <out.png>
## Columns: 1024 album (unchanged path) | 256 album, old path (raw LINEAR) | 256 album, new path.

const A1024 := "res://assets/destinations/Sandy_Voyage_Assets_v2/london_album_1024.png"
const A256 := "res://assets/destinations/gyeongju/gyeongju_s1_v2_album256.png"


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://album_display.png"
	await process_frame
	var Postcard: GDScript = load("res://scripts/ui/postcard_image.gd")
	DisplayServer.window_set_size(Vector2i(3150, 1110))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_size = Vector2i(2100, 740)
	var bg := ColorRect.new()
	bg.color = Color(0.96, 0.94, 0.92)
	bg.size = Vector2(2100, 740)
	root.add_child(bg)
	var titles := ["1024 (London) - unchanged", "256 old: raw texture + LINEAR", "256 new: x4 NEAREST, then LINEAR"]
	for i in 3:
		var x := 10 + i * 700
		var l := Label.new()
		l.text = titles[i]
		l.position = Vector2(x, 8)
		l.add_theme_color_override("font_color", Color(0.2, 0.18, 0.2))
		l.add_theme_font_size_override("font_size", 22)
		root.add_child(l)
		var c: Control
		if i == 1:
			var tr := TextureRect.new()   # the previous behaviour for comparison
			tr.texture = load(A256)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			c = tr
		else:
			var p: Control = Postcard.new()
			p.path = A1024 if i == 0 else A256
			p.full_res = true
			c = p
		c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		c.position = Vector2(x, 45)
		c.size = Vector2(680, 680)
		root.add_child(c)
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved %s %s" % [out, img.get_size()])
	quit()
