class_name BoardView
extends Control
## Draws the block board and handles drag input. One drag moves a block along one
## axis (chosen from the initial drag direction); it is clamped by walls, edges and
## other blocks, then snaps to the nearest cell with a short settle animation.

signal block_moved(block: SandBlock)

const AXIS_THRESHOLD := 10.0
const SETTLE_SPEED := 14.0

var game: SandGame
var fx: GrainFx  # suction: fill follows landed grains
var cell := 80.0

var _drag: SandBlock
var _drag_start := Vector2.ZERO
var _drag_axis := Vector2i.ZERO
var _drag_offset := Vector2.ZERO
var _drag_min := 0.0
var _drag_max := 0.0
var _settle := {}       # block id -> Vector2 visual offset decaying to zero
var _ghosts := []       # removed-block pop animations
var _landing := []      # suction: removed blocks kept on screen until their last grains land
var _hint := PackedInt32Array()  # column_reach() snapshot while dragging
var _time := 0.0
var _font: Font


func bind(g: SandGame) -> void:
	game = g
	cell = size.x / g.board.cols
	g.block_filled.connect(_on_block_filled)
	_font = ThemeDB.fallback_font
	queue_redraw()


func block_rect(b: SandBlock, c: Vector2i) -> Rect2:
	return Rect2(Vector2(b.pos + c) * cell + visual_offset(b), Vector2(cell, cell))


func visual_offset(b: SandBlock) -> Vector2:
	if b == _drag:
		return _drag_offset
	return _settle.get(b.id, Vector2.ZERO)


## Local-space point where a grain should land for `b`, near sand column `px_x`.
func intake_point(b: SandBlock, sand_x: float) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for c in b.cells:
		if b.pos.y + c.y != 0:
			continue
		var r := block_rect(b, c)
		var d := absf(r.get_center().x - sand_x)
		if d < best_d:
			best_d = d
			best = r.position
	return best + Vector2(randf_range(0.2, 0.8) * cell, randf_range(0.25, 0.7) * cell)


func _gui_input(event: InputEvent) -> void:
	if game == null or game.cleared:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _drag != null:
		_motion(event.position)
		accept_event()


func _press(p: Vector2) -> void:
	var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
	var b := game.board.block_at(c)
	if b == null or _settle.has(b.id):
		return
	_drag = b
	_drag_start = p
	_drag_axis = Vector2i.ZERO
	_drag_offset = Vector2.ZERO
	game.set_held(b, true)
	# Hint: which intake columns could feed this block's color right now (same rule as collection).
	_hint = game.contact_masks()
	Sfx.play("drag_start")


func _motion(p: Vector2) -> void:
	var d := p - _drag_start
	if _drag_axis == Vector2i.ZERO:
		if d.length() < AXIS_THRESHOLD:
			return
		_drag_axis = Vector2i.RIGHT if absf(d.x) >= absf(d.y) else Vector2i.DOWN
		_drag_min = -game.board.max_steps(_drag, -_drag_axis) * cell
		_drag_max = game.board.max_steps(_drag, _drag_axis) * cell
	var along := d.x if _drag_axis == Vector2i.RIGHT else d.y
	along = clampf(along, _drag_min, _drag_max)
	_drag_offset = Vector2(_drag_axis) * along
	queue_redraw()


func _release() -> void:
	if _drag == null:
		return
	var b := _drag
	_drag = null
	_hint = PackedInt32Array()
	var along := _drag_offset.x if _drag_axis == Vector2i.RIGHT else _drag_offset.y
	var steps := roundi(along / cell)
	if steps != 0:
		var dir := _drag_axis * signi(steps)
		if game.try_move(b, dir, absi(steps)):
			_drag_offset -= Vector2(dir * absi(steps)) * cell
			block_moved.emit(b)
			Sfx.play("block_land")
	if _drag_offset.length() > 0.5:
		_settle[b.id] = _drag_offset
	else:
		game.set_held(b, false)
	_drag_offset = Vector2.ZERO
	queue_redraw()


## Fill shown in the block: suction grains count when they arrive.
func shown_progress(b: SandBlock) -> float:
	if b.capacity <= 0:
		return 1.0
	var flying := fx.pending(b.id) if fx != null and game.is_suction() else 0
	return clampf(float(b.collected - flying) / b.capacity, 0.0, 1.0)


func _on_block_filled(b: SandBlock) -> void:
	if fx != null and game.is_suction() and fx.pending(b.id) > 0:
		# Logic already freed the cells; keep drawing the block until the last grain lands.
		_landing.append(b)
		return
	_pop(b)


func _pop(b: SandBlock) -> void:
	var rects := []
	for c in b.cells:
		rects.append(Rect2(Vector2(b.pos + c) * cell, Vector2(cell, cell)))
	_ghosts.append({"rects": rects, "color": game.map.palette[b.color_id], "t": 0.0})
	Sfx.play("block_full")


