class_name UiKit
extends RefCounted
## Pastel theme + small widget helpers shared by all screens.

const BG := Color("#fff6ec")
const PANEL := Color("#ffe9d6")
const PANEL_DARK := Color("#f3d5bd")
const TEXT := Color("#6b4f4f")
const TEXT_SOFT := Color("#a3857a")
const ACCENT := Color("#ff9f7a")
const BUTTON := Color("#ffd2b8")
const BUTTON_HOVER := Color("#ffc6a6")
const BUTTON_PRESSED := Color("#ffb08c")
const EMPTY_SAND := Color("#f4eadf")
const BOARD_BG := Color("#f9e4d2")
const BOARD_CELL := Color("#f3d9c4")
const WALL := Color("#d9b8a3")

static var _theme: Theme


static func box(color: Color, radius := 18, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 26
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var c: Color = {"normal": BUTTON, "hover": BUTTON_HOVER, "pressed": BUTTON_PRESSED,
			"focus": BUTTON, "disabled": PANEL_DARK}[state]
		t.set_stylebox(state, "Button", box(c, 22, 3, Color("#e8a988")))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_SOFT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 26, 3, Color("#f0c9ae")))
	t.set_stylebox("background", "ProgressBar", box(PANEL_DARK, 10))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 10))
	_theme = t
	return t


