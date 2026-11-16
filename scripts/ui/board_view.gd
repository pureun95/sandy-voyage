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
var _geo := {}  # SandBlock -> cached block-local drawing geometry (see _block_geo)
var _badge_font: FontVariation


func bind(g: SandGame) -> void:
	game = g
	cell = size.x / g.board.cols
	_geo.clear()
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
	if _drag != null:
		_release()  # a release was lost (e.g. focus change): never leave a block held
	var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
	var b := game.board.block_at(c)
	if b == null or _settle.has(b.id):
		return
	_drag = b
	_drag_start = p
	_drag_axis = Vector2i.ZERO
	_drag_offset = Vector2.ZERO
	# The block keeps collecting until the drag really starts (_motion locks an axis):
	# selecting a block, or pressing without moving it, does not pause its suction.
	# Hint: which intake columns could feed this block's color right now (same rule as collection).
	_hint = game.contact_masks()
	Sfx.play("drag_start")


func _motion(p: Vector2) -> void:
	var d := p - _drag_start
	if _drag_axis == Vector2i.ZERO:
		if d.length() < AXIS_THRESHOLD:
			return
		_drag_axis = Vector2i.RIGHT if absf(d.x) >= absf(d.y) else Vector2i.DOWN
		game.set_held(_drag, true)  # lifted: stops collecting until it lands again
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
	# The pop starts as the block's exact crate outline and expands/fades from its centre.
	var g := _block_geo(b)
	var box: Rect2 = g.outer_box
	var centre := box.get_center()
	_ghosts.append({
		"poly": _shift(g.outer, -centre),
		"at": Vector2(b.pos) * cell + centre,
		"color": g.c_shine, "rim": g.c_rim_light, "t": 0.0,
	})
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
		# Columns the dragged block already feeds from where it stands are not new targets.
		var here := _drag.contact_columns()
		for x in bd.cols:
			if here.has(x):
				continue
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
	var k := cell / 80.0
	for g in _ghosts:
		var t: float = g.t
		var e := 1.0 - pow(1.0 - t, 3.0)  # ease-out
		var poly: PackedVector2Array = g.poly
		draw_set_transform(g.at, 0.0, Vector2.ONE * (1.0 + 0.16 * e))
		draw_colored_polygon(poly, Color(g.color, (1.0 - t) * 0.85))
		var ring := poly.duplicate()
		ring.append(poly[0])
		draw_polyline(ring, Color(1, 1, 1, (1.0 - t) * 0.95), 4.0 * k * (1.0 - t * 0.6))
		# Pixel bits fly off the crate corners.
		var bit := 5.0 * k
		for p in poly:
			var q := p * (1.0 + 0.35 * e)
			draw_rect(Rect2(q - Vector2(bit, bit) * 0.5, Vector2(bit, bit)), Color(g.rim, 1.0 - t))
		draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- block look: "pixel travel crate"
# Pure drawing. Each block's shape is turned into block-local polygons once (_block_geo) and
# reused every frame; only the sand level, lift/offset and pulses change per frame.
# Sizes are authored for the 80px reference cell and scaled by k = cell / 80.

const CRATE_INSET := 3.0     # gap between the crate and its board cells
const CRATE_CHAMFER := 6.0   # cut corners (pixel-art step)
const CRATE_DEPTH := 5.0     # dark side band under the rim
const CRATE_RIM := 8.0       # rim thickness
const CRATE_WALL := 7.0      # shaded back wall at the top of the well
const CRATE_LIFT := 5.0      # rise while dragged
# Percent badge. The game is 720 logical px wide, so 1 px ≈ 0.57dp on a 411dp phone and
# 0.5dp on a 360dp one: 18 px digits ≈ 10.3 / 9dp. Digits are bold and large, "%" is small so
# "100%" still fits a 1-cell crate. The badge sits on the rim corner, over little of the sand.
const BADGE_FONT := 18
const BADGE_PCT_FONT := 12
const BADGE_EMBOLDEN := 0.6
const BADGE_H := 23.0
const BADGE_PAD := 5.0


