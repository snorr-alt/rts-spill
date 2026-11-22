class_name Building
extends Node2D
## Bygning: rådhus, hus eller brakker. Starter som byggeplass (complete = false) som
## arbeiderne bygger ferdig. Bygninger kan trene enheter og kan angripes og ødelegges.

var main: Node
var map: GameMap
var player: Player
var type := "house"
var def: Dictionary
var cell := Vector2i.ZERO
var size := 2
var hp := 1.0
var max_hp := 1.0
var complete := false
var progress := 0.0  # 0–1 for byggingen
var queue: Array[String] = []  # enheter som venter på trening
var train_t := 0.0  # sekunder brukt på enheten først i køen
var selected := false
var dead := false
var _flash := 0.0
var _redraw_t := 0.0


func setup(m: Node, p: Player, t: String, c: Vector2i, built: bool) -> void:
	main = m
	map = m.map
	player = p
	type = t
	def = Defs.BUILDINGS[t]
	size = def.size
	cell = c
	max_hp = def.hp
	position = Vector2(c * GameMap.TILE)
	complete = built
	progress = 1.0 if built else 0.0
	hp = max_hp if built else maxf(1.0, max_hp * 0.05)
	for y in size:
		for x in size:
			map.set_solid(c + Vector2i(x, y), true)


func rect() -> Rect2i:
	return Rect2i(cell, Vector2i(size, size))


func world_rect() -> Rect2:
	return Rect2(position, Vector2(size, size) * GameMap.TILE)


func has_cell(c: Vector2i) -> bool:
	return rect().has_point(c)


func contains(world: Vector2) -> bool:
	return world_rect().has_point(world)


func center() -> Vector2:
	return position + Vector2(size, size) * GameMap.TILE * 0.5


## Avstand fra et punkt til nærmeste kant av bygningen (0 hvis punktet er inni)
func distance_to(p: Vector2) -> float:
	var r := world_rect()
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)


func display_name() -> String:
	return def.name


## En arbeider bygger i `delta` sekunder. Gir true når bygningen blir ferdig.
func build(delta: float) -> bool:
	if complete:
		return false
	var step: float = delta / def.time
	progress = minf(1.0, progress + step)
	hp = minf(max_hp, hp + max_hp * step * 0.95)
	if progress >= 1.0:
		complete = true
		player.stats.built += 1
		main.on_building_complete(self)
		return true
	return false


func can_train(unit: String) -> bool:
	return complete and not dead and unit in def.trains and queue.size() < 5 \
		and player.can_afford(Defs.UNITS[unit].cost) and player.pop_with_queue() < player.pop_cap()


func train(unit: String) -> bool:
	if not can_train(unit):
		return false
	player.pay(Defs.UNITS[unit].cost)
	queue.append(unit)
	return true


func cancel_last() -> void:
	if queue.is_empty():
		return
	var u: String = queue.pop_back()
	player.refund(Defs.UNITS[u].cost)
	if queue.is_empty():
		train_t = 0.0


func train_progress() -> float:
	if queue.is_empty():
		return 0.0
	return train_t / Defs.UNITS[queue[0]].time


func take_damage(amount: float, from: Unit) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.15
	main.on_damaged(self, from)
	if hp <= 0.0:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	for y in size:
		for x in size:
			map.set_solid(cell + Vector2i(x, y), false)
	# Penger for enheter i kø tapes (som når en bygning faller i Age of Empires)
	queue.clear()
	main.on_building_died(self)
	queue_free()


func _process(delta: float) -> void:
	if dead:
		return
	_flash = maxf(0.0, _flash - delta)
	if complete and not queue.is_empty():
		# Venter hvis det ikke er plass i folketallet
		if player.pop() < player.pop_cap():
			train_t += delta
			var u: String = queue[0]
			if train_t >= Defs.UNITS[u].time:
				train_t = 0.0
				queue.pop_front()
				main.spawn_unit(player, u, self)
	# Tegn på nytt bare når noe kan ha endret seg, og bare når bygningen er på skjermen
	_redraw_t -= delta
	if (_redraw_t <= 0.0 or _flash > 0.0) and main.view_rect.intersects(world_rect()):
		_redraw_t = 0.1
		queue_redraw()


