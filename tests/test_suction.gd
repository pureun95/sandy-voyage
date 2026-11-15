extends SceneTree
## Rule B-2 (range-limited chain suction) tests:
##   godot --headless --path . -s res://tests/test_suction.gd
## Synthetic maps use one board column per sand column (px_per_col = 1), so a "dot" block at
## column c has exactly one intake cell: (c, bottom row).

var failures := 0
var passes := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  PASS ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


## Each char is a color digit, '.' = empty.
func make_game(rows: Array, board_rows: int, blocks: Array, link := 3, reach := 100.0, finish := 0.0) -> SandGame:
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
	board.cols = m.width
	board.rows = board_rows
	for b in blocks:
		board.blocks.append(b)
	var g := SandGame.new()
	g.setup(m, board, "gravity", "suction")
	var d: SuctionDrain = g.collector
	d.link = link
	d.reach = reach
	d.finish_at = finish
	return g


func blk(id: String, color: int, pos: Vector2i, cap: int, shape := "dot") -> SandBlock:
	return SandBlock.create(id, color, SandBlock.shape_cells(shape), pos, cap)


func at(g: SandGame, x: int, y: int) -> int:
	return g.map.get_id(x, y)


## hawaii_01 opening (8x4 layout): palm cannot reach the landscape alone; the lagoon lid
## has to make room. Palm right 3, lagoon left 2, palm up 1. Returns palm, or null if a
## move was rejected.
func open_palm(g: SandGame) -> SandBlock:
	var p1 := g.board.get_block("p1")
	var l1 := g.board.get_block("l1")
	if not (g.try_move(p1, Vector2i.RIGHT, 3) and g.try_move(l1, Vector2i.LEFT, 2) and g.try_move(p1, Vector2i.UP, 1)):
		return null
	return p1


func _init() -> void:
	test_setup()
	test_contact()
	test_link()
	test_reach()
	test_spread_scan()
	test_capacity()
	test_finish()
	test_independent()
	test_hawaii_restart()
	test_hawaii()
	print("PASSED %d  FAILURES %d" % [passes, failures])
	quit(1 if failures > 0 else 0)


func test_setup() -> void:
	print("[setup]")
	var g: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_01"), 128).game
	var d: SuctionDrain = g.collector
	check(g.is_gravity() and g.is_suction(), "hawaii_01 uses gravity + suction (B-2)")
	check(d.link == 3 and is_equal_approx(d.reach, 48.0) and is_equal_approx(d.finish_at, 0.9),
		"128 grid: link 3 cells, reach 48 cells, finish at 90% (from game_config.json)")
	var g64: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_01"), 64).game
	var d64: SuctionDrain = g64.collector
	check(d64.link == 2 and is_equal_approx(d64.reach, 24.0), "64 grid: scaled to link 2, reach 24 cells")
	check(not g.sim.diagonal_needs_side_gap and not g64.sim.diagonal_needs_side_gap,
		"hawaii_01 uses the original diagonal rule at 128 and 64 (side-gap variant not adopted)")
	var gc: Dictionary = StageLoader.config().get("gravity", {})
	check(gc.get("diagonal_needs_side_gap", true) == false, "gravity default keeps the original diagonal rule")
	check(g.sim.column_wake and g64.sim.column_wake and gc.get("column_wake", true) == false,
		"hawaii_01 uses column wake at 128 and 64; the gravity default keeps it off")
	var flipped: Dictionary = StageLoader.get_stage("hawaii_01").duplicate(true)
	flipped["diagonal_needs_side_gap"] = true
	check(StageLoader.build(flipped, 128).game.sim.diagonal_needs_side_gap,
		"the stage setting still switches the side-gap variant on for comparison")
	for id in ["hawaii_02", "fuji_01", "london_03"]:
		var o: SandGame = StageLoader.build(StageLoader.get_stage(id), 128).game
		check(not o.is_gravity() and not o.is_suction(), "%s keeps the channel rule" % id)
	var before := g.map.cells.duplicate()
	for i in 120:
		g.tick(1.0 / 60.0)
	check(g.map.cells == before and g.remaining == g.total, "no block touches the landscape at start: nothing moves")


