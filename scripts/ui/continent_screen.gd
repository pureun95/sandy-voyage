class_name ContinentScreen
extends Control
## One continent (design A3): regional map with every destination of the continent, filter
## chips and a 3-column postcard grid. Tapping a postcard opens the DestinationSheet (A4).

signal back_requested
signal stage_chosen(stage_id: String)
signal album_requested(continent_id: String)

const MAP_Y := 110.0
const MAP_H := 400.0

var continent_id := ""
var open_destination := ""   # opened as a sheet right away (returning from a stage)
var _filter := "all"
var _grid: GridContainer
var _chips: HBoxContainer
var _sheet: DestinationSheet


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var c := TravelCatalog.continent(continent_id)
	var save := App.save
	var pr := TravelCatalog.continent_progress(save, continent_id)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	UiKit.top_bar(self, str(c.get("name_ko", "")), func(): back_requested.emit(),
		UiKit.chip("%d/%d" % [pr.stamps, pr.total]), "%s · %d곳" % [c.get("name_en", ""), pr.total])

	var cur := TravelCatalog.current_destination(save)
	var map := MapView.region(c.map, Vector2(720, MAP_H))
	map.position = Vector2(0, MAP_Y)
	var list := TravelCatalog.in_continent(continent_id)
	# Premium first so free / playable pins are drawn on top.
	var ordered := list.filter(func(d): return d.access != "free" and not TravelCatalog.is_built(d.id))
	ordered.append_array(list.filter(func(d): return d.access == "free" or TravelCatalog.is_built(d.id)))
	for d in ordered:
		var style := WorldMapScreen._pin_style(d.id, cur)
		if d.access != "free" and style == "unbuilt":
			style = "premium"
		map.pins.append({"lat": d.lat, "lon": d.lon, "big": d.access == "free" or TravelCatalog.is_built(d.id), "style": style})
	add_child(map)
	_labels(map, ordered, cur)
	var shade := ColorRect.new()
	shade.color = UiKit.SHADOW
	shade.position = Vector2(0, MAP_Y + MAP_H)
	shade.size = Vector2(720, 6)
	add_child(shade)
	var legend := UiKit.label("■ 무료 · ▫ 여행 패스", 14, UiKit.TEXT_SOFT)
	legend.position = Vector2(560, MAP_Y + MAP_H - 26)
	add_child(legend)

	_chips = HBoxContainer.new()
	_chips.position = Vector2(28, MAP_Y + MAP_H + 22)
	_chips.add_theme_constant_override("separation", 10)
	add_child(_chips)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, MAP_Y + MAP_H + 84)
	scroll.size = Vector2(720, 1280 - scroll.position.y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 22)
	pad.add_child(_grid)
	_rebuild()
	if open_destination != "":
		open_sheet(open_destination)


func _labels(map: MapView, list: Array, cur: String) -> void:
	var boxes: Array[Rect2] = []
	var shown := list.filter(func(d): return d.access == "free" or TravelCatalog.is_built(d.id))
	for d in shown:
		var p := map.point(d.lat, d.lon)
		var l := UiKit.title(str(d.name_ko), 16, Color.WHITE if d.id == cur else UiKit.TEXT)
		var sb := PixelBox.make(UiKit.ACCENT if d.id == cur else UiKit.PAPER, UiKit.RIM, Color.TRANSPARENT, Color.TRANSPARENT, 0.0, 2.0)
		l.add_theme_stylebox_override("normal", sb)
		var sz := l.get_combined_minimum_size()
		var r := Rect2(p + Vector2(16, -sz.y * 0.5), sz)
		if r.end.x > map.size.x - 4:
			r.position.x = p.x - 16 - sz.x
		if boxes.any(func(o): return o.intersects(r)) or not Rect2(Vector2.ZERO, map.size).encloses(r):
			continue
		boxes.append(r)
		l.position = map.position + r.position
		l.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(l)


