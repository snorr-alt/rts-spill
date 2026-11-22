class_name Unit
extends Node2D
## Felles grunnlag for alle enheter: liv, bevegelse langs sti, angrep og død.
## Arbeideren (worker.gd) legger til samling og bygging. Soldater bruker denne klassen direkte.

enum S { IDLE, MOVE, ATTACK, TO_RES, GATHER, TO_TOWN, TO_BUILD, BUILD }

const MELEE_REACH := 18.0
const BUILDING_REACH := 26.0
const PICK_RADIUS := 20.0

var main: Node
var map: GameMap
var player: Player
var type := "sword"
var def: Dictionary
var hp := 1.0
var max_hp := 1.0
var state := S.IDLE
var selected := false
var dead := false

var target_unit: Unit = null
var target_building: Building = null
## Angrepsmarsj: gå mot et mål, men slåss med fiender underveis (brukes av AI-en)
var attack_move := false
var attack_dest := Vector2.ZERO

var _path := PackedVector2Array()
var _path_i := 0
var _cool := 0.0
var _repath_t := 0.0
var _scan_t := 0.0
var _anim := 0.0
var _flash := 0.0
var _guard_pos := Vector2.ZERO
var _guarding := false  # jakter på en fiende den fikk øye på selv (ikke en ordre)
var facing := Vector2.RIGHT


func setup(m: Node, p: Player, t: String) -> void:
	main = m
	map = m.map
	player = p
	type = t
	def = Defs.UNITS[t]
	max_hp = def.hp
	hp = max_hp
	_scan_t = randf() * 0.5
	_anim = randf() * 10.0


func is_military() -> bool:
	return type != "worker"


func cell() -> Vector2i:
	return map.tile_of(position)


func is_idle() -> bool:
	return state == S.IDLE


func display_name() -> String:
	return def.name


func _start_cell() -> Vector2i:
	var c := cell()
	return c if map.is_walkable(c) else map.nearest_walkable(c)


func _set_path_to_cell(goal: Vector2i) -> bool:
	_path = map.path_between(_start_cell(), goal)
	_path_i = 1 if _path.size() > 1 else 0
	return not _path.is_empty()


func _set_path_to_rect(r: Rect2i) -> bool:
	_path = map.path_to_rect(_start_cell(), r)
	_path_i = 1 if _path.size() > 1 else 0
	return not _path.is_empty()


# ------------------------------------------------------------------ ordre

func cmd_move(to: Vector2, attack := false) -> void:
	_clear_targets()
	attack_move = attack
	attack_dest = to
	_guarding = false
	var goal := map.nearest_walkable(map.tile_of(to))
	if _set_path_to_cell(goal):
		if map.tile_of(to) == goal:
			_path[_path.size() - 1] = to
		state = S.MOVE
	else:
		state = S.IDLE


func cmd_attack_unit(u: Unit) -> void:
	_clear_targets()
	attack_move = false
	_guarding = false
	target_unit = u
	state = S.ATTACK
	_repath_t = 0.0


func cmd_attack_building(b: Building) -> void:
	_clear_targets()
	attack_move = false
	_guarding = false
	target_building = b
	state = S.ATTACK
	_repath_t = 0.0


func cmd_stop() -> void:
	_clear_targets()
	attack_move = false
	_guarding = false
	_path = PackedVector2Array()
	state = S.IDLE


func _clear_targets() -> void:
	target_unit = null
	target_building = null


## Kalles når en ny bygning dukker opp: går stien gjennom den, finnes en ny vei til samme sted
func repath_if_blocked(r: Rect2) -> void:
	if _path_i >= _path.size():
		return
	for i in range(_path_i, _path.size()):
		if r.has_point(_path[i]):
			var last := _path[_path.size() - 1]
			if _set_path_to_cell(map.nearest_walkable(map.tile_of(last))):
				if map.is_walkable(map.tile_of(last)):
					_path[_path.size() - 1] = last
			return