func test_contact() -> void:
	print("[direct contact]")
	# Block at column 0 touches blue; red is 2 cells away (inside the link) but not touching.
	var a := blk("a", 0, Vector2i(0, 0), 10)
	var g := make_game(["........", "1.0....."], 1, [a])
	var got: PackedInt32Array = g.collector.step(a, 1 << 30)
	check(got.is_empty() and a.collected == 0, "no collection without a same-color grain on the intake")
	check(g.collector.reachable_count(a, Vector2i(2, 0)) == 1, "same block moved onto the red grain would collect it")
	g.board.move(a, Vector2i.RIGHT, 2)
	got = g.collector.step(a, 1 << 30)
	check(got.size() == 1 and at(g, 2, 1) == SandMap.EMPTY and at(g, 0, 1) == 1, "contact -> red taken, blue untouched")
	var b := blk("b", 0, Vector2i(0, 1), 10)
	var g2 := make_game(["0"], 2, [b])
	check(g2.collector.step(b, 1 << 30).is_empty(), "block below row 0 never collects")


func test_link() -> void:
	print("[link distance 3]")
	# Seed at x=0; x=3 is 3 cells from it (linked); x=7 is 4 cells from x=3 (not linked).
	# Blue grains sit in the gaps: they are jumped over, never taken.
	var a := blk("a", 0, Vector2i(0, 0), 50)
	var g := make_game(["0110...0........"], 1, [a])
	g.collector.step(a, 1 << 30)
	check(at(g, 0, 0) == SandMap.EMPTY and at(g, 3, 0) == SandMap.EMPTY, "grain 3 cells away is chained (over other colors)")
	check(at(g, 7, 0) == 0, "grain 4 cells beyond the chain is not taken")
	check(at(g, 1, 0) == 1 and at(g, 2, 0) == 1, "other colors in the gap are never taken")
	check(a.collected == 2, "collected count = emptied cells (2)")
	# Diagonal (3,3) is Chebyshev 3: linked. From there (4,3) is Chebyshev 4: not linked.
	var c := blk("c", 0, Vector2i(0, 0), 50)
	var g2 := make_game([
		".......0",
		"........",
		"........",
		"...0....",
		"........",
		"........",
		"0......."], 1, [c])
	g2.collector.step(c, 1 << 30)
	check(at(g2, 3, 3) == SandMap.EMPTY and at(g2, 7, 0) == 0,
		"diagonal (3,3) away is linked; a grain (4,3) further from it is not")


func test_reach() -> void:
	print("[reach 48 -> tested with reach 10]")
	# Full red rectangle 20 x 14, block at column 0 (intake cell (0,13)), reach 10.
	var rows := []
	for y in 14:
		rows.append("0".repeat(20))
	var a := blk("a", 0, Vector2i(0, 0), 1000)
	var g := make_game(rows, 1, [a], 3, 10.0)
	var expect := {}
	for y in 14:
		for x in 20:
			var dy := 13 - y
			if x * x + dy * dy <= 100:
				expect[y * 20 + x] = true
	var got: PackedInt32Array = g.collector.step(a, 1 << 30)
	var ok := got.size() == expect.size()
	for i in got:
		ok = ok and expect.has(i)
	check(ok, "exactly the grains with sqrt(dx^2+dy^2) <= 10 from the intake cell are taken (%d)" % got.size())
	var outside := 0
	for y in 14:
		for x in 20:
			if not expect.has(y * 20 + x) and at(g, x, y) == 0:
				outside += 1
	check(outside == 20 * 14 - expect.size(), "every grain outside the reach is still in place (%d)" % outside)


func test_spread_scan() -> void:
	print("[scan spread over frames]")
	var rows := []
	for y in 14:
		rows.append("0".repeat(20))
	var a := blk("a", 0, Vector2i(0, 0), 1000)
	var g := make_game(rows, 1, [a], 3, 10.0)
	var d: SuctionDrain = g.collector
	d.scan_visits_per_frame = 60  # about one cell expansion per frame
	var frames := 0
	var got := PackedInt32Array()
	var changed := 13 * 20 + 5  # (5,13): inside the reach; turns blue mid-scan (as if sand fell)
	while got.is_empty() and frames < 1000:
		got = d.step(a, 1000)
		frames += 1
		if frames == 3:
			var cells := g.map.cells
			g.map.cells = PackedByteArray()
			cells[changed] = 1
			g.map.cells = cells
	check(frames > 10 and d.is_busy() == false, "scan took %d frames, then grains flowed" % frames)
	check(at(g, 5, 13) == 1 and not got.has(changed), "a cell that changed color during the scan is not taken")
	var reds := 0
	for v in g.map.cells:
		if v == 0:
			reds += 1
	check(reds + a.collected == 20 * 14 - 1, "red conserved across the spread scan")


