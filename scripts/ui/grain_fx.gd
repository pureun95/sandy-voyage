class_name GrainFx
extends Control
## Flying sand grains (pure visual). Stores particles in packed arrays and draws them
## in one _draw call. Data is already updated when a grain spawns here; this only
## shows it streaming from its landscape position into the collecting block.

var limit := 1200
var flight := Vector2(0.35, 0.6)
var grain := 5.0

var _from := PackedVector2Array()
var _ctrl := PackedVector2Array()
var _to := PackedVector2Array()
var _t := PackedFloat32Array()
var _dur := PackedFloat32Array()
var _col := PackedColorArray()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var cfg := StageLoader.config()
	limit = int(cfg.get("particle_limit", limit))
	var f: Array = cfg.get("particle_flight_seconds", [0.35, 0.6])
	flight = Vector2(f[0], f[1])


func count() -> int:
	return _t.size()


func spawn(from: Vector2, to: Vector2, color: Color) -> void:
	if _t.size() >= limit:
		return
	_from.append(from)
	# Fall mostly straight down first, then curve into the block like a drain.
	_ctrl.append(Vector2(from.x + (to.x - from.x) * 0.15, lerpf(from.y, to.y, 0.8)))
	_to.append(to)
	_t.append(0.0)
	_dur.append(randf_range(flight.x, flight.y))
	_col.append(color)


func _process(delta: float) -> void:
	if _t.is_empty():
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
