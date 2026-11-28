extends RefCounted
## Injects test-only destinations/stages (a JSON fixture such as
## res://tests/fixtures/gyeongju_test_stages.json) into StageLoader's in-memory caches.
## data/*.json and save files are never written. Used by autoplay (--extra-stages=) and
## tests/validate_levels.gd (--extra=). Not exported (tests/* is in the export exclude filter).


## Returns the injected stage ids (empty + error on a bad file).
static func inject(path: String) -> PackedStringArray:
	var ids := PackedStringArray()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("stage_fixture: cannot read %s" % path)
		return ids
	StageLoader.destinations()  # fill the caches first so lazy loading does not drop the injection
	StageLoader.stages()
	for d in data.get("destinations", []):
		var dest: Dictionary = d.duplicate(true)
		dest.album_path = str(d.album)
		var paths := {}
		for res in d.puzzle:
			paths[res] = str(d.puzzle[res])
		dest.puzzle_paths = paths
		var colors: Array[Color] = []
		var keys: Array[String] = []
		for p in d.palette:
			keys.append(p.key)
			colors.append(Color.html(p.color))
		dest.palette_colors = colors
		dest.palette_keys = keys
		StageLoader._dest_cache[d.id] = dest
	for s in data.get("stages", []):
		if not StageLoader.get_stage(str(s.id)).is_empty():
			push_error("stage_fixture: stage %s already exists in data/stages.json" % s.id)
			continue
		StageLoader._stage_cache.append(s)
		ids.append(str(s.id))
	return ids
