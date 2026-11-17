class_name AlbumScreen
extends Control
## Travel album (design A): one page per continent. Each destination shows its three stage
## postcards (a postcard is collected by clearing that stage, read from save.cleared) and a
## visit stamp once all three are collected. Pictures are lazy thumbnails (PostcardImage);
## the original image is loaded only for the single full view.
## The older per-destination record (save.album, first clear) is kept and unchanged.

signal back_requested

var continent_id := ""
var _list: VBoxContainer
var _tabs: HBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var save := App.save
	if continent_id == "":
		var cur := TravelCatalog.current_destination(save)
		continent_id = str(TravelCatalog.destination(cur).get("continent", "")) if cur != "" else str(TravelCatalog.continents()[0].id)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var total := TravelCatalog.destinations().size() * TravelCatalog.stages_per_destination()
	UiKit.top_bar(self, "여행 앨범", func(): back_requested.emit(),
		UiKit.chip("엽서 %d/%d" % [TravelCatalog.total_postcards(save), total], "book"))
	var stamps := UiKit.label("방문 완료 스탬프 %d / %d곳" % [TravelCatalog.total_stamps(save), TravelCatalog.destinations().size()],
		18, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	stamps.position = Vector2(0, 98)
	stamps.size = Vector2(720, 26)
	add_child(stamps)

	var tab_scroll := ScrollContainer.new()
	tab_scroll.position = Vector2(0, 134)
	tab_scroll.size = Vector2(720, 70)
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(tab_scroll)
	var tab_pad := MarginContainer.new()
	tab_pad.add_theme_constant_override("margin_left", 24)
	tab_pad.add_theme_constant_override("margin_right", 24)
	tab_pad.add_theme_constant_override("margin_top", 6)
	tab_scroll.add_child(tab_pad)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 10)
	tab_pad.add_child(_tabs)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(0, 210)
	_scroll.size = Vector2(720, 1070)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 40)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 20)
	pad.add_child(_list)
	_show(continent_id)


func _show(cid: String) -> void:
	continent_id = cid
	for ch in _tabs.get_children():
		ch.queue_free()
	for c in TravelCatalog.continents():
		var pr := TravelCatalog.continent_progress(App.save, c.id)
		var id: String = c.id
		var b := UiKit.px_button("%s %d/%d" % [c.name_ko, pr.stamps, pr.total], func(): _show(id), "chip", 18)
		if id == cid:
			b.add_theme_stylebox_override("normal", PixelBox.make(UiKit.TEXT, UiKit.TEXT, Color.TRANSPARENT, Color.TRANSPARENT, 0.0, 6.0))
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(k, Color.WHITE)
		_tabs.add_child(b)
	for ch in _list.get_children():
		ch.queue_free()
	_scroll.scroll_vertical = 0
	var list := TravelCatalog.in_continent(cid)
	var ready_list := list.filter(func(d): return TravelCatalog.is_built(d.id))
	var later := list.filter(func(d): return not TravelCatalog.is_built(d.id))
	for d in ready_list:
		_list.add_child(_page(d))
	if not later.is_empty():
		var h := UiKit.title("준비 중인 여행지 %d곳" % later.size(), 20, UiKit.TEXT_SOFT)
		_list.add_child(h)
		for d in later:
			_list.add_child(_later_row(d))


