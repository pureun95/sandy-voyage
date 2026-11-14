extends SceneTree
## Gravity rule A tests (falling sand + contact-started 4-connected cluster drain):
## godot --headless --path . -s res://tests/test_gravity.gd
## hawaii_01 now ships with rule B-2 ("collect": "suction", see test_suction.gd); the Hawaii
## checks here build hawaii_01 explicitly with rule A ("collect": "drain") so A stays covered.

var failures := 0
var passes := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


## Each char is a color digit, '.' = empty. Board columns = `cols` (width must divide).
func make_game(rows: Array, cols: int, board_rows: int, blocks: Array) -> SandGame:
	var m := SandMap.new()
	m.height = rows.size()
	m.width = (rows[0] as String).length()
	m.palette = [Color.RED, Color.BLUE, Color.GREEN]
	m.cells.resize(m.width * m.height)
	for y in m.height:
		for x in m.width:
			var ch: String = rows[y][x]
			m.cells[y * m.width + x] = SandMap.EMPTY if ch == "." else int(ch)
	var board := PuzzleBoard.new()
	board.cols = cols
	board.rows = board_rows
	for b in blocks:
		board.blocks.append(b)
	var g := SandGame.new()
	g.setup(m, board, "gravity")
	return g


## hawaii_01 opening (8x4 layout): palm cannot reach the landscape alone; the lagoon lid
## has to make room. Palm right 3, lagoon left 2, palm up 1. Returns palm, or null if a
## move was rejected.
func open_palm(g: SandGame) -> SandBlock:
	var p1 := g.board.get_block("p1")
	var l1 := g.board.get_block("l1")
	if not (g.try_move(p1, Vector2i.RIGHT, 3) and g.try_move(l1, Vector2i.LEFT, 2) and g.try_move(p1, Vector2i.UP, 1)):
		return null
	return p1


## hawaii_01 with collection rule A.
func hawaii_a(res: int) -> SandGame:
	var st := StageLoader.get_stage("hawaii_01").duplicate(true)
	st["collect"] = "drain"
	return StageLoader.build(st, res).game


func blk(id: String, color: int, shape: String, pos: Vector2i, cap: int) -> SandBlock:
	return SandBlock.create(id, color, SandBlock.shape_cells(shape), pos, cap)


func at(g: SandGame, x: int, y: int) -> int:
	return g.map.get_id(x, y)


func _init() -> void:
	test_stable_start()
	test_fall_rules()
	test_drain_rules()
	test_cluster_order()
	test_block_removal()
	test_hawaii_full_play()
	print("PASSED %d  FAILURES %d" % [passes, failures])
	quit(1 if failures > 0 else 0)


func test_stable_start() -> void:
	print("[stable start]")
	var g := hawaii_a(128)
	check(g.is_gravity() and not g.is_suction(), "hawaii_01 (rule A build) runs the gravity drain")
	var before := g.map.cells.duplicate()
	check(not g.sim.is_active(), "no active chunk at start (picture fully packed)")
	var moved := 0
	for i in 600:
		moved += g.sim.step()
	for i in 120:
		g.tick(1.0 / 60.0)  # no block touches the landscape at start
	check(moved == 0 and g.map.cells == before, "600 steps + 2s of ticks: nothing moves, picture identical")
	var other: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_02"), 128).game
	check(not other.is_gravity(), "other stages keep the channel rule")


func test_fall_rules() -> void:
	print("[falling]")
	var g := make_game(["...", ".0.", "..."], 3, 1, [])
	g.sim.wake(4)
	g.sim.step()
	check(at(g, 1, 1) == SandMap.EMPTY and at(g, 1, 2) == 0, "grain falls straight down one cell per step")
	var d := make_game([".0.", ".1."], 3, 1, [])
	d.sim.wake(1)
	d.sim.step()
	var went_left := at(d, 0, 1) == 0
	var went_right := at(d, 2, 1) == 0
	check(at(d, 1, 0) == SandMap.EMPTY and (went_left != went_right), "blocked below -> slides diagonally down")
	var f := make_game(["0.."], 3, 1, [])
	f.sim.wake(0)
	for i in 10:
		f.sim.step()
	check(at(f, 0, 0) == 0, "grain on the floor never slides sideways")
	var p := make_game(["0..", "...", "...", "..."], 3, 1, [])
	p.sim.wake(0)
	p.sim.settle()
	check(p.map.remaining() == 1 and at(p, 0, 3) == 0, "falls to the floor and stays; floor holds sand (no block)")
	# Other colors collapse too: red is drained below, the blue column above falls into its place.
	var red := blk("r", 0, "dot", Vector2i(0, 0), 10)
	var c := make_game(["1", "1", "0"], 1, 1, [red])
	c.collector.step(red, 1)
	c.sim.settle()
	check(at(c, 0, 2) == 1 and at(c, 0, 1) == 1 and at(c, 0, 0) == SandMap.EMPTY,
		"blue above falls into the drained red cell")
	var got: PackedInt32Array = c.collector.step(red, 10)
	check(got.is_empty() and red.collected == 1, "red block then touches blue: nothing more collected")