# ------------------------------------------------------------------ hver fysikkramme

func _physics_process(delta: float) -> void:
	if dead:
		return
	_anim += delta
	_cool = maxf(0.0, _cool - delta)
	_flash = maxf(0.0, _flash - delta)
	_scan_t -= delta
	match state:
		S.IDLE:
			if is_military() and _scan_t <= 0.0:
				_scan_t = 0.5
				_look_for_enemy(false)
		S.MOVE:
			if attack_move and _scan_t <= 0.0:
				_scan_t = 0.4
				if _look_for_enemy(true):
					return
			if _follow(delta):
				state = S.IDLE
				attack_move = false
		S.ATTACK:
			_attack(delta)
		_:
			_worker_state(delta)
	# Tegn bare på nytt når enheten er på skjermen (sparer mye på telefonen)
	if main.view_rect.has_point(position):
		queue_redraw()


## Overstyres av arbeideren
func _worker_state(_delta: float) -> void:
	pass


func _follow(delta: float) -> bool:
	if _path_i >= _path.size():
		return true
	var p := _path[_path_i]
	var to := p - position
	var step: float = def.speed * delta
	if to.length() > 0.01:
		facing = to.normalized()
	if to.length() <= step:
		position = p
		_path_i += 1
		return _path_i >= _path.size()
	position += to.normalized() * step
	return false


# ------------------------------------------------------------------ kamp

func _look_for_enemy(include_buildings: bool) -> bool:
	var sight: float = def.sight * GameMap.TILE
	var e: Unit = main.nearest_enemy_unit(position, sight, player.team)
	if e != null:
		var was_idle := state == S.IDLE
		var keep_move := attack_move
		var keep_dest := attack_dest
		cmd_attack_unit(e)
		attack_move = keep_move
		attack_dest = keep_dest
		if was_idle and not keep_move:
			_guarding = true
			_guard_pos = position
		return true
	if include_buildings:
		var b: Building = main.nearest_enemy_building(position, sight, player.team)
		if b != null:
			var keep_dest := attack_dest
			cmd_attack_building(b)
			attack_move = true
			attack_dest = keep_dest
			return true
	return false


func _in_range() -> bool:
	var reach: float = def.range * GameMap.TILE
	if target_unit != null:
		return position.distance_to(target_unit.position) <= maxf(reach, MELEE_REACH)
	return target_building.distance_to(position) <= maxf(reach, BUILDING_REACH)


func _target_valid() -> bool:
	if target_unit != null:
		return is_instance_valid(target_unit) and not target_unit.dead
	if target_building != null:
		return is_instance_valid(target_building) and not target_building.dead
	return false


func _attack(delta: float) -> void:
	if not _target_valid():
		_clear_targets()
		_after_fight()
		return
	# Gir opp jakten hvis fienden lokker den for langt hjemmefra
	if _guarding and position.distance_to(_guard_pos) > def.sight * GameMap.TILE * 2.0:
		var home := _guard_pos
		cmd_move(home)
		return
	var tpos: Vector2 = target_unit.position if target_unit != null else target_building.center()
	if _in_range():
		_path = PackedVector2Array()
		facing = (tpos - position).normalized() if tpos != position else facing
		if _cool <= 0.0:
			_cool = def.cooldown
			_hit()
		return
	# Gå nærmere. Finn ny sti av og til, siden målet kan flytte seg.
	_repath_t -= delta
	if _repath_t <= 0.0 or _path_i >= _path.size():
		_repath_t = 0.6
		var ok := false
		if target_unit != null:
			ok = _set_path_to_cell(map.nearest_walkable(target_unit.cell()))
			if ok:
				_path[_path.size() - 1] = target_unit.position
		else:
			ok = _set_path_to_rect(target_building.rect())
		if not ok:
			_clear_targets()
			_after_fight()
			return
	_follow(delta)


