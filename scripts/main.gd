class_name Main
extends Node2D
## Hovedscenen: kart, spillere, enheter, bygninger, kamera, valg, ordre, bygging og seier/tap.
##
## Berøring:  trykk = velg / gi ordre,  dra = flytt kartet,  knip = zoom,
##            hold stille og dra = velg flere,  dobbelttrykk på enhet = alle av typen på skjermen.
## PC:        venstreklikk = velg / gi ordre,  høyreklikk = ordre,  dra = flytt,  hjul = zoom.

const START_WORKERS := 3
const TAP_SLOP := 14.0
const LONG_PRESS := 0.4
const DOUBLE_TAP := 0.4
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.6
const MOUSE_ID := 1000
const BUCKET := 128.0  # størrelse på rutene i oppslagstabellen for enheter (piksler)
const SEPARATION := 11.0
const SEP_CELL := 16.0  # finere rutenett bare for å skyve enheter fra hverandre

## Valg som overlever «Ny kamp» (scenen lastes på nytt)
static var difficulty := 1
static var ai_both := false  # brukes av testen: begge lag styres av AI
static var seed_override := -1
static var skip_menu := false

var map: GameMap
var players: Array[Player] = []
var me: Player
var ais: Array[AIController] = []
var units_root: Node2D
var overlay: Node2D
var cam: Camera2D
var hud: Hud
var game_time := 0.0
var game_over := false
var winner := -1

var selected: Array[Unit] = []
var selected_building: Building = null
var selected_enemy: Unit = null
var selected_res := Vector2i(-1, -1)
var build_menu := false
var placing := ""  # bygningstype som plasseres, eller ""
var place_cell := Vector2i.ZERO

var _buckets := {}
var _sep_grid := {}
## Det kameraet ser (med litt margin), i verdenskoordinater. Enheter utenfor tegnes ikke på nytt.
var view_rect := Rect2()
var _sep_frame := 0
var _pointers := {}  # id -> {"start", "pos", "t"}
var _mode := ""  # "", "pan", "box", "pinch"
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _last_tap_unit: Unit = null
var _last_tap_time := -10.0
var _markers: Array = []  # [world_pos, age, color]
var _arrows: Array = []  # [from, to, age]
var _marks: Array = []  # [world_pos, age, size] – rester etter døde enheter og bygninger
var _clock := 0.0
var _alert_t := -100.0
var _victory_t := 0.0
var _ghost_world := Vector2.INF


func _ready() -> void:
	if seed_override >= 0:
		seed(seed_override)
	else:
		randomize()
	map = GameMap.new()
	add_child(map)
	map.generate(randi())

	units_root = Node2D.new()
	units_root.y_sort_enabled = true
	add_child(units_root)

	overlay = Node2D.new()
	overlay.z_index = 50
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

	for t in 2:
		var p := Player.new(t)
		players.append(p)
		var tc := _add_building(p, "town", map.bases[t], true)
		for i in START_WORKERS:
			spawn_unit(p, "worker", tc)
	me = players[0]
	var diff: Dictionary = Defs.DIFFICULTY[difficulty]
	players[1].is_ai = true
	players[1].gather_mult = diff.gather
	ais.append(AIController.new(self, players[1], diff))
	if ai_both:
		players[0].is_ai = true
		ais.append(AIController.new(self, players[0], Defs.DIFFICULTY[1]))
	for a in ais:
		add_child(a)

	cam = Camera2D.new()
	cam.position = me.town().center()
	cam.zoom = Vector2(1.4, 1.4)
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	hud.main = self
	add_child(hud)
	if not skip_menu and not ai_both:
		hud.show_menu()


# ---------------------------------------------------------------- enheter og bygninger

func _add_building(p: Player, type: String, c: Vector2i, built: bool) -> Building:
	var b := Building.new()
	b.setup(self, p, type, c, built)
	units_root.add_child(b)
	p.buildings.append(b)
	# Flytt enheter som står der bygningen kommer
	var wr := b.world_rect()
	for q in players:
		for u in q.units:
			if b.has_cell(u.cell()):
				u.position = map.center_of(map.nearest_walkable(u.cell()))
			u.repath_if_blocked(wr)
	return b


## Plasser en byggeplass og send arbeiderne dit. Gir bygningen, eller null hvis det ikke gikk.
func place_building(p: Player, type: String, c: Vector2i, builders: Array) -> Building:
	var def: Dictionary = Defs.BUILDINGS[type]
	if not map.can_place(c, def.size) or not p.can_afford(def.cost):
		return null
	p.pay(def.cost)
	var b := _add_building(p, type, c, false)
	for w in builders:
		if w is Worker and is_instance_valid(w) and not w.dead:
			w.cmd_build(b)
	return b