static func label(text: String, size := 26, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func button(text: String, cb: Callable, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 72)
	b.pressed.connect(func():
		Sfx.play("ui_tap")
		cb.call())
	return b


static func lighten(c: Color, amount: float) -> Color:
	return c.lerp(Color.WHITE, amount)


# ---------------------------------------------------------------- travel postcard style (A)

const PAPER := Color("#fffaf3")
const RIM := Color("#f0c9ae")
const SHADOW := Color("#e8cbb3")
const SHADOW_SOFT := Color("#efd9c6")
const ACCENT_DARK := Color("#e98762")
const ACCENT_SOFT := Color("#ffd0b8")
const MINT := Color("#8fc9b9")
const PIP_OFF := Color("#f3d5bd")
const LOCKED := Color("#b9a497")
const STAMP := Color("#e98762")

const ICONS := {
	"plane": ["...#....", "...##...", "#..###..", "########", "#..###..", "...##...", "...#....", "........"],
	"lock": ["..####..", ".#....#.", ".#....#.", "########", "###..###", "###..###", "########", "........"],
	"gear": ["...##...", ".######.", ".##..##.", "##....##", "##....##", ".##..##.", ".######.", "...##..."],
	"book": ["........", "###..###", "#..##..#", "#..##..#", "#..##..#", "#..##..#", "########", "........"],
	"map": ["##..##..", "#.##.##.", "#..#..##", "#..#..#.", "#..#..#.", "##.##.#.", "..##..##", "........"],
	"back": ["...#....", "..##....", ".#######", "########", ".#######", "..##....", "...#....", "........"],
	"star": ["...##...", "...##...", "########", ".######.", "..####..", ".##..##.", "##....##", "........"],
	"check": ["........", ".......#", "......##", "#....##.", "##..##..", ".####...", "..##....", "........"],
}

static var _bold: FontVariation
static var _icon_cache := {}


static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


## Label in the bold UI font.
static func title(text: String, size := 26, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_font_override("font", bold_font())
	return l


## 8x8 pixel icon as a texture (cached per name/color).
static func icon_texture(icon_name: String, color: Color, px := 1) -> Texture2D:
	var key := "%s%s%d" % [icon_name, color.to_html(), px]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var img := Image.create(8 * px, 8 * px, false, Image.FORMAT_RGBA8)
	var rows: Array = ICONS.get(icon_name, [])
	for y in rows.size():
		for x in 8:
			if str(rows[y])[x] == "#":
				img.fill_rect(Rect2i(x * px, y * px, px, px), color)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[key] = tex
	return tex


static func icon(icon_name: String, color: Color, px := 4) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(icon_name, color)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(8 * px, 8 * px)
	t.size = t.custom_minimum_size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func card_box(highlight := false, shadow := SHADOW_SOFT) -> PixelBox:
	return PixelBox.make(PAPER, ACCENT if highlight else RIM, shadow)


## Pixel button. kind: "primary" (coral), "secondary" (paper), "chip" (small paper).
static func px_button(text: String, cb: Callable, kind := "secondary", size := 26, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", bold_font())
	b.add_theme_font_size_override("font_size", size)
	var primary := kind == "primary"
	var fg := Color.WHITE if primary else TEXT
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", TEXT_SOFT)
	var base := ACCENT if primary else PAPER
	var lip := ACCENT_DARK if primary else Color("#f6e2d0")
	var rim := Color.TRANSPARENT if primary else RIM
	var shadow := Color("#f2b598") if primary else SHADOW_SOFT
	var lip_h := 0.0 if kind == "chip" else 8.0
	var margin := 6.0 if kind == "chip" else 10.0
	b.add_theme_stylebox_override("normal", PixelBox.make(base, rim, shadow, lip, lip_h, margin))
	b.add_theme_stylebox_override("hover", PixelBox.make(base.lightened(0.06), rim, shadow, lip, lip_h, margin))
	b.add_theme_stylebox_override("pressed", PixelBox.make(base.darkened(0.06), rim, Color.TRANSPARENT, lip, lip_h * 0.5, margin))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", PixelBox.make(PIP_OFF.lightened(0.3), RIM, Color.TRANSPARENT, Color.TRANSPARENT, 0.0, margin))
	if icon_name != "":
		b.icon = icon_texture(icon_name, fg, 3 if kind != "chip" or text == "" else 2)
		b.expand_icon = false
		b.add_theme_constant_override("h_separation", 12)
	if kind != "chip":
		b.custom_minimum_size = Vector2(0, 96 if primary else 80)
	b.pressed.connect(func():
		Sfx.play("ui_tap")
		cb.call())
	return b


## Small square icon button (back, settings).
static func icon_button(icon_name: String, cb: Callable) -> Button:
	var b := px_button("", cb, "chip", 20, "")
	b.icon = icon_texture(icon_name, TEXT_SOFT, 4)
	b.custom_minimum_size = Vector2(64, 60)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## Paper chip label (e.g. "★ 스탬프 2 / 100").
static func chip(text: String, icon_name := "star") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PixelBox.make(PAPER, RIM, Color.TRANSPARENT, Color.TRANSPARENT, 0.0, 6.0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	if icon_name != "":
		var ic := icon(icon_name, ACCENT, 3)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	h.add_child(title(text, 20))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Three progress pips (cleared stages of a destination).
static func pips(cleared: int, total := 3, current := -1) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in total:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(18, 18)
		r.color = ACCENT if i < cleared else (ACCENT_SOFT if i == current else PIP_OFF)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return h


## Common top bar: back button, centred title (+ optional subtitle), right chip.
static func top_bar(parent: Control, title_text: String, on_back: Callable, right: Control = null, sub := "") -> void:
	var back := icon_button("back", on_back)
	back.position = Vector2(28, 28)
	parent.add_child(back)
	var t := title(title_text, 36, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.position = Vector2(120, 22 if sub != "" else 30)
	t.size = Vector2(480, 50)
	parent.add_child(t)
	if sub != "":
		var s := label(sub, 15, TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		s.position = Vector2(120, 70)
		s.size = Vector2(480, 22)
		parent.add_child(s)
	if right != null:
		parent.add_child(right)
		right.position = Vector2(692 - right.get_combined_minimum_size().x, 34)


## White postcard: picture (cover crop, lazy thumbnail) with a paper border, a flat drop
## shadow and an optional caption strip. Without a picture it shows a blank postcard.
static func postcard(path: String, img_size: Vector2, caption := "", placeholder := "", dim := false,
		pad := 14.0, caption_size := 22) -> Control:
	var cap_h := 46.0 if caption != "" else 0.0
	var root := Panel.new()
	var frame := PixelBox.make(Color.WHITE, Color.TRANSPARENT, Color("#e2c3a8"))
	frame.step = 2.0
	root.add_theme_stylebox_override("panel", frame)
	root.size = img_size + Vector2(pad * 2, pad * 2 + cap_h)
	root.custom_minimum_size = root.size
	root.pivot_offset = root.size * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := PostcardImage.create(path, img_size, placeholder, dim)
	img.position = Vector2(pad, pad)
	root.add_child(img)
	if caption != "":
		var l := title(caption, caption_size, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(0, pad + img_size.y + 4)
		l.size = Vector2(root.size.x, cap_h - 4)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(l)
	return root


## Flat clickable card (a Button without text) whose content is added by the caller.
static func card_button(min_size: Vector2, cb: Callable, highlight := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.size = min_size
	var rim := ACCENT if highlight else RIM
	var shadow := Color("#f2b598") if highlight else SHADOW_SOFT
	b.add_theme_stylebox_override("normal", PixelBox.make(PAPER, rim, shadow))
	b.add_theme_stylebox_override("hover", PixelBox.make(PAPER.lightened(0.3), rim, shadow))
	b.add_theme_stylebox_override("pressed", PixelBox.make(PIP_OFF.lightened(0.5), rim, Color.TRANSPARENT))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		Sfx.play("ui_tap")
		cb.call())
	return b


## Makes every descendant of `c` ignore the mouse (content placed on a card_button).
static func pass_mouse(c: Node) -> void:
	for ch in c.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		pass_mouse(ch)


## Small coral tag ("여행 중").
static func tag(text: String, size := 15) -> Label:
	var t := title(" %s " % text, size, Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	t.add_theme_stylebox_override("normal", sb)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## Row of controls laid out left to right (sizes resolve once in the tree).
static func row(items: Array, gap := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in items:
		(it as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(it)
	return h


## Thin progress bar.
static func bar(width: float, frac: float, fill := MINT) -> Control:
	var bg := ColorRect.new()
	bg.color = PIP_OFF
	bg.custom_minimum_size = Vector2(width, 10)
	bg.size = bg.custom_minimum_size
	var f := ColorRect.new()
	f.color = fill
	f.size = Vector2(maxf(0.0, width * clampf(frac, 0.0, 1.0)), 10)
	bg.add_child(f)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## Full-screen dimmer that eats input; returns it so callers can add a panel on top.
static func dimmer(parent: Control, alpha := 0.5) -> Control:
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(TEXT, alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	o.add_child(dim)
	parent.add_child(o)
	return o
