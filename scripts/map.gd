class_name GameMap
extends Node2D
## Kartet er et rutenett. Hver rute er gress, tre eller stein. Trær og stein (og bygninger)
## er «solide» i stifinningen. Arbeiderne hogger fra ruta ved siden av treet.

const TILE := 32
const W := 64
const H := 48
const WOOD_PER_TREE := 100

enum T { GRASS, TREE, ROCK }

var tiles := PackedByteArray()
var wood := PackedInt32Array()
var shade := PackedFloat32Array()
var astar := AStarGrid2D.new()

const N8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.07
	tiles.resize(W * H)
	wood.resize(W * H)
	shade.resize(W * H)
	var center := Vector2(W / 2.0, H / 2.0)
	for y in H:
		for x in W:
			var i := y * W + x
			shade[i] = rng.randf()
			var n := noise.get_noise_2d(x, y)
			var d := Vector2(x, y).distance_to(center)
			var t := T.GRASS
			if d > 8.0 and n > 0.22:
				t = T.TREE
			elif d > 9.0 and n < -0.55 and rng.randf() < 0.6:
				t = T.ROCK
			if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
				t = T.TREE
			tiles[i] = t
	# To skoger like ved rådhuset, så det alltid er noe å hogge i starten
	var a := rng.randf() * TAU
	for k in 2:
		var ang := a + k * PI * (0.8 + rng.randf() * 0.4)
		var c := center + Vector2.from_angle(ang) * (10.0 + rng.randf() * 2.0)
		for y in range(int(c.y) - 4, int(c.y) + 5):
			for x in range(int(c.x) - 4, int(c.x) + 5):
				if _in(Vector2i(x, y)) and Vector2(x, y).distance_to(c) < 3.2 + rng.randf() * 0.8:
					tiles[y * W + x] = T.TREE
	for i in W * H:
		wood[i] = WOOD_PER_TREE if tiles[i] == T.TREE else 0

	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE, TILE) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in H:
		for x in W:
			if tiles[y * W + x] != T.GRASS:
				astar.set_point_solid(Vector2i(x, y), true)
	queue_redraw()


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func center_of(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE, TILE) * 0.5


func size_px() -> Vector2:
	return Vector2(W * TILE, H * TILE)


func is_tree(c: Vector2i) -> bool:
	return _in(c) and tiles[c.y * W + c.x] == T.TREE


func is_walkable(c: Vector2i) -> bool:
	return _in(c) and not astar.is_point_solid(c)


func set_solid(c: Vector2i, solid: bool) -> void:
	if _in(c):
		astar.set_point_solid(c, solid)


## Hogger én enhet ved fra treet. Returnerer hvor mye ved det ga (0 hvis treet er borte).
func chop(c: Vector2i) -> int:
	if not is_tree(c):
		return 0
	var i := c.y * W + c.x
	wood[i] -= 1
	if wood[i] <= 0:
		tiles[i] = T.GRASS
		astar.set_point_solid(c, false)
		queue_redraw()
	elif wood[i] % 20 == 0:
		queue_redraw()
	return 1


func path_between(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	if not is_walkable(from_cell) or not is_walkable(to_cell):
		return PackedVector2Array()
	return astar.get_point_path(from_cell, to_cell)


## Bredde-først-søk over gangbare ruter fra `start`. Finner nærmeste gangbare rute som ligger
## inntil en rute der `is_target` er sann. Gir {"goal": rute å stå på, "target": målruta}.
func nearest_adjacent(start: Vector2i, is_target: Callable, max_nodes := 4000) -> Dictionary:
	if not _in(start):
		return {}
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and head < max_nodes:
		var c: Vector2i = queue[head]
		head += 1
		for d in N8:
			var nb := c + d
			if is_target.call(nb):
				return {"goal": c, "target": nb}
		for d in N8:
			var nb := c + d
			if seen.has(nb) or not is_walkable(nb):
				continue
			# Ikke skjær hjørner mellom to solide ruter
			if d.x != 0 and d.y != 0 and (not is_walkable(c + Vector2i(d.x, 0)) or not is_walkable(c + Vector2i(0, d.y))):
				continue
			seen[nb] = true
			queue.append(nb)
	return {}


## Nærmeste gangbare rute til `c` (brukes når noen trykker på en solid rute eller havner fast).
func nearest_walkable(c: Vector2i) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, 12):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) == r and is_walkable(c + Vector2i(x, y)):
					return c + Vector2i(x, y)
	return c


func _draw() -> void:
	var grass_a := Color(0.33, 0.52, 0.22)
	var grass_b := Color(0.37, 0.56, 0.24)
	for y in H:
		for x in W:
			var i := y * W + x
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			draw_rect(r, grass_a.lerp(grass_b, shade[i]))
			if tiles[i] == T.ROCK:
				var c := r.get_center()
				draw_circle(c + Vector2(2, 4), 13.0, Color(0, 0, 0, 0.25))
				draw_circle(c, 13.0, Color(0.48, 0.47, 0.45))
				draw_circle(c + Vector2(-4, -4), 6.0, Color(0.6, 0.59, 0.56))
	# Tretoppene tegnes etterpå, så de kan overlappe nabo-rutene og ligne skog
	for y in H:
		for x in W:
			var i := y * W + x
			if tiles[i] != T.TREE:
				continue
			var c := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
			var jitter := Vector2(shade[i] - 0.5, fposmod(shade[i] * 7.0, 1.0) - 0.5) * 6.0
			c += jitter
			var full := float(wood[i]) / WOOD_PER_TREE
			var rad := 9.0 + 9.0 * full
			draw_circle(c + Vector2(3, 5), rad, Color(0, 0, 0, 0.22))
			draw_rect(Rect2(c.x - 2.5, c.y, 5, 10), Color(0.35, 0.22, 0.12))
			draw_circle(c, rad, Color(0.13, 0.30, 0.12).lerp(Color(0.17, 0.36, 0.14), shade[i]))
			draw_circle(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.5, Color(0.22, 0.44, 0.18, 0.8))