func spawn_unit(p: Player, type: String, from: Building) -> Unit:
	var u: Unit = Worker.new() if type == "worker" else Unit.new()
	u.setup(self, p, type)
	# Ut på siden av bygningen som vender mot midten av kartet
	var mid := Vector2(GameMap.W, GameMap.H) * 0.5
	var best := Vector2i(-1, -1)
	var best_d := INF
	var r := from.rect()
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var c := Vector2i(x, y)
			if r.has_point(c) or not map.is_walkable(c):
				continue
			var d := Vector2(c).distance_squared_to(mid) + randf() * 30.0
			if d < best_d:
				best_d = d
				best = c
	if best.x < 0:
		best = map.nearest_walkable(from.cell)
	u.position = map.center_of(best) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	units_root.add_child(u)
	p.units.append(u)
	p.stats.trained += 1
	if type == "worker" and from.type == "town" and not p.is_ai:
		# Nye arbeidere samler det det er minst av (av mat og tre), så økonomien holdes i gang
		(u as Worker).cmd_auto_gather("food" if p.res.food <= p.res.wood else "wood")
	return u


func on_building_complete(b: Building) -> void:
	if b.player == me and not me.is_ai:
		hud.message("%s er ferdig" % b.display_name())


func on_unit_died(u: Unit) -> void:
	u.player.units.erase(u)
	u.player.stats.lost += 1
	selected.erase(u)
	if _last_tap_unit == u:
		_last_tap_unit = null
	if selected_enemy == u:
		selected_enemy = null
	_marks.append([u.position, 0.0, 6.0])


func on_building_died(b: Building) -> void:
	b.player.buildings.erase(b)
	if selected_building == b:
		selected_building = null
	_marks.append([b.center(), 0.0, b.size * 14.0])
	if b.player == me and not me.is_ai:
		hud.message("%s ble ødelagt!" % b.display_name())


func on_damaged(target: Node2D, from: Unit) -> void:
	if from == null or not is_instance_valid(from):
		return
	var victim: Player = target.player
	for a in ais:
		if a.player == victim:
			a.on_attacked(target, from)
	if victim == me and not me.is_ai and _clock - _alert_t > 10.0:
		_alert_t = _clock
		hud.alert("Du blir angrepet!", target.position)


func add_arrow(from: Vector2, to: Vector2) -> void:
	_arrows.append([from, to, 0.0])


# ---------------------------------------------------------------- oppslag

func _rebuild_buckets() -> void:
	_buckets.clear()
	for p in players:
		for u in p.units:
			var k := Vector2i(floori(u.position.x / BUCKET), floori(u.position.y / BUCKET))
			if _buckets.has(k):
				_buckets[k].append(u)
			else:
				_buckets[k] = [u]


func nearest_enemy_unit(pos: Vector2, radius: float, team: int) -> Unit:
	var best: Unit = null
	var best_d := radius * radius
	var r := ceili(radius / BUCKET)
	var k0 := Vector2i(floori(pos.x / BUCKET), floori(pos.y / BUCKET))
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var list = _buckets.get(k0 + Vector2i(x, y))
			if list == null:
				continue
			for u in list:
				# Tabellen bygges i fysikksteget; en enhet kan ha blitt fjernet siden
				if not is_instance_valid(u) or u.dead or u.player.team == team:
					continue
				var d: float = pos.distance_squared_to(u.position)
				if d > radius * radius:
					continue
				# Soldater foretrekkes framfor arbeidere
				if u.type == "worker":
					d *= 1.6
				if d < best_d:
					best_d = d
					best = u
	return best


func nearest_enemy_building(pos: Vector2, radius: float, team: int) -> Building:
	var best: Building = null
	var best_d := radius
	for p in players:
		if p.team == team:
			continue
		for b in p.buildings:
			var d := b.distance_to(pos)
			if d < best_d:
				best_d = d
				best = b
	return best


func unit_at(world: Vector2) -> Unit:
	var best: Unit = null
	var best_d := Unit.PICK_RADIUS / clampf(cam.zoom.x, 0.8, 2.0) * 1.4
	for p in players:
		for u in p.units:
			var d := u.position.distance_to(world + Vector2(0, 3))
			if p == me:
				d *= 0.8  # egne enheter er lettere å treffe
			if d < best_d:
				best_d = d
				best = u
	return best


func building_at(world: Vector2) -> Building:
	for p in players:
		for b in p.buildings:
			if b.contains(world):
				return b
	return null


# ---------------------------------------------------------------- hver ramme

