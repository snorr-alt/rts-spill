class_name Building
extends Node2D
## Bygning. Starter som byggeplass (complete = false) som arbeiderne bygger ferdig.
## Bygninger kan trene enheter og forske (tidsalder), være leveringsplass for ressurser,
## gi mat (gården) eller skyte (tårnet). De kan angripes og ødelegges.

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
var queue: Array[String] = []  # enheter og forskning som venter
var train_t := 0.0  # sekunder brukt på det første i køen
var selected := false
var dead := false
## Samlingspunkt for nye enheter (Vector2.INF = ingen)
var rally := Vector2.INF
## Gården: mat igjen og arbeideren som jobber der
var food := 0
var farmer: Node2D = null

var _flash := 0.0
var _redraw_t := 0.0
var _cool := 0.0
var _scan_t := 0.0


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
	food = def.get("food", 0)
	if not is_walkable():
		for y in size:
			for x in size:
				map.set_solid(c + Vector2i(x, y), true)


func is_walkable() -> bool:
	return def.get("walkable", false)


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


func accepts(kind: String) -> bool:
	return complete and not dead and kind in def.get("drop", [])


func trains_anything() -> bool:
	for id: String in def.trains:
		if not Defs.is_tech(id):
			return true
	return false


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


## Gården gir én mat. Er den tom, forsvinner den (som i Age of Empires).
func take_food() -> int:
	if food <= 0 or dead:
		return 0
	food -= 1
	if food <= 0:
		die()
	return 1


## Hvorfor en enhet eller forskning ikke kan settes i kø ("" hvis den kan)
func train_block_reason(id: String) -> String:
	if not complete or dead or not id in def.trains:
		return "Ikke her"
	var d := Defs.item(id)
	if player.age < d.age:
		return Defs.AGES[d.age]
	if Defs.is_tech(id):
		var why := player.feudal_block_reason()
		if why != "":
			return why
		if not queue.is_empty():
			return "Køen må være tom"
	elif queue.size() >= 5:
		return "Køen er full"
	elif player.pop_with_queue() >= player.pop_cap():
		return "Bygg hus"
	if not queue.is_empty() and Defs.is_tech(queue[0]):
		return "Forsker"
	if not player.can_afford(d.cost):
		return "For dyrt"
	return ""


func can_train(id: String) -> bool:
	return train_block_reason(id) == ""


func train(id: String) -> bool:
	if not can_train(id):
		return false
	player.pay(Defs.item(id).cost)
	queue.append(id)
	return true


func cancel_last() -> void:
	if queue.is_empty():
		return
	var u: String = queue.pop_back()
	player.refund(Defs.item(u).cost)
	if queue.is_empty():
		train_t = 0.0


func train_progress() -> float:
	if queue.is_empty():
		return 0.0
	return train_t / Defs.item(queue[0]).time


func take_damage(amount: float, from: Node2D) -> void:
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
	if not is_walkable():
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
		var id: String = queue[0]
		# Enheter venter hvis det ikke er plass i folketallet
		if Defs.is_tech(id) or player.pop() < player.pop_cap():
			train_t += delta
			if train_t >= Defs.item(id).time:
				train_t = 0.0
				queue.pop_front()
				if Defs.is_tech(id):
					main.on_tech_done(player, id)
				else:
					main.spawn_unit(player, id, self)
	if type == "tower" and complete:
		_tower(delta)
	# Tegn på nytt bare når noe kan ha endret seg, og bare når bygningen er på skjermen
	_redraw_t -= delta
	if (_redraw_t <= 0.0 or _flash > 0.0) and main.view_rect.intersects(world_rect()):
		_redraw_t = 0.1
		queue_redraw()


## Tårnet skyter på nærmeste fiende innenfor rekkevidde
func _tower(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	_scan_t -= delta
	if _cool > 0.0 or _scan_t > 0.0:
		return
	_scan_t = 0.25
	var e: Unit = main.nearest_enemy_unit(center(), def.range * GameMap.TILE, player.team)
	if e == null:
		return
	_cool = def.cooldown
	main.add_arrow(center() + Vector2(0, -26), e.position + Vector2(0, -4))
	e.take_damage(Defs.damage(def, e.def), self)


# ------------------------------------------------------------------ tegning

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
			"lumber":
				_draw_camp(s, team_col, Color(0.55, 0.36, 0.18))
			"mining":
				_draw_camp(s, team_col, Color(0.95, 0.80, 0.25))
			"mill":
				_draw_mill(s, team_col)
			"farm":
				_draw_farm(s, team_col)
			"range":
				_draw_range(s, team_col)
			"stable":
				_draw_stable(s, team_col)
			"tower":
				_draw_tower(s, team_col)
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
	if selected and rally != Vector2.INF:
		var rp := rally - position
		draw_line(Vector2(s, s) * 0.5, rp, Color(1, 1, 1, 0.35), 1.5)
		_flag(rp + Vector2(0, 8), team_col)


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


func _roof(s: float, top: float, eave: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(2, eave), Vector2(s * 0.5, top), Vector2(s - 2, eave)]), col)


func _draw_town(s: float, col: Color) -> void:
	var r := Rect2(4, 10, s - 8, s - 14)
	_shadow(r)
	draw_rect(r, Color(0.72, 0.60, 0.42))
	draw_rect(r, Color(0.45, 0.35, 0.22), false, 2.0)
	var roof := Color(0.55, 0.23, 0.16) if player.age == 0 else Color(0.35, 0.38, 0.45)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 30), Vector2(s * 0.5, 0), Vector2(s, 30)]), roof)
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
	_roof(s, 4, 22, Color(0.50, 0.30, 0.18))
	draw_rect(Rect2(2, 20, s - 4, 4), col.darkened(0.15))
	draw_rect(Rect2(s * 0.5 - 6, s - 20, 12, 16), Color(0.30, 0.19, 0.10))


