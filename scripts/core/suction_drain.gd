class_name SuctionDrain
extends GravityDrain
## Collection rule B-2 "range-limited chain suction" (prototype for hawaii_01, 2026-11-14).
## Stage opt-in: "physics": "gravity" + "collect": "suction". Rule A (GravityDrain) is unchanged.
##
## All distances are in cells of the sand grid (one cell = one grain). The config values are
## given for the 128x128 grid and scaled by width/128 for other resolutions (StageLoader).
##  - Start: an intake pixel of the block (landscape bottom row above one of its row-0 cells)
##    holds a grain of the block's color. No contact, no collection.
##  - Link: a grain of the block's color joins the pull when it is within `link` cells of a
##    grain already in the pull, measured as max(|dx|, |dy|) (Chebyshev). With link 3 up to
##    two cells of other colors or empty space may lie between them.
##  - Reach: only grains whose distance to the nearest intake pixel of this block,
##    sqrt(dx^2 + dy^2), is <= `reach` cells. Grains outside are never chained through.
##  - Other colors are never taken; a block never takes more than its remaining room.
##  - Finish: once block.collected >= ceil(finish_at * capacity) (finish_at > 0), the block
##    pulls every remaining grain of its color, up to its room, ignoring link/reach/contact,
##    at `finish_speed_scale` times the normal rate, while it rests on board row 0.
##
## A session (per block, reset whenever the block moves or is picked up):
##   scan -> queue -> take. The scan is a BFS that may be spread over several frames
##   (`scan_visits_per_frame`). The queue holds the found cells, farthest first. A cell is
##   only taken if it still holds the block's color at that moment (the sand keeps falling
##   during the session; a cell that changed is skipped, so a wrong grain is never taken).
##   Cells are fixed positions inside the reach, so anything taken is always within reach.
##   When the queue runs out it scans again (normal mode needs contact again).
##
## `last_targets`: for the last step(), pairs [cell, intake pixel] per collected grain (the
## grain's cell and the intake pixel it is pulled into), for the suction animation.

class Session:
	var finishing := false
	var scanning := false
	var order := PackedInt32Array()
	var head := 0
	var finish_row := -1
	var frames := 0
	var seen := PackedByteArray()
	var queue := PackedInt32Array()
	var near_x := PackedInt32Array()  # per x: nearest intake x
	var dxt := PackedInt32Array()     # per x: |x - nearest intake x|


var link := 3
var reach := 48.0
var finish_at := 0.9
var finish_speed_scale := 3.0
var scan_visits_per_frame := 15000

var last_targets := PackedInt32Array()
var last_finishing := false

## Stats (tests / reports).
var finish_triggers := 0
var finish_grains := 0
var scans := 0
var scan_usec_max := 0
var scan_usec_frame := 0  # scan time spent in the current frame (reset by SandGame.tick)
var scan_frames_max := 0  # most frames one scan was spread over

var _sessions := {}       # block id -> Session
var _finish_seen := {}    # block id -> true once its finish started (for the stats)


func _init(p_map: SandMap, p_board: PuzzleBoard, p_sim: SandSim) -> void:
	super(p_map, p_board, p_sim)


func reset_session(block: SandBlock) -> void:
	super.reset_session(block)
	_sessions.erase(block.id)


func reset_all() -> void:
	super.reset_all()
	_sessions.clear()


func finish_threshold(block: SandBlock) -> int:
	return ceili(finish_at * block.capacity)


func is_finishing(block: SandBlock) -> bool:
	return finish_at > 0.0 and not block.removed and block.collected >= finish_threshold(block) \
		and not block.is_full()


func rate_scale(block: SandBlock) -> float:
	return finish_speed_scale if is_finishing(block) else 1.0


## True while some session still has a scan running or grains queued.
func is_busy() -> bool:
	for id in _sessions:
		var s: Session = _sessions[id]
		if s.scanning or not s.queue.is_empty():
			return true
	return false


## How many grains a scan at `at` would queue right now (normal or finish mode, capped by
## room). Synchronous, does not touch the block's session. Used by tests and the policy.
func reachable_count(block: SandBlock, at: Vector2i = block.pos) -> int:
	var keep := block.pos
	block.pos = at
	var s := Session.new()
	s.finishing = is_finishing(block)
	var n := 0
	if _begin_scan(block, s):
		_advance_scan(block, s, 1 << 30)
		n = s.queue.size()
	block.pos = keep
	return n


func _session(block: SandBlock) -> Session:
	var s: Session = _sessions.get(block.id)
	if s == null:
		s = Session.new()
		_sessions[block.id] = s
	return s


