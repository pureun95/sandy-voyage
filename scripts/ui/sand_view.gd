class_name SandView
extends Control
## Renders SandMap.cells directly: the byte array is uploaded as one R8 texture whenever
## the sand changes, and a palette shader colors it. No per-grain nodes, no per-pixel
## GDScript work, so falling sand (thousands of moved cells per step) costs one upload.

const PaletteShader := preload("res://scripts/ui/sand_palette.gdshader")

var game: SandGame
var texture: ImageTexture
var _sand: TextureRect
var _version := -1


func bind(g: SandGame) -> void:
	game = g
	mouse_filter = MOUSE_FILTER_IGNORE
	var img := Image.create_from_data(g.map.width, g.map.height, false, Image.FORMAT_R8, g.map.cells)
	texture = ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = PaletteShader
	var pal := PackedColorArray()
	pal.resize(16)
	for i in g.map.palette.size():
		pal[i] = g.map.palette[i]
	mat.set_shader_parameter("palette", pal)
	_sand = TextureRect.new()
	_sand.texture = texture
	_sand.material = mat
	_sand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sand.stretch_mode = TextureRect.STRETCH_SCALE
	_sand.mouse_filter = MOUSE_FILTER_IGNORE
	_sand.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_sand)
	_version = g.sand_version
	queue_redraw()


func grain_size() -> float:
	return size.x / game.map.width


## Local-space center of sand pixel `index`.
func grain_center(index: int) -> Vector2:
	var w := game.map.width
	var g := grain_size()
	@warning_ignore("integer_division")
	return Vector2((index % w + 0.5) * g, (index / w + 0.5) * g)


func _process(_delta: float) -> void:
	if game and game.sand_version != _version:
		_version = game.sand_version
		texture.update(Image.create_from_data(game.map.width, game.map.height, false, Image.FORMAT_R8, game.map.cells))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.EMPTY_SAND)
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
