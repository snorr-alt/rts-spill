class_name GameMap
extends Node2D
## Kartet er et rutenett. Hver rute er gress, stein (pynt) eller en ressurs: tre, bærbusk,
## gullgruve eller steingruve. Alt annet enn gress, og bygninger, er «solid» i stifinningen.
##
## Kartet er punktsymmetrisk, så begge lag får like gode startplasser. Det tegnes i biter
## (16 x 16 ruter), og bare biten der noe endrer seg blir tegnet på nytt. Bakken er ett bilde.

signal tile_changed(c: Vector2i)

const TILE := 32
const W := 96
const H := 64
const CHUNK := 16

enum T { GRASS, TREE, ROCK, BERRY, GOLD, STONE }

## Hvilken ressurs hver rutetype gir, og hvor mye som er i én rute
const KIND := {T.TREE: "wood", T.BERRY: "food", T.GOLD: "gold", T.STONE: "stone"}
const AMOUNT := {T.TREE: 100, T.BERRY: 125, T.GOLD: 250, T.STONE: 200}
const NAMES := {T.TREE: "Tre", T.BERRY: "Bærbusk", T.GOLD: "Gullgruve", T.STONE: "Steingruve"}

var tiles := PackedByteArray()
var amount := PackedInt32Array()
var shade := PackedFloat32Array()
var astar := AStarGrid2D.new()
## Øvre venstre rute for rådhuset til hvert lag
var bases: Array[Vector2i] = []

var _object_chunks: Array[Node2D] = []
var _visit := PackedInt32Array()
var _visit_gen := 0
var _queue := PackedInt32Array()

const N8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
const N4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


class Chunk extends Node2D:
	var map: GameMap
	var rect: Rect2i
	var objects := false

	func _draw() -> void:
		map._draw_objects(self, rect)


# ------------------------------------------------------------------ generering

func generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.07
	tiles.resize(W * H)
	amount.resize(W * H)
	shade.resize(W * H)
	_visit.resize(W * H)
	_queue.resize(W * H)

	# Baser: blå til venstre, rød speilet til høyre
	var b0 := Vector2i(15, rng.randi_range(14, H - 17))
	bases = [b0, Vector2i(W - 3 - b0.x, H - 3 - b0.y)]
	var centers: Array[Vector2] = [Vector2(b0) + Vector2(1.5, 1.5), Vector2(bases[1]) + Vector2(1.5, 1.5)]

	for y in H:
		for x in W:
			var i := y * W + x
			shade[i] = rng.randf()
			# Samme terreng på begge halvdeler (speilet gjennom midten)
			var m := _mirror(Vector2i(x, y)) if x >= W / 2 else Vector2i(x, y)
			var n := noise.get_noise_2d(m.x, m.y)
			var t := T.GRASS
			if n > 0.24:
				t = T.TREE
			elif n < -0.55 and _hash01(m) < 0.6:
				t = T.ROCK
			if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
				t = T.TREE
			tiles[i] = t
	for c in centers:
		_fill_circle(c, 8.5, T.GRASS)

	# Ressurser ved basen og lenger ute. Alt plasseres for blå og speiles for rød.
	var a := rng.randf() * TAU
	var plan: Array = []  # [type, posisjon, antall]
	for k in 2:
		var ang := a + k * PI * (0.75 + rng.randf() * 0.5)
		plan.append([T.TREE, centers[0] + Vector2.from_angle(ang) * (11.0 + rng.randf() * 2.0), 0])
	plan.append([T.BERRY, centers[0] + Vector2.from_angle(a + PI * 0.5) * 6.5, 6])
	plan.append([T.GOLD, centers[0] + Vector2.from_angle(a + PI * 0.5 + 2.1) * 8.5, 6])
	plan.append([T.STONE, centers[0] + Vector2.from_angle(a + PI * 0.5 + 4.2) * 9.0, 5])
	for kind in [T.BERRY, T.GOLD, T.GOLD, T.STONE]:
		for attempt in 40:
			var p := Vector2(rng.randf_range(6, W - 6), rng.randf_range(6, H - 6))
			if p.distance_to(centers[0]) > 16.0 and p.distance_to(centers[1]) > 16.0 and absf(p.x - W / 2.0) > 4.0:
				plan.append([kind, p, 4 + rng.randi() % 3])
				break
	for item in plan:
		var s := rng.randi()
		for side in 2:
			var p: Vector2 = item[1] if side == 0 else Vector2(W - 1, H - 1) - item[1]
			if item[0] == T.TREE:
				_forest(p, s)
			else:
				_cluster(item[0], p, item[2], s, side == 1)

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
	_make_chunks()


