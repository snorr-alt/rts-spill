class_name Worker
extends Node2D
## Landsbyarbeider. Kan gå, hogge tre og bære ved tilbake til rådhuset.
## Når et tre er tomt, finner arbeideren selv det nærmeste treet.

enum S { IDLE, MOVE, TO_TREE, CHOP, TO_TOWN }

const SPEED := 80.0
const CAPACITY := 10
const CHOP_TIME := 0.6
const PICK_RADIUS := 20.0

var main: Node
var map: GameMap
var town: TownCenter
var state := S.IDLE
var tree := Vector2i(-1, -1)
var carry := 0
var selected := false

var _path := PackedVector2Array()
var _path_i := 0
var _chop_t := 0.0
var _anim := 0.0
var _stuck_t := 0.0


func cell() -> Vector2i:
	return map.tile_of(position)


func is_idle() -> bool:
	return state == S.IDLE


func cmd_move(target: Vector2) -> void:
	tree = Vector2i(-1, -1)
	var goal := map.nearest_walkable(map.tile_of(target))
	if _set_path(goal):
		if map.tile_of(target) == goal:
			_path[_path.size() - 1] = target
		state = S.MOVE
	else:
		state = S.IDLE


func cmd_gather(tree_cell: Vector2i) -> void:
	tree = tree_cell
	_go_to_tree()


func cmd_return() -> void:
	if carry > 0:
		_go_town()
	else:
		cmd_move(town.center() + Vector2(0, GameMap.TILE * 2.2))


## Hogg det nærmeste treet (brukes av nye arbeidere og «Hogg tre»-knappen)
func cmd_auto_gather() -> void:
	_find_tree()


func _set_path(goal: Vector2i) -> bool:
	var start := cell()
	if not map.is_walkable(start):
		start = map.nearest_walkable(start)
	_path = map.path_between(start, goal)
	_path_i = 1 if _path.size() > 1 else 0
	_stuck_t = 0.0
	return not _path.is_empty()


func _go_to_tree() -> void:
	var t := tree
	var r := map.nearest_adjacent(_start_cell(), func(c: Vector2i) -> bool: return c == t)
	if r.is_empty() or not map.is_tree(tree):
		_find_tree()
		return
	if _set_path(r.goal):
		state = S.TO_TREE
	else:
		_find_tree()


func _find_tree() -> void:
	var r := map.nearest_adjacent(_start_cell(), map.is_tree)
	if r.is_empty() or not _set_path(r.goal):
		if carry > 0:
			_go_town()
		else:
			state = S.IDLE
		return
	tree = r.target
	state = S.TO_TREE


func _go_town() -> void:
	var r := map.nearest_adjacent(_start_cell(), town.has_cell)
	if r.is_empty() or not _set_path(r.goal):
		state = S.IDLE
		return
	state = S.TO_TOWN


func _start_cell() -> Vector2i:
	var c := cell()
	return c if map.is_walkable(c) else map.nearest_walkable(c)


func _adjacent_to(c: Vector2i) -> bool:
	var d := cell() - c
	return maxi(absi(d.x), absi(d.y)) <= 1


func _physics_process(delta: float) -> void:
	_anim += delta
	match state:
		S.MOVE, S.TO_TREE, S.TO_TOWN:
			if _follow(delta):
				_arrived()
		S.CHOP:
			_chop(delta)
	queue_redraw()


func _follow(delta: float) -> bool:
	if _path_i >= _path.size():
		return true
	var target := _path[_path_i]
	var to := target - position
	var step := SPEED * delta
	if to.length() <= step:
		position = target
		_path_i += 1
		return _path_i >= _path.size()
	position += to.normalized() * step
	return false


func _arrived() -> void:
	match state:
		S.MOVE:
			state = S.IDLE
		S.TO_TREE:
			if map.is_tree(tree) and _adjacent_to(tree):
				state = S.CHOP
				_chop_t = 0.0
			else:
				_find_tree()
		S.TO_TOWN:
			if carry > 0:
				main.add_wood(carry)
				carry = 0
			if map.is_tree(tree):
				_go_to_tree()
			else:
				_find_tree()


func _chop(delta: float) -> void:
	if not map.is_tree(tree):
		if carry < CAPACITY:
			_find_tree()
		else:
			_go_town()
		return
	_chop_t += delta
	if _chop_t < CHOP_TIME:
		return
	_chop_t = 0.0
	carry += map.chop(tree)
	if carry >= CAPACITY:
		_go_town()
	elif not map.is_tree(tree):
		_find_tree()


func _draw() -> void:
	# Skygge og valgring
	draw_set_transform(Vector2(0, 7), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
	if selected:
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 28, Color(0.4, 1.0, 0.4), 3.0)
	draw_set_transform(Vector2.ZERO)
	var bob := 0.0
	if state == S.MOVE or state == S.TO_TREE or state == S.TO_TOWN:
		bob = absf(sin(_anim * 14.0)) * -2.0
	var o := Vector2(0, bob)
	# Veden på ryggen
	if carry > 0:
		var h := 2.0 + 8.0 * carry / CAPACITY
		draw_rect(Rect2(o + Vector2(-9, 2 - h), Vector2(5, h)), Color(0.55, 0.36, 0.18))
	draw_circle(o, 6.0, Color(0.20, 0.40, 0.90))
	draw_circle(o + Vector2(0, -7), 4.0, Color(0.93, 0.78, 0.62))
	# Øks som svinger mot treet
	if state == S.CHOP:
		var dir := (map.center_of(tree) - position).normalized()
		var swing := sin(_anim * 10.0) * 0.9
		var hand := o + Vector2(0, -2)
		var tip := hand + dir.rotated(swing) * 11.0
		draw_line(hand, tip, Color(0.45, 0.30, 0.15), 2.0)
		draw_circle(tip, 2.5, Color(0.75, 0.75, 0.8))
