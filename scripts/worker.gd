class_name Worker
extends Node2D
## Landsbyarbeider. Kan gå, samle tre, mat (bær), gull og stein og bære det til rådhuset.
## Arbeideren bærer bare én ressurstype om gangen. Når en ressurs er tom, finner den selv
## den nærmeste av samme type.

enum S { IDLE, MOVE, TO_RES, GATHER, TO_TOWN }

const SPEED := 80.0
const CAPACITY := 10
const PICK_RADIUS := 20.0
## Sekunder per enhet for hver ressurstype
const RATE := {"wood": 0.6, "food": 0.55, "gold": 0.75, "stone": 0.8}
const CARRY_COLOR := {
	"wood": Color(0.55, 0.36, 0.18), "food": Color(0.85, 0.15, 0.25),
	"gold": Color(1.0, 0.82, 0.2), "stone": Color(0.8, 0.8, 0.78),
}

var main: Node
var map: GameMap
var town: TownCenter
var state := S.IDLE
var target := Vector2i(-1, -1)  # ressursruta arbeideren jobber på
var kind := "wood"  # hva arbeideren samler (eller sist samlet)
var carry := 0
var carry_kind := ""
var selected := false

var _path := PackedVector2Array()
var _path_i := 0
var _gather_t := 0.0
var _anim := 0.0


func cell() -> Vector2i:
	return map.tile_of(position)


func is_idle() -> bool:
	return state == S.IDLE


func cmd_move(to: Vector2) -> void:
	target = Vector2i(-1, -1)
	var goal := map.nearest_walkable(map.tile_of(to))
	if _set_path(goal):
		if map.tile_of(to) == goal:
			_path[_path.size() - 1] = to
		state = S.MOVE
	else:
		state = S.IDLE


func cmd_gather(res_cell: Vector2i) -> void:
	if not map.is_resource(res_cell):
		return
	target = res_cell
	kind = map.kind_at(res_cell)
	_go_to_target()


## Samle nærmeste ressurs av en type («Tre/Mat/Gull/Stein»-knappene og nye arbeidere)
func cmd_auto_gather(what := "") -> void:
	if what != "":
		kind = what
	target = Vector2i(-1, -1)
	_find_resource()


func cmd_return() -> void:
	if carry > 0:
		_go_town()
	else:
		cmd_move(town.center() + Vector2(0, GameMap.TILE * 2.2))


func _set_path(goal: Vector2i) -> bool:
	_path = map.path_between(_start_cell(), goal)
	_path_i = 1 if _path.size() > 1 else 0
	return not _path.is_empty()


func _start_cell() -> Vector2i:
	var c := cell()
	return c if map.is_walkable(c) else map.nearest_walkable(c)


func _target_ok() -> bool:
	return map.kind_at(target) == kind


func _go_to_target() -> void:
	var t := target
	var r := map.nearest_adjacent(_start_cell(), func(c: Vector2i) -> bool: return c == t)
	if r.is_empty() or not _set_path(r.goal):
		_find_resource()
		return
	state = S.TO_RES


func _find_resource() -> void:
	var k := kind
	var r := map.nearest_adjacent(_start_cell(), func(c: Vector2i) -> bool: return map.kind_at(c) == k)
	if r.is_empty() or not _set_path(r.goal):
		if carry > 0:
			_go_town()
		else:
			state = S.IDLE
		return
	target = r.target
	state = S.TO_RES


func _go_town() -> void:
	var r := map.nearest_adjacent(_start_cell(), town.has_cell)
	if r.is_empty() or not _set_path(r.goal):
		state = S.IDLE
		return
	state = S.TO_TOWN


func _adjacent_to(c: Vector2i) -> bool:
	var d := cell() - c
	return maxi(absi(d.x), absi(d.y)) <= 1


func _physics_process(delta: float) -> void:
	_anim += delta
	match state:
		S.MOVE, S.TO_RES, S.TO_TOWN:
			if _follow(delta):
				_arrived()
		S.GATHER:
			_gather(delta)
	queue_redraw()


func _follow(delta: float) -> bool:
	if _path_i >= _path.size():
		return true
	var p := _path[_path_i]
	var to := p - position
	var step := SPEED * delta
	if to.length() <= step:
		position = p
		_path_i += 1
		return _path_i >= _path.size()
	position += to.normalized() * step
	return false


func _arrived() -> void:
	match state:
		S.MOVE:
			state = S.IDLE
		S.TO_RES:
			if _target_ok() and _adjacent_to(target):
				# Bytter arbeideren ressurstype, mister den det den bar (som i Age of Empires)
				if carry_kind != kind:
					carry = 0
					carry_kind = kind
				state = S.GATHER
				_gather_t = 0.0
			else:
				_find_resource()
		S.TO_TOWN:
			if carry > 0:
				main.add_resource(carry_kind, carry)
				carry = 0
			if _target_ok():
				_go_to_target()
			else:
				_find_resource()


func _gather(delta: float) -> void:
	if not _target_ok():
		if carry < CAPACITY:
			_find_resource()
		else:
			_go_town()
		return
	_gather_t += delta
	if _gather_t < RATE[kind]:
		return
	_gather_t = 0.0
	carry += map.take(target)
	if carry >= CAPACITY:
		_go_town()
	elif not _target_ok():
		_find_resource()


func _draw() -> void:
	# Skygge og valgring
	draw_set_transform(Vector2(0, 7), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
	if selected:
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 28, Color(0.4, 1.0, 0.4), 3.0)
	draw_set_transform(Vector2.ZERO)
	var bob := 0.0
	if state == S.MOVE or state == S.TO_RES or state == S.TO_TOWN:
		bob = absf(sin(_anim * 14.0)) * -2.0
	var o := Vector2(0, bob)
	# Lasten på ryggen i ressursens farge
	if carry > 0:
		var h := 2.0 + 8.0 * carry / CAPACITY
		var col: Color = CARRY_COLOR.get(carry_kind, Color.WHITE)
		draw_rect(Rect2(o + Vector2(-10, 2 - h), Vector2(6, h)), col)
		draw_rect(Rect2(o + Vector2(-10, 2 - h), Vector2(6, h)), col.darkened(0.4), false, 1.0)
	draw_circle(o, 6.0, Color(0.20, 0.40, 0.90))
	draw_circle(o + Vector2(0, -7), 4.0, Color(0.93, 0.78, 0.62))
	if state != S.GATHER:
		return
	# Verktøyet svinger mot ressursen: øks for tre, hakke for gull og stein, hånd for bær
	var dir := (map.center_of(target) - position).normalized()
	var hand := o + Vector2(0, -2)
	if kind == "food":
		var reach := hand + dir * (6.0 + 3.0 * absf(sin(_anim * 6.0)))
		draw_line(hand, reach, Color(0.93, 0.78, 0.62), 2.5)
		return
	var tip := hand + dir.rotated(sin(_anim * 10.0) * 0.9) * 11.0
	draw_line(hand, tip, Color(0.45, 0.30, 0.15), 2.0)
	if kind == "wood":
		draw_circle(tip, 2.5, Color(0.75, 0.75, 0.8))
	else:
		var side := (tip - hand).normalized().orthogonal() * 4.0
		draw_line(tip - side, tip + side, Color(0.6, 0.6, 0.65), 2.5)