func _page(d: Dictionary) -> Control:
	var save := App.save
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UiKit.card_box())
	card.custom_minimum_size = Vector2(664, 300)
	var n := TravelCatalog.cleared_count(save, d.id)
	var total := TravelCatalog.stages_per_destination()
	var head := UiKit.row([UiKit.title(str(d.name_ko), 28),
		UiKit.label("%s · 엽서 %d/%d%s" % [d.country_ko, n, total, "" if d.access == "free" else " · 여행 패스"], 16, UiKit.TEXT_SOFT)], 12)
	head.position = Vector2(22, 16)
	card.add_child(head)
	var stamp: StampMark
	if TravelCatalog.is_visited(save, d.id):
		stamp = StampMark.create("VISITED\n%s" % d.name_ko, 84, -10.0)
	else:
		stamp = StampMark.create("방문 전", 72, -10.0, UiKit.LOCKED, true)
	stamp.position = Vector2(664 - stamp.size.x - 14, 4)
	card.add_child(stamp)
	for i in total:
		var k := i + 1
		var sid := TravelCatalog.stage_id(d.id, k)
		var built := TravelCatalog.is_stage_built(sid)
		var got := save.is_cleared(sid)
		var slot := Button.new()
		slot.flat = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.position = Vector2(20 + i * 212, 72)
		slot.size = Vector2(200, 214)
		card.add_child(slot)
		var pc := UiKit.postcard(TravelCatalog.postcard_path(d.id, k) if built else "", Vector2(188, 140), "", "준비 중" if not built else "", not got, 6.0)
		slot.add_child(pc)
		if built and not got:
			var lock := UiKit.icon("lock", UiKit.LOCKED, 5)
			lock.position = Vector2(84, 54)
			slot.add_child(lock)
		var cap := UiKit.title("%d. %s" % [k, TravelCatalog.stage_title(sid)] if built else "%d. 준비 중" % k, 17,
			UiKit.TEXT if got else UiKit.TEXT_SOFT)
		cap.position = Vector2(2, 158)
		cap.size = Vector2(196, 26)
		cap.clip_text = true
		slot.add_child(cap)
		var when := ""
		if got:
			var at := save.clear_time(sid)
			when = Time.get_date_string_from_unix_time(at) if at > 0 else "획득"
		elif built:
			when = "미획득"
		var w := UiKit.label(when, 14, UiKit.TEXT_SOFT)
		w.position = Vector2(2, 184)
		slot.add_child(w)
		UiKit.pass_mouse(slot)
		if got:
			slot.pressed.connect(func(): _full(d, k))
	return card


func _later_row(d: Dictionary) -> Control:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", PixelBox.make(UiKit.BG, UiKit.PIP_OFF))
	card.custom_minimum_size = Vector2(664, 74)
	var sub := UiKit.label("%s · %s" % [d.country_ko, d.subject_ko], 15, UiKit.TEXT_SOFT)
	sub.clip_text = true
	sub.custom_minimum_size = Vector2(10, 0)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiKit.row([UiKit.title(str(d.name_ko), 22, UiKit.TEXT_SOFT), sub], 10)
	head.position = Vector2(22, 18)
	head.size = Vector2(430, 40)
	card.add_child(head)
	for i in TravelCatalog.stages_per_destination():
		var r := ReferenceRect.new()
		r.border_color = UiKit.PIP_OFF
		r.border_width = 3.0
		r.editor_only = false
		r.position = Vector2(470 + i * 62, 14)
		r.size = Vector2(52, 46)
		card.add_child(r)
	return card


func _full(d: Dictionary, k: int) -> void:
	var sid := TravelCatalog.stage_id(d.id, k)
	var o := UiKit.dimmer(self, 0.0)
	var dim: ColorRect = o.get_child(0)
	dim.color = Color(UiKit.BG, 0.96)
	var t := UiKit.title("%s · %d. %s" % [d.name_ko, k, TravelCatalog.stage_title(sid)], 34, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.position = Vector2(0, 190)
	t.size = Vector2(720, 56)
	o.add_child(t)
	var img := PostcardImage.new()
	img.path = TravelCatalog.postcard_path(d.id, k)
	img.full_res = true
	img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img.position = Vector2(20, 270)
	img.size = Vector2(680, 680)
	img.mouse_filter = MOUSE_FILTER_IGNORE
	o.add_child(img)
	var at := App.save.clear_time(sid)
	var when := UiKit.label(Time.get_date_string_from_unix_time(at) if at > 0 else "", 20, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	when.position = Vector2(0, 966)
	when.size = Vector2(720, 30)
	o.add_child(when)
	var close := UiKit.label("화면을 누르면 닫혀요", 18, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	close.position = Vector2(0, 1010)
	close.size = Vector2(720, 30)
	o.add_child(close)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			o.queue_free())
