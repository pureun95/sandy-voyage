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
