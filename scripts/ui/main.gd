extends Control
## Root: switches between home, world map, continent (+ destination sheet), album and game.
## Debug: `-- --autoplay=<stage_id> --shots=<dir>` plays the stage via simulated drags.

var _screen: Control


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var auto := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay="):
			auto = a.substr(11)
	if auto != "":
		var pilot := preload("res://scripts/debug/autoplay.gd").new()
		pilot.main = self
		pilot.stage_id = auto
		add_child(pilot)
	else:
		show_home()


func _swap(c: Control) -> void:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = c
	add_child(c)
	move_child(c, 0)


func show_home() -> HomeScreen:
	var h := HomeScreen.new()
	h.stage_chosen.connect(show_game)
	h.map_requested.connect(show_world_map)
	h.album_requested.connect(func(): show_album())
	_swap(h)
	return h


func show_world_map() -> WorldMapScreen:
	var w := WorldMapScreen.new()
	w.back_requested.connect(show_home)
	w.continent_chosen.connect(func(cid): show_continent(cid))
	_swap(w)
	return w


## `open_destination` opens that destination's sheet on top (e.g. returning from a stage).
func show_continent(continent_id: String, open_destination := "") -> ContinentScreen:
	var c := ContinentScreen.new()
	c.continent_id = continent_id
	c.open_destination = open_destination
	c.back_requested.connect(show_world_map)
	c.stage_chosen.connect(show_game)
	c.album_requested.connect(func(cid): show_album(cid))
	_swap(c)
	return c


func show_destination(destination_id: String) -> ContinentScreen:
	var d := TravelCatalog.destination(destination_id)
	return show_continent(str(d.get("continent", "")), destination_id)


func show_game(stage_id: String) -> GameScreen:
	var g := GameScreen.new()
	g.exit_requested.connect(func(): show_destination(str(TravelCatalog.split_stage_id(g.stage_id).get("destination", ""))))
	g.next_requested.connect(show_game)
	_swap(g)
	g.start(stage_id)
	return g


func show_album(continent_id := "") -> AlbumScreen:
	var a := AlbumScreen.new()
	a.continent_id = continent_id
	a.back_requested.connect(show_home)
	_swap(a)
	return a
