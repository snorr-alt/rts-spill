extends Node2D
## Hovedscenen: kart, rådhus, arbeidere, kamera, valg og kommandoer.
##
## Berøring:  trykk = velg / gi ordre,  dra = flytt kartet,  knip = zoom,
##            hold stille og dra = velg flere,  dobbelttrykk på arbeider = alle på skjermen.
## PC:        venstreklikk = velg / gi ordre,  høyreklikk = ordre,  dra = flytt,  hjul = zoom.

const WORKER_COST := 50
const TRAIN_TIME := 10.0
const POP_CAP := 10
const START_WORKERS := 3
const START_WOOD := 100

const TAP_SLOP := 14.0
const LONG_PRESS := 0.4
const DOUBLE_TAP := 0.4
const ZOOM_MIN := 0.6
const ZOOM_MAX := 2.6
const MOUSE_ID := 1000

var map: GameMap
var town: TownCenter
var units_root: Node2D
var overlay: Node2D
var cam: Camera2D
var hud: Hud

var wood := START_WOOD
var workers: Array[Worker] = []
var selected: Array[Worker] = []

var _pointers := {}  # id -> {"start", "pos", "t"}
var _mode := ""  # "", "pan", "box", "pinch"
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _last_tap_unit: Worker = null
var _last_tap_time := -10.0
var _markers: Array = []  # [world_pos, age, color]
var _clock := 0.0


func _ready() -> void:
	randomize()
	map = GameMap.new()
	add_child(map)
	map.generate(randi())

	units_root = Node2D.new()
	units_root.y_sort_enabled = true
	add_child(units_root)

	town = TownCenter.new()
	town.setup(map, Vector2i(GameMap.W / 2 - 1, GameMap.H / 2 - 1))
	units_root.add_child(town)

	overlay = Node2D.new()
	overlay.z_index = 50
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

	cam = Camera2D.new()
	cam.position = town.center()
	cam.zoom = Vector2(1.5, 1.5)
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	hud.main = self
	add_child(hud)

	for i in START_WORKERS:
		_spawn_worker()


# ---------------------------------------------------------------- økonomi

func add_wood(n: int) -> void:
	wood += n


func can_train() -> bool:
	return wood >= WORKER_COST and workers.size() + town.queue < POP_CAP and town.queue < TownCenter.MAX_QUEUE


func train_worker() -> bool:
	if not can_train():
		return false
	wood -= WORKER_COST
	town.queue += 1
	return true


func _spawn_worker() -> Worker:
	# Nye arbeidere kommer ut langs nedre kant av rådhuset, ikke oppå hverandre
	var k := workers.size() % (TownCenter.SIZE + 2)
	var c := map.nearest_walkable(town.cell + Vector2i(k - 1, TownCenter.SIZE))
	var w := Worker.new()
	w.main = self
	w.map = map
	w.town = town
	w.position = map.center_of(c) + Vector2(randf_range(-8, 8), randf_range(-6, 6))
	units_root.add_child(w)
	workers.append(w)
	return w


func _process(delta: float) -> void:
	_clock += delta
	if town.queue > 0:
		town.progress += delta / TRAIN_TIME
		if town.progress >= 1.0:
			town.progress = 0.0
			town.queue -= 1
			_spawn_worker().cmd_auto_gather()
	else:
		town.progress = 0.0
	# Langt trykk uten bevegelse starter valgboks
	if _pointers.size() == 1 and _mode == "":
		var p: Dictionary = _pointers.values()[0]
		if _clock - p.t > LONG_PRESS:
			_mode = "box"
			_box_a = p.start
			_box_b = p.pos
	for m in _markers:
		m[1] += delta
	_markers = _markers.filter(func(m: Array) -> bool: return m[1] < 0.6)
	overlay.queue_redraw()


# ---------------------------------------------------------------- valg

func idle_workers() -> Array[Worker]:
	var out: Array[Worker] = []
	for w in workers:
		if w.is_idle():
			out.append(w)
	return out


func _set_selection(list: Array[Worker]) -> void:
	for w in selected:
		w.selected = false
	selected = list
	for w in selected:
		w.selected = true
	town.selected = false


func clear_selection() -> void:
	_set_selection([] as Array[Worker])


func select_idle() -> void:
	var idle := idle_workers()
	if idle.is_empty():
		return
	_set_selection(idle)
	cam.position = idle[0].position
	_clamp_cam()


func select_town() -> void:
	_set_selection([] as Array[Worker])
	town.selected = true


func auto_gather_selected() -> void:
	for w in selected:
		w.cmd_auto_gather()


func _worker_at(world: Vector2) -> Worker:
	var best: Worker = null
	var best_d := Worker.PICK_RADIUS / clampf(cam.zoom.x, 0.8, 2.0) * 1.4
	for w in workers:
		var d := w.position.distance_to(world + Vector2(0, 3))
		if d < best_d:
			best_d = d
			best = w
	return best


func _workers_on_screen() -> Array[Worker]:
	var out: Array[Worker] = []
	var r := Rect2(_to_world(Vector2.ZERO), get_viewport_rect().size / cam.zoom.x)
	for w in workers:
		if r.has_point(w.position):
			out.append(w)
	return out


# ---------------------------------------------------------------- kommandoer

