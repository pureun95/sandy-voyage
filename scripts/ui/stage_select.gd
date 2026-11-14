class_name StageSelect
extends Control

signal stage_chosen(stage_id: String)
signal album_requested


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 40)
	scroll.size = Vector2(640, 1100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(640, 0)
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)
	v.add_child(UiKit.label("모래 세계 일주", 48, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label("Sandy Voyage", 24, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var dests := StageLoader.destinations()
	for dest_id in StageLoader.destination_order():
		var d: Dictionary = dests[dest_id]
		var list := StageLoader.stages().filter(func(s): return s.destination == dest_id)
		if list.is_empty():
			continue
		var head := UiKit.label("%s  %s" % [d.name_ko, "· 앨범 획득" if App.save.is_unlocked(dest_id) else ""], 30)
		head.custom_minimum_size = Vector2(0, 56)
		head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		v.add_child(head)
		for s in list:
			var mark := "  ✓" if App.save.is_cleared(s.id) else ""
			var sid: String = s.id
			v.add_child(UiKit.button(str(s.name_ko) + mark, func(): stage_chosen.emit(sid)))
	var bar := HBoxContainer.new()
	bar.position = Vector2(40, 1170)
	bar.size = Vector2(640, 80)
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)
	var album := UiKit.button("여행 앨범", func(): album_requested.emit())
	album.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(album)
	var settings := UiKit.button("설정", func(): add_child(SettingsPanel.create()))
	settings.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(settings)
