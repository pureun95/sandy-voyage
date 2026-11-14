extends SceneTree
## Gameplay rule tests: godot --headless --path . -s res://tests/test_gameplay.gd

var failures := 0
var passes := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


## Map from strings: each char is a color digit, '.' = empty.
func make_map(rows: Array) -> SandMap:
	var m := SandMap.new()
	m.height = rows.size()
	m.width = (rows[0] as String).length()
	m.palette = [Color.RED, Color.BLUE, Color.GREEN]
	m.cells.resize(m.width * m.height)
	for y in m.height:
		for x in m.width:
			var ch: String = rows[y][x]
			m.cells[y * m.width + x] = SandMap.EMPTY if ch == "." else int(ch)
	return m


func make_game(rows: Array, cols: int, board_rows: int, blocks: Array, walls := []) -> SandGame:
	var board := PuzzleBoard.new()
	board.cols = cols
	board.rows = board_rows
	for w in walls:
		board.walls[w] = true
	for b in blocks:
		board.blocks.append(b)
	var g := SandGame.new()
	g.setup(make_map(rows), board)
	return g


func blk(id: String, color: int, shape: String, pos: Vector2i, cap: int) -> SandBlock:
	return SandBlock.create(id, color, SandBlock.shape_cells(shape), pos, cap)


func _init() -> void:
	test_palette_mapping()
	test_movement()
	test_contact_rules()
	test_shared_channel_rescan()
	test_channel_start_rules()
	test_capacity_and_removal()
	test_clear()
	test_save_restore()
	test_validator_catches_bad_levels()
	test_real_stage()
	print("PASSED %d  FAILURES %d" % [passes, failures])
	quit(1 if failures > 0 else 0)


func test_palette_mapping() -> void:
	print("[palette mapping]")
	var dests := StageLoader.destinations()
	for id in dests:
		var d: Dictionary = dests[id]
		for res in [64, 128]:
			var m := StageLoader.load_map(d, res)
			check(m != null, "%s@%d maps onto named palette" % [id, res])
			if m == null:
				continue
			var counts := m.count_by_color()
			var all_used := true
			for c in counts:
				all_used = all_used and c > 0
			check(all_used and counts.size() == d.palette_colors.size(),
				"%s@%d every palette color has sand %s" % [id, res, counts])
	# Fuji: frequency rank of pink/dark-pink differs between 64 and 128; ids must not.
	var fuji: Dictionary = dests.fuji
	var m64 := StageLoader.load_map(fuji, 64)
	var m128 := StageLoader.load_map(fuji, 128)
	var pagoda: int = fuji.palette_keys.find("pagoda")
	check(m64.palette[pagoda].to_html(false) == "c86889" and m128.palette[pagoda].to_html(false) == "cc6689",
		"fuji 'pagoda' id resolves to each resolution's own exact color")
	# A pixel's id points to the color it actually has.
	var img := (load(fuji.puzzle_paths["64"]) as Texture2D).get_image()
	var mism := 0
	for y in 64:
		for x in 64:
			if m64.palette[m64.get_id(x, y)].to_rgba32() != (img.get_pixel(x, y).to_rgba32() | 0xFF):
				mism += 1
	check(mism == 0, "mapped ids reproduce the source pixels exactly")
	# Unmappable color is rejected.
	var bad := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	bad.set_pixel(0, 0, Color.BLACK)
	bad.set_pixel(1, 0, Color.WHITE)
	check(SandMap.from_image_with_palette(bad, [Color.BLACK, Color.RED] as Array[Color]) == null,
		"color far from palette is rejected")