## Et trykk på kartet: velger noe, eller gir ordre til de valgte arbeiderne.
func tap_world(world: Vector2) -> void:
	hud.dismiss_hint()
	var u := _worker_at(world)
	if u != null:
		if u == _last_tap_unit and _clock - _last_tap_time < DOUBLE_TAP:
			_set_selection(_workers_on_screen())
		else:
			_set_selection([u] as Array[Worker])
		_last_tap_unit = u
		_last_tap_time = _clock
		return
	_last_tap_unit = null
	if not selected.is_empty():
		command_at(world)
	elif town.contains(world):
		select_town()
	else:
		clear_selection()


func command_at(world: Vector2) -> void:
	if selected.is_empty():
		return
	var c := map.tile_of(world)
	if town.has_cell(c):
		for w in selected:
			w.cmd_return()
		_markers.append([town.center(), 0.0, Color(1.0, 0.9, 0.3)])
	elif map.is_tree(c):
		for w in selected:
			w.cmd_gather(c)
		_markers.append([map.center_of(c), 0.0, Color(1.0, 0.6, 0.2)])
	else:
		# Spre de valgte litt, så de ikke står oppå hverandre
		var n := selected.size()
		var cols := ceili(sqrt(n))
		for i in n:
			var off := Vector2(i % cols - (cols - 1) * 0.5, i / cols - (cols - 1) * 0.5) * 16.0
			selected[i].cmd_move(world + off)
		_markers.append([world, 0.0, Color(0.4, 1.0, 0.4)])


# ---------------------------------------------------------------- inndata

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_down(e.index, e.position)
		else:
			_up(e.index, e.position)
	elif e is InputEventScreenDrag:
		_move(e.index, e.position)
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					_down(MOUSE_ID, e.position)
				else:
					_up(MOUSE_ID, e.position)
			MOUSE_BUTTON_RIGHT:
				if e.pressed and not hud.blocks(e.position):
					command_at(_to_world(e.position))
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					_zoom_at(e.position, 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					_zoom_at(e.position, 1.0 / 1.1)
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		_move(MOUSE_ID, e.position)


func _down(id: int, pos: Vector2) -> void:
	if hud.blocks(pos):
		return
	_pointers[id] = {"start": pos, "pos": pos, "t": _clock}
	if _pointers.size() == 2:
		_mode = "pinch"
		var ps := _pointers.values()
		_pinch_dist = ps[0].pos.distance_to(ps[1].pos)
		_pinch_mid = (ps[0].pos + ps[1].pos) * 0.5
	elif _pointers.size() == 1:
		_mode = ""


func _move(id: int, pos: Vector2) -> void:
	if not _pointers.has(id):
		return
	var p: Dictionary = _pointers[id]
	var prev: Vector2 = p.pos
	p.pos = pos
	match _mode:
		"pinch":
			if _pointers.size() < 2:
				return
			var ps := _pointers.values()
			var a: Vector2 = ps[0].pos
			var b: Vector2 = ps[1].pos
			var d := a.distance_to(b)
			var mid := (a + b) * 0.5
			cam.position -= (mid - _pinch_mid) / cam.zoom.x
			if _pinch_dist > 1.0:
				_zoom_at(mid, d / _pinch_dist)
			_pinch_dist = d
			_pinch_mid = mid
			_clamp_cam()
		"box":
			_box_b = pos
		"pan":
			cam.position -= (pos - prev) / cam.zoom.x
			_clamp_cam()
		_:
			if pos.distance_to(p.start) > TAP_SLOP:
				_mode = "pan"
				cam.position -= (pos - p.start) / cam.zoom.x
				_clamp_cam()


func _up(id: int, pos: Vector2) -> void:
	if not _pointers.has(id):
		return
	_pointers.erase(id)
	match _mode:
		"pinch":
			_mode = "pan" if not _pointers.is_empty() else ""
		"box":
			_select_box()
			_mode = ""
		"pan":
			if _pointers.is_empty():
				_mode = ""
		_:
			tap_world(_to_world(pos))


func _select_box() -> void:
	var r := Rect2(_to_world(_box_a), Vector2.ZERO).expand(_to_world(_box_b))
	var list: Array[Worker] = []
	for w in workers:
		if r.grow(6).has_point(w.position):
			list.append(w)
	_set_selection(list)
	hud.dismiss_hint()


# ---------------------------------------------------------------- kamera

func _to_world(screen: Vector2) -> Vector2:
	return cam.position + (screen - get_viewport_rect().size * 0.5) / cam.zoom.x


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := _to_world(screen)
	var z := clampf(cam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.position = before - (screen - get_viewport_rect().size * 0.5) / z
	_clamp_cam()


func _clamp_cam() -> void:
	var half := get_viewport_rect().size * 0.5 / cam.zoom.x
	var s := map.size_px()
	var margin := 64.0
	cam.position.x = clampf(cam.position.x, minf(half.x - margin, s.x * 0.5), maxf(s.x - half.x + margin, s.x * 0.5))
	cam.position.y = clampf(cam.position.y, minf(half.y - margin, s.y * 0.5), maxf(s.y - half.y + margin, s.y * 0.5))


# ---------------------------------------------------------------- tegning oppå alt

func _draw_overlay() -> void:
	for m in _markers:
		var t: float = m[1] / 0.6
		var col: Color = m[2]
		col.a = 1.0 - t
		overlay.draw_arc(m[0], 6.0 + 14.0 * t, 0.0, TAU, 24, col, 3.0)
	if _mode == "box":
		var r := Rect2(_to_world(_box_a), Vector2.ZERO).expand(_to_world(_box_b))
		overlay.draw_rect(r, Color(0.4, 1.0, 0.4, 0.15))
		overlay.draw_rect(r, Color(0.4, 1.0, 0.4, 0.9), false, 2.0 / cam.zoom.x)