func test_drain_rules() -> void:
	print("[drain / contact]")
	# Direct contact required: red sand right next door, but the intake pixel is blue.
	var a := blk("a", 0, "dot", Vector2i(0, 0), 10)
	var g := make_game(["00", "10"], 2, 2, [a])
	var got: PackedInt32Array = g.collector.step(a, 10)
	check(got.is_empty(), "no collection without direct same-color contact at the intake")
	g.board.move(a, Vector2i.DOWN, 1)
	g.board.move(a, Vector2i.RIGHT, 1)
	got = g.collector.step(a, 10)
	check(got.is_empty(), "block below row 0 never collects")
	# Other colors are never crossed: red on top is separated by a blue band.
	var b := blk("b", 0, "dot", Vector2i(1, 0), 10)
	var g2 := make_game(["000", "111", "101"], 3, 1, [b])
	got = g2.collector.step(b, 10)
	check(got.size() == 1 and at(g2, 1, 2) == SandMap.EMPTY, "only the touching red grain (cluster of 1)")
	check(at(g2, 0, 0) == 0 and at(g2, 1, 0) == 0 and at(g2, 2, 0) == 0, "red behind blue untouched")
	check(g2.map.count_by_color()[1] == 5, "no blue grain collected")
	# Diagonal links don't join a cluster.
	var c := blk("c", 0, "dot", Vector2i(1, 0), 10)
	var g3 := make_game(["01", "10"], 2, 1, [c])
	got = g3.collector.step(c, 10)
	check(got.size() == 1 and at(g3, 0, 0) == 0, "diagonal red neighbour not collected")
	# Only the exposed top cells of the block are intakes (an I2v block has one).
	var v := blk("v", 0, "I2v", Vector2i(0, 0), 10)
	var g4 := make_game(["00", "00"], 2, 2, [v])
	check(g4.collector.intake_pixels(v).size() == 1, "I2v exposes one intake cell (its top cell)")


func test_cluster_order() -> void:
	print("[cluster pulled in sequence]")
	# Red L-shaped cluster: intake at (3,1); path (3,1)<-(3,0)<-(2,0)<-(1,0)<-(0,0).
	var r := blk("r", 0, "dot", Vector2i(3, 0), 10)
	var g := make_game(["0000", "1110"], 4, 1, [r])
	var order := []
	var all_paths_ok := true
	for k in 5:
		var got: PackedInt32Array = g.collector.step(r, 1)
		if got.size() != 1:
			break
		order.append(got[0])
		var path: PackedInt32Array = g.collector.last_paths[0]
		all_paths_ok = all_paths_ok and path[0] == got[0] and path[path.size() - 1] == 7
		# Remaining red must still be connected to the intake through red.
		all_paths_ok = all_paths_ok and _red_connected_to(g, 7)
	check(order == [0, 1, 2, 3, 7], "one grain per step, farthest first along the path (%s)" % [order])
	check(all_paths_ok, "each grain's path ends at the intake; remaining cluster stays connected")
	check(g.map.count_by_color()[1] == 3 and r.collected == 5, "blue untouched; collected count = emptied cells")