func _physics_process(_delta: float) -> void:
	_rebuild_buckets()
	_sep_frame += 1
	if _sep_frame % 3 == 0:
		_separate()


## Skyv enheter som står oppå hverandre litt fra hverandre. Bruker et fint rutenett
## (16 px), så hver enhet bare sammenlignes med de få som står helt inntil.
func _separate() -> void:
	_sep_grid.clear()
	for p in players:
		for u in p.units:
			var k := Vector2i(floori(u.position.x / SEP_CELL), floori(u.position.y / SEP_CELL))
			var list = _sep_grid.get(k)
			if list == null:
				_sep_grid[k] = [u]
			else:
				list.append(u)
	for p in players:
		for a in p.units:
			var k := Vector2i(floori(a.position.x / SEP_CELL), floori(a.position.y / SEP_CELL))
			var push := Vector2.ZERO
			for y in range(-1, 2):
				for x in range(-1, 2):
					var list = _sep_grid.get(k + Vector2i(x, y))
					if list == null:
						continue
					for b: Unit in list:
						if a == b:
							continue
						var d := a.position - b.position
						var l2 := d.length_squared()
						if l2 < SEPARATION * SEPARATION:
							var l := sqrt(l2)
							if l < 0.01:
								d = Vector2.from_angle(randf() * TAU)
								l = 0.01
							push += d / l * (SEPARATION - l) * 0.5
			if push != Vector2.ZERO:
				# Enheter som jobber står mer stødig
				if a.state == Unit.S.GATHER or a.state == Unit.S.BUILD:
					push *= 0.3
				var np := a.position + push.limit_length(3.0)
				if map.is_walkable(map.tile_of(np)):
					a.position = np


func _process(delta: float) -> void:
	_clock += delta
	game_time += delta
	var vs := get_viewport_rect().size / cam.zoom.x
	view_rect = Rect2(cam.position - vs * 0.5, vs).grow(48.0)
	# Langt trykk uten bevegelse starter valgboks
	if _pointers.size() == 1 and _mode == "":
		var p: Dictionary = _pointers.values()[0]
		if _clock - p.t > LONG_PRESS and placing == "":
			_mode = "box"
			_box_a = p.start
			_box_b = p.pos
	for m in _markers:
		m[1] += delta
	_markers = _markers.filter(func(m: Array) -> bool: return m[1] < 0.6)
	for a in _arrows:
		a[2] += delta
	_arrows = _arrows.filter(func(a: Array) -> bool: return a[2] < 0.25)
	for m in _marks:
		m[1] += delta
	_marks = _marks.filter(func(m: Array) -> bool: return m[1] < 8.0)
	if placing != "":
		place_cell = _ghost_cell()
	if selected_enemy != null and (not is_instance_valid(selected_enemy) or selected_enemy.dead):
		selected_enemy = null
	if selected_building != null and (not is_instance_valid(selected_building) or selected_building.dead):
		selected_building = null
	_victory_t -= delta
	if _victory_t <= 0.0 and not game_over:
		_victory_t = 1.0
		_check_victory()
	overlay.queue_redraw()


func _check_victory() -> void:
	for p in players:
		if not p.defeated and p.units.is_empty() and p.town() == null:
			p.defeated = true
	var alive := players.filter(func(p: Player) -> bool: return not p.defeated)
	if alive.size() <= 1:
		game_over = true
		winner = alive[0].team if alive.size() == 1 else -1
		if not ai_both:
			hud.show_end(winner == me.team)


func new_game() -> void:
	get_tree().paused = false
	skip_menu = false
	get_tree().reload_current_scene()


func start_game(diff: int) -> void:
	difficulty = diff
	skip_menu = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null:
		hud.toggle_pause()


# ---------------------------------------------------------------- valg

func _set_selection(list: Array[Unit]) -> void:
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	selected = list
	for u in selected:
		u.selected = true
	if selected_building != null and is_instance_valid(selected_building):
		selected_building.selected = false
	selected_building = null
	selected_enemy = null
	selected_res = Vector2i(-1, -1)
	build_menu = false


func clear_selection() -> void:
	_set_selection([] as Array[Unit])


func select_building(b: Building) -> void:
	_set_selection([] as Array[Unit])
	selected_building = b
	b.selected = true


func idle_workers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in me.units:
		if u.type == "worker" and u.is_idle():
			out.append(u)
	return out


func select_idle() -> void:
	var idle := idle_workers()
	if idle.is_empty():
		return
	_set_selection(idle)
	look_at_world(idle[0].position)