func test_movement() -> void:
	print("[movement]")
	var a := blk("a", 0, "I2h", Vector2i(0, 2), 1)
	var b := blk("b", 1, "dot", Vector2i(3, 2), 1)
	var g := make_game(["........"], 4, 4, [a, b], [Vector2i(0, 0)])
	var bd := g.board
	check(bd.validate().is_empty(), "valid layout")
	check(bd.max_steps(a, Vector2i.RIGHT) == 1, "a can slide right until b (1)")
	check(not bd.move(a, Vector2i.RIGHT, 2), "cannot move through block b")
	check(a.pos == Vector2i(0, 2), "failed move leaves block in place")
	check(bd.move(a, Vector2i.RIGHT, 1) and a.pos == Vector2i(1, 2), "move right 1")
	check(bd.max_steps(a, Vector2i.DOWN) == 1, "boundary: 1 step to bottom edge")
	check(not bd.move(a, Vector2i.DOWN, 2), "cannot leave board bottom")
	check(bd.move(a, Vector2i.UP, 2) and a.pos == Vector2i(1, 0), "move up to row 0")
	check(bd.max_steps(a, Vector2i.LEFT) == 0, "wall at (0,0) stops left move")
	check(bd.max_steps(a, Vector2i.UP) == 0, "top edge stops up move")
	check(not bd.move(a, Vector2i(1, 1), 1), "diagonal move rejected")
	check(not bd.move(a, Vector2i(2, 0), 1), "non-unit direction rejected")
	check(a.cells == ([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i]), "shape unchanged after moves (no rotation)")
	check(not bd.has_method("rotate") and not a.has_method("rotate"), "no rotate API exists")
	# A horizontal domino cannot enter a 1-wide vertical shaft (it would only fit rotated).
	var c := blk("c", 0, "I2h", Vector2i(0, 3), 1)
	var g2 := make_game(["...."], 3, 4, [c], [Vector2i(0, 2), Vector2i(2, 2), Vector2i(0, 1), Vector2i(2, 1)])
	check(g2.board.max_steps(c, Vector2i.UP) == 0, "horizontal block cannot enter vertical 1-wide gap")
	# Layout errors.
	var o1 := blk("o1", 0, "O", Vector2i(3, 0), 1)
	var o2 := blk("o2", 0, "dot", Vector2i(0, 0), 1)
	var o3 := blk("o3", 0, "dot", Vector2i(0, 0), 1)
	var g3 := make_game(["...."], 4, 2, [o1, o2, o3])
	var errs := g3.board.validate()
	check(errs.size() == 3, "validate reports 2 out-of-bounds cells + 1 overlap (%s)" % [errs])


func test_contact_rules() -> void:
	print("[contact]")
	# 8px wide, board 2 cols -> 4 px per column. Bottom row: left=red(0), right=blue(1).
	var rows := [
		"00001111",
		"00001111",
		"00001111",
	]
	var red := blk("r", 0, "dot", Vector2i(1, 0), 100)   # under BLUE
	var g := make_game(rows, 2, 3, [red])
	g.collect_all_now()
	check(red.collected == 0 and g.remaining == 24, "red block touching only blue sand collects nothing")
	g.board.move(red, Vector2i.DOWN, 1)
	g.board.move(red, Vector2i.LEFT, 1)
	g.collector.reset_all()
	g.collect_all_now()
	check(red.collected == 0, "red block not touching (row 1) collects nothing")
	g.board.move(red, Vector2i.UP, 1)
	g.collector.reset_all()
	var got := g.collector.step(red, 4)
	check(got.size() == 4, "red block touching red sand collects (step budget 4)")
	var first_ok := true
	for i in got:
		@warning_ignore("integer_division")
		first_ok = first_ok and i / 8 == 2  # bottom row first: nearest the contact face
	check(first_ok, "collection starts at the touched bottom row")
	check(red.collected == 4 and g.map.count_by_color()[0] == 8, "red sand count decreased by 4")
	g.collect_all_now()
	check(red.collected == 12 and g.map.count_by_color()[1] == 12, "only red taken; blue untouched")

	# Isolated region: red pocket enclosed by blue is not reachable through blue.
	var rows2 := [
		"11111111",
		"11001111",
		"11111111",
		"00000000",
	]
	var r2 := blk("r2", 0, "dot", Vector2i(0, 0), 100)
	var b2 := blk("b2", 1, "dot", Vector2i(1, 1), 100)
	var g2 := make_game(rows2, 2, 2, [r2, b2])
	g2.collect_all_now()
	check(r2.collected == 8, "red takes the 8 reachable bottom grains, not the enclosed pocket")
	check(g2.map.get_id(2, 1) == 0 and g2.map.get_id(3, 1) == 0, "enclosed red pocket still present")
	# Through the opened channel, blue becomes reachable; then the pocket opens.
	g2.board.move(b2, Vector2i.UP, 1)
	g2.collect_all_now()
	check(b2.collected == 22, "blue collects via opened channel (22 grains)")
	check(r2.collected == 10, "after blue is removed, red pocket is reachable (10)")

	# Diagonal-only adjacency doesn't count. 2x2 pixels, 2 cols (1 px each).
	var g3 := make_game(["01", "10"], 2, 1, [blk("d", 0, "dot", Vector2i(0, 0), 10)])
	g3.collect_all_now()
	check(g3.board.blocks[0].collected == 0, "red block under blue pixel; red pixel only diagonal -> nothing")
	var g4 := make_game(["01", "10"], 2, 1, [blk("d", 0, "dot", Vector2i(1, 0), 10)])
	g4.collect_all_now()
	check(g4.board.blocks[0].collected == 1 and g4.map.get_id(0, 0) == 0,
		"takes touched red pixel but not red diagonal neighbour")
	# Held (being dragged) blocks do not collect.
	var h := blk("h", 0, "dot", Vector2i(0, 0), 10)
	var g5 := make_game(["00", "00"], 2, 1, [h])
	g5.set_held(h, true)
	g5.tick(1.0)
	check(h.collected == 0, "block being dragged does not collect")
	g5.set_held(h, false)
	g5.grains_per_second = 2.0
	g5.tick(1.0)
	check(h.collected == 2, "collection is paced by grains_per_second (2 in 1s)")