func _red_connected_to(g: SandGame, intake: int) -> bool:
	var w := g.map.width
	var reds := 0
	for v in g.map.cells:
		if v == 0:
			reds += 1
	if reds == 0:
		return true
	if g.map.cells[intake] != 0:
		return false
	var seen := {intake: true}
	var q := [intake]
	while not q.is_empty():
		var j: int = q.pop_back()
		for n in [j - 1 if j % w > 0 else -1, j + 1 if j % w < w - 1 else -1, j - w, j + w]:
			if n >= 0 and n < g.map.cells.size() and not seen.has(n) and g.map.cells[n] == 0:
				seen[n] = true
				q.append(n)
	return seen.size() == reds


func test_block_removal() -> void:
	print("[block removal]")
	var a := blk("a", 0, "dot", Vector2i(0, 0), 2)
	var b := blk("b", 0, "dot", Vector2i(0, 1), 2)
	var g := make_game(["0", "0", "0", "0"], 1, 2, [a, b])
	var cleared := [false]
	g.stage_cleared.connect(func(): cleared[0] = true)
	for i in 120:
		g.tick(1.0 / 60.0)
	check(a.removed and a.collected == a.capacity, "full block removed at exactly its capacity")
	check(g.board.block_at(Vector2i(0, 0)) == null, "its cell is free again")
	check(g.remaining == 2 and not cleared[0], "sand left -> not cleared after a block is removed")
	check(g.board.move(b, Vector2i.UP, 1), "another block moves into the freed cell")
	for i in 120:
		g.tick(1.0 / 60.0)
	check(b.removed and g.remaining == 0 and cleared[0], "second block collects the fallen sand -> cleared")
	check(g.board.get_block("a").removed, "removed block stays removed")


func test_hawaii_full_play() -> void:
	print("[hawaii_01 gravity rule A: full paced play]")
	for res in [128, 64]:
		var g := hawaii_a(res)
		var initial := g.map.count_by_color()
		var caps := PackedInt32Array()
		caps.resize(initial.size())
		for b in g.board.blocks:
			caps[b.color_id] += b.capacity
		check(caps == initial, "@%d capacities per color equal sand per color %s" % [res, initial])
		var ok := [true]
		var checks := [0]
		var on_grains := func(_b, _idx: PackedInt32Array):
			checks[0] += 1
			var collected := PackedInt32Array()
			collected.resize(initial.size())
			for bb in g.board.blocks:
				collected[bb.color_id] += bb.collected
			var now := g.map.count_by_color()
			for c in initial.size():
				if now[c] + collected[c] != initial[c]:
					ok[0] = false
			if g.map.remaining() != g.remaining:
				ok[0] = false
		g.grains_collected.connect(on_grains)
		var r := LevelSolver.play_gravity(g)
		g.grains_collected.disconnect(on_grains)  # lambda captures g: break the cycle
		check(r.status == "cleared" and g.remaining == 0 and g.cleared, "@%d cleared by the play policy (%s, drags %s, %.0fs sim)" % [
			res, r.status, r.get("drags"), r.get("sim_seconds", 0.0)])
		check(ok[0] and checks[0] > 0, "@%d per color: remaining + collected == initial at every collection (%d checks)" % [res, checks[0]])
		var full_ok := true
		for b in g.board.blocks:
			full_ok = full_ok and b.removed and b.collected == b.capacity
		check(full_ok, "@%d every block filled exactly to capacity and removed" % res)
	# The picture really deforms: after the first collection the sim moves other grains.
	var g2 := hawaii_a(128)
	var p1 := open_palm(g2)
	check(p1 != null, "hawaii_01 opening: palm right, lagoon left, palm up are all legal moves")
	var before := g2.map.cells.duplicate()
	var collected_cells := {}
	g2.grains_collected.connect(func(_b, idx):
		for i in idx:
			collected_cells[i] = true)
	for i in 90:
		g2.tick(1.0 / 60.0)
	var changed_elsewhere := 0
	for i in before.size():
		if before[i] != g2.map.cells[i] and not collected_cells.has(i):
			changed_elsewhere += 1
	var got: int = p1.collected if p1 != null else 0
	check(got > 0 and changed_elsewhere > 100,
		"collection makes the picture collapse (%d grains collected, %d other cells changed in 1.5s)" % [got, changed_elsewhere])
	# Deterministic: same inputs, same sand.
	var g3 := hawaii_a(128)
	open_palm(g3)
	for i in 90:
		g3.tick(1.0 / 60.0)
	check(g3.map.cells == g2.map.cells, "simulation is deterministic")
