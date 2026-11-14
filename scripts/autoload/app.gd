extends Node
## Autoload "App": persistent save + settings shared by all screens.

var save := SaveStore.new()


func _ready() -> void:
	save.load_data()


func resolution() -> int:
	var r := int(save.get_setting("resolution", StageLoader.config().get("default_resolution", 128)))
	return r if r in [64, 128] else 128
