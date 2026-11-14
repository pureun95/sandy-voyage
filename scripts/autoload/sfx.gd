extends Node
## Autoload "Sfx": sound events decoupled from game code.
## Game code only calls Sfx.play("event"). Which file plays for an event is set in
## data/sounds.json, so sounds can be added or swapped without touching gameplay.
## Events: drag_start, block_land, collect_grain, block_full, stage_clear, ui_tap.

const SOUNDS_PATH := "res://data/sounds.json"
const POOL_SIZE := 6

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_play := {}


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS_PATH))
	if parsed is Dictionary:
		var events: Dictionary = parsed.get("events", {})
		for ev in events:
			var path := str(events[ev])
			if path != "" and ResourceLoader.exists(path):
				_streams[ev] = load(path)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func enabled() -> bool:
	return bool(App.save.get_setting("sound", true))


## `min_interval` throttles rapid repeats (e.g. per-grain events).
func play(event: String, volume_db := 0.0, min_interval := 0.0) -> void:
	if not enabled() or not _streams.has(event):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_interval > 0.0 and now - float(_last_play.get(event, -99.0)) < min_interval:
		return
	_last_play[event] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[event]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()