func test_shared_channel_rescan() -> void:
	print("[two blocks, channel opened by the other block]")
	# Red block A sits under red sand; a blue band separates it from more red above.
	# Blue block B removes the band while A is idle; A must then reach the upper red.
	var rows := [
		"00000000",
		"11111111",
		"00001111",
	]
	var a := blk("a", 0, "dot", Vector2i(0, 0), 12)
	var b := blk("b", 1, "dot", Vector2i(1, 0), 12)
	for order in [[a, b], [b, a]]:
		a.collected = 0; a.removed = false; b.collected = 0; b.removed = false
		var g := make_game(rows, 2, 1, order)
		g.grains_per_second = 180.0  # 3 grains per 60fps tick
		for i in 600:
			g.tick(1.0 / 60.0)
			if g.cleared:
				break
		check(g.cleared and a.collected == 12 and b.collected == 12,
			"order %s: A resumes through the channel B opened (a=%d b=%d)" % [order[0].id + order[1].id, a.collected, b.collected])


func test_channel_start_rules() -> void:
	print("[channel / first-contact rules]")
	# 8 px wide, 2 board columns (4 px each). Left half of the bottom is an open channel
	# (already collected) leading up to red sand; right half of the bottom is blue.
	var rows := [
		"00000000",
		"00001111",
		"....1111",
	]
	# 1) Block under BLUE: a channel to red exists elsewhere, but this face touches only blue.
	var r1 := blk("r1", 0, "dot", Vector2i(1, 0), 100)
	var g1 := make_game(rows, 2, 2, [r1])
	g1.collect_all_now()
	check(r1.collected == 0, "channel elsewhere does not let a block start without its own contact")
	# 2) Block one row below the channel column (not touching the landscape at all).
	var r2 := blk("r2", 0, "dot", Vector2i(0, 1), 100)
	var g2 := make_game(rows, 2, 2, [r2])
	g2.collect_all_now()
	check(r2.collected == 0, "block not on the intake row collects nothing even under a channel")
	# 3) Channel connects only through blue: red behind blue is never taken.
	var walled := [
		"00000000",
		"11111111",
		"....1111",
	]
	var r3 := blk("r3", 0, "dot", Vector2i(0, 0), 100)
	var g3 := make_game(walled, 2, 1, [r3])
	g3.collect_all_now()
	check(r3.collected == 0, "channel blocked by another color: no collection through it")
	# 4) Diagonal-only link between channel and red does not count.
	var diag := [
		"0111",
		"1.11",
	]
	var r4 := blk("r4", 0, "dot", Vector2i(0, 0), 100)  # 2 cols x 2 px; col 0 = px 0..1
	var g4 := make_game(diag, 2, 1, [r4])
	g4.collect_all_now()
	check(r4.collected == 0, "red touching the channel only diagonally is not collected")
	# 5) Approved behaviour: face on an open channel that physically connects to red.
	#    Collection is progressive, nearest first (no far sand vanishing at once).
	var r5 := blk("r5", 0, "dot", Vector2i(0, 0), 100)
	var g5 := make_game(rows, 2, 1, [r5])
	var first := g5.collector.step(r5, 4)
	var near_first := true
	for i in first:
		@warning_ignore("integer_division")
		near_first = near_first and i / 8 == 1  # row 1 is adjacent to the channel; row 0 is farther
	check(first.size() == 4 and near_first, "through a connected channel: nearest red grains go first")
	g5.collect_all_now()
	check(r5.collected == 12 and g5.map.count_by_color()[1] == 8, "all connected red taken, blue untouched")


