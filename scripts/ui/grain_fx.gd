class_name GrainFx
extends Control
## Flying sand grains (pure visual). Stores particles in packed arrays and draws them
## in one _draw call. The sand data is already updated when a grain spawns here.
##  - spawn():      channel rule, a curved flight from the landscape into the block.
##  - spawn_path(): gravity rule A, a grain travelling along its real same-color path to
##                  the intake, then into the block (drawn lighter so the stream shows
##                  over sand of the same color).
##  - spawn_suction(): gravity rule B-2, a grain lifted from its own cell (it appears there
##                  the same frame the cell is emptied, so nothing vanishes), pulled with
##                  growing speed to its intake cell, then into the block. Original color with
##                  a contrasting rim and a short trail. Never dropped: one particle per
##                  collected grain, and `in_flight[block id]` counts them until they land,
##                  so the shown fill can follow the arriving grains.

const PATH_POINTS := 8

var limit := 1200
var flight := Vector2(0.35, 0.6)
var path_speed := 520.0
var grain := 5.0

var _from := PackedVector2Array()
var _ctrl := PackedVector2Array()
var _to := PackedVector2Array()
var _t := PackedFloat32Array()
var _dur := PackedFloat32Array()
var _col := PackedColorArray()

var _pp := PackedVector2Array()   # PATH_POINTS slots per path particle
var _pn := PackedInt32Array()     # used points
var _plen := PackedFloat32Array() # total length
var _pt := PackedFloat32Array()
var _pd := PackedFloat32Array()
var _pc := PackedColorArray()

var suction_speed := 350.0   # px/s (set from config by the game screen)
var suction_min := 0.22
var suction_max := 0.8
var suction_finish_scale := 1.6
var in_flight := {}               # block id -> particles still flying to it
var _sf := PackedVector2Array()   # from
var _sc := PackedVector2Array()   # bezier control
var _sv := PackedVector2Array()   # intake (landscape bottom)
var _st := PackedVector2Array()   # inside the block
var _su := PackedFloat32Array()   # 0..1
var _sd := PackedFloat32Array()   # duration
var _scol := PackedColorArray()
var _srim := PackedColorArray()
var _sid := PackedStringArray()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var cfg := StageLoader.config()
	limit = int(cfg.get("particle_limit", limit))
	var f: Array = cfg.get("particle_flight_seconds", [0.35, 0.6])
	flight = Vector2(f[0], f[1])


func count() -> int:
	return _t.size() + _pt.size() + _su.size()


func in_flight_total() -> int:
	return _su.size()


func pending(block_id: String) -> int:
	return int(in_flight.get(block_id, 0))


## `from`: the grain's cell centre; `via`: its intake cell centre; `to`: landing point in the block.
func spawn_suction(from: Vector2, via: Vector2, to: Vector2, color: Color, block_id: String, finishing := false) -> void:
	var d := from.distance_to(via) + via.distance_to(to) * 0.5
	var dur := clampf(d / suction_speed, suction_min, suction_max) * randf_range(0.92, 1.08)
	if finishing:
		dur /= suction_finish_scale
	# Control point: straight above the intake, a little toward the grain, plus a slight swirl,
	# so grains curve in as if drawn by the block.
	var side := Vector2(-(via.y - from.y), via.x - from.x).normalized() * randf_range(-0.12, 0.12) * from.distance_to(via)
	_sf.append(from)
	_sc.append(Vector2(lerpf(via.x, from.x, 0.35), lerpf(from.y, via.y, 0.55)) + side)
	_sv.append(via)
	_st.append(to)
	_su.append(0.0)
	_sd.append(dur)
	_scol.append(color)
	_srim.append(color.darkened(0.55) if color.get_luminance() > 0.45 else color.lightened(0.55))
	_sid.append(block_id)
	in_flight[block_id] = int(in_flight.get(block_id, 0)) + 1


func _suction_pos(i: int, u: float) -> Vector2:
	const SPLIT := 0.82
	if u < SPLIT:
		var e := u / SPLIT
		e = e * e * (0.6 + 0.4 * e)  # starts slow (lifts from its cell), then accelerates
		var a := _sf[i].lerp(_sc[i], e)
		var b := _sc[i].lerp(_sv[i], e)
		return a.lerp(b, e)
	return _sv[i].lerp(_st[i], (u - SPLIT) / (1.0 - SPLIT))


func spawn(from: Vector2, to: Vector2, color: Color) -> void:
	if count() >= limit:
		return
	_from.append(from)
	# Fall mostly straight down first, then curve into the block like a drain.
	_ctrl.append(Vector2(from.x + (to.x - from.x) * 0.15, lerpf(from.y, to.y, 0.8)))
	_to.append(to)
	_t.append(0.0)
	_dur.append(randf_range(flight.x, flight.y))
	_col.append(color)