func _draw_block(b: SandBlock) -> void:
	var g := _block_geo(b)
	var k := cell / 80.0
	var lifted := b == _drag
	var lift := CRATE_LIFT * k if lifted else 0.0
	var origin := Vector2(b.pos) * cell + visual_offset(b)

	# Pre-triangulated static layers (draw_colored_polygon would re-triangulate every frame).
	var ci := get_canvas_item()
	# Shadow stays on the board; it softens while the crate is lifted.
	draw_set_transform(origin + Vector2(0, lift + 4.0 * k if lifted else 5.0 * k))
	RenderingServer.canvas_item_add_triangle_array(ci, g.shadow_idx, g.outer,
		g.shadow_cols_lift if lifted else g.shadow_cols)

	draw_set_transform(origin - Vector2(0, lift))
	# Rim (dark side band, lit top band, mid tone), well back wall and floor: one call.
	RenderingServer.canvas_item_add_triangle_array(ci, g.body_idx, g.body_pts, g.body_cols)

	# Sand: one level across the whole shape, drawn from cached horizontal strips.
	var shown := shown_progress(b)
	var box: Rect2 = g.well_box
	var fill_top := box.end.y - box.size.y * shown
	if shown > 0.0:
		for s in g.strips:
			if s.y1 <= fill_top:
				continue
			var y0 := maxf(s.y0, fill_top)
			for sp in s.spans:
				draw_rect(Rect2(sp.x, y0, sp.y - sp.x, s.y1 - y0), g.c_sand)
		# Grain-sized speckle, cached bottom-up: stop at the first one above the level.
		var pos: PackedVector2Array = g.speck_pos
		var tone: PackedByteArray = g.speck_tone
		var gs := Vector2(g.speck_size, g.speck_size)
		for i in pos.size():
			if pos[i].y < fill_top:
				break
			draw_rect(Rect2(pos[i], gs), g.c_speck_lo if tone[i] == 0 else g.c_speck_hi)
		if shown < 1.0:
			var spans := _spans_at(g.strips, minf(fill_top + 2.0 * k, box.end.y - 0.01))
			var line_h := minf(2.5 * k, box.end.y - fill_top + 1.0 * k)
			for sp in spans:
				draw_rect(Rect2(sp.x, fill_top - 1.0 * k, sp.y - sp.x, line_h), g.c_surface)
				if fill_top + 4.0 * k < box.end.y:
					draw_rect(Rect2(sp.x, fill_top + 1.5 * k, sp.y - sp.x, 2.5 * k), g.c_shine)

	# Contact pulse along the top rim while actually collecting.
	if b.pos.y == 0 and game.collector.is_collecting(b) and not game.is_held(b):
		var a := 0.55 + 0.35 * sin(_time * 10.0)
		_fill_polys(g.glow, Color(1, 1, 1, a))

	# Percent badge: bottom-right cell corner, on the rim; hidden at 0%.
	var pct_i := int(floor(shown * 100.0))
	if pct_i > 0:
		_draw_badge(g, pct_i, k)
	draw_set_transform(Vector2.ZERO)


