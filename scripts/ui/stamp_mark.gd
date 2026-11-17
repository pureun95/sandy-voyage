class_name StampMark
extends Control
## Round travel stamp: a ring with one or two centred lines of text, slightly rotated.

var text := ""
var color := UiKit.STAMP
var dashed := false


static func create(p_text: String, diameter := 96.0, rot_deg := -12.0, p_color := UiKit.STAMP, p_dashed := false) -> StampMark:
	var s := StampMark.new()
	s.text = p_text
	s.color = p_color
	s.dashed = p_dashed
	s.custom_minimum_size = Vector2(diameter, diameter)
	s.size = s.custom_minimum_size
	s.pivot_offset = s.size * 0.5
	s.rotation_degrees = rot_deg
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _draw() -> void:
	var c := size * 0.5
	var rad := size.x * 0.5 - 3.0
	if dashed:
		for i in 16:
			draw_arc(c, rad, TAU * i / 16.0, TAU * (i + 0.5) / 16.0, 4, color, 3.0)
	else:
		draw_arc(c, rad, 0.0, TAU, 48, color, 4.0)
		draw_arc(c, rad - 7.0, 0.0, TAU, 48, Color(color, 0.5), 2.0)
	var font := UiKit.bold_font()
	var lines := text.split("\n")
	var fs := int(size.x / (4.6 if lines.size() > 1 else 4.0))
	var lh := fs * 1.05
	var y0 := c.y - lh * (lines.size() - 1) * 0.5 + fs * 0.35
	for i in lines.size():
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var fit := minf(1.0, (size.x - 22.0) / maxf(w, 1.0))
		var f2 := int(fs * fit)
		var w2 := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, f2).x
		draw_string(font, Vector2(c.x - w2 * 0.5, y0 + i * lh), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, f2, color)
