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


func resolution() -> int:
	var r := int(save.get_setting("resolution", StageLoader.config().get("default_resolution", 128)))
	return r if r in [64, 128] else 128