func test_capacity() -> void:
	print("[capacity]")
	var a := blk("a", 0, Vector2i(0, 0), 3)
	var g := make_game(["0000000000"], 1, [a])
	var over := [false]
	g.grains_collected.connect(func(b: SandBlock, _i):
		if b.collected > b.capacity: over[0] = true)
	var removed_at := [-1]
	g.block_filled.connect(func(b: SandBlock): removed_at[0] = b.collected)
	for i in 60:
		g.tick(1.0 / 60.0)
	check(not over[0] and a.collected == 3 and removed_at[0] == 3, "never above capacity; removed at exactly 3/3")
	check(g.map.remaining() == 7 and not g.cleared, "the other 7 grains stay; stage not cleared")


func test_finish() -> void:
	print("[90% finish]")
	# 9 linked reds next to the intake + 1 red far away (beyond the link). Capacity 10.
	var a := blk("a", 0, Vector2i(0, 0), 10)
	var g := make_game(["000000000.........0."], 1, [a], 3, 100.0, 0.9)
	var d: SuctionDrain = g.collector
	var seen9 := [false]
	var removed_at := [-1]
	g.grains_collected.connect(func(b: SandBlock, _i):
		if b.collected == 9 and not b.removed: seen9[0] = true)
	g.block_filled.connect(func(b: SandBlock): removed_at[0] = b.collected)
	for i in 120:
		g.tick(1.0 / 60.0)
	check(seen9[0], "at 9/10 (90%) the block is still on the board")
	check(a.removed and removed_at[0] == 10 and at(g, 18, 0) == SandMap.EMPTY,
		"finish pulls the far grain, block removed at exactly 10/10")
	check(d.finish_triggers == 1 and d.finish_grains == 1 and g.cleared, "finish triggered once, took 1 grain; stage cleared")
	# Disabled: the far grain stays and the block waits at 9/10.
	var a2 := blk("a", 0, Vector2i(0, 0), 10)
	var g2 := make_game(["000000000.........0."], 1, [a2], 3, 100.0, 0.0)
	for i in 120:
		g2.tick(1.0 / 60.0)
	check(a2.collected == 9 and not a2.removed and at(g2, 18, 0) == 0, "finish_at 0 disables it")
	# Two red blocks: finish of 'a' must not take the grain left for 'b' (room-limited).
	var a3 := blk("a", 0, Vector2i(0, 0), 10)
	var b3 := blk("b", 0, Vector2i(0, 1), 1)
	var g3 := make_game(["000000000........00."], 2, [a3, b3], 3, 100.0, 0.9)
	for i in 120:
		g3.tick(1.0 / 60.0)
	var reds := 0
	for v in g3.map.cells:
		if v == 0:
			reds += 1
	check(a3.removed and a3.collected == 10 and reds == 1 and b3.collected == 0,
		"finish takes only its room: 1 red left for the other red block")
	check(g3.board.move(b3, Vector2i.UP, 1), "the other block moves up into the freed cell")


