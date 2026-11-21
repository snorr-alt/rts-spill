class_name GameMap
extends Node2D
## Kartet er et rutenett. Hver rute er gress, stein (pynt) eller en ressurs: tre, bærbusk,
## gullgruve eller steingruve. Alt annet enn gress er «solid» i stifinningen, og arbeiderne
## samler fra ruta ved siden av.

const TILE := 32
const W := 64
const H := 48

enum T { GRASS, TREE, ROCK, BERRY, GOLD, STONE }

## Hvilken ressurs hver rutetype gir, og hvor mye som er i én rute
const KIND := {T.TREE: "wood", T.BERRY: "food", T.GOLD: "gold", T.STONE: "stone"}
const AMOUNT := {T.TREE: 100, T.BERRY: 125, T.GOLD: 250, T.STONE: 200}
const NAMES := {T.TREE: "Tre", T.BERRY: "Bærbusk", T.GOLD: "Gullgruve", T.STONE: "Steingruve"}

var tiles := PackedByteArray()
var amount := PackedInt32Array()
var shade := PackedFloat32Array()
var astar := AStarGrid2D.new()

const N8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
const N4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.07
	tiles.resize(W * H)
	amount.resize(W * H)
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
	# Ressurser ved basen (bær, gull, stein i hver sin retning) og flere lenger ute
	var b := a + PI * 0.5
	_cluster(T.BERRY, center + Vector2.from_angle(b) * 6.5, 6, rng)
	_cluster(T.GOLD, center + Vector2.from_angle(b + 2.1) * 8.5, 5, rng)
	_cluster(T.STONE, center + Vector2.from_angle(b + 4.2) * 9.0, 4, rng)
	for kind in [T.BERRY, T.GOLD, T.GOLD, T.STONE, T.STONE, T.BERRY]:
		for attempt in 30:
			var p := Vector2(rng.randf_range(5, W - 5), rng.randf_range(5, H - 5))
			if p.distance_to(center) > 15.0:
				_cluster(kind, p, 4 + rng.randi() % 3, rng)
				break

	for i in W * H:
		amount[i] = AMOUNT.get(tiles[i], 0)

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


## En klump av én ressurstype. Rydder plass rundt først, så den alltid kan nås.
func _cluster(kind: int, at: Vector2, count: int, rng: RandomNumberGenerator) -> void:
	var c0 := Vector2i(at.round())
	c0.x = clampi(c0.x, 4, W - 5)
	c0.y = clampi(c0.y, 4, H - 5)
	for y in range(-3, 4):
		for x in range(-3, 4):
			var c := c0 + Vector2i(x, y)
			if Vector2(x, y).length() < 3.2 and c.x >= 2 and c.y >= 2 and c.x < W - 2 and c.y < H - 2:
				tiles[c.y * W + c.x] = T.GRASS
	var cells: Array[Vector2i] = [c0]
	tiles[c0.y * W + c0.x] = kind
	var tries := 0
	while cells.size() < count and tries < 60:
		tries += 1
		var from: Vector2i = cells[rng.randi() % cells.size()]
		var nb: Vector2i = from + N4[rng.randi() % 4]
		if Vector2(nb - c0).length() < 2.0 and tiles[nb.y * W + nb.x] == T.GRASS:
			tiles[nb.y * W + nb.x] = kind
			cells.append(nb)


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func center_of(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE, TILE) * 0.5


func size_px() -> Vector2:
	return Vector2(W * TILE, H * TILE)


func tile_at(c: Vector2i) -> int:
	return tiles[c.y * W + c.x] if _in(c) else T.ROCK


## "wood", "food", "gold", "stone" eller "" hvis ruta ikke er en ressurs
func kind_at(c: Vector2i) -> String:
	return KIND.get(tile_at(c), "")


func is_resource(c: Vector2i) -> bool:
	return kind_at(c) != ""


func is_tree(c: Vector2i) -> bool:
	return tile_at(c) == T.TREE


func amount_at(c: Vector2i) -> int:
	return amount[c.y * W + c.x] if _in(c) else 0


func is_walkable(c: Vector2i) -> bool:
	return _in(c) and not astar.is_point_solid(c)


