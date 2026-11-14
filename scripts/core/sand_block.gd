class_name SandBlock
extends RefCounted
## A movable collection block. Pure data: no nodes, no rendering.
## Blocks never rotate: `cells` is fixed at creation.

const SHAPES := {
	"dot": [[0, 0]],
	"I2h": [[0, 0], [1, 0]],
	"I2v": [[0, 0], [0, 1]],
	"I3h": [[0, 0], [1, 0], [2, 0]],
	"I3v": [[0, 0], [0, 1], [0, 2]],
	"I4h": [[0, 0], [1, 0], [2, 0], [3, 0]],
	"O": [[0, 0], [1, 0], [0, 1], [1, 1]],
	"L": [[0, 0], [0, 1], [1, 1]],          # ㄴ
	"J": [[1, 0], [0, 1], [1, 1]],          # ┘
	"Lr": [[0, 0], [1, 0], [0, 1]],         # ┌
	"Jr": [[0, 0], [1, 0], [1, 1]],         # ㄱ
	"T": [[0, 0], [1, 0], [2, 0], [1, 1]],  # ㅜ
	"Td": [[1, 0], [0, 1], [1, 1], [2, 1]], # ㅗ
	"L3": [[0, 0], [0, 1], [0, 2], [1, 2]],
}

var id := ""
var color_id := 0
var pos := Vector2i.ZERO
var cells: Array[Vector2i] = []
var capacity := 0
var collected := 0
var removed := false


static func create(p_id: String, p_color: int, cell_list: Array, p_pos: Vector2i, p_capacity := 0) -> SandBlock:
	var b := SandBlock.new()
	b.id = p_id
	b.color_id = p_color
	b.pos = p_pos
	b.capacity = p_capacity
	for c in cell_list:
		b.cells.append(Vector2i(int(c[0]), int(c[1])) if c is Array else c)
	return b


static func shape_cells(shape: String) -> Array:
	return SHAPES.get(shape, [])


func occupied(at: Vector2i = pos) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(at + c)
	return out


func bounds_size() -> Vector2i:
	var s := Vector2i.ZERO
	for c in cells:
		s.x = maxi(s.x, c.x + 1)
		s.y = maxi(s.y, c.y + 1)
	return s


func progress() -> float:
	return 0.0 if capacity <= 0 else float(collected) / capacity


func room() -> int:
	return capacity - collected


func is_full() -> bool:
	return collected >= capacity


## Board columns whose top face touches the landscape (cells on board row 0).
func contact_columns(at: Vector2i = pos) -> PackedInt32Array:
	var out := PackedInt32Array()
	if removed:
		return out
	for c in cells:
		if at.y + c.y == 0:
			out.append(at.x + c.x)
	return out