## Collection depends on contact, never on whether the block moved: every resting block keeps
## its own session and re-checks its intake each frame.
func test_independent() -> void:
	print("[independent blocks: restart on new contact, simultaneous, move/remove mid-collection]")
	# 1-3) Red block A stands still at column 0 with blue on its intake (no contact). Blue block
	# B at column 1 chains the blue grain under A away; red falls onto A's intake and A starts
	# collecting by itself.
	var a := blk("a", 0, Vector2i(0, 0), 3)
	var b := blk("b", 1, Vector2i(1, 0), 2)
	var g := make_game(["0...", "0...", "0...", "11.."], 1, [a, b])
	var first := {}
	var tick := [0]
	g.grains_collected.connect(func(blk_: SandBlock, _idx): if not first.has(blk_.id): first[blk_.id] = tick[0])
	check(g.collector.step(a, 1 << 30).is_empty(), "A has no contact at start (blue sits on its intake)")
	for i in 300:
		tick[0] = i
		g.tick(1.0 / 60.0)
		if g.cleared:
			break
	check(a.pos == Vector2i(0, 0) and a.collected == 3 and a.removed,
		"A never moved, collected all 3 red grains once red fell onto its intake, removed at 3/3")
	check(first.has("b") and first.has("a") and first.a > first.b,
		"A started after B freed its intake (B tick %s, A tick %s)" % [first.get("b"), first.get("a")])
	check(b.collected == 2 and g.cleared, "B took both blue grains; stage cleared")

	# 4-7) Two blocks collect at once; B moves mid-collection; A is removed mid-collection.
	var ra := blk("ra", 0, Vector2i(0, 0), 4)
	var bb := blk("bb", 1, Vector2i(3, 0), 12, "I2h")  # covers both blue columns
	var rows := []
	for y in 6:
		rows.append("00.11.")
	var g2 := make_game(rows, 2, [ra, bb])
	g2.grains_per_second = 60.0  # one grain per block per tick
	var init := g2.map.count_by_color()
	var per_tick := {}
	g2.grains_collected.connect(func(blk_: SandBlock, idx: PackedInt32Array): per_tick[blk_.id] = int(per_tick.get(blk_.id, 0)) + idx.size())
	var both_same_tick := false
	var a_steady := true
	var conserved := true
	var b_after_a_removed := 0
	var moved := false
	var back := false
	var b_while_down := 0
	for i in 200:
		per_tick.clear()
		var a_before := ra.collected
		g2.tick(1.0 / 60.0)
		if per_tick.has("ra") and per_tick.has("bb"):
			both_same_tick = true
		if not ra.removed and i > 0 and ra.collected == a_before:
			a_steady = false  # A must keep taking a grain every tick, also on B's move tick
		if i == 2:
			moved = g2.try_move(bb, Vector2i.DOWN, 1)  # B leaves the landscape while both collect
		elif i > 2 and i <= 5 and moved and not back:
			b_while_down += int(per_tick.get("bb", 0))
		if i == 5:
			back = g2.try_move(bb, Vector2i.UP, 1)  # and comes back: new session, contact again
		if ra.removed:
			b_after_a_removed += int(per_tick.get("bb", 0))
		var now := g2.map.count_by_color()
		for c in 2:
			var got := ra.collected if c == 0 else bb.collected
			if now[c] + got != init[c]:
				conserved = false
		if bb.removed:
			break
	check(both_same_tick, "both blocks collect in the same tick")
	check(moved and back and b_while_down == 0, "B moved down mid-collection (stopped: no contact) and back up")
	check(a_steady, "A kept collecting every tick while B moved (sessions are independent)")
	check(ra.removed and ra.collected == 4, "A removed at exactly 4/4 while B was still collecting")
	check(b_after_a_removed > 0 and bb.removed and bb.collected == 12,
		"B kept collecting after A was removed (%d more), then filled %d/12" % [b_after_a_removed, bb.collected])
	check(conserved, "per color: sand left + collected == initial after every tick (no grain counted twice)")


## Real hawaii_01 sand: jungle collects and stays; palm then collects next to it; the sand that
## falls onto jungle's intake is collected without moving jungle. Also: whenever a resting
## block has contact (what the drag hint shows), it is collecting within a few frames.
func test_hawaii_restart() -> void:
	print("[hawaii_01: resting block restarts on new contact]")
	for res in [128, 64]:
		var g: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_01"), res).game
		var d: SuctionDrain = g.collector
		var j := g.board.get_block("j1")
		var p := g.board.get_block("p1")
		# Legal, non-overlapping layout on the 8x4 board: jungle on row 0, the rest below.
		var lay := {"j1": Vector2i(1, 0), "p1": Vector2i(3, 3), "l1": Vector2i(5, 3), "o1": Vector2i(6, 1), "f1": Vector2i(0, 2)}
		for id in lay:
			g.board.get_block(id).pos = lay[id]
		check(g.board.validate().is_empty(), "@%d test layout is legal (no overlap, inside the board)" % res)
		var worst := [0]
		var run := {}
		var watch := func() -> void:
			for b in g.board.blocks:
				if b.removed or b.contact_columns().is_empty():
					continue
				var masks := g.contact_masks()
				var hinted := false
				for c in b.contact_columns():
					hinted = hinted or ((masks[c] >> b.color_id) & 1) == 1
				if hinted and not d.is_collecting(b):
					run[b.id] = int(run.get(b.id, 0)) + 1
					worst[0] = maxi(worst[0], run[b.id])
				else:
					run.erase(b.id)
		for i in 1200:
			g.tick(1.0 / 60.0)
			watch.call()
			if g.is_idle():
				break
		var j_first := j.collected
		check(j_first > 0, "@%d jungle collected at x1 (%d)" % [res, j_first])
		p.pos = Vector2i(3, 0)
		check(g.board.validate().is_empty(), "@%d palm placed next to jungle (x3)" % res)
		g.collector.reset_session(p)
		var j_before := j.collected
		for i in 1800:
			g.tick(1.0 / 60.0)
			watch.call()
			if g.is_idle() and i > 30:
				break
		check(j.pos == Vector2i(1, 0) and j.collected > j_before,
			"@%d jungle never moved and collected %d more grains that fell onto it while palm collected %d" % [
				res, j.collected - j_before, p.collected])
		check(worst[0] <= 10, "@%d a resting block with contact (hint shown) collects within 10 frames (worst %d)" % [res, worst[0]])
		var left := g.map.count_by_color()
		var ok := g.remaining == g.total - j.collected - p.collected
		for b in g.board.blocks:
			ok = ok and b.collected <= b.capacity
		check(ok and left[j.color_id] + j.collected == StageLoader.build(StageLoader.get_stage("hawaii_01"), res).game.map.count_by_color()[j.color_id],
			"@%d sand conserved, no block above capacity" % res)


