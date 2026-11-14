class_name SettingsPanel
extends RefCounted
## Settings popup: sound on/off and the 64/128 sand resolution comparison switch.


static func create(on_resolution_changed: Callable = Callable()) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(80, 380)
	panel.size = Vector2(560, 420)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(UiKit.label("설정", 34, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var sound := UiKit.button("", func(): pass)
	var res := UiKit.button("", func(): pass)
	var refresh := func():
		sound.text = "소리: %s" % ("켜짐" if App.save.get_setting("sound", true) else "꺼짐")
		res.text = "모래 해상도: %d×%d (비교용)" % [App.resolution(), App.resolution()]
	refresh.call()
	sound.pressed.connect(func():
		App.save.set_setting("sound", not bool(App.save.get_setting("sound", true)))
		refresh.call())
	res.pressed.connect(func():
		App.save.set_setting("resolution", 64 if App.resolution() == 128 else 128)
		refresh.call()
		if on_resolution_changed.is_valid():
			on_resolution_changed.call())
	v.add_child(sound)
	v.add_child(res)
	v.add_child(UiKit.label("해상도를 바꾸면 현재 스테이지가 처음부터 다시 시작돼요.", 20, UiKit.TEXT_SOFT))
	v.add_child(UiKit.button("닫기", func(): root.queue_free()))
	return root