func _draw() -> void:
	var s := float(size * GameMap.TILE)
	var team_col := player.color
	if not complete:
		_draw_site(s)
	else:
		match type:
			"town":
				_draw_town(s, team_col)
			"house":
				_draw_house(s, team_col)
			"barracks":
				_draw_barracks(s, team_col)
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, s, s), Color(1, 0.3, 0.2, _flash * 2.0))
	if selected:
		draw_rect(Rect2(-3, -3, s + 6, s + 6), Color(0.4, 1.0, 0.4), false, 2.0)
	# Liv og fremdrift
	var y := s + 4.0
	if selected or hp < max_hp:
		draw_rect(Rect2(0, y, s, 6), Color(0, 0, 0, 0.6))
		var f := hp / max_hp
		draw_rect(Rect2(1, y + 1, (s - 2) * f, 4), Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.2, 0.15), 1.0 - f))
		y += 8.0
	if not complete or not queue.is_empty():
		var p := progress if not complete else train_progress()
		draw_rect(Rect2(0, y, s, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(1, y + 1, (s - 2) * p, 4), Color(0.4, 0.8, 1.0))


func _draw_site(s: float) -> void:
	draw_rect(Rect2(2, 2, s - 4, s - 4), Color(0.55, 0.45, 0.30, 0.6))
	var h := (s - 8) * progress
	draw_rect(Rect2(4, s - 4 - h, s - 8, h), Color(0.72, 0.60, 0.42))
	# Stillas
	var col := Color(0.42, 0.28, 0.14)
	for k in 4:
		var x := 4.0 + (s - 8.0) * k / 3.0
		draw_line(Vector2(x, 4), Vector2(x, s - 4), col, 2.0)
	draw_line(Vector2(4, s * 0.5), Vector2(s - 4, s * 0.5), col, 2.0)
	draw_line(Vector2(4, 4), Vector2(s - 4, s - 4), col, 1.0)
	draw_rect(Rect2(2, 2, s - 4, s - 4), player.color, false, 2.0)


func _shadow(r: Rect2) -> void:
	draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.25))


func _flag(at: Vector2, col: Color) -> void:
	draw_line(at, at + Vector2(0, -22), Color(0.9, 0.9, 0.9), 2.0)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -22), at + Vector2(16, -18), at + Vector2(0, -13)]), col)


func _draw_town(s: float, col: Color) -> void:
	var r := Rect2(4, 10, s - 8, s - 14)
	_shadow(r)
	draw_rect(r, Color(0.72, 0.60, 0.42))
	draw_rect(r, Color(0.45, 0.35, 0.22), false, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 30), Vector2(s * 0.5, 0), Vector2(s, 30)]), Color(0.55, 0.23, 0.16))
	draw_rect(Rect2(0, 28, s, 6), col.darkened(0.2))
	draw_rect(Rect2(s * 0.5 - 8, s - 30, 16, 26), Color(0.30, 0.19, 0.10))
	draw_rect(Rect2(14, 46, 12, 12), Color(0.25, 0.30, 0.38))
	draw_rect(Rect2(s - 26, 46, 12, 12), Color(0.25, 0.30, 0.38))
	_flag(Vector2(s * 0.5, 0), col)


func _draw_house(s: float, col: Color) -> void:
	var r := Rect2(6, 18, s - 12, s - 22)
	_shadow(r)
	draw_rect(r, Color(0.78, 0.66, 0.48))
	draw_rect(r, Color(0.45, 0.35, 0.22), false, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(2, 22), Vector2(s * 0.5, 4), Vector2(s - 2, 22)]), Color(0.50, 0.30, 0.18))
	draw_rect(Rect2(2, 20, s - 4, 4), col.darkened(0.15))
	draw_rect(Rect2(s * 0.5 - 6, s - 20, 12, 16), Color(0.30, 0.19, 0.10))


func _draw_barracks(s: float, col: Color) -> void:
	var r := Rect2(2, 12, s - 4, s - 16)
	_shadow(r)
	draw_rect(r, Color(0.48, 0.40, 0.34))
	draw_rect(r, Color(0.28, 0.22, 0.18), false, 2.0)
	# Tinder på muren
	for k in 6:
		draw_rect(Rect2(2 + k * (s - 4) / 6.0, 6, (s - 4) / 12.0, 8), Color(0.48, 0.40, 0.34))
	draw_rect(Rect2(s * 0.5 - 12, s - 34, 24, 30), Color(0.22, 0.15, 0.10))
	draw_rect(Rect2(2, 26, s - 4, 5), col)
	# Kryssede sverd som skilt
	var c := Vector2(s * 0.5, 46)
	draw_line(c + Vector2(-9, -9), c + Vector2(9, 9), Color(0.85, 0.85, 0.9), 3.0)
	draw_line(c + Vector2(9, -9), c + Vector2(-9, 9), Color(0.85, 0.85, 0.9), 3.0)
	_flag(Vector2(10, 6), col)
