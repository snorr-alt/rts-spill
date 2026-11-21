extends Node
## Fast test som kjøres ved hver bygging (se ci/build_apk.sh). Spiller uten skjerm og sjekker:
##  1. kartet har trær som kan nås fra rådhuset
##  2. et trykk på en arbeider velger den, og et trykk på et tre setter den i gang med å hogge
##  3. arbeiderne hogger, bærer veden hjem, og ressurstelleren går opp
##  4. rådhuset trener en ny arbeider, og den går selv og hogger
##  5. en arbeider finner fram til et fjernt punkt rundt hindringer
##  6. når et tre er hogd ned, finner arbeideren et nytt tre selv

const SPEED := 8.0

var main: Node
var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.physics_ticks_per_second = int(60 * SPEED)
	Engine.time_scale = SPEED
	_run()


func _fail(msg: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("SMOKE FEIL: ", msg)
	get_tree().quit(1)


func _wait(game_seconds: float) -> void:
	await get_tree().create_timer(game_seconds, true, true).timeout


func _wait_until(cond: Callable, game_seconds: float) -> bool:
	var t := 0.0
	while t < game_seconds:
		if cond.call():
			return true
		await _wait(0.25)
		t += 0.25
	return cond.call()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	main = get_tree().current_scene
	if main == null or not ("workers" in main):
		_fail("fant ikke hovedscenen")
		return
	var map: GameMap = main.map
	var town: TownCenter = main.town

	# 1
	var start := map.nearest_adjacent(map.nearest_walkable(town.cell + Vector2i(1, 3)), map.is_tree)
	if start.is_empty():
		_fail("ingen trær kan nås fra rådhuset")
		return
	if main.workers.size() != main.START_WORKERS:
		_fail("feil antall arbeidere ved start: %d" % main.workers.size())
		return
	print("1 ok: tre ved ", start.target)

	# 2
	var w: Worker = main.workers[0]
	main.tap_world(w.position)
	if main.selected.size() != 1 or main.selected[0].position.distance_to(w.position) > 12.0:
		_fail("trykk på arbeider valgte den ikke")
		return
	w = main.selected[0]
	main.tap_world(map.center_of(start.target))
	if w.state != Worker.S.TO_TREE and w.state != Worker.S.CHOP:
		_fail("arbeideren gikk ikke til treet (tilstand %d)" % w.state)
		return
	print("2 ok: trykk velger og gir ordre")

	# 3
	main.clear_selection()
	for o: Worker in main.workers:
		if o != w:
			o.cmd_auto_gather()
	var wood0: int = main.wood
	var ok := await _wait_until(func() -> bool: return main.wood >= wood0 + 30, 60.0)
	if not ok:
		_fail("veden kom ikke hjem (tre: %d)" % main.wood)
		return
	print("3 ok: tre = ", main.wood)

	# 4
	main.wood = 200
	main.select_town()
	if not main.train_worker() or not main.train_worker():
		_fail("kunne ikke trene arbeider")
		return
	if main.wood != 100:
		_fail("trening trakk ikke riktig pris")
		return
	ok = await _wait_until(func() -> bool: return main.workers.size() == main.START_WORKERS + 2, 30.0)
	if not ok:
		_fail("nye arbeidere ble ikke ferdige")
		return
	await _wait(1.0)
	var nw: Worker = main.workers[-1]
	if nw.is_idle():
		_fail("ny arbeider gikk ikke for å hogge")
		return
	print("4 ok: folk = ", main.workers.size())

	# 5
	# Et fjernt punkt som kan nås: gå fra hjørnet mot rådhuset til stien finnes
	var mover: Worker = main.workers[1]
	var far := Vector2i(-1, -1)
	for k in range(0, 20):
		var c := map.nearest_walkable(Vector2i(4 + k, 4 + k * GameMap.H / GameMap.W))
		if map.is_walkable(c) and not map.path_between(mover.cell(), c).is_empty():
			far = c
			break
	if far.x < 0 or Vector2(far).distance_to(Vector2(town.cell)) < 12.0:
		_fail("fant ikke noe fjernt punkt som kan nås")
		return
	main._set_selection([mover] as Array[Worker])
	main.command_at(map.center_of(far))
	if mover.state != Worker.S.MOVE:
		_fail("arbeideren fikk ikke gå-ordre")
		return
	ok = await _wait_until(func() -> bool: return mover.is_idle(), 60.0)
	if not ok or mover.position.distance_to(map.center_of(far)) > GameMap.TILE * 1.5:
		_fail("arbeideren kom ikke fram (avstand %d)" % int(mover.position.distance_to(map.center_of(far))))
		return
	print("5 ok: kom fram til ", far)
	main.clear_selection()

	# 6
	var cw: Worker = main.workers[2]
	cw.cmd_auto_gather()
	await _wait_until(func() -> bool: return cw.state == Worker.S.CHOP, 30.0)
	var first := cw.tree
	map.wood[first.y * GameMap.W + first.x] = 1
	ok = await _wait_until(func() -> bool: return cw.tree != first and not cw.is_idle(), 20.0)
	if not ok or map.is_tree(first):
		_fail("arbeideren fant ikke nytt tre")
		return
	print("6 ok: nytt tre ", cw.tree)

	print("SMOKE OK")
	get_tree().quit(0)