func _draw_badge(g: Dictionary, pct_i: int, k: float) -> void:
	if _badge_font == null:
		_badge_font = FontVariation.new()
		_badge_font.base_font = _font
		_badge_font.variation_embolden = BADGE_EMBOLDEN
	var num := str(pct_i)
	var fs := maxi(10, roundi(BADGE_FONT * k))
	var ps := maxi(8, roundi(BADGE_PCT_FONT * k))
	var nw := _badge_font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pw := _badge_font.get_string_size("%", HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x
	var bh := BADGE_H * k
	var bw := nw + pw + (BADGE_PAD * 2.0 + 1.0) * k
	var cr: Rect2 = g.badge_cell
	# Right edge just inside the crate's outer edge (over the rim); bottom 1px into the gap
	# below the crate, so it covers the rim and only the lowest few px of the well.
	var badge := Rect2(cr.end.x - (CRATE_INSET + 1.0) * k - bw, cr.end.y - (CRATE_INSET - 1.0) * k - bh, bw, bh)
	draw_style_box(g.badge_box, badge)
	draw_rect(Rect2(badge.position.x + 2.0 * k, badge.position.y + 1.0 * k, badge.size.x - 4.0 * k, 1.5 * k), g.c_badge_hi)
	var asc := _badge_font.get_ascent(fs)
	var base_y := badge.position.y + (bh - (asc + _badge_font.get_descent(fs))) * 0.5 + asc
	var x := badge.position.x + BADGE_PAD * k
	draw_string(_badge_font, Vector2(x, base_y), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_string(_badge_font, Vector2(x + nw + 1.0 * k, base_y), "%", HORIZONTAL_ALIGNMENT_LEFT, -1, ps, Color(1, 1, 1, 0.9))


## Rim tone: the sand color pulled toward the UI's cocoa text color; light sands are pulled
## further so foam / snow crates still read on the beige board.
static func _rim_color(sand: Color) -> Color:
	var amt := clampf((sand.get_luminance() - 0.3) * 0.85, 0.14, 0.5)
	return sand.lerp(UiKit.TEXT, amt).darkened(0.06)


## Block-local geometry and colors, built once per block (cells and color never change).
func _block_geo(b: SandBlock) -> Dictionary:
	var g: Dictionary = _geo.get(b, {})
	if not g.is_empty():
		return g
	var k := cell / 80.0
	var sand: Color = game.map.palette[b.color_id]
	var rim := _rim_color(sand)
	var depth := CRATE_DEPTH * k
	var outer := _chamfer(_cell_union(b), CRATE_INSET * k, CRATE_CHAMFER * k)
	var top_face := _clip([outer], _shift(outer, Vector2(0, -depth)))
	var well := _offset(_shift(outer, Vector2(0, -depth * 0.5)), -CRATE_RIM * k, Geometry2D.JOIN_MITER)
	var strips := _strips(well)
	var floor_c := UiKit.BG.lerp(sand, 0.3)

	var glow := []
	var corner := b.cells[0]
	for c in b.cells:
		if c.y == 0:
			glow.append_array(_clip([outer], _rect_poly(Rect2(Vector2(c) * cell, Vector2(cell, 6.0 * k)))))
		if c.y > corner.y or (c.y == corner.y and c.x > corner.x):
			corner = c

	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = rim.darkened(0.25)
	badge_box.set_corner_radius_all(maxi(1, roundi(3.0 * k)))

	g = {
		"outer": outer, "outer_box": _bounds(outer),
		"top_face": top_face,
		"top_mid": _clip(top_face, _shift(outer, Vector2(0, 3.0 * k))),
		"well": well, "well_box": _bounds(well),
		"floor": _clip([well], _shift(well, Vector2(0, CRATE_WALL * k))),
		"strips": strips, "glow": glow,
		"badge_cell": Rect2(Vector2(corner) * cell, Vector2(cell, cell)), "badge_box": badge_box,
		"c_sand": sand, "c_rim": rim,
		"c_rim_dark": rim.darkened(0.28), "c_rim_light": rim.lightened(0.32),
		"c_floor": floor_c, "c_wall": floor_c.lerp(rim, 0.3),
		"c_surface": sand.lerp(rim, 0.55), "c_shine": sand.lerp(Color.WHITE, 0.35),
		"c_speck_lo": sand.darkened(0.07), "c_speck_hi": sand.lightened(0.09),
		"c_shadow": Color(UiKit.TEXT, 0.22), "c_shadow_lift": Color(UiKit.TEXT, 0.14),
		"c_badge_hi": Color(rim.lightened(0.25), 0.55),
	}
	_build_speckle(g, well, b)
	# Static layers, triangulated once, back to front.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	_add_tris(pts, cols, idx, [outer], g.c_rim_dark)
	_add_tris(pts, cols, idx, top_face, g.c_rim_light)
	_add_tris(pts, cols, idx, g.top_mid, g.c_rim)
	_add_tris(pts, cols, idx, [well], g.c_wall)
	_add_tris(pts, cols, idx, g.floor, g.c_floor)
	g.body_pts = pts
	g.body_cols = cols
	g.body_idx = idx
	g.shadow_idx = Geometry2D.triangulate_polygon(outer)
	var sc := PackedColorArray()
	var scl := PackedColorArray()
	sc.resize(outer.size())
	scl.resize(outer.size())
	sc.fill(g.c_shadow)
	scl.fill(g.c_shadow_lift)
	g.shadow_cols = sc
	g.shadow_cols_lift = scl
	_geo[b] = g
	return g


static func _add_tris(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, polys: Array, col: Color) -> void:
	for p in polys:
		if p.size() < 3:
			continue
		var tri := Geometry2D.triangulate_polygon(p)
		if tri.is_empty():
			continue
		var base := pts.size()
		pts.append_array(p)
		for i in p.size():
			cols.append(col)
		for t in tri:
			idx.append(base + t)


## Speckle squares the size of one landscape grain, fully inside the well, sorted bottom-up.
func _build_speckle(g: Dictionary, well: PackedVector2Array, b: SandBlock) -> void:
	var k := cell / 80.0
	var size_px := clampf(fx.grain if fx != null else 5.0 * k, 3.0 * k, 7.0 * k)
	var box: Rect2 = g.well_box
	var seed := absi(hash(b.id))
	var pos := PackedVector2Array()
	var tone := PackedByteArray()
	var row := 0
	var y := box.end.y - size_px
	while y >= box.position.y:
		var col := 0
		var x := box.position.x
		while x + size_px <= box.end.x:
			var m := absi((col * 73856093) ^ (row * 19349663) ^ seed) % 7
			if m <= 1:
				var r := Rect2(x, y, size_px, size_px).grow(-0.01)
				if Geometry2D.is_point_in_polygon(r.position, well) and Geometry2D.is_point_in_polygon(r.end, well) \
						and Geometry2D.is_point_in_polygon(Vector2(r.end.x, r.position.y), well) \
						and Geometry2D.is_point_in_polygon(Vector2(r.position.x, r.end.y), well):
					pos.append(Vector2(x, y))
					tone.append(m)
			x += size_px
			col += 1
		y -= size_px
		row += 1
	g.speck_pos = pos
	g.speck_tone = tone
	g.speck_size = size_px


func _fill_polys(polys: Array, col: Color) -> void:
	for p in polys:
		if p.size() >= 3:
			draw_colored_polygon(p, col)


# ---------------------------------------------------------------- geometry helpers (block-local)

## Union of the block's cells. Cells are merged in edge-adjacent order: merging a cell that only
## touches the shape at a corner (J, Td start that way) would split the union in two.
func _cell_union(b: SandBlock) -> PackedVector2Array:
	var todo: Array[Vector2i] = b.cells.duplicate()
	var first: Vector2i = todo.pop_front()
	var done := {first: true}
	var acc := _rect_poly(Rect2(Vector2(first) * cell, Vector2(cell, cell)))
	while not todo.is_empty():
		var merged := false
		for i in todo.size():
			var c: Vector2i = todo[i]
			if done.has(c + Vector2i.UP) or done.has(c + Vector2i.DOWN) or done.has(c + Vector2i.LEFT) or done.has(c + Vector2i.RIGHT):
				acc = _largest(Geometry2D.merge_polygons(acc, _rect_poly(Rect2(Vector2(c) * cell, Vector2(cell, cell)))))
				done[c] = true
				todo.remove_at(i)
				merged = true
				break
		if not merged:
			break  # disconnected shape (none exist): draw the connected part
	return acc


## The well as horizontal strips of constant spans (1px sampling, equal rows merged), so the
## sand level is a handful of draw_rect calls instead of a polygon clip per frame.
static func _strips(well: PackedVector2Array) -> Array:
	var box := _bounds(well)
	var out := []
	var y := floorf(box.position.y)
	while y < box.end.y:
		var y0 := maxf(y, box.position.y)
		var y1 := minf(y + 1.0, box.end.y)
		var mid := (y0 + y1) * 0.5
		var spans: Array[Vector2] = []
		for seg in Geometry2D.intersect_polyline_with_polygon(
				PackedVector2Array([Vector2(box.position.x - 1.0, mid), Vector2(box.end.x + 1.0, mid)]), well):
			var a := minf(seg[0].x, seg[seg.size() - 1].x)
			var c := maxf(seg[0].x, seg[seg.size() - 1].x)
			spans.append(Vector2(snappedf(a, 0.01), snappedf(c, 0.01)))
		spans.sort_custom(func(p, q): return p.x < q.x)
		if not out.is_empty() and out[-1].spans == spans:
			out[-1].y1 = y1
		elif not spans.is_empty():
			out.append({"y0": y0, "y1": y1, "spans": spans})
		y += 1.0
	return out


static func _spans_at(strips: Array, y: float) -> Array:
	for s in strips:
		if y >= s.y0 and y < s.y1:
			return s.spans
	return []


static func _chamfer(base: PackedVector2Array, inset: float, c: float) -> PackedVector2Array:
	var p := _offset(base, -inset, Geometry2D.JOIN_MITER)
	return _offset(_offset(p, -c, Geometry2D.JOIN_MITER), c, Geometry2D.JOIN_SQUARE)


static func _offset(p: PackedVector2Array, d: float, join: int) -> PackedVector2Array:
	return _largest(Geometry2D.offset_polygon(p, d, join))


static func _largest(arr: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_a := 0.0
	for p in arr:
		var s := 0.0
		for i in p.size():
			var a: Vector2 = p[i]
			var c: Vector2 = p[(i + 1) % p.size()]
			s += a.x * c.y - c.x * a.y
		if absf(s) > best_a:
			best_a = absf(s)
			best = p
	return best


static func _shift(p: PackedVector2Array, v: Vector2) -> PackedVector2Array:
	return Transform2D(0.0, v) * p


static func _clip(polys: Array, mask: PackedVector2Array) -> Array:
	var out := []
	for p in polys:
		if p.size() >= 3 and mask.size() >= 3:
			out.append_array(Geometry2D.intersect_polygons(p, mask))
	return out


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r
