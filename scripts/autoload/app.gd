extends Node
## Autoload "App": persistent save + settings shared by all screens.

var save := SaveStore.new()
## Lazily made postcard thumbnails (see ThumbLoader).
var thumbs: ThumbLoader
## Store purchases. Not saved locally: a store integration (not implemented yet) will fill these
## from the platform's purchase records. Separate from content readiness (TravelCatalog).
var entitlements := {"travel_pass": false, "no_ads": false}


func _ready() -> void:
	save.load_data()
	thumbs = ThumbLoader.new()
	thumbs.name = "Thumbs"
	add_child(thumbs)


## Sand resolution used to build stages (see effective_resolution). Reads the save, never writes it.
func resolution() -> int:
	return effective_resolution(save.get_setting("resolution", StageLoader.config().get("default_resolution", 128)),
		OS.is_debug_build())


## Release builds always run 128: the 64/128 comparison switch is debug-only (SettingsPanel),
## so a 64 saved by an earlier build must not strand a player there. The saved value itself is
## kept as is. Debug builds honour a saved 64 or 128; anything else falls back to 128.
const RELEASE_RESOLUTION := 128


static func effective_resolution(saved: Variant, debug_build: bool) -> int:
	if not debug_build:
		return RELEASE_RESOLUTION
	var r := int(saved) if (saved is int or saved is float or saved is String) else 0
	return r if r in [64, 128] else RELEASE_RESOLUTION
