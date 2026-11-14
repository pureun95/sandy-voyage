class_name AlbumScreen
extends Control
## Travel album: one card per destination from data/destinations.json.
## Unlocked cards show the album art; locked cards show a lock placeholder.

signal back_requested


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var title := UiKit.label("여행 앨범", 44, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 36)
	title.size = Vector2(720, 60)
	add_child(title)
	var ids := StageLoader.destination_order()
	var got := ids.filter(func(i): return App.save.is_unlocked(i)).size()
	var sub := UiKit.label("%d / %d 곳" % [got, ids.size()], 24, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 98)
	sub.size = Vector2(720, 36)
	add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 150)
	scroll.size = Vector2(640, 1000)
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)
	var dests := StageLoader.destinations()
	for id in ids:
		grid.add_child(_card(dests[id]))

	var back := UiKit.button("뒤로", func(): back_requested.emit())
	back.position = Vector2(40, 1170)
	back.size = Vector2(640, 80)
	add_child(back)


func _card(d: Dictionary) -> Control:
	var unlocked := App.save.is_unlocked(d.id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(310, 370)
	var v := VBoxContainer.new()
	panel.add_child(v)
	if unlocked:
		var img := TextureRect.new()
		img.texture = load(d.album_path)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		img.custom_minimum_size = Vector2(270, 270)
		img.mouse_filter = MOUSE_FILTER_STOP
		img.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				_show_full(d))
		v.add_child(img)
		v.add_child(UiKit.label(d.name_ko, 28, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var at := int(App.save.data.album[d.id].get("at", 0))
		var date := Time.get_date_string_from_unix_time(at) if at > 0 else ""
		v.add_child(UiKit.label(date, 18, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var lock := Panel.new()
		lock.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, 18))
		lock.custom_minimum_size = Vector2(270, 270)
		var q := UiKit.label("잠김", 30, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		lock.add_child(q)
		v.add_child(lock)
		v.add_child(UiKit.label("???", 28, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiKit.label("스테이지를 완료하면 열려요", 18, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	return panel


func _show_full(d: Dictionary) -> void:
	var o := Control.new()
	o.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(UiKit.BG, 0.95)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	o.add_child(dim)
	var img := TextureRect.new()
	img.texture = load(d.album_path)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img.position = Vector2(20, 280)
	img.size = Vector2(680, 680)
	o.add_child(img)
	var title_label := UiKit.label(d.name_ko, 40, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	title_label.position = Vector2(0, 200)
	title_label.size = Vector2(720, 60)
	o.add_child(title_label)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			o.queue_free())
	add_child(o)
