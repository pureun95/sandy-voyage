class_name HomeScreen
extends Control
## Home (design A1): title, three overlapping postcards (current destination in front),
## "now travelling" card, continue / world map / album, settings.

signal stage_chosen(stage_id: String)
signal map_requested
signal album_requested

var continue_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var save := App.save
	var ent := App.entitlements
	continue_id = TravelCatalog.continue_stage(save, ent)
	var cur := TravelCatalog.current_destination(save)
	var fresh: bool = save.data.cleared.is_empty() and cur == ""
	var front := cur
	if front == "" and continue_id != "":
		front = TravelCatalog.split_stage_id(continue_id).destination

	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	# Depth layer 1: a faint map behind the postcards.
	var map := MapView.world(720.0)
	map.set_palette(MapView.PAL_FAINT)
	map.position = Vector2(0, 470)
	add_child(map)

	var stamps := UiKit.chip("스탬프 %d / %d" % [TravelCatalog.total_stamps(save), TravelCatalog.destinations().size()])
	stamps.position = Vector2(28, 30)
	add_child(stamps)
	var gear := UiKit.icon_button("gear", func(): add_child(SettingsPanel.create()))
	gear.position = Vector2(628, 28)
	add_child(gear)

	var t := UiKit.title("모래 세계 일주", 66, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_color_override("font_shadow_color", UiKit.PIP_OFF)
	t.add_theme_constant_override("shadow_offset_x", 4)
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.position = Vector2(0, 112)
	t.size = Vector2(720, 90)
	add_child(t)
	var sub := UiKit.title("S A N D Y   V O Y A G E", 18, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 200)
	sub.size = Vector2(720, 30)
	add_child(sub)

	_postcards(front)
	_now_card(cur, fresh)

	var main_btn: Button
	if continue_id != "":
		var label := "여행 시작하기" if fresh else "이어서 여행하기"
		main_btn = UiKit.px_button(label, func(): stage_chosen.emit(continue_id), "primary", 32, "plane")
	else:
		main_btn = UiKit.px_button("세계 지도 보기", func(): map_requested.emit(), "primary", 32, "map")
	main_btn.position = Vector2(60, 960)
	main_btn.size = Vector2(600, 96)
	add_child(main_btn)
	var row := HBoxContainer.new()
	row.position = Vector2(60, 1086)
	row.size = Vector2(600, 80)
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	var m := UiKit.px_button("세계 지도", func(): map_requested.emit(), "secondary", 26, "map")
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(m)
	var a := UiKit.px_button("여행 앨범  %d" % TravelCatalog.total_postcards(save), func(): album_requested.emit(), "secondary", 26, "book")
	a.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(a)


## Front: the current destination. Behind: two other built destinations, most recent first.
func _postcards(front: String) -> void:
	var others: Array = TravelCatalog.visit_route(App.save)
	others.reverse()
	for d in TravelCatalog.free_order():
		others.append(d)
	for d in TravelCatalog.destinations():
		others.append(d.id)
	var sides: Array = []
	for d in others:
		if d != front and not sides.has(d) and TravelCatalog.cover_path(d) != "":
			sides.append(d)
		if sides.size() == 2:
			break
	var specs := [[Vector2(42, 332), -9.0, 250.0], [Vector2(428, 318), 8.0, 250.0]]
	for i in sides.size():
		var d: String = sides[i]
		var pc := UiKit.postcard(TravelCatalog.cover_path(d), Vector2(specs[i][2], specs[i][2]), _name(d), "", false, 12.0, 20)
		pc.position = specs[i][0]
		pc.rotation_degrees = specs[i][1]
		add_child(pc)
		if TravelCatalog.is_visited(App.save, d):
			var st := StampMark.create("VISITED\n%s" % _short(d), 88, -18.0, Color(UiKit.STAMP, 0.85))
			st.position = pc.position + Vector2(-6 if i == 0 else 190, -26)
			add_child(st)
	if front == "":
		return
	var main_pc := UiKit.postcard(TravelCatalog.cover_path(front), Vector2(410, 410), _caption(front), "", false, 14.0, 22)
	main_pc.position = Vector2(141, 286)
	main_pc.rotation_degrees = -2.0
	add_child(main_pc)
	var n := TravelCatalog.cleared_count(App.save, front)
	var st2 := StampMark.create("%d/%d\n%s" % [n, TravelCatalog.stages_per_destination(), _short(front)], 108, 12.0)
	st2.position = Vector2(520, 600)
	add_child(st2)


func _now_card(cur: String, fresh: bool) -> void:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UiKit.card_box())
	card.position = Vector2(60, 806)
	card.size = Vector2(600, 122)
	add_child(card)
	var head := "지금 여행 중"
	var line := ""
	var dest := cur
	var sid := App.save.last_played()
	if cur != "" and continue_id.begins_with(cur + "_"):
		sid = continue_id  # show the stage that "continue" opens
	if fresh and continue_id != "":
		head = "첫 여행지"
		sid = continue_id
		dest = TravelCatalog.split_stage_id(sid).destination
	elif continue_id == "" and cur == "":
		head = "여행 기록"
		line = "준비된 여행지를 모두 다녀왔어요"
	if line == "" and dest != "":
		var n := int(TravelCatalog.split_stage_id(sid).n)
		line = "%s  ·  %d. %s" % [_name(dest), n, TravelCatalog.stage_title(sid)]
	var h := UiKit.title(head, 18, UiKit.TEXT_SOFT)
	h.position = Vector2(26, 16)
	card.add_child(h)
	var l := UiKit.title(line, 30)
	l.position = Vector2(26, 52)
	l.size = Vector2(548, 44)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(l)
	if dest != "":
		var p := UiKit.pips(TravelCatalog.cleared_count(App.save, dest), TravelCatalog.stages_per_destination(),
			int(TravelCatalog.split_stage_id(continue_id).n) - 1 if continue_id.begins_with(dest + "_") else -1)
		p.position = Vector2(500, 18)
		card.add_child(p)


static func _name(dest_id: String) -> String:
	return str(TravelCatalog.destination(dest_id).get("name_ko", dest_id))


static func _short(dest_id: String) -> String:
	var en := str(StageLoader.destinations().get(dest_id, {}).get("name_en", ""))
	return en.to_upper() if en != "" else _name(dest_id)


static func _caption(dest_id: String) -> String:
	var en := str(StageLoader.destinations().get(dest_id, {}).get("name_en", ""))
	return "%s · %s" % [_name(dest_id), en.to_upper()] if en != "" else _name(dest_id)