func test_capacity_and_removal() -> void:
	print("[capacity]")
	var a := blk("a", 0, "dot", Vector2i(0, 0), 3)
	var b := blk("b", 0, "dot", Vector2i(1, 1), 5)
	var g := make_game(["0000", "0000"], 2, 2, [a, b])
	var filled := []
	g.block_filled.connect(func(x): filled.append(x.id))
	g.collect_all_now()
	check(a.collected == 3, "capacity limits collection (3 of 8 reachable)")
	check(a.removed and filled == ["a"], "full block removed with signal")
	check(g.board.block_at(Vector2i(0, 0)) == null, "removed block frees its cell")
	check(g.board.move(b, Vector2i.UP, 1) and g.board.move(b, Vector2i.LEFT, 1), "another block can move into freed cell")
	g.collect_all_now()
	check(b.collected == 5 and b.removed, "second block fills to capacity and is removed")


func test_clear() -> void:
	print("[clear]")
	var a := blk("a", 0, "dot", Vector2i(0, 0), 2)
	var b := blk("b", 1, "dot", Vector2i(0, 1), 2)
	var g := make_game(["11", "00"], 1, 2, [a, b])
	var cleared := [false]
	g.stage_cleared.connect(func(): cleared[0] = true)
	# Note: 2 px wide, 1 column -> 2 px per column.
	g.collect_all_now()
	check(g.remaining == 2 and not g.is_cleared() and not cleared[0], "sand left -> not cleared (%d left)" % g.remaining)
	g.board.move(b, Vector2i.UP, 1)
	g.collect_all_now()
	check(g.remaining == 0 and g.is_cleared() and cleared[0], "all sand removed -> cleared")