func _process(delta: float) -> void:
	_time += delta
	for id in _settle.keys():
		var o: Vector2 = _settle[id]
		o = o.lerp(Vector2.ZERO, 1.0 - exp(-SETTLE_SPEED * delta))
		if o.length() < 0.5:
			_settle.erase(id)
			var b := game.board.get_block(id)
			if b:
				game.set_held(b, false)
		else:
			_settle[id] = o
	for b in _landing.duplicate():
		if fx == null or fx.pending(b.id) == 0:
			_landing.erase(b)
			_pop(b)
	for g in _ghosts:
		g.t += delta / 0.55
	_ghosts = _ghosts.filter(func(g): return g.t < 1.0)
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var bd := game.board
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BOARD_BG)
	for y in bd.rows:
		for x in bd.cols:
			var r := Rect2(Vector2(x, y) * cell, Vector2(cell, cell)).grow(-3)
			if bd.walls.has(Vector2i(x, y)):
				draw_rect(r, UiKit.WALL)
				draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, 6)), UiKit.WALL.lightened(0.2))
			else:
				draw_rect(r, UiKit.BOARD_CELL)
	# Intake strip: board row 0 touches the landscape.
	draw_rect(Rect2(0, 0, size.x, 4), UiKit.ACCENT.lerp(UiKit.BOARD_BG, 0.4))
	if _drag != null and not _hint.is_empty():
		var hc: Color = game.map.palette[_drag.color_id]
		var pulse := 0.3 + 0.15 * sin(_time * 6.0)
		for x in bd.cols:
			if (_hint[x] >> _drag.color_id) & 1 and not bd.walls.has(Vector2i(x, 0)):
				var r := Rect2(Vector2(x, 0) * cell, Vector2(cell, cell)).grow(-3)
				draw_rect(r, Color(hc, pulse))
				draw_rect(Rect2(r.position.x, 0, r.size.x, 8), Color(hc, 0.9))

	for b in bd.blocks:
		if not b.removed and b != _drag:
			_draw_block(b)
	if _drag != null:
		_draw_block(_drag)
	for b in _landing:
		_draw_block(b)
	for g in _ghosts:
		var t: float = g.t
		var col: Color = g.color
		for r in g.rects:
			var rr: Rect2 = r
			var grow := t * cell * 0.25
			draw_rect(rr.grow(grow), Color(UiKit.lighten(col, 0.4), 1.0 - t))
			draw_rect(rr.grow(grow), Color(1, 1, 1, (1.0 - t) * 0.9), false, 4.0)


func _draw_block(b: SandBlock) -> void:
	var sand: Color = game.map.palette[b.color_id]
	var body := UiKit.lighten(sand, 0.72)
	var edge := sand.darkened(0.25)
	var bs := b.bounds_size()
	var origin := Vector2(b.pos) * cell + visual_offset(b)
	var inner_h := bs.y * cell
	var shown := shown_progress(b)
	var fill_top := origin.y + inner_h * (1.0 - shown)
	var lift := 4.0 if b == _drag else 0.0
	for c in b.cells:
		var r := block_rect(b, c).grow(-4)
		r.position.y -= lift
		draw_rect(r, body)
		# Sand level inside the block (shared across the whole shape).
		var top := maxf(r.position.y, fill_top)
		if top < r.end.y:
			var fr := Rect2(r.position.x, top, r.size.x, r.end.y - top)
			draw_rect(fr, sand)
			if top > r.position.y + 1.0:
				var wobble := sin(_time * 6.0 + r.position.x * 0.05) * 1.5
				draw_rect(Rect2(fr.position.x, top - 1.0 + wobble * 0.0, fr.size.x, 3), sand.lightened(0.3))
	# Outline per exposed cell edge so the shape reads as one piece.
	var cellset := {}
	for c in b.cells:
		cellset[c] = true
	for c in b.cells:
		var r := block_rect(b, c).grow(-4)
		r.position.y -= lift
		if not cellset.has(c + Vector2i.UP):
			draw_line(r.position, Vector2(r.end.x, r.position.y), edge, 5.0)
		if not cellset.has(c + Vector2i.DOWN):
			draw_line(Vector2(r.position.x, r.end.y), r.end, edge, 5.0)
		if not cellset.has(c + Vector2i.LEFT):
			draw_line(r.position, Vector2(r.position.x, r.end.y), edge, 5.0)
		if not cellset.has(c + Vector2i.RIGHT):
			draw_line(Vector2(r.end.x, r.position.y), r.end, edge, 5.0)
	# Contact glow while actually collecting.
	if game.collector.is_collecting(b) and not game.is_held(b):
		var a := 0.55 + 0.35 * sin(_time * 10.0)
		for c in b.cells:
			if b.pos.y + c.y == 0:
				var r := block_rect(b, c)
				draw_rect(Rect2(r.position.x + 4, r.position.y, r.size.x - 8, 6), Color(1, 1, 1, a))
	# Percent label on the first cell.
	var pct := "%d%%" % int(floor(shown * 100.0))
	var first := block_rect(b, b.cells[0])
	first.position.y -= lift
	var fs := 22
	var tw := _font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := first.get_center() + Vector2(-tw * 0.5, fs * 0.35)
	draw_string(_font, tp + Vector2(1, 1), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8))
	draw_string(_font, tp, pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, edge.darkened(0.3))