## Sagbruk og gruveleir: åpent skur med en haug av ressursen foran
func _draw_camp(s: float, col: Color, pile: Color) -> void:
	var r := Rect2(4, 14, s - 8, s - 30)
	_shadow(r)
	draw_rect(r, Color(0.40, 0.28, 0.16))
	_roof(s, 2, 18, Color(0.58, 0.42, 0.26))
	draw_rect(Rect2(2, 16, s - 4, 3), col)
	for k in 3:
		draw_circle(Vector2(14 + k * 12, s - 10), 6.0, pile)
		draw_arc(Vector2(14 + k * 12, s - 10), 6.0, 0.0, TAU, 12, pile.darkened(0.4), 1.0)
	draw_circle(Vector2(20, s - 18), 6.0, pile.lightened(0.1))


func _draw_mill(s: float, col: Color) -> void:
	var r := Rect2(12, 20, s - 24, s - 24)
	_shadow(r)
	draw_rect(r, Color(0.80, 0.72, 0.56))
	_roof(s, 6, 22, Color(0.55, 0.23, 0.16))
	draw_rect(Rect2(10, 20, s - 20, 3), col)
	# Vingene snurrer sakte
	var hub := Vector2(s * 0.5, 24)
	var a: float = main.game_time * 0.8
	for k in 4:
		var d := Vector2.from_angle(a + k * PI * 0.5)
		draw_line(hub, hub + d * 24.0, Color(0.35, 0.25, 0.15), 2.5)
		draw_line(hub + d * 8.0 + d.orthogonal() * 4.0, hub + d * 24.0 + d.orthogonal() * 4.0, Color(0.92, 0.90, 0.85), 4.0)
	draw_circle(hub, 3.0, Color(0.3, 0.2, 0.1))


func _draw_farm(s: float, col: Color) -> void:
	draw_rect(Rect2(1, 1, s - 2, s - 2), Color(0.45, 0.32, 0.18))
	var f := float(food) / float(def.food)
	var crop := Color(0.85, 0.75, 0.30).lerp(Color(0.40, 0.62, 0.22), f)
	for k in 6:
		var y := 6.0 + k * (s - 10) / 6.0
		draw_line(Vector2(5, y), Vector2(s - 5, y), Color(0.35, 0.24, 0.12), 2.0)
		draw_line(Vector2(6, y + 3), Vector2(6 + (s - 12) * f, y + 3), crop, 3.0)
	draw_rect(Rect2(1, 1, s - 2, s - 2), col.darkened(0.3), false, 1.5)


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


func _draw_range(s: float, col: Color) -> void:
	var r := Rect2(2, 14, s - 4, s - 18)
	_shadow(r)
	draw_rect(r, Color(0.62, 0.50, 0.32))
	draw_rect(r, Color(0.38, 0.28, 0.16), false, 2.0)
	_roof(s, 0, 18, Color(0.36, 0.45, 0.26))
	draw_rect(Rect2(2, 16, s - 4, 4), col)
	# Blink
	var c := Vector2(s * 0.5, s * 0.62)
	for k in 3:
		draw_circle(c, 14.0 - k * 4.5, Color(0.9, 0.9, 0.85) if k % 2 == 0 else Color(0.8, 0.15, 0.15))
	draw_line(c + Vector2(-14, -12), c, Color(0.35, 0.22, 0.1), 2.0)
	_flag(Vector2(s - 10, 4), col)


func _draw_stable(s: float, col: Color) -> void:
	var r := Rect2(2, 16, s - 4, s - 20)
	_shadow(r)
	draw_rect(r, Color(0.55, 0.36, 0.22))
	draw_rect(r, Color(0.32, 0.20, 0.10), false, 2.0)
	_roof(s, 2, 20, Color(0.42, 0.26, 0.14))
	draw_rect(Rect2(2, 18, s - 4, 4), col)
	# Stalldører med kryss
	for k in 2:
		var d := Rect2(12 + k * (s * 0.5 - 6), s - 36, s * 0.5 - 18, 30)
		draw_rect(d, Color(0.40, 0.25, 0.12))
		draw_line(d.position, d.end, Color(0.28, 0.16, 0.08), 2.0)
		draw_line(Vector2(d.end.x, d.position.y), Vector2(d.position.x, d.end.y), Color(0.28, 0.16, 0.08), 2.0)
	# Hestesko
	draw_arc(Vector2(s * 0.5, 34), 7.0, 0.3, PI - 0.3, 10, Color(0.75, 0.75, 0.8), 3.0)
	_flag(Vector2(10, 4), col)


func _draw_tower(s: float, col: Color) -> void:
	# Høyt tårn som rager opp over ruta
	var r := Rect2(5, -28, s - 10, s + 26)
	_shadow(Rect2(5, s - 8, s - 10, 8))
	draw_rect(r, Color(0.60, 0.58, 0.55))
	draw_rect(r, Color(0.35, 0.34, 0.32), false, 2.0)
	for k in 3:
		draw_rect(Rect2(3 + k * 9, -34, 6, 7), Color(0.60, 0.58, 0.55))
	draw_rect(Rect2(s * 0.5 - 3, -16, 6, 10), Color(0.15, 0.12, 0.10))
	draw_rect(Rect2(5, -4, s - 10, 4), col)