func _rebuild() -> void:
	for ch in _chips.get_children():
		ch.queue_free()
	var list := TravelCatalog.in_continent(continent_id)
	var counts := {
		"all": list.size(),
		"free": list.filter(func(d): return d.access == "free").size(),
		"playable": list.filter(func(d): return _playable(d.id)).size(),
	}
	for spec in [["all", "전체"], ["free", "무료"], ["playable", "플레이 가능"]]:
		var key: String = spec[0]
		var b := UiKit.px_button("%s %d" % [spec[1], counts[key]], func():
			_filter = key
			_rebuild(), "chip", 18)
		if key == _filter:
			b.add_theme_stylebox_override("normal", PixelBox.make(UiKit.TEXT, UiKit.TEXT, Color.TRANSPARENT, Color.TRANSPARENT, 0.0, 6.0))
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(k, Color.WHITE)
		_chips.add_child(b)
	for ch in _grid.get_children():
		ch.queue_free()
	var shown := list
	if _filter == "free":
		shown = list.filter(func(d): return d.access == "free")
	elif _filter == "playable":
		shown = list.filter(func(d): return _playable(d.id))
	if shown.is_empty():
		_grid.add_child(UiKit.label("아직 떠날 수 있는 여행지가 없어요", 20, UiKit.TEXT_SOFT))
	for d in shown:
		_grid.add_child(_card(d))


static func _playable(dest_id: String) -> bool:
	return TravelCatalog.is_built(dest_id) and TravelCatalog.has_access(dest_id, App.entitlements)


func _card(d: Dictionary) -> Control:
	var save := App.save
	var cur := TravelCatalog.current_destination(save)
	var built := TravelCatalog.is_built(d.id)
	var access := TravelCatalog.has_access(d.id, App.entitlements)
	var card := UiKit.card_button(Vector2(212, 204), func(): open_sheet(d.id), d.id == cur)
	# Premium cards show only the lock; free cards still to be made show their landmark.
	var img := PostcardImage.create(TravelCatalog.cover_path(d.id), Vector2(188, 118),
		str(d.subject_ko) if access else "", not (built and access))
	img.position = Vector2(12, 12)
	card.add_child(img)
	if not access:
		var lock := UiKit.icon("lock", UiKit.LOCKED, 5)
		lock.position = Vector2(86, 50)
		card.add_child(lock)
	if d.id == cur:
		var tag := UiKit.tag("여행 중", 14)
		tag.position = Vector2(18, 18)
		card.add_child(tag)
	if TravelCatalog.is_visited(save, d.id):
		var st := StampMark.create("VISITED", 64, -14.0)
		st.position = Vector2(136, 68)
		card.add_child(st)
	var nm := UiKit.title(str(d.name_ko), 20, UiKit.TEXT if built and access else UiKit.TEXT_SOFT)
	nm.position = Vector2(14, 136)
	nm.size = Vector2(184, 30)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(nm)
	var status: Control
	if not access:
		status = UiKit.title("여행 패스", 13, Color("#b48a76"))
	elif not built:
		status = UiKit.title("준비 중", 13, UiKit.TEXT_SOFT)
	else:
		status = UiKit.pips(TravelCatalog.cleared_count(save, d.id))
	var country := UiKit.label(str(d.country_ko), 14, UiKit.TEXT_SOFT)
	country.clip_text = true
	country.custom_minimum_size = Vector2(10, 0)
	country.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bottom := UiKit.row([country, status], 6)
	bottom.position = Vector2(14, 168)
	bottom.size = Vector2(184, 26)
	card.add_child(bottom)
	UiKit.pass_mouse(card)
	return card


func open_sheet(dest_id: String) -> void:
	if is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = DestinationSheet.new()
	_sheet.destination_id = dest_id
	_sheet.stage_chosen.connect(func(sid): stage_chosen.emit(sid))
	_sheet.album_requested.connect(func(): album_requested.emit(continent_id))
	add_child(_sheet)
