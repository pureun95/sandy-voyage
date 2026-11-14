class_name SaveStore
extends RefCounted
## Local progress: cleared stages, unlocked album entries, settings. JSON in user://.

const VERSION := 1

var path := "user://save.json"
var data := {}


func _init(p_path := "user://save.json") -> void:
	path = p_path
	data = _defaults()


static func _defaults() -> Dictionary:
	return {"version": VERSION, "cleared": {}, "album": {},
		"settings": {"resolution": 128, "sound": true}}


func load_data() -> void:
	data = _defaults()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for k in data:
			if parsed.has(k) and typeof(parsed[k]) == typeof(data[k]):
				if data[k] is Dictionary:
					data[k].merge(parsed[k], true)
				else:
					data[k] = parsed[k]


func save_data() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveStore: cannot write %s (%s)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func mark_cleared(stage_id: String, destination_id: String) -> void:
	var now := int(Time.get_unix_time_from_system())
	if not data.cleared.has(stage_id):
		data.cleared[stage_id] = {"at": now}
	if not data.album.has(destination_id):
		data.album[destination_id] = {"at": now, "first_stage": stage_id}
	save_data()


func is_cleared(stage_id: String) -> bool:
	return data.cleared.has(stage_id)


func is_unlocked(destination_id: String) -> bool:
	return data.album.has(destination_id)


func get_setting(key: String, default: Variant = null) -> Variant:
	return data.settings.get(key, default)


func set_setting(key: String, value: Variant) -> void:
	data.settings[key] = value
	save_data()