func _mirror(c: Vector2i) -> Vector2i:
	return Vector2i(W - 1 - c.x, H - 1 - c.y)


func _hash01(c: Vector2i) -> float:
	return fposmod(sin(c.x * 12.9898 + c.y * 78.233) * 43758.5453, 1.0)


func _fill_circle(c: Vector2, r: float, t: int) -> void:
	for y in range(int(c.y - r) - 1, int(c.y + r) + 2):
		for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
			if x >= 2 and y >= 2 and x < W - 2 and y < H - 2 and Vector2(x, y).distance_to(c) < r:
				tiles[y * W + x] = t


func _forest(c: Vector2, s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	for y in range(int(c.y) - 5, int(c.y) + 6):
		for x in range(int(c.x) - 5, int(c.x) + 6):
			if x >= 2 and y >= 2 and x < W - 2 and y < H - 2 and Vector2(x, y).distance_to(c) < 3.4 + rng.randf() * 0.8:
				tiles[y * W + x] = T.TREE


## En klump av én ressurstype. Rydder plass rundt først, så den alltid kan nås.
## `flip` speiler retningene, så den røde klumpen får samme form som den blå.
func _cluster(kind: int, at: Vector2, count: int, s: int, flip: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var c0 := Vector2i(at.round())
	c0.x = clampi(c0.x, 5, W - 6)
	c0.y = clampi(c0.y, 5, H - 6)
	_fill_circle(Vector2(c0), 3.3, T.GRASS)
	var cells: Array[Vector2i] = [c0]
	tiles[c0.y * W + c0.x] = kind
	var tries := 0
	while cells.size() < count and tries < 80:
		tries += 1
		var from: Vector2i = cells[rng.randi() % cells.size()]
		var d: Vector2i = N4[rng.randi() % 4]
		var nb: Vector2i = from + (-d if flip else d)
		if Vector2(nb - c0).length() < 2.0 and tiles[nb.y * W + nb.x] == T.GRASS:
			tiles[nb.y * W + nb.x] = kind
			cells.append(nb)


func _make_chunks() -> void:
	for c in _object_chunks:
		c.queue_free()
	_object_chunks.clear()
	# Bakken er ett bilde med én piksel per rute, forstørret uten utjevning (én tegneoperasjon)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var grass_a := Color(0.33, 0.52, 0.22)
	var grass_b := Color(0.37, 0.56, 0.24)
	for y in H:
		for x in W:
			img.set_pixel(x, y, grass_a.lerp(grass_b, shade[y * W + x]))
	var ground := Sprite2D.new()
	ground.texture = ImageTexture.create_from_image(img)
	ground.centered = false
	ground.scale = Vector2(TILE, TILE)
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ground)
	_make_tree_textures()
	for cy in ceili(float(H) / CHUNK):
		for cx in ceili(float(W) / CHUNK):
			var ch := Chunk.new()
			ch.map = self
			ch.rect = Rect2i(cx * CHUNK, cy * CHUNK, mini(CHUNK, W - cx * CHUNK), mini(CHUNK, H - cy * CHUNK))
			ch.objects = true
			add_child(ch)
			_object_chunks.append(ch)


## Ferdigtegnede trær (fire fargevarianter). Et tre blir da ett firkantbilde å tegne
## i stedet for fire sirkler med mange hjørner hver – mye lettere for telefonen.
const TREE_TEX := 64
var _tree_tex: Array[ImageTexture] = []


func _make_tree_textures() -> void:
	_tree_tex.clear()
	var n := TREE_TEX
	for v in 4:
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var crown := Color(0.13, 0.30, 0.12).lerp(Color(0.17, 0.36, 0.14), v / 3.0)
		var hi := Color(0.22, 0.44, 0.18)
		# Kronen har radius 0.36 av bildet, sentrert litt over midten
		var cc := Vector2(0.46, 0.44) * n
		var rad := 0.36 * n
		for y in n:
			for x in n:
				var p := Vector2(x + 0.5, y + 0.5)
				var col := Color(0, 0, 0, 0)
				# skygge
				var ds := p.distance_to(cc + Vector2(0.07, 0.11) * n)
				if ds < rad:
					col = Color(0, 0, 0, 0.22 * clampf(rad - ds, 0.0, 1.0))
				# stamme
				if absf(p.x - cc.x) < 0.05 * n and p.y > cc.y and p.y < cc.y + 0.22 * n:
					col = Color(0.35, 0.22, 0.12)
				# krone med myk kant og lys flekk
				var d := p.distance_to(cc)
				if d < rad:
					var c2 := crown
					var dh := p.distance_to(cc - Vector2(0.3, 0.3) * rad)
					if dh < rad * 0.5:
						c2 = c2.lerp(hi, 0.8 * clampf(rad * 0.5 - dh, 0.0, 1.0))
					c2.a = clampf(rad - d, 0.0, 1.0)
					col = col.blend(c2) if col.a > 0.0 else c2
				img.set_pixel(x, y, col)
		_tree_tex.append(ImageTexture.create_from_image(img))


func _redraw_at(c: Vector2i) -> void:
	var idx := (c.y / CHUNK) * ceili(float(W) / CHUNK) + c.x / CHUNK
	if idx >= 0 and idx < _object_chunks.size():
		_object_chunks[idx].queue_redraw()


# ------------------------------------------------------------------ oppslag

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
		tile_changed.emit(c)


## Kan en bygning på `size` x `size` ruter stå med øvre venstre hjørne i `c`?
func can_place(c: Vector2i, size: int) -> bool:
	if c.x < 1 or c.y < 1 or c.x + size > W - 1 or c.y + size > H - 1:
		return false
	for y in size:
		for x in size:
			if not is_walkable(c + Vector2i(x, y)):
				return false
	return true


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
		_redraw_at(c)
		tile_changed.emit(c)
	elif amount[i] % 10 == 0:
		_redraw_at(c)
	return 1


# ------------------------------------------------------------------ stifinning

func path_between(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	if not is_walkable(from_cell) or not is_walkable(to_cell):
		return PackedVector2Array()
	return astar.get_point_path(from_cell, to_cell)


## Sti til en av rutene rundt et rektangel (en bygning). Prøver de nærmeste rutene først.
func path_to_rect(from_cell: Vector2i, r: Rect2i) -> PackedVector2Array:
	var ring: Array[Vector2i] = []
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var c := Vector2i(x, y)
			if not r.has_point(c) and is_walkable(c):
				ring.append(c)
	if ring.is_empty():
		return PackedVector2Array()
	var fc := Vector2(from_cell)
	ring.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return fc.distance_squared_to(Vector2(p)) < fc.distance_squared_to(Vector2(q)))
	for k in mini(4, ring.size()):
		var path := path_between(from_cell, ring[k])
		if not path.is_empty():
			return path
	return PackedVector2Array()


## Bredde-først-søk over gangbare ruter fra `start`. Finner nærmeste gangbare rute som ligger
## inntil en rute der `is_target` er sann. Gir {"goal": rute å stå på, "target": målruta}.
## Bruker gjenbrukte pakkede tabeller, så det er raskt nok til å kjøres ofte.
func nearest_adjacent(start: Vector2i, is_target: Callable, max_nodes := 6000) -> Dictionary:
	if not is_walkable(start):
		return {}
	_visit_gen += 1
	var gen := _visit_gen
	var head := 0
	var tail := 0
	_queue[tail] = start.y * W + start.x
	tail += 1
	_visit[start.y * W + start.x] = gen
	while head < tail and head < max_nodes:
		var idx := _queue[head]
		head += 1
		var c := Vector2i(idx % W, idx / W)
		for d in N8:
			var nb := c + d
			if is_target.call(nb):
				return {"goal": c, "target": nb}
		for d in N8:
			var nb := c + d
			if not is_walkable(nb):
				continue
			var ni := nb.y * W + nb.x
			if _visit[ni] == gen:
				continue
			# Ikke skjær hjørner mellom to solide ruter
			if d.x != 0 and d.y != 0 and (not is_walkable(c + Vector2i(d.x, 0)) or not is_walkable(c + Vector2i(0, d.y))):
				continue
			_visit[ni] = gen
			_queue[tail] = ni
			tail += 1
	return {}


## Som nearest_adjacent, men leter etter en bestemt ressurstype. Raskere fordi den sjekker
## tabellen direkte i stedet for å kalle en funksjon for hver nabo.
func nearest_adjacent_tile(start: Vector2i, tile_type: int, max_nodes := 6000) -> Dictionary:
	if not is_walkable(start):
		return {}
	_visit_gen += 1
	var gen := _visit_gen
	var head := 0
	var tail := 0
	_queue[tail] = start.y * W + start.x
	tail += 1
	_visit[start.y * W + start.x] = gen
	while head < tail and head < max_nodes:
		var idx := _queue[head]
		head += 1
		var cx := idx % W
		var cy := idx / W
		for d in N8:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var ni := ny * W + nx
			if tiles[ni] == tile_type:
				return {"goal": Vector2i(cx, cy), "target": Vector2i(nx, ny)}
			if _visit[ni] == gen or astar.is_point_solid(Vector2i(nx, ny)):
				continue
			if d.x != 0 and d.y != 0 and (astar.is_point_solid(Vector2i(nx, cy)) or astar.is_point_solid(Vector2i(cx, ny))):
				continue
			_visit[ni] = gen
			_queue[tail] = ni
			tail += 1
	return {}


## Nærmeste gangbare rute til `c` (brukes når noen trykker på en solid rute eller havner fast).
func nearest_walkable(c: Vector2i) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, 14):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) == r and is_walkable(c + Vector2i(x, y)):
					return c + Vector2i(x, y)
	return c