## `points`: screen positions from the grain's cell along its path to the block.
func spawn_path(points: PackedVector2Array, color: Color) -> void:
	if count() >= limit or points.size() < 2:
		return
	var pts := points
	if pts.size() > PATH_POINTS:
		pts = PackedVector2Array()
		for k in PATH_POINTS:
			pts.append(points[roundi(float(k) * (points.size() - 1) / (PATH_POINTS - 1))])
	var length := 0.0
	for k in range(1, pts.size()):
		length += pts[k - 1].distance_to(pts[k])
	var base := _pp.size()
	_pp.resize(base + PATH_POINTS)
	for k in pts.size():
		_pp[base + k] = pts[k]
	_pn.append(pts.size())
	_plen.append(length)
	_pt.append(0.0)
	_pd.append(clampf(length / path_speed, 0.18, 1.1) * randf_range(0.9, 1.1))
	_pc.append(color.lightened(0.35))


func _process(delta: float) -> void:
	if _t.is_empty() and _pt.is_empty() and _su.is_empty():
		return
	var si := 0
	while si < _su.size():
		_su[si] += delta / _sd[si]
		if _su[si] >= 1.0:
			var id := _sid[si]
			in_flight[id] = int(in_flight.get(id, 1)) - 1
			if int(in_flight[id]) <= 0:
				in_flight.erase(id)
			var last := _su.size() - 1
			_sf[si] = _sf[last]; _sc[si] = _sc[last]; _sv[si] = _sv[last]; _st[si] = _st[last]
			_su[si] = _su[last]; _sd[si] = _sd[last]; _scol[si] = _scol[last]; _srim[si] = _srim[last]
			_sid[si] = _sid[last]
			_sf.resize(last); _sc.resize(last); _sv.resize(last); _st.resize(last)
			_su.resize(last); _sd.resize(last); _scol.resize(last); _srim.resize(last); _sid.resize(last)
		else:
			si += 1
	var i := 0
	while i < _t.size():
		_t[i] += delta / _dur[i]
		if _t[i] >= 1.0:
			var last := _t.size() - 1
			_from[i] = _from[last]; _ctrl[i] = _ctrl[last]; _to[i] = _to[last]
			_t[i] = _t[last]; _dur[i] = _dur[last]; _col[i] = _col[last]
			_from.resize(last); _ctrl.resize(last); _to.resize(last)
			_t.resize(last); _dur.resize(last); _col.resize(last)
		else:
			i += 1
	i = 0
	while i < _pt.size():
		_pt[i] += delta / _pd[i]
		if _pt[i] >= 1.0:
			var last := _pt.size() - 1
			for k in PATH_POINTS:
				_pp[i * PATH_POINTS + k] = _pp[last * PATH_POINTS + k]
			_pn[i] = _pn[last]; _plen[i] = _plen[last]; _pt[i] = _pt[last]
			_pd[i] = _pd[last]; _pc[i] = _pc[last]
			_pp.resize(last * PATH_POINTS)
			_pn.resize(last); _plen.resize(last); _pt.resize(last); _pd.resize(last); _pc.resize(last)
		else:
			i += 1
	queue_redraw()


func _draw() -> void:
	var s := Vector2(grain, grain)
	for i in _t.size():
		var t := _t[i]
		var e := t * t * (1.6 - 0.6 * t)  # gentle start, accelerating into the block
		var a := _from[i].lerp(_ctrl[i], e)
		var b := _ctrl[i].lerp(_to[i], e)
		var p := a.lerp(b, e)
		var sc := 1.0 - 0.35 * e
		draw_rect(Rect2(p - s * sc * 0.5, s * sc), _col[i])
	for i in _pt.size():
		var t := _pt[i]
		var d := t * t * (1.5 - 0.5 * t) * _plen[i]  # accelerate toward the intake
		var base := i * PATH_POINTS
		var p := _pp[base + _pn[i] - 1]
		for k in range(1, _pn[i]):
			var seg := _pp[base + k - 1].distance_to(_pp[base + k])
			if d <= seg or k == _pn[i] - 1:
				p = _pp[base + k - 1].lerp(_pp[base + k], clampf(d / maxf(seg, 0.001), 0.0, 1.0))
				break
			d -= seg
		var sc := 1.0 - 0.3 * t
		draw_rect(Rect2(p - s * sc * 0.5, s * sc), _pc[i])
	for i in _su.size():
		var u := _su[i]
		var col := _scol[i]
		# Short trail (same color, fading) so the motion reads as a stream, not a jump.
		for back in [0.08, 0.04]:
			if u > back:
				var q := _suction_pos(i, u - back)
				var ts := s * (0.55 if back > 0.05 else 0.75)
				draw_rect(Rect2(q - ts * 0.5, ts), Color(col, 0.35 if back > 0.05 else 0.6))
		var p := _suction_pos(i, u)
		var sc := 1.0 if u < 0.82 else 1.0 - 0.45 * (u - 0.82) / 0.18
		var r := Rect2(p - s * sc * 0.5, s * sc)
		draw_rect(r.grow(1.0), _srim[i])  # rim keeps it distinct over sand of any color
		draw_rect(r, col)
