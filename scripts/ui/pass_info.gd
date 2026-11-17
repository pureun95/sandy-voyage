class_name PassInfo
extends RefCounted
## Temporary travel-pass notice. Purchases are not implemented: this panel only explains that
## premium destinations open with the travel pass and has no buy / price button.


static func open(parent: Control) -> Control:
	var o := UiKit.dimmer(parent, 0.55)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", PixelBox.make(UiKit.PAPER, UiKit.RIM, UiKit.SHADOW))
	panel.position = Vector2(70, 400)
	panel.size = Vector2(580, 430)
	o.add_child(panel)
	var lock := UiKit.icon("lock", UiKit.ACCENT, 6)
	lock.position = Vector2(266, 36)
	panel.add_child(lock)
	var t := UiKit.title("여행 패스", 34, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.position = Vector2(0, 100)
	t.size = Vector2(580, 50)
	panel.add_child(t)
	var body := UiKit.label("프리미엄 여행지는 여행 패스로 열 수 있어요.\n여행 패스는 아직 준비 중이라 지금은 구매할 수 없어요.\n무료 여행지 10곳은 언제든 떠날 수 있어요.",
		21, UiKit.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	body.position = Vector2(30, 166)
	body.size = Vector2(520, 130)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(body)
	var ok := UiKit.px_button("확인", func(): o.queue_free(), "secondary", 24)
	ok.position = Vector2(150, 316)
	ok.size = Vector2(280, 80)
	panel.add_child(ok)
	return o