# ------------------------------------------------------------------ tegning

func _draw_objects(ci: CanvasItem, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * W + x
			var t := tiles[i]
			if t == T.GRASS or t == T.TREE:
				continue
			var c := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
			var full := float(amount[i]) / float(AMOUNT.get(t, 1))
			match t:
				T.ROCK:
					# Store, mørke kampesteiner (pynt) – skal ikke forveksles med steingruver
					ci.draw_circle(c + Vector2(3, 5), 14.0, Color(0, 0, 0, 0.28))
					ci.draw_circle(c, 14.0, Color(0.30, 0.28, 0.26))
					ci.draw_circle(c + Vector2(-4, -5), 7.0, Color(0.38, 0.36, 0.33))
					ci.draw_arc(c, 14.0, 0.3, 1.8, 8, Color(0.18, 0.17, 0.16), 2.0)
				T.BERRY:
					_draw_berry(ci, c, full, shade[i])
				T.GOLD:
					_draw_mine(ci, c, full, shade[i], Color(0.55, 0.50, 0.40), Color(1.0, 0.82, 0.2))
				T.STONE:
					_draw_mine(ci, c, full, shade[i], Color(0.66, 0.66, 0.64), Color(0.86, 0.86, 0.84))
	# Tretoppene til slutt, så de overlapper nabo-rutene og ligner skog
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * W + x
			if tiles[i] != T.TREE:
				continue
			var c := Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
			c += Vector2(shade[i] - 0.5, fposmod(shade[i] * 7.0, 1.0) - 0.5) * 6.0
			var full := float(amount[i]) / AMOUNT[T.TREE]
			var rad := 9.0 + 9.0 * full
			# Bildet er laget så kronens radius er 0,36 av bredden og midten ligger i (0,46; 0,44)
			var sz := rad / 0.36
			ci.draw_texture_rect(_tree_tex[int(shade[i] * 3.99)], Rect2(c - Vector2(0.46, 0.44) * sz, Vector2(sz, sz)), false)


func _draw_berry(ci: CanvasItem, c: Vector2, full: float, s: float) -> void:
	var rad := 11.0 + 4.0 * full
	ci.draw_circle(c + Vector2(2, 4), rad, Color(0, 0, 0, 0.22))
	ci.draw_circle(c, rad, Color(0.16, 0.36, 0.13))
	ci.draw_circle(c + Vector2(-2, -2), rad * 0.75, Color(0.22, 0.46, 0.18))
	var berries := 2 + int(full * 7.0)
	for k in berries:
		var ang := k * 2.4 + s * 6.0
		var p := c + Vector2.from_angle(ang) * rad * (0.15 + 0.55 * fposmod(k * 0.37 + s, 1.0))
		ci.draw_circle(p, 3.2, Color(0.80, 0.10, 0.20))
		ci.draw_circle(p + Vector2(-1, -1), 1.1, Color(1, 0.6, 0.65))


func _draw_mine(ci: CanvasItem, c: Vector2, full: float, s: float, rock: Color, shine: Color) -> void:
	var sc := 0.6 + 0.4 * full
	var pts := PackedVector2Array()
	for k in 7:
		var ang := k * TAU / 7.0 + s
		pts.append(c + Vector2.from_angle(ang) * 14.0 * sc * (0.8 + 0.2 * fposmod(k * 0.61 + s * 3.0, 1.0)))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(3, 4))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	ci.draw_colored_polygon(pts, rock)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, rock.darkened(0.35), 1.5)
	for k in 3:
		var p := c + Vector2(cos(k * 2.1 + s * 5.0), sin(k * 2.1 + s * 5.0)) * 6.0 * sc
		ci.draw_rect(Rect2(p - Vector2(2.5, 2.5) * sc, Vector2(5, 5) * sc), shine)


## Farge for en rute på minikartet
func minimap_color(i: int) -> Color:
	match tiles[i]:
		T.TREE: return Color(0.12, 0.30, 0.11)
		T.ROCK: return Color(0.26, 0.25, 0.23)
		T.BERRY: return Color(0.75, 0.15, 0.25)
		T.GOLD: return Color(0.95, 0.80, 0.2)
		T.STONE: return Color(0.75, 0.75, 0.72)
	return Color(0.33, 0.52, 0.22)
