class_name GameScreen
extends Control
## Layout (720x1280): top info / sand landscape / block board / controls.
## The board's top edge is placed exactly on the landscape's bottom edge, matching
## the logical contact rule (board row 0 touches the landscape's bottom pixel row).

signal exit_requested
signal next_requested(stage_id: String)

const LAND_POS := Vector2(40, 116)
const LAND_SIZE := 640.0

var stage_id := ""
var game: SandGame
var sand_view: SandView
var board_view: BoardView
var fx: GrainFx
var _title: Label
var _progress: ProgressBar
var _pct: Label
var _overlay: Control
var _clear_pending := -1.0
var _settings: Control
var last_tick_usec := 0


func start(p_stage_id: String) -> void:
	stage_id = p_stage_id
	for c in get_children():
		c.queue_free()
	var stage := StageLoader.get_stage(stage_id)
	var built := StageLoader.build(stage, App.resolution())
	if built.game == null:
		push_error("GameScreen: %s" % [built.errors])
		add_child(UiKit.label("스테이지를 불러오지 못했어요\n%s" % "\n".join(built.errors)))
		return
	game = built.game
	_clear_pending = -1.0
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	# Top info
	_title = UiKit.label(str(game.stage.get("name_ko", stage_id)), 30)
	_title.position = Vector2(40, 18)
	_title.size = Vector2(520, 40)
	add_child(_title)
	var res := UiKit.label("%s · %d×%d" % [game.destination.get("name_ko", ""), game.map.width, game.map.height], 20, UiKit.TEXT_SOFT)
	res.position = Vector2(40, 60)
	add_child(res)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.position = Vector2(300, 66)
	_progress.size = Vector2(300, 22)
	_progress.max_value = 1.0
	add_child(_progress)
	_pct = UiKit.label("0%", 22, UiKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_pct.position = Vector2(600, 58)
	_pct.size = Vector2(80, 30)
	add_child(_pct)

	# Frame around landscape + board (one physical column).
	var cols := game.board.cols
	var cell := LAND_SIZE / cols
	var board_h := cell * game.board.rows
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, 22))
	frame.position = LAND_POS - Vector2(10, 10)
	frame.size = Vector2(LAND_SIZE + 20, LAND_SIZE + board_h + 20)
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(frame)

	sand_view = SandView.new()
	sand_view.position = LAND_POS
	sand_view.size = Vector2(LAND_SIZE, LAND_SIZE)
	add_child(sand_view)
	sand_view.bind(game)

	board_view = BoardView.new()
	board_view.position = LAND_POS + Vector2(0, LAND_SIZE)
	board_view.size = Vector2(LAND_SIZE, board_h)
	add_child(board_view)
	board_view.bind(game)

	fx = GrainFx.new()
	fx.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	fx.grain = sand_view.grain_size()
	add_child(fx)

	game.grains_collected.connect(_on_grains)
	game.stage_cleared.connect(_on_cleared)

	# Bottom controls
	var bar := HBoxContainer.new()
	bar.position = Vector2(40, 1170)
	bar.size = Vector2(640, 80)
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)
	for spec in [["목록", func(): exit_requested.emit()], ["다시 하기", func(): start(stage_id)],
			["설정", func(): _toggle_settings()]]:
		var b := UiKit.button(spec[0], spec[1])
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		bar.add_child(b)


func _on_grains(block: SandBlock, indices: PackedInt32Array) -> void:
	var color: Color = game.map.palette[block.color_id]
	var land_to_screen := sand_view.position
	var board_to_screen := board_view.position
	if game.is_gravity():
		# Each grain streams along its same-color path (cell -> intake pixel), then into the block.
		for path: PackedInt32Array in game.collector.last_paths:
			var pts := PackedVector2Array()
			for c in path:
				pts.append(land_to_screen + sand_view.grain_center(c))
			var intake := sand_view.grain_center(path[path.size() - 1]).x
			pts.append(board_to_screen + board_view.intake_point(block, intake))
			fx.spawn_path(pts, color)
		Sfx.play("collect_grain", -6.0, 0.06)
		return
	for i in indices:
		var from := land_to_screen + sand_view.grain_center(i)
		var to := board_to_screen + board_view.intake_point(block, sand_view.grain_center(i).x)
		fx.spawn(from, to, color)
	Sfx.play("collect_grain", -6.0, 0.06)


func _on_cleared() -> void:
	App.save.mark_cleared(stage_id, str(game.destination.id))
	_clear_pending = 0.9  # let the last grains land first


func _process(delta: float) -> void:
	if game == null:
		return
	var t0 := Time.get_ticks_usec()
	game.tick(delta)
	last_tick_usec = Time.get_ticks_usec() - t0
	_progress.value = game.sand_progress()
	_pct.text = "%d%%" % int(floor(game.sand_progress() * 100.0))
	if _clear_pending > 0.0:
		_clear_pending -= delta
		if _clear_pending <= 0.0:
			_show_clear()


func _show_clear() -> void:
	Sfx.play("stage_clear")
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(UiKit.BG, 0.85)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 120)
	panel.size = Vector2(640, 1000)
	_overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	v.add_child(UiKit.label("%s 도착!" % game.destination.get("name_ko", ""), 40, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var img := TextureRect.new()
	img.texture = load(game.destination.album_path)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img.custom_minimum_size = Vector2(580, 580)
	v.add_child(img)
	v.add_child(UiKit.label("여행 앨범에 기록되었어요", 26, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var next_id := _next_stage_id()
	if next_id != "":
		v.add_child(UiKit.button("다음 스테이지", func(): next_requested.emit(next_id)))
	v.add_child(UiKit.button("스테이지 목록", func(): exit_requested.emit()))


func _next_stage_id() -> String:
	var list := StageLoader.stages()
	for i in list.size():
		if list[i].id == stage_id and i + 1 < list.size():
			return list[i + 1].id
	return ""


func _toggle_settings() -> void:
	if is_instance_valid(_settings):
		_settings.queue_free()
		return
	_settings = SettingsPanel.create(func(): start(stage_id))
	add_child(_settings)
