class_name WorldMapScreen
extends Control
## World map (design A2): the map shows only the free destinations, the travel route and one
## progress badge per continent; continents are chosen from the badges or the cards below.
## Destinations are never picked from the world map itself (100 pins would not be tappable).

signal back_requested
signal continent_chosen(continent_id: String)

const MAP_Y := 110.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var save := App.save
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	UiKit.top_bar(self, "세계 지도", func(): back_requested.emit(),
		UiKit.chip("%d/%d" % [TravelCatalog.total_stamps(save), TravelCatalog.destinations().size()]))

	var cur := TravelCatalog.current_destination(save)
	var map := MapView.world(720.0)
	map.position = Vector2(0, MAP_Y)
	for d in TravelCatalog.destinations():
		if d.access == "free":
			map.pins.append({"lat": d.lat, "lon": d.lon, "big": true, "style": _pin_style(d.id, cur)})
	for id in TravelCatalog.visit_route(save):
		var d := TravelCatalog.destination(id)
		map.route.append(Vector2(d.lat, d.lon))
	add_child(map)
	var shade := ColorRect.new()
	shade.color = UiKit.SHADOW
	shade.position = Vector2(0, MAP_Y + map.size.y)
	shade.size = Vector2(720, 6)
	add_child(shade)
	var cur_cont := str(TravelCatalog.destination(cur).get("continent", ""))
	for c in TravelCatalog.continents():
		var badge := _badge(c, map, c.id == cur_cont)
		add_child(badge)

	var hint := UiKit.title("대륙을 골라 여행지를 펼쳐 보세요", 22)
	hint.position = Vector2(30, MAP_Y + map.size.y + 24)
	add_child(hint)
	var hint2 := UiKit.label("지도에는 무료 여행지만 표시돼요", 16, UiKit.TEXT_SOFT)
	hint2.position = Vector2(30, MAP_Y + map.size.y + 56)
	add_child(hint2)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, MAP_Y + map.size.y + 90)
	scroll.size = Vector2(720, 1280 - scroll.position.y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 30)
	pad.custom_minimum_size = Vector2(720, 0)
	scroll.add_child(pad)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 22)
	pad.add_child(list)
	for c in TravelCatalog.continents():
		list.add_child(_card(c, c.id == cur_cont, cur))


static func _pin_style(dest_id: String, cur: String) -> String:
	if dest_id == cur:
		return "current"
	if TravelCatalog.is_visited(App.save, dest_id):
		return "done"
	return "open" if TravelCatalog.is_built(dest_id) else "unbuilt"


func _badge(c: Dictionary, map: MapView, highlight: bool) -> Button:
	var pr := TravelCatalog.continent_progress(App.save, c.id)
	var sum := Vector2.ZERO
	var list := TravelCatalog.in_continent(c.id)
	for d in list:
		sum += map.point(d.lat, d.lon)
	var ce := sum / maxf(1.0, list.size())
	var b := UiKit.px_button("%s %d/%d" % [c.name_ko, pr.stamps, pr.total], func(): continent_chosen.emit(c.id), "chip", 17)
	if highlight:
		b.add_theme_stylebox_override("normal", PixelBox.make(UiKit.ACCENT, UiKit.ACCENT_DARK, Color.TRANSPARENT, Color.TRANSPARENT, 0.0, 6.0))
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color.WHITE)
	var w := b.get_combined_minimum_size().x
	var y := ce.y - 46.0 if c.id == "europe" else ce.y + 14.0
	b.position = Vector2(clampf(ce.x - w * 0.5, 4.0, 716.0 - w), MAP_Y + clampf(y, 4.0, map.size.y - 40.0))
	return b


func _card(c: Dictionary, highlight: bool, cur: String) -> Control:
	var pr := TravelCatalog.continent_progress(App.save, c.id)
	var card := UiKit.card_button(Vector2(664, 184), func(): continent_chosen.emit(c.id), highlight)
	# Representative picture: the current / first built destination's postcard, else the
	# continent's own pixel map.
	var built: Array = TravelCatalog.in_continent(c.id).filter(func(d): return TravelCatalog.is_built(d.id))
	built.sort_custom(func(a, b): return a.id == cur and b.id != cur)
	var art: Control
	if not built.is_empty():
		art = UiKit.postcard(TravelCatalog.cover_path(built[0].id), Vector2(196, 144), "", "", false, 6.0)
	else:
		var holder := Panel.new()
		var fr := PixelBox.make(Color.WHITE, Color.TRANSPARENT, Color("#e2c3a8"))
		fr.step = 2.0
		holder.add_theme_stylebox_override("panel", fr)
		holder.size = Vector2(208, 156)
		var spec: Dictionary = c.map.duplicate()
		spec.scale = maxf(1.0, floorf(float(spec.scale) * 0.5))
		var mini := MapView.region(spec, Vector2(196, 144))
		for d in TravelCatalog.in_continent(c.id):
			mini.pins.append({"lat": d.lat, "lon": d.lon, "big": false, "style": "premium" if d.access != "free" else "unbuilt"})
		mini.position = Vector2(6, 6)
		holder.add_child(mini)
		art = holder
	art.position = Vector2(14, 12)
	art.rotation_degrees = -1.5
	card.add_child(art)

	var head := [UiKit.title(c.name_ko, 28)]
	if highlight:
		head.append(UiKit.tag("여행 중"))
	var head_row := UiKit.row(head, 12)
	head_row.position = Vector2(244, 14)
	card.add_child(head_row)
	var en := UiKit.label(str(c.name_en), 14, UiKit.TEXT_SOFT)
	en.position = Vector2(246, 56)
	card.add_child(en)
	var info := UiKit.label("%d곳 · 무료 %d · 플레이 가능 %d · 스탬프 %d" % [pr.total, pr.free, pr.built, pr.stamps], 17, UiKit.TEXT_SOFT)
	info.position = Vector2(246, 78)
	card.add_child(info)
	var progress := UiKit.bar(370, float(pr.stamps) / maxf(1.0, pr.total))
	progress.position = Vector2(246, 108)
	card.add_child(progress)
	if built.is_empty():
		var soon := UiKit.label("새 여행지 엽서를 준비하고 있어요", 16, UiKit.TEXT_SOFT)
		soon.position = Vector2(246, 134)
		card.add_child(soon)
	else:
		var x := 246.0
		for d in built.slice(0, 3):
			var th := PostcardImage.create(TravelCatalog.cover_path(d.id), Vector2(72, 54))
			th.position = Vector2(x, 128)
			card.add_child(th)
			x += 80.0
		var names := UiKit.label(", ".join(built.slice(0, 3).map(func(d): return d.name_ko)), 16, UiKit.TEXT)
		names.position = Vector2(x + 4, 144)
		card.add_child(names)
	var chev := UiKit.title("›", 40, Color("#c9a48f"))
	chev.position = Vector2(628, 64)
	card.add_child(chev)
	UiKit.pass_mouse(card)
	return card