func set_solid(c: Vector2i, solid: bool) -> void:
	if _in(c):
		astar.set_point_solid(c, solid)


## Tar én enhet fra ressursruta. Returnerer 1, eller 0 hvis den er tom.
## Når ruta er tom, blir den gress og kan gås over.
func take(c: Vector2i) -> int:
	if not is_resource(c):
		return 0
	var i := c.y * W + c.x
	amount[i] -= 1
	if amount[i] <= 0:
		tiles[i] = T.GRASS
		astar.set_point_solid(c, false)
		queue_redraw()
	elif amount[i] % 10 == 0:
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
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), grass_a.lerp(grass_b, shade[i]))
	for y in H:
		for x in W:
			var i := y * W + x
			var c := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
			var full := float(amount[i]) / float(AMOUNT.get(tiles[i], 1))
			match tiles[i]:
				T.ROCK:
					draw_circle(c + Vector2(2, 4), 13.0, Color(0, 0, 0, 0.25))
					draw_circle(c, 13.0, Color(0.40, 0.39, 0.38))
					draw_circle(c + Vector2(-4, -4), 6.0, Color(0.50, 0.49, 0.47))
				T.BERRY:
					_draw_berry(c, full, shade[i])
				T.GOLD:
					_draw_mine(c, full, shade[i], Color(0.55, 0.50, 0.40), Color(1.0, 0.82, 0.2))
				T.STONE:
					_draw_mine(c, full, shade[i], Color(0.66, 0.66, 0.64), Color(0.86, 0.86, 0.84))
	# Tretoppene tegnes til slutt, så de kan overlappe nabo-rutene og ligne skog
	for y in H:
		for x in W:
			var i := y * W + x
			if tiles[i] != T.TREE:
				continue
			var c := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
			c += Vector2(shade[i] - 0.5, fposmod(shade[i] * 7.0, 1.0) - 0.5) * 6.0
			var full := float(amount[i]) / AMOUNT[T.TREE]
			var rad := 9.0 + 9.0 * full
			draw_circle(c + Vector2(3, 5), rad, Color(0, 0, 0, 0.22))
			draw_rect(Rect2(c.x - 2.5, c.y, 5, 10), Color(0.35, 0.22, 0.12))
			draw_circle(c, rad, Color(0.13, 0.30, 0.12).lerp(Color(0.17, 0.36, 0.14), shade[i]))
			draw_circle(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.5, Color(0.22, 0.44, 0.18, 0.8))


func _draw_berry(c: Vector2, full: float, s: float) -> void:
	var rad := 11.0 + 4.0 * full
	draw_circle(c + Vector2(2, 4), rad, Color(0, 0, 0, 0.22))
	draw_circle(c, rad, Color(0.16, 0.36, 0.13))
	draw_circle(c + Vector2(-2, -2), rad * 0.75, Color(0.22, 0.46, 0.18))
	var berries := 2 + int(full * 7.0)
	for k in berries:
		var ang := k * 2.4 + s * 6.0
		var p := c + Vector2.from_angle(ang) * rad * (0.15 + 0.55 * fposmod(k * 0.37 + s, 1.0))
		draw_circle(p, 3.2, Color(0.80, 0.10, 0.20))
		draw_circle(p + Vector2(-1, -1), 1.1, Color(1, 0.6, 0.65))


func _draw_mine(c: Vector2, full: float, s: float, rock: Color, shine: Color) -> void:
	var sc := 0.6 + 0.4 * full
	var pts := PackedVector2Array()
	for k in 7:
		var ang := k * TAU / 7.0 + s
		pts.append(c + Vector2.from_angle(ang) * 14.0 * sc * (0.8 + 0.2 * fposmod(k * 0.61 + s * 3.0, 1.0)))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(3, 4))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	draw_colored_polygon(pts, rock)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, rock.darkened(0.35), 1.5)
	for k in 3:
		var p := c + Vector2(cos(k * 2.1 + s * 5.0), sin(k * 2.1 + s * 5.0)) * 6.0 * sc
		draw_rect(Rect2(p - Vector2(2.5, 2.5) * sc, Vector2(5, 5) * sc), shine)
