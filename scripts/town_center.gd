class_name TownCenter
extends Node2D
## Rådhuset: 3 x 3 ruter. Her leverer arbeiderne ved, og her trenes nye arbeidere.

const SIZE := 3
const MAX_QUEUE := 5

var cell := Vector2i.ZERO
var map: GameMap
var selected := false
var queue := 0
var progress := 0.0  # 0–1 for arbeideren som trenes nå


func setup(m: GameMap, c: Vector2i) -> void:
	map = m
	cell = c
	position = Vector2(c * GameMap.TILE)
	for y in SIZE:
		for x in SIZE:
			map.set_solid(c + Vector2i(x, y), true)


func has_cell(c: Vector2i) -> bool:
	return c.x >= cell.x and c.y >= cell.y and c.x < cell.x + SIZE and c.y < cell.y + SIZE


func contains(world: Vector2) -> bool:
	return has_cell(map.tile_of(world))


func center() -> Vector2:
	return position + Vector2(SIZE, SIZE) * GameMap.TILE * 0.5


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := SIZE * GameMap.TILE
	var r := Rect2(4, 10, s - 8, s - 14)
	draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r, Color(0.72, 0.60, 0.42))
	draw_rect(r, Color(0.45, 0.35, 0.22), false, 2.0)
	# Tak
	var roof := PackedVector2Array([Vector2(0, 30), Vector2(s * 0.5, 0), Vector2(s, 30)])
	draw_colored_polygon(roof, Color(0.55, 0.23, 0.16))
	draw_rect(Rect2(0, 28, s, 6), Color(0.45, 0.18, 0.12))
	# Dør og vinduer
	draw_rect(Rect2(s * 0.5 - 8, s - 30, 16, 26), Color(0.30, 0.19, 0.10))
	draw_rect(Rect2(14, 46, 12, 12), Color(0.25, 0.30, 0.38))
	draw_rect(Rect2(s - 26, 46, 12, 12), Color(0.25, 0.30, 0.38))
	# Flagg i spillerfargen
	draw_line(Vector2(s * 0.5, 0), Vector2(s * 0.5, -22), Color(0.9, 0.9, 0.9), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(s * 0.5, -22), Vector2(s * 0.5 + 16, -18), Vector2(s * 0.5, -13)]), Color(0.2, 0.4, 0.9))
	if selected:
		draw_rect(Rect2(-3, -3, s + 6, s + 6), Color(0.4, 1.0, 0.4), false, 2.0)
	if queue > 0:
		draw_rect(Rect2(0, s + 4, s, 7), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(1, s + 5, (s - 2) * progress, 5), Color(0.4, 0.8, 1.0))
