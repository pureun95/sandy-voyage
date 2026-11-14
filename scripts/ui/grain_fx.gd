class_name GrainFx
extends Control
## Flying sand grains (pure visual). Stores particles in packed arrays and draws them
## in one _draw call. The sand data is already updated when a grain spawns here.
##  - spawn():      channel rule, a curved flight from the landscape into the block.
##  - spawn_path(): gravity rule, a grain travelling along its real same-color path to
##                  the intake, then into the block (drawn lighter so the stream shows
##                  over sand of the same color).

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


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var cfg := StageLoader.config()
	limit = int(cfg.get("particle_limit", limit))
	var f: Array = cfg.get("particle_flight_seconds", [0.35, 0.6])
	flight = Vector2(f[0], f[1])


func count() -> int:
	return _t.size() + _pt.size()


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
	if _t.is_empty() and _pt.is_empty():
		return
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