func test_hawaii() -> void:
	print("[hawaii_01 B-2: full paced play]")
	for res in [128, 64]:
		var g: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_01"), res).game
		var d: SuctionDrain = g.collector
		if res == 64:
			d.scan_visits_per_frame = 300  # force scans over many frames
		var initial := g.map.count_by_color()
		var caps := PackedInt32Array()
		caps.resize(initial.size())
		for b in g.board.blocks:
			caps[b.color_id] += b.capacity
		check(caps == initial, "@%d capacities per color equal sand per color %s" % [res, initial])
		var st := {"ok": true, "reach_ok": true, "cap_ok": true, "checks": 0, "far": 0.0}
		var w := g.map.width
		var on_grains := func(_b: SandBlock, idx: PackedInt32Array):
			st.checks += 1
			var collected := PackedInt32Array()
			collected.resize(initial.size())
			for bb in g.board.blocks:
				collected[bb.color_id] += bb.collected
				if bb.collected > bb.capacity:
					st.cap_ok = false
			var now := g.map.count_by_color()
			for c in initial.size():
				if now[c] + collected[c] != initial[c]:
					st.ok = false
			if g.map.remaining() != g.remaining:
				st.ok = false
				if st.checks < 3000: print("    remaining mismatch map=", g.map.remaining(), " game=", g.remaining)
			if d.last_targets.size() != idx.size() * 2:
				st.ok = false
				if st.checks < 3000: print("    targets mismatch ", d.last_targets.size(), " vs ", idx.size())
			if not d.last_finishing:
				var t: PackedInt32Array = d.last_targets
				for k in range(0, t.size(), 2):
					@warning_ignore("integer_division")
					var dx := float(t[k] % w - t[k + 1] % w)
					@warning_ignore("integer_division")
					var dy := float(t[k + 1] / w - t[k] / w)
					var dist := sqrt(dx * dx + dy * dy)
					st.far = maxf(st.far, dist)
					if dist > d.reach + 0.001:
						st.reach_ok = false
		g.grains_collected.connect(on_grains)
		var r := LevelSolver.play_gravity(g)
		g.grains_collected.disconnect(on_grains)
		check(r.status == "cleared" and g.remaining == 0 and g.cleared,
			"@%d cleared by the play policy (%s, drags %s, %.0fs sim)" % [res, r.status, r.get("drags"), r.get("sim_seconds", 0.0)])
		check(st.ok and st.checks > 0, "@%d per color: remaining + collected == initial at every collection (%d checks)" % [res, st.checks])
		check(st.reach_ok, "@%d every non-finish grain within reach %.0f of its intake (max %.1f)" % [res, d.reach, st.far])
		check(st.cap_ok, "@%d no block ever above capacity" % res)
		var full_ok := true
		for b in g.board.blocks:
			full_ok = full_ok and b.removed and b.collected == b.capacity
		check(full_ok, "@%d every block filled exactly to capacity and removed" % res)
		check(d.finish_triggers == 5 and d.finish_grains > 0,
			"@%d finish triggered for all 5 blocks (%d grains, %.1f%% of sand)" % [res, d.finish_grains, 100.0 * d.finish_grains / g.total])
	# Collapse: the first placement makes the rest of the picture move.
	var g2: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_01"), 128).game
	var p2 := open_palm(g2)
	check(p2 != null, "hawaii_01 opening: palm right, lagoon left, palm up are all legal moves")
	var before := g2.map.cells.duplicate()
	var taken := {}
	g2.grains_collected.connect(func(_b, idx):
		for i in idx:
			taken[i] = true)
	for i in 120:
		g2.tick(1.0 / 60.0)
	var moved := 0
	for i in before.size():
		if before[i] != g2.map.cells[i] and not taken.has(i):
			moved += 1
	check(p2 != null and p2.collected > 0 and moved > 100,
		"suction makes the picture collapse (%d taken, %d other cells changed in 2s)" % [taken.size(), moved])
	var g3: SandGame = StageLoader.build(StageLoader.get_stage("hawaii_01"), 128).game
	open_palm(g3)
	for i in 120:
		g3.tick(1.0 / 60.0)
	check(g3.map.cells == g2.map.cells, "deterministic")