func _hit() -> void:
	if target_unit != null:
		var dmg := maxf(1.0, def.atk - target_unit.def.armor)
		if def.range > 0.0:
			main.add_arrow(position + Vector2(0, -6), target_unit.position + Vector2(0, -4))
		target_unit.take_damage(dmg, self)
	else:
		var dmg: float = maxf(1.0, def.atk * def.vs_building)
		if def.range > 0.0:
			main.add_arrow(position + Vector2(0, -6), target_building.center())
		target_building.take_damage(dmg, self)


## Hva enheten gjør når målet er borte
func _after_fight() -> void:
	if attack_move:
		cmd_move(attack_dest, true)
	elif _guarding:
		var home := _guard_pos
		if is_military() and _look_for_enemy(false):
			_guarding = true
			_guard_pos = home
			return
		_guarding = false
		cmd_move(home)
	else:
		state = S.IDLE
		if is_military():
			_scan_t = 0.0


func take_damage(amount: float, from: Unit) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.15
	main.on_damaged(self, from)
	if hp <= 0.0:
		if from != null and is_instance_valid(from):
			from.player.stats.kills += 1
		die()
		return
	# Soldater som står i ro, slår tilbake
	if from != null and is_instance_valid(from) and is_military() and state == S.IDLE:
		_guard_pos = position
		cmd_attack_unit(from)
		_guarding = true


func die() -> void:
	if dead:
		return
	dead = true
	main.on_unit_died(self)
	queue_free()


# ------------------------------------------------------------------ tegning

func _draw() -> void:
	draw_set_transform(Vector2(0, 7), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
	if selected:
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 28, Color(0.4, 1.0, 0.4), 3.0)
	draw_set_transform(Vector2.ZERO)
	var moving := state in [S.MOVE, S.TO_RES, S.TO_TOWN, S.TO_BUILD] or (state == S.ATTACK and not _path.is_empty())
	var o := Vector2(0, -absf(sin(_anim * 14.0)) * 2.0 if moving else 0.0)
	_draw_body(o)
	if _flash > 0.0:
		draw_circle(o, 7.0, Color(1, 0.2, 0.1, 0.6))
	if selected or hp < max_hp:
		var w := 18.0
		draw_rect(Rect2(-w * 0.5, -19, w, 4), Color(0, 0, 0, 0.6))
		var f := hp / max_hp
		draw_rect(Rect2(-w * 0.5 + 1, -18, (w - 2) * f, 2), Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.2, 0.15), 1.0 - f))


func _draw_body(o: Vector2) -> void:
	var col := player.color
	var dir := facing
	match type:
		"sword":
			draw_circle(o, 7.0, col)
			draw_circle(o + Vector2(0, -8), 4.5, Color(0.93, 0.78, 0.62))
			draw_arc(o + Vector2(0, -9), 4.5, PI, TAU, 10, Color(0.6, 0.6, 0.65), 3.0)  # hjelm
			var swing := 0.0
			if state == S.ATTACK and _cool > def.cooldown - 0.25:
				swing = -1.2
			var hand := o + dir.orthogonal() * 6.0
			draw_line(hand, hand + dir.rotated(swing) * 12.0, Color(0.85, 0.85, 0.9), 2.5)
			draw_circle(o - dir.orthogonal() * 6.0, 4.0, col.darkened(0.35))  # skjold
		"archer":
			draw_circle(o, 6.0, col)
			draw_circle(o + Vector2(0, -7), 4.0, Color(0.93, 0.78, 0.62))
			draw_arc(o + Vector2(0, -8), 4.5, PI, TAU, 10, Color(0.25, 0.45, 0.2), 2.5)  # hette
			var bc := o + dir * 7.0
			draw_arc(bc, 7.0, dir.angle() - 1.2, dir.angle() + 1.2, 10, Color(0.5, 0.32, 0.15), 2.0)
		_:
			draw_circle(o, 6.0, col)
			draw_circle(o + Vector2(0, -7), 4.0, Color(0.93, 0.78, 0.62))