## Starts a scan from the block's current intake. Returns false when nothing can start
## (normal mode without direct contact).
func _begin_scan(block: SandBlock, s: Session) -> bool:
	var w := map.width
	var intake := intake_pixels(block)
	if intake.is_empty():
		return false
	var cells := map.cells
	var color := block.color_id
	if not s.finishing:
		# Cheap contact test first: a resting block re-checks only its intake pixels every
		# frame, so new contact (sand that fell onto it) starts a scan without moving it.
		var touching := false
		for i in intake:
			if cells[i] == color:
				touching = true
				break
		if not touching:
			return false
	# Per-x distance to the nearest intake column.
	s.near_x.resize(w)
	s.dxt.resize(w)
	for x in w:
		var best := -1
		var bd := 1 << 30
		for i in intake:
			var d := absi(i % w - x)
			if d < bd:
				bd = d
				best = i % w
		s.near_x[x] = best
		s.dxt[x] = bd
	s.order = PackedInt32Array()
	s.head = 0
	s.frames = 0
	s.queue = PackedInt32Array()
	if s.finishing:
		s.finish_row = map.height - 1
		s.scanning = true
		return true
	s.seen = PackedByteArray()
	s.seen.resize(w * map.height)
	for i in intake:
		if cells[i] == color:  # direct contact only
			s.seen[i] = 1
			s.order.append(i)
	if s.order.is_empty():
		return false
	s.scanning = true
	return true


## Advances the scan by about `budget` cell visits. Returns true when the scan finished
## (the queue is then filled).
func _advance_scan(block: SandBlock, s: Session, budget: int) -> bool:
	var t0 := Time.get_ticks_usec()
	s.frames += 1
	var w := map.width
	var h := map.height
	var cells := map.cells
	var color := block.color_id
	var visits := 0
	if s.finishing:
		# Every grain of the color, nearest rows first (bottom up); taken farthest first.
		while s.finish_row >= 0 and visits < budget:
			var row := s.finish_row * w
			for x in w:
				if cells[row + x] == color:
					s.order.append(row + x)
			s.finish_row -= 1
			visits += w
		var done := s.finish_row < 0
		_note_scan_time(t0)
		if done:
			_finish_scan(block, s)
		return done
	var r2 := reach * reach
	var win := (2 * link + 1) * (2 * link + 1)
	while s.head < s.order.size():
		if visits >= budget:
			_note_scan_time(t0)
			return false
		var j := s.order[s.head]
		s.head += 1
		var jx := j % w
		@warning_ignore("integer_division")
		var jy := j / w
		var x0 := maxi(0, jx - link)
		var x1 := mini(w, jx + link + 1)
		for yy in range(maxi(0, jy - link), mini(h, jy + link + 1)):
			var dy := h - 1 - yy
			var dy2 := float(dy * dy)
			if dy2 > r2:
				continue
			var row := yy * w
			for xx in range(x0, x1):
				var n := row + xx
				if s.seen[n] == 0 and cells[n] == color:
					var dx := s.dxt[xx]
					if dx * dx + dy2 <= r2:
						s.seen[n] = 1
						s.order.append(n)
		visits += win
	_note_scan_time(t0)
	_finish_scan(block, s)
	return true


func _finish_scan(block: SandBlock, s: Session) -> void:
	scans += 1
	scan_frames_max = maxi(scan_frames_max, s.frames)
	s.scanning = false
	s.seen = PackedByteArray()
	# Keep the nearest `room` cells (BFS / bottom-up order), take them farthest first.
	var room := block.room()
	if s.order.size() > room:
		s.order.resize(room)
	s.queue = s.order
	s.order = PackedInt32Array()


func _note_scan_time(t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	scan_usec_frame += dt
	scan_usec_max = maxi(scan_usec_max, dt)


## Collects up to `budget` grains for `block`. Returns the emptied cell indices.
func step(block: SandBlock, budget: int, _max_visits := 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	last_paths.clear()
	last_targets = PackedInt32Array()
	_collected_last[block.id] = 0
	if block.removed or block.is_full() or budget <= 0:
		return out
	var s := _session(block)
	var fin := is_finishing(block)
	if fin != s.finishing:
		s.finishing = fin
		s.scanning = false
		s.queue = PackedInt32Array()
		if fin and not _finish_seen.has(block.id):
			_finish_seen[block.id] = true
			finish_triggers += 1
	last_finishing = fin
	var want := mini(budget, block.room())
	var color := block.color_id
	var cells := map.cells
	var w := map.width
	var row := (map.height - 1) * w
	var scanned := false
	var taken := {}  # cells taken in this call are emptied at the end; a rescan must skip them
	while out.size() < want:
		if s.queue.is_empty():
			if scanned:
				break
			if not s.scanning and not _begin_scan(block, s):
				break
			var budget_visits := scan_visits_per_frame if budget < (1 << 29) else (1 << 30)
			if not _advance_scan(block, s, budget_visits):
				break  # scan continues next frame
			scanned = true
			continue
		var i := s.queue[s.queue.size() - 1]
		s.queue.resize(s.queue.size() - 1)
		if cells[i] != color or taken.has(i):
			continue  # the sand moved since the scan; never take a different grain
		taken[i] = true
		out.append(i)
		last_targets.append(i)
		last_targets.append(row + s.near_x[i % w])
	if out.is_empty():
		return out
	map.cells = PackedByteArray()  # sole ownership for writes
	for i in out:
		cells[i] = EMPTY
		sim.wake(i)
	map.cells = cells
	block.collected += out.size()
	changes += out.size()
	if fin:
		finish_grains += out.size()
	_collected_last[block.id] = out.size()
	return out
