class_name SandView
extends Control
## Renders the SandMap as one texture (one texel per grain). No per-grain nodes.
## Only grains reported by `grains_collected` are cleared; everything else keeps
## its original position and color.

var game: SandGame
var image: Image
var texture: ImageTexture
var _dirty := false
var _clear := Color(0, 0, 0, 0)


func bind(g: SandGame) -> void:
	game = g
	image = g.map.to_image()
	texture = ImageTexture.create_from_image(image)
	g.grains_collected.connect(_on_grains)
	mouse_filter = MOUSE_FILTER_IGNORE
	queue_redraw()


func grain_size() -> float:
	return size.x / game.map.width


## Local-space center of sand pixel `index`.
func grain_center(index: int) -> Vector2:
	var w := game.map.width
	var g := grain_size()
	@warning_ignore("integer_division")
	return Vector2((index % w + 0.5) * g, (index / w + 0.5) * g)


func _on_grains(_block: SandBlock, indices: PackedInt32Array) -> void:
	var w := game.map.width
	for i in indices:
		@warning_ignore("integer_division")
		image.set_pixel(i % w, i / w, _clear)
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		texture.update(image)
		_dirty = false


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, UiKit.EMPTY_SAND)
	# Faint dot pattern so emptied areas read as an empty glass, not a missing image.
	var step := 20.0
	var dot := UiKit.EMPTY_SAND.darkened(0.05)
	var y := step * 0.5
	while y < size.y:
		var x := step * 0.5
		while x < size.x:
			draw_rect(Rect2(x - 1.5, y - 1.5, 3, 3), dot)
			x += step
		y += step
	if texture:
		draw_texture_rect(texture, r, false)
