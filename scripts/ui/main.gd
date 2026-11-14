extends Control
## Root: switches between stage list, game and album.
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
		show_stage_select()


func _swap(c: Control) -> void:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = c
	add_child(c)
	move_child(c, 0)


func show_stage_select() -> void:
	var s := StageSelect.new()
	s.stage_chosen.connect(show_game)
	s.album_requested.connect(show_album)
	_swap(s)


func show_game(stage_id: String) -> GameScreen:
	var g := GameScreen.new()
	g.exit_requested.connect(show_stage_select)
	g.next_requested.connect(show_game)
	_swap(g)
	g.start(stage_id)
	return g


func show_album() -> void:
	var a := AlbumScreen.new()
	a.back_requested.connect(show_stage_select)
	_swap(a)
