class_name AIController
extends Node
## Datamotstanderen. Tenker én gang i sekundet:
##  1. økonomi: setter ledige arbeidere på den ressursen det mangler mest folk på, trener arbeidere
##  2. bygger hus før folketallet er fullt, og brakker når økonomien er i gang
##  3. trener sverdmenn og bueskyttere på skift, men aldri flere enn neste bølge pluss en hjemmestyrke
##  4. forsvarer basen når den blir angrepet (arbeiderne hjelper til hvis det ikke finnes soldater)
##  5. angriper i bølger som blir større for hver gang
## Vanskelighetsgraden styrer samlefart, når første angrep kommer, bølgestørrelse og antall arbeidere.

const BASE_RADIUS := 14.0 * GameMap.TILE

var main: Main
var player: Player
var diff: Dictionary
var wave_size := 5
var next_attack := 360.0
var waves_sent := 0
var attacking: Array[Unit] = []

var _think_t := 0.0
var _threat_pos := Vector2.INF
var _threat_t := -100.0
var _rebalance_t := 0.0
var _toggle := 0


func _init(m: Main, p: Player, d: Dictionary) -> void:
	main = m
	player = p
	diff = d
	wave_size = d.wave
	next_attack = d.first_attack
	_think_t = randf()


func _process(delta: float) -> void:
	_think_t -= delta
	if _think_t > 0.0:
		return
	_think_t = 1.0
	if player.defeated or main.game_over:
		return
	_economy()
	_build()
	_military()
	_defend()
	_attack()


func on_attacked(_target: Node2D, from: Unit) -> void:
	_threat_pos = from.position
	_threat_t = main.game_time


# ---------------------------------------------------------------- økonomi

func _targets() -> Dictionary:
	if player.count_buildings("barracks", true) == 0:
		return {"food": 0.5, "wood": 0.4, "gold": 0.1, "stone": 0.0}
	return {"food": 0.42, "wood": 0.28, "gold": 0.3, "stone": 0.0}


func _economy() -> void:
	var workers := player.workers()
	var counts := {"food": 0, "wood": 0, "gold": 0, "stone": 0}
	for u in workers:
		var w := u as Worker
		if w.is_gathering():
			counts[w.kind] += 1
	var targets := _targets()
	for u in workers:
		var w := u as Worker
		if not w.is_idle():
			continue
		var kind := _most_needed(counts, targets, workers.size())
		w.cmd_auto_gather(kind)
		counts[kind] += 1
	# Flytt en arbeider av og til hvis fordelingen har skjeve seg
	_rebalance_t -= 1.0
	if _rebalance_t <= 0.0:
		_rebalance_t = 15.0
		var need := _most_needed(counts, targets, workers.size())
		var too_many := ""
		var worst := 0.5
		for k: String in counts:
			var extra: float = counts[k] - targets[k] * workers.size()
			if extra > worst:
				worst = extra
				too_many = k
		if too_many != "" and too_many != need:
			for u in workers:
				var w := u as Worker
				if w.is_gathering() and w.kind == too_many:
					w.cmd_auto_gather(need)
					break
	var town := player.town()
	if town != null and town.queue.is_empty() and workers.size() < diff.workers:
		town.train("worker")


func _most_needed(counts: Dictionary, targets: Dictionary, total: int) -> String:
	var best := "food"
	var best_gap := -INF
	for k: String in targets:
		if targets[k] <= 0.0:
			continue
		var gap: float = targets[k] * maxi(total, 1) - counts[k]
		if gap > best_gap:
			best_gap = gap
			best = k
	return best


# ---------------------------------------------------------------- bygging

func _build() -> void:
	var town := player.town()
	if town == null:
		return
	var unfinished := 0
	for b in player.buildings:
		if not b.complete:
			unfinished += 1
	# Hus før det blir fullt
	var room := player.pop_cap() - player.pop_with_queue()
	var margin := 3 + 2 * player.count_buildings("barracks", false)
	if player.pop_cap() < Defs.POP_MAX and room <= margin and _unfinished_of("house") == 0:
		if player.can_afford(Defs.BUILDINGS.house.cost):
			_place("house", 1)
		return
	if unfinished > 0:
		return
	var wcount := player.count_units("worker")
	var barracks := player.count_buildings("barracks", true)
	if barracks < diff.barracks and wcount >= 8 + barracks * 6 and player.can_afford(Defs.BUILDINGS.barracks.cost):
		_place("barracks", 3)
		return
	# Har den mye ubrukte ressurser, bygger den én brakke ekstra (ikke på lett)
	if diff.name != "Lett" and barracks < diff.barracks + 1 and player.res.food > 500 and player.res.gold > 300 and player.res.wood > 300:
		_place("barracks", 2)


func _unfinished_of(type: String) -> int:
	var n := 0
	for b in player.buildings:
		if b.type == type and not b.complete:
			n += 1
	return n