func select_army() -> void:
	var army := me.military()
	if army.is_empty():
		return
	_set_selection(army)
	var c := Vector2.ZERO
	for u in army:
		c += u.position
	look_at_world(c / army.size())


func selected_workers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in selected:
		if u.type == "worker":
			out.append(u)
	return out


func auto_gather_selected(kind: String) -> void:
	for u in selected_workers():
		(u as Worker).cmd_auto_gather(kind)


func stop_selected() -> void:
	for u in selected:
		u.cmd_stop()


func _units_on_screen(type: String) -> Array[Unit]:
	var out: Array[Unit] = []
	var r := Rect2(_to_world(Vector2.ZERO), get_viewport_rect().size / cam.zoom.x)
	for u in me.units:
		if u.type == type and r.has_point(u.position):
			out.append(u)
	return out


# ---------------------------------------------------------------- bygging

func open_build_menu(open: bool) -> void:
	build_menu = open


func start_placing(type: String) -> void:
	if not me.can_afford(Defs.BUILDINGS[type].cost):
		hud.message("Ikke nok ressurser")
		return
	placing = type
	build_menu = false
	_ghost_world = Vector2.INF
	place_cell = _ghost_cell()


func cancel_placing() -> void:
	placing = ""


func confirm_placing() -> void:
	if placing == "":
		return
	var b := place_building(me, placing, place_cell, selected_workers())
	if b == null:
		hud.message("Kan ikke bygge her" if me.can_afford(Defs.BUILDINGS[placing].cost) else "Ikke nok ressurser")
		return
	_markers.append([b.center(), 0.0, Color(0.4, 1.0, 0.4)])
	placing = ""


## Byggeplassen følger midten av skjermen, eller stedet du sist trykket. Er det opptatt der,
## hopper den til nærmeste ledige plass (med én rute luft rundt), så den sjelden står rødt.
func _ghost_cell() -> Vector2i:
	var size: int = Defs.BUILDINGS[placing].size
	var w := _ghost_world if _ghost_world != Vector2.INF else cam.position
	var base := map.tile_of(w - Vector2(size, size) * GameMap.TILE * 0.5 + Vector2(GameMap.TILE, GameMap.TILE) * 0.5)
	if map.can_place(base, size):
		return base
	for r in range(1, 5):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) != r:
					continue
				var c := base + Vector2i(x, y)
				if map.can_place(c - Vector2i(1, 1), size + 2):
					var d := Vector2(x, y).length()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return base


# ---------------------------------------------------------------- kommandoer

## Et trykk på kartet: velger noe, eller gir ordre til de valgte enhetene.
func tap_world(world: Vector2) -> void:
	hud.dismiss_hint()
	if placing != "":
		_ghost_world = world
		return
	var u := unit_at(world)
	if u != null and u.player == me:
		if u == _last_tap_unit and _clock - _last_tap_time < DOUBLE_TAP:
			_set_selection(_units_on_screen(u.type))
		else:
			_set_selection([u] as Array[Unit])
		_last_tap_unit = u
		_last_tap_time = _clock
		return
	_last_tap_unit = null
	if not selected.is_empty():
		command_at(world)
		return
	var b := building_at(world)
	if b != null:
		select_building(b)
	elif u != null:
		_set_selection([] as Array[Unit])
		selected_enemy = u
	elif map.is_resource(map.tile_of(world)):
		clear_selection()
		selected_res = map.tile_of(world)
	else:
		clear_selection()


func command_at(world: Vector2) -> void:
	if selected.is_empty():
		return
	var c := map.tile_of(world)
	var enemy := unit_at(world)
	if enemy != null and enemy.player != me:
		for u in selected:
			u.cmd_attack_unit(enemy)
		_markers.append([enemy.position, 0.0, Color(1.0, 0.25, 0.2)])
		return
	var b := building_at(world)
	if b != null and b.player != me:
		for u in selected:
			u.cmd_attack_building(b)
		_markers.append([b.center(), 0.0, Color(1.0, 0.25, 0.2)])
		return
	var movers: Array[Unit] = []
	for u in selected:
		if u.type == "worker":
			var w := u as Worker
			if b != null and not b.complete:
				w.cmd_build(b)
			elif b != null and b.type == "town":
				w.cmd_return()
			elif map.is_resource(c):
				w.cmd_gather(c)
			else:
				movers.append(u)
		else:
			movers.append(u)
	if b != null:
		_markers.append([b.center(), 0.0, Color(1.0, 0.9, 0.3)])
	elif map.is_resource(c):
		_markers.append([map.center_of(c), 0.0, Worker.CARRY_COLOR[map.kind_at(c)]])
	if movers.is_empty():
		return
	# Spre enhetene litt, så de ikke står oppå hverandre
	var n := movers.size()
	var cols := ceili(sqrt(n))
	for i in n:
		var off := Vector2(i % cols - (cols - 1) * 0.5, i / cols - (cols - 1) * 0.5) * 16.0
		movers[i].cmd_move(world + off)
	_markers.append([world, 0.0, Color(0.4, 1.0, 0.4)])