func test_save_restore() -> void:
	print("[save]")
	var path := "user://test_save_%d.json" % Time.get_ticks_usec()
	var s := SaveStore.new(path)
	s.load_data()
	check(not s.is_unlocked("hawaii") and not s.is_cleared("hawaii_01"), "fresh save is empty")
	s.mark_cleared("hawaii_01", "hawaii")
	s.set_setting("resolution", 64)
	var s2 := SaveStore.new(path)
	s2.load_data()
	check(s2.is_cleared("hawaii_01") and s2.is_unlocked("hawaii"), "cleared stage + album restored from disk")
	check(not s2.is_unlocked("london"), "other destinations stay locked")
	check(int(s2.get_setting("resolution")) == 64, "settings restored")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{broken json")
	f.close()
	var s3 := SaveStore.new(path)
	s3.load_data()
	check(not s3.is_unlocked("hawaii"), "corrupt save falls back to defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_validator_catches_bad_levels() -> void:
	print("[level validator]")
	var base := {"id": "t", "destination": "hawaii", "board": {"cols": 8, "rows": 5}, "walls": [],
		"blocks": [
			{"id": "j", "color": "jungle", "shape": "O", "pos": [0, 2]},
			{"id": "l", "color": "lagoon", "shape": "I2h", "pos": [2, 2]},
			{"id": "p", "color": "palm", "shape": "I2h", "pos": [4, 2]},
			{"id": "o", "color": "ocean", "shape": "dot", "pos": [6, 2]},
			{"id": "f", "color": "foam", "shape": "dot", "pos": [7, 2]},
		]}
	var ok := LevelValidator.validate(base, 64)
	check(ok.ok and ok.status == "solvable", "baseline test level is clearable (%s)" % [ok.errors])
	var cap := base.duplicate(true)
	cap.blocks[0].capacity = 10
	var r := LevelValidator.validate(cap, 64)
	check(not r.ok and "
".join(r.errors).contains("jungle': sand"), "capacity/sand mismatch reported")
	var oob := base.duplicate(true)
	oob.blocks[0].pos = [7, 2]
	r = LevelValidator.validate(oob, 64)
	check(not r.ok and "
".join(r.errors).contains("outside"), "block outside board reported")
	var ov := base.duplicate(true)
	ov.blocks[1].pos = [1, 2]
	r = LevelValidator.validate(ov, 64)
	check(not r.ok and "
".join(r.errors).contains("overlaps"), "initial overlap reported")
	var gap := base.duplicate(true)
	gap.walls = [[2, 1], [5, 1]]
	gap.blocks[2] = {"id": "p", "color": "palm", "shape": "I3h", "pos": [2, 3]}
	r = LevelValidator.validate(gap, 64)
	check(not r.ok and "
".join(r.errors).contains("never reach the intake"), "wide block that can't pass wall gap reported")
	var nob := base.duplicate(true)
	nob.blocks.remove_at(4)
	r = LevelValidator.validate(nob, 64)
	check(not r.ok and "
".join(r.errors).contains("foam': sand"), "color with no block reported")
	# Original fuji_03 draft: every block can reach the intake alone, but partly filled
	# blocks park on row 0 while the snow/mist blocks stay locked out -> search proves stuck.
	var fuji3 := {"id": "fuji_03_draft", "destination": "fuji", "board": {"cols": 8, "rows": 5},
		"walls": [[0, 2], [7, 2], [3, 3], [4, 3]],
		"blocks": [
			{"id": "s1", "color": "sky", "shape": "I2h", "pos": [1, 1]},
			{"id": "b1", "color": "blossom", "shape": "I2v", "pos": [3, 1]},
			{"id": "b2", "color": "blossom", "shape": "I2v", "pos": [4, 1]},
			{"id": "pg", "color": "pagoda", "shape": "O", "pos": [5, 1]},
			{"id": "sn", "color": "snow", "shape": "I3h", "pos": [0, 4]},
			{"id": "m1", "color": "mountain", "shape": "L", "pos": [1, 2]},
			{"id": "mi", "color": "mist", "shape": "I3h", "pos": [5, 4]},
		]}
	r = LevelValidator.validate(fuji3, 64)
	check(not r.ok and "
".join(r.errors).contains("'sn'") and "
".join(r.errors).contains("never reach"),
		"original fuji_03 draft rejected: snow block can't pass the walls")
	# Deadlock only real-rule search can find: each block reaches the intake on its own,
	# but the blue block parked on row 0 touches red sand, and the red block below can't get past it.
	var red := blk("red", 0, "dot", Vector2i(0, 1), 1)
	var blue := blk("blue", 1, "dot", Vector2i(0, 0), 1)
	var dead := make_game(["1", "0"], 1, 2, [blue, red])
	check(LevelValidator._can_reach_intake_alone(dead.board, red) and LevelValidator._can_reach_intake_alone(dead.board, blue),
		"deadlock case passes the static per-block check")
	var sol := LevelSolver.solve(dead)
	check(sol.status == "unsolvable" and sol.remaining == 2, "solver proves deadlock (status=%s)" % sol.status)


func test_real_stage() -> void:
	print("[hawaii_01 real play, paced ticks]")
	for res in [128, 64]:
		var built := StageLoader.build(StageLoader.get_stage("hawaii_01"), res)
		var g: SandGame = built.game
		check(built.errors.is_empty(), "@%d builds without errors" % res)
		var counts := g.map.count_by_color()
		var caps := PackedInt32Array()
		caps.resize(counts.size())
		for b in g.board.blocks:
			caps[b.color_id] += b.capacity
		check(caps == counts, "@%d auto capacities equal sand per color %s" % [res, counts])
		var cleared := [false]
		g.stage_cleared.connect(func(): cleared[0] = true)
		var ticks := 0
		var guard := 0
		while not g.cleared and guard < 200:
			guard += 1
			var r := LevelSolver.find_next(g.board, g.collector)
			if r.status != "found":
				break
			for m in r.moves:
				g.try_move(g.board.get_block(m.id), m.dir, m.steps)
			# Let real-time collection run until nothing is being collected.
			var idle := 0
			while idle < 30 and not g.cleared:
				var before := g.remaining
				g.tick(1.0 / 60.0)
				ticks += 1
				idle = idle + 1 if g.remaining == before else 0
		check(cleared[0] and g.remaining == 0, "@%d stage cleared through paced ticks (%d ticks = %.1fs sim)" % [res, ticks, ticks / 60.0])
		check(g.board.active_blocks().is_empty(), "@%d every block filled and removed" % res)