func _place(type: String, builders: int) -> void:
	var town := player.town()
	var size: int = Defs.BUILDINGS[type].size
	var center := town.cell + Vector2i(1, 1)
	var enemy_dir := Vector2(main.map.bases[1 - player.team] - town.cell).normalized()
	var best := Vector2i(-1, -1)
	var best_score := INF
	for r in range(4, 13):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) != r:
					continue
				var c := center + Vector2i(x, y)
				# Én rute luft rundt, så bygningene ikke stenger veier
				if not main.map.can_place(c - Vector2i(1, 1), size + 2):
					continue
				var off := Vector2(x, y)
				# Hus bak basen, brakker mot fienden
				var toward := off.normalized().dot(enemy_dir)
				var score := off.length() + (toward * 3.0 if type == "house" else -toward * 3.0) + randf() * 2.0
				if score < best_score:
					best_score = score
					best = c
		if best.x >= 0 and r >= 6:
			break
	if best.x < 0:
		return
	var chosen := _pick_builders(builders, main.map.center_of(best))
	main.place_building(player, type, best, chosen)


func _pick_builders(n: int, near: Vector2) -> Array:
	var cands: Array = []
	for u in player.workers():
		var w := u as Worker
		if not w.is_building():
			cands.append(w)
	cands.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_squared_to(near) < b.position.distance_squared_to(near))
	return cands.slice(0, n)


# ---------------------------------------------------------------- hær

func _military() -> void:
	if player.count_units("worker") < diff.mil_workers:
		return
	# Ikke bygg opp en større hær enn neste bølge pluss en liten hjemmestyrke
	var army := player.military().size()
	for b in player.buildings:
		army += b.queue.size() if b.type == "barracks" else 0
	if army >= wave_size + diff.extra:
		return
	for b in player.buildings:
		if b.type != "barracks" or not b.complete or b.queue.size() >= 2:
			continue
		var order := ["sword", "archer"] if _toggle % 2 == 0 else ["archer", "sword"]
		for u: String in order:
			if b.train(u):
				_toggle += 1
				break


func _defend() -> void:
	var town := player.town()
	if town == null:
		return
	var home := town.center()
	# Fiender nær basen?
	var threat: Unit = main.nearest_enemy_unit(home, BASE_RADIUS, player.team)
	var threat_pos := threat.position if threat != null else Vector2.INF
	if threat == null and main.game_time - _threat_t < 4.0 and _threat_pos.distance_to(home) < BASE_RADIUS * 1.3:
		threat_pos = _threat_pos
	if threat_pos == Vector2.INF:
		return
	var army := player.military()
	var defenders := 0
	for u in army:
		if u in attacking and u.position.distance_to(home) > BASE_RADIUS * 2.0:
			continue
		defenders += 1
		if u.state == Unit.S.IDLE or (u.state == Unit.S.MOVE and not u.attack_move):
			u.cmd_move(threat_pos, true)
	# Ingen soldater hjemme: arbeiderne nærmest slår tilbake mot små angrep
	if defenders == 0 and threat != null:
		var enemies := 0
		for p in main.players:
			if p == player:
				continue
			for e in p.units:
				if e.position.distance_to(home) < BASE_RADIUS:
					enemies += 1
		if enemies <= 4:
			var ws := _pick_builders(mini(enemies * 3, 8), threat.position)
			for w in ws:
				if w.state != Unit.S.ATTACK:
					w.cmd_attack_unit(threat)


func _attack() -> void:
	var alive: Array[Unit] = []
	for u in attacking:
		if is_instance_valid(u) and not u.dead:
			alive.append(u)
	attacking = alive
	var town := player.town()
	var home := town.center() if town != null else Vector2.ZERO
	# Bølgen som er ute: gi nye mål til dem som står ledige
	for u in attacking:
		if u.state == Unit.S.IDLE:
			var t := _enemy_target(u.position)
			if t != Vector2.INF:
				u.cmd_move(t, true)
	if main.game_time < next_attack:
		return
	var ready: Array[Unit] = []
	for u in player.military():
		if u in attacking:
			continue
		if u.state == Unit.S.IDLE or town == null or u.position.distance_to(home) < BASE_RADIUS:
			ready.append(u)
	if ready.size() < wave_size:
		return
	# Send bølgen; resten blir hjemme som forsvar
	ready.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_squared_to(home) > b.position.distance_squared_to(home))
	ready = ready.slice(0, wave_size)
	var target := _enemy_target(home)
	if target == Vector2.INF:
		return
	for u in ready:
		u.cmd_move(target + Vector2(randf_range(-40, 40), randf_range(-40, 40)), true)
		attacking.append(u)
	waves_sent += 1
	wave_size = mini(wave_size + 2, 24)
	next_attack = main.game_time + 75.0


## Nærmeste fiendebygning (helst rådhuset), ellers nærmeste fiendeenhet
func _enemy_target(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for p in main.players:
		if p == player:
			continue
		for b in p.buildings:
			var d := from.distance_to(b.center()) * (0.6 if b.type == "town" else 1.0)
			if d < best_d:
				best_d = d
				best = b.center()
		if best == Vector2.INF:
			for u in p.units:
				var d := from.distance_to(u.position)
				if d < best_d:
					best_d = d
					best = u.position
	return best