# ---------------------------------------------------------------- inndata

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused:
		return
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
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		hud.toggle_pause()


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
			_pan(pos - prev)
		_:
			if pos.distance_to(p.start) > TAP_SLOP:
				_mode = "pan"
				_pan(pos - p.start)


func _pan(screen_delta: Vector2) -> void:
	cam.position -= screen_delta / cam.zoom.x
	_clamp_cam()
	# Når du plasserer en bygning, følger den midten av skjermen mens du drar
	if placing != "":
		_ghost_world = Vector2.INF


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
	var list: Array[Unit] = []
	for u in me.units:
		if r.grow(6).has_point(u.position):
			list.append(u)
	# Er det soldater i boksen, velges bare de (som i Age of Empires)
	var army: Array[Unit] = []
	for u in list:
		if u.is_military():
			army.append(u)
	_set_selection(army if not army.is_empty() else list)
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
	var margin := 96.0
	cam.position.x = clampf(cam.position.x, minf(half.x - margin, s.x * 0.5), maxf(s.x - half.x + margin, s.x * 0.5))
	cam.position.y = clampf(cam.position.y, minf(half.y - margin, s.y * 0.5), maxf(s.y - half.y + margin, s.y * 0.5))


func look_at_world(p: Vector2) -> void:
	cam.position = p
	_clamp_cam()
	if placing != "":
		_ghost_world = Vector2.INF


# ---------------------------------------------------------------- tegning oppå alt

func _draw_overlay() -> void:
	for m in _marks:
		var a: float = 1.0 - m[1] / 8.0
		var s: float = m[2]
		overlay.draw_circle(m[0], s, Color(0.25, 0.18, 0.12, 0.45 * a))
		if s < 10.0:
			overlay.draw_line(m[0] + Vector2(-4, -4), m[0] + Vector2(4, 4), Color(0.6, 0.1, 0.1, a), 2.0)
			overlay.draw_line(m[0] + Vector2(4, -4), m[0] + Vector2(-4, 4), Color(0.6, 0.1, 0.1, a), 2.0)
	for ar in _arrows:
		var t: float = ar[2] / 0.25
		var p: Vector2 = ar[0].lerp(ar[1], t)
		var dir: Vector2 = (ar[1] - ar[0]).normalized()
		overlay.draw_line(p - dir * 7.0, p, Color(0.3, 0.2, 0.1), 1.5)
	for m in _markers:
		var t: float = m[1] / 0.6
		var col: Color = m[2]
		col.a = 1.0 - t
		overlay.draw_arc(m[0], 6.0 + 14.0 * t, 0.0, TAU, 24, col, 3.0)
	if map.is_resource(selected_res):
		overlay.draw_arc(map.center_of(selected_res), 18.0, 0.0, TAU, 28, Color(1, 1, 1, 0.8), 2.0)
	elif selected_res.x >= 0:
		selected_res = Vector2i(-1, -1)
	if selected_enemy != null:
		overlay.draw_arc(selected_enemy.position + Vector2(0, 7), 12.0, 0.0, TAU, 24, Color(1, 0.3, 0.3), 2.0)
	if placing != "":
		var size: int = Defs.BUILDINGS[placing].size
		var ok := map.can_place(place_cell, size)
		var r := Rect2(Vector2(place_cell * GameMap.TILE), Vector2(size, size) * GameMap.TILE)
		var col := Color(0.3, 1.0, 0.3) if ok else Color(1.0, 0.25, 0.2)
		overlay.draw_rect(r, Color(col, 0.3))
		overlay.draw_rect(r, col, false, 3.0)
		for y in size:
			for x in size:
				var c := place_cell + Vector2i(x, y)
				if not map.is_walkable(c):
					overlay.draw_rect(Rect2(Vector2(c * GameMap.TILE), Vector2(GameMap.TILE, GameMap.TILE)), Color(1, 0, 0, 0.35))
	if _mode == "box":
		var r := Rect2(_to_world(_box_a), Vector2.ZERO).expand(_to_world(_box_b))
		overlay.draw_rect(r, Color(0.4, 1.0, 0.4, 0.15))
		overlay.draw_rect(r, Color(0.4, 1.0, 0.4, 0.9), false, 2.0 / cam.zoom.x)
