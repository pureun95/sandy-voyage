class_name DestinationSheet
extends Control
## Destination bottom sheet (design A4): big postcard, visit stamp, the three stage postcards
## with their state (cleared / open / locked / not built yet / needs the travel pass).

signal stage_chosen(stage_id: String)
signal album_requested

const TOP := 150.0

var destination_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var save := App.save
	var ent := App.entitlements
	var d := TravelCatalog.destination(destination_id)
	var dim := ColorRect.new()
	dim.color = Color(UiKit.TEXT, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.position.y < TOP:
			queue_free())
	add_child(dim)
	var sheet := Panel.new()
	sheet.add_theme_stylebox_override("panel", PixelBox.make(UiKit.BG, UiKit.RIM))
	sheet.position = Vector2(0, TOP)
	sheet.size = Vector2(720, 1280 - TOP + 20)
	add_child(sheet)
	var handle := ColorRect.new()
	handle.color = UiKit.RIM
	handle.position = Vector2(315, 18)
	handle.size = Vector2(90, 8)
	sheet.add_child(handle)

	var cover := TravelCatalog.cover_path(destination_id)
	var pc := UiKit.postcard(cover, Vector2(632, 286), "", str(d.get("subject_ko", "")), false, 14.0)
	pc.position = Vector2(30, 40)
	pc.rotation_degrees = -1.0
	sheet.add_child(pc)

	var en := str(StageLoader.destinations().get(destination_id, {}).get("name_en", ""))
	var name_l := UiKit.title(str(d.get("name_ko", "")), 40)
	name_l.position = Vector2(30, 368)
	sheet.add_child(name_l)
	if en != "":
		var en_l := UiKit.title(en.to_upper(), 16, UiKit.TEXT_SOFT)
		en_l.position = Vector2(42 + name_l.get_combined_minimum_size().x, 388)
		sheet.add_child(en_l)
	var cont := TravelCatalog.continent(str(d.get("continent", "")))
	var premium := TravelCatalog.is_premium(destination_id)
	var info := UiKit.label("%s · %s · %s" % [d.get("country_ko", ""), cont.get("name_ko", ""),
		"프리미엄 여행지" if premium else "무료 여행지"], 19, UiKit.TEXT_SOFT)
	info.position = Vector2(32, 424)
	sheet.add_child(info)
	var cleared := TravelCatalog.cleared_count(save, destination_id)
	var total := TravelCatalog.stages_per_destination()
	var stamp: StampMark
	if TravelCatalog.is_visited(save, destination_id):
		stamp = StampMark.create("VISITED\n%s" % (en.to_upper() if en != "" else d.get("name_ko", "")), 104, 10.0)
	else:
		stamp = StampMark.create("%d/%d" % [cleared, total], 96, 10.0, UiKit.STAMP if cleared > 0 else UiKit.LOCKED, cleared == 0)
	stamp.position = Vector2(588 - stamp.size.x * 0.5 + 20, 352)
	sheet.add_child(stamp)

	var built := TravelCatalog.is_built(destination_id)
	var access := TravelCatalog.has_access(destination_id, ent)
	var y := 466.0
	if not built or not access:
		var text := "아직 준비 중인 여행지예요. 엽서가 완성되면 떠날 수 있어요."
		if not access:
			text = "여행 패스로 열리는 프리미엄 여행지예요." if built else "프리미엄 여행지예요. 엽서를 준비하고 있어요."
		var note := UiKit.label(text, 19, UiKit.TEXT)
		note.position = Vector2(32, y)
		note.size = Vector2(500, 30)
		sheet.add_child(note)
		if not access:
			var info_b := UiKit.px_button("여행 패스 안내", func(): PassInfo.open(self), "chip", 17, "lock")
			info_b.position = Vector2(500, y - 6)
			sheet.add_child(info_b)
		y += 42.0
	var q := UiKit.title("어디부터 둘러볼까요?", 22)
	q.position = Vector2(30, y)
	sheet.add_child(q)
	y += 44.0
	for i in total:
		var card := _stage_card(i + 1)
		card.position = Vector2(30 + i * 222, y)
		sheet.add_child(card)

	var row := HBoxContainer.new()
	row.position = Vector2(30, y + 340)
	row.size = Vector2(660, 80)
	row.add_theme_constant_override("separation", 16)
	sheet.add_child(row)
	var alb := UiKit.px_button("앨범에서 %s 엽서 보기" % d.get("name_ko", ""), func(): album_requested.emit(), "secondary", 22, "book")
	alb.size_flags_horizontal = SIZE_EXPAND_FILL
	alb.size_flags_stretch_ratio = 2.0
	row.add_child(alb)
	var close := UiKit.px_button("닫기", func(): queue_free(), "secondary", 22)
	close.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(close)


func _stage_card(n: int) -> Control:
	var sid := TravelCatalog.stage_id(destination_id, n)
	var state := TravelCatalog.stage_state(App.save, destination_id, n, App.entitlements)
	var open := state == "open"
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UiKit.card_box(open, Color("#f2b598") if open else UiKit.SHADOW_SOFT))
	card.size = Vector2(208, 318)
	var built := state != "unbuilt"
	var path := TravelCatalog.postcard_path(destination_id, n) if built else ""
	var img := PostcardImage.create(path, Vector2(184, 124), "새 엽서 준비 중" if not built else "",
		state in ["locked", "pass"])
	img.position = Vector2(12, 12)
	card.add_child(img)
	var num := UiKit.title(" %d " % n, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiKit.PAPER
	num.add_theme_stylebox_override("normal", sb)
	num.position = Vector2(18, 18)
	card.add_child(num)
	if state == "cleared":
		var st := StampMark.create("CLEAR", 70, -12.0)
		st.position = Vector2(118, 58)
		card.add_child(st)
	elif state in ["locked", "pass"]:
		var lock := UiKit.icon("lock", UiKit.LOCKED, 5)
		lock.position = Vector2(84, 52)
		card.add_child(lock)
	var t := UiKit.title(TravelCatalog.stage_title(sid) if built else "준비 중", 19,
		UiKit.TEXT if built else UiKit.TEXT_SOFT)
	t.position = Vector2(14, 146)
	t.size = Vector2(180, 60)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(t)
	var btn: Button
	match state:
		"cleared":
			btn = UiKit.px_button("다시 하기", func(): stage_chosen.emit(sid), "secondary", 20)
		"open":
			btn = UiKit.px_button("출발!", func(): stage_chosen.emit(sid), "primary", 22)
		"locked":
			btn = UiKit.px_button("이전 엽서 먼저", func(): pass, "secondary", 17)
			btn.disabled = true
		"pass":
			btn = UiKit.px_button("여행 패스", func(): pass, "secondary", 18)
			btn.disabled = true
		_:
			btn = UiKit.px_button("준비 중", func(): pass, "secondary", 18)
			btn.disabled = true
	btn.custom_minimum_size = Vector2(0, 0)
	btn.position = Vector2(12, 228)
	btn.size = Vector2(184, 70)
	card.add_child(btn)
	return card
