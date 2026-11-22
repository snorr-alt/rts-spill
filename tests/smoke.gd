extends Node
## Fast test som kjøres ved hver bygging (se ci/build_apk.sh). Spiller uten skjerm.
##
## Del A – du mot en fiende som står stille (AI-en er slått av):
##  1. kartet: begge lag har rådhus og 3 arbeidere, alle fire ressurser ligger nær basen
##  2. trykk velger en arbeider, trykk på en ressurs setter den i arbeid
##  3. tre, mat, gull og stein kommer inn i telleren
##  4. folketallet stopper på 5 til det finnes hus
##  5. bygge hus via byggemenyen (plasser + bekreft) – folketallet går til 10
##  5b. sagbruk ved skogen: veden leveres der i stedet for i rådhuset
##  5c. mølle og gård: arbeideren som bygger gården, dyrker den; tom gård forsvinner, og bonden
##      finner en ny gård selv
##  5d. samlingspunkt: ny arbeider fra rådhuset går rett til ressursen punktet står på
##  6. bygge brakker; skytebane, stall, tårn og spydmann er låst i mørketiden
##  6b. føydaltid i rådhuset (krever to av sagbruk/gruveleir/mølle/brakker), så låses alt opp
##  6c. trene sverdmann, spydmann, bueskytter, speider og ridder
##  6d. styrketrekanten: spydmann mot rytter, rytter mot bueskytter, bueskytter mot fotfolk
##  7. sverdmannen angriper av seg selv en fiende som kommer nær, bueskytteren skyter på avstand
##  7b. tårnet skyter fiender innen rekkevidde
##  8. soldater river en fiendebygning, og rutene blir gangbare igjen
##  9. en soldat som blir angrepet, slår tilbake
## 10. seier når fienden har mistet rådhuset og alle enheter
##
## Del B – AI mot AI på normal: begge bygger hus, leveringsplasser og brakker, går opp i
## føydaltid, bygger skytebane, trener flere typer soldater og angriper.
## Skriver også ut hvor fort spillet går (sekunder spilltid per sekund), som mål på ytelsen.

const SPEED := 8.0

var main: Main
var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Main.skip_menu = true
	Main.seed_override = int(Time.get_unix_time_from_system()) % 100000
	print("Frø: ", Main.seed_override)
	_speed(SPEED)
	_run()


func _speed(s: float) -> void:
	Engine.physics_ticks_per_second = int(60 * s)
	Engine.max_physics_steps_per_frame = 16
	Engine.time_scale = s


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


## Gjør en bygning ferdig med en gang (for å spare tid i testen; byggingen er testet i 5)
func _finish(b: Building) -> void:
	if b != null and not b.complete:
		b.build(999.0)


func _spot(size: int, near: Vector2i) -> Vector2i:
	for r in range(3, 14):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var c := near + Vector2i(x, y)
				if main.map.can_place(c - Vector2i(1, 1), size + 2):
					return c
	return Vector2i(-1, -1)


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	main = get_tree().current_scene as Main
	if main == null:
		_fail("fant ikke hovedscenen")
		return
	for a in main.ais:
		a.set_process(false)
	if not await _part_a():
		return
	if not await _part_b():
		return
	print("SMOKE OK")
	get_tree().quit(0)


func _part_a() -> bool:
	var map := main.map
	var me := main.me
	var foe := main.players[1]
	var tc := me.town()

	# 1
	if tc == null or foe.town() == null or me.units.size() != 3 or foe.units.size() != 3:
		_fail("feil oppstart")
		return false
	var near := {}
	for k: String in Defs.RES_ORDER:
		var r := map.nearest_adjacent(map.nearest_walkable(tc.cell + Vector2i(1, 3)), func(c: Vector2i) -> bool: return map.kind_at(c) == k)
		if r.is_empty() or Vector2(r.target).distance_to(Vector2(tc.cell)) > 16.0:
			_fail("fant ikke %s nær basen" % k)
			return false
		near[k] = r.target
	print("1 ok: ressurser ved basen ", near)

	# 2
	var w: Worker = me.units[0]
	main.tap_world(w.position)
	if main.selected.size() != 1:
		_fail("trykk på arbeider valgte den ikke")
		return false
	w = main.selected[0]
	main.tap_world(map.center_of(near.wood))
	if w.state != Unit.S.TO_RES or w.kind != "wood":
		_fail("arbeideren gikk ikke til treet")
		return false
	main.clear_selection()
	print("2 ok")

	# 3
	(me.units[1] as Worker).cmd_gather(near.food)
	(me.units[2] as Worker).cmd_gather(near.gold)
	var before: Dictionary = me.res.duplicate()
	if not await _wait_until(func() -> bool: return me.res.wood >= before.wood + 10 and me.res.food >= before.food + 10 and me.res.gold >= before.gold + 10, 90.0):
		_fail("ressursene kom ikke hjem: %s" % str(me.res))
		return false
	(me.units[2] as Worker).cmd_gather(near.stone)
	if not await _wait_until(func() -> bool: return me.res.stone >= before.stone + 10, 60.0):
		_fail("steinen kom ikke hjem")
		return false
	(me.units[2] as Worker).cmd_auto_gather("wood")
	print("3 ok: ", me.res)

	# 4
	me.res.food = 500
	if me.pop_cap() != 5:
		_fail("folketallet skulle starte på 5, er %d" % me.pop_cap())
		return false
	if not tc.train("worker") or not tc.train("worker"):
		_fail("kunne ikke trene to arbeidere")
		return false
	if tc.can_train("worker"):
		_fail("kunne trene forbi folketallet")
		return false
	if not await _wait_until(func() -> bool: return me.units.size() == 5, 40.0):
		_fail("arbeiderne ble ikke ferdige")
		return false
	print("4 ok: folk %d/%d" % [me.pop(), me.pop_cap()])

	# 5
	me.res.wood = 1000
	var spot := _spot(2, tc.cell + Vector2i(-4, 0))
	var builders: Array[Unit] = [me.units[3], me.units[4]]
	main._set_selection(builders)
	main.open_build_menu(true)
	main.start_placing("house")
	main._ghost_world = map.center_of(spot) + Vector2(GameMap.TILE, GameMap.TILE) * 0.5
	await get_tree().process_frame
	await get_tree().process_frame
	if main.place_cell != spot:
		_fail("spøkelseshuset står feil: %s, ville %s" % [main.place_cell, spot])
		return false
	main.confirm_placing()
	if me.count_buildings("house") != 1:
		_fail("huset ble ikke plassert")
		return false
	main.clear_selection()
	if not await _wait_until(func() -> bool: return me.pop_cap() == 10, 40.0):
		_fail("huset ble ikke ferdig")
		return false
	await _wait(1.0)
	for b in builders:
		if b.is_idle():
			_fail("bygger gikk ikke tilbake til arbeid")
			return false
	print("5 ok: folk %d/%d" % [me.pop(), me.pop_cap()])

	# 5b
	var wood_worker := me.units[0] as Worker
	var forest := map.nearest_adjacent_tile(map.nearest_walkable(tc.cell + Vector2i(1, 3)), GameMap.T.TREE)
	var lspot := Vector2i(-1, -1)
	for rr in range(1, 6):
		for y in range(-rr, rr + 1):
			for x in range(-rr, rr + 1):
				if lspot.x < 0 and map.can_place(forest.goal + Vector2i(x, y), 2) and Vector2(x, y).length() > 1.5:
					lspot = forest.goal + Vector2i(x, y)
	var lumber := main.place_building(me, "lumber", lspot, [wood_worker])
	if lumber == null:
		_fail("sagbruket ble ikke plassert")
		return false
	if not await _wait_until(func() -> bool: return lumber.complete, 60.0):
		_fail("sagbruket ble ikke ferdig")
		return false
	wood_worker.cmd_gather(forest.target)
	if not await _wait_until(func() -> bool: return wood_worker.state == Unit.S.TO_TOWN, 60.0):
		_fail("vedhoggeren gikk ikke for å levere")
		return false
	if wood_worker.target_building != lumber:
		_fail("veden ble ikke levert på sagbruket, men på %s" % wood_worker.target_building.display_name())
		return false
	print("5b ok: leverer ved på sagbruket")

	# 5c
	var farmer := me.units[1] as Worker
	var mill := main.place_building(me, "mill", _spot(2, tc.cell + Vector2i(0, -5)), [farmer])
	_finish(mill)
	var fspot := _spot(2, mill.cell + Vector2i(0, -3))
	var farm := main.place_building(me, "farm", fspot, [farmer])
	if farm == null:
		_fail("gården ble ikke plassert")
		return false
	if map.is_walkable(fspot) == false:
		_fail("gården skal kunne gås over")
		return false
	if not await _wait_until(func() -> bool: return farmer.farm == farm and farmer.state == Unit.S.GATHER, 60.0):
		_fail("byggeren begynte ikke å dyrke gården")
		return false
	var farm2 := main.place_building(me, "farm", _spot(2, mill.cell + Vector2i(4, -3)), [])
	_finish(farm2)
	var food0: int = me.res.food
	if not await _wait_until(func() -> bool: return me.res.food >= food0 + 10, 40.0):
		_fail("maten fra gården kom ikke hjem")
		return false
	farm.food = 2
	var farm_ref: WeakRef = weakref(farm)
	if not await _wait_until(func() -> bool: return farm_ref.get_ref() == null, 30.0):
		_fail("tom gård forsvant ikke")
		return false
	if not await _wait_until(func() -> bool: return farmer.farm == farm2, 10.0):
		_fail("bonden fant ikke den andre gården")
		return false
	print("5c ok: gård dyrkes, tom gård forsvinner, bonden finner ny")

	# 5d
	me.res.food += 200
	main.select_building(tc)
	main.tap_world(map.center_of(near.gold))
	if tc.rally == Vector2.INF:
		_fail("samlingspunktet ble ikke satt")
		return false
	main.clear_selection()
	var n_before := me.units.size()
	if not tc.train("worker"):
		_fail("kunne ikke trene arbeider til samlingspunktet")
		return false
	if not await _wait_until(func() -> bool: return me.units.size() > n_before, 20.0):
		_fail("arbeideren ble ikke ferdig")
		return false
	var newbie := me.units[-1] as Worker
	if newbie.kind != "gold" or not newbie.is_gathering():
		_fail("ny arbeider gikk ikke til gullet ved samlingspunktet")
		return false
	tc.rally = Vector2.INF
	print("5d ok: samlingspunkt")

	# 6
	var bspot := _spot(3, tc.cell + Vector2i(4, 0))
	var bk := main.place_building(me, "barracks", bspot, [me.units[3], me.units[4]])
	if bk == null:
		_fail("brakkene ble ikke plassert")
		return false
	if not await _wait_until(func() -> bool: return bk.complete, 60.0):
		_fail("brakkene ble ikke ferdige")
		return false
	me.res = {"wood": 3000, "food": 3000, "gold": 3000, "stone": 3000}
	for t: String in ["range", "stable", "tower"]:
		if me.build_block_reason(t) == "":
			_fail("%s skulle vært låst i mørketiden" % t)
			return false
	if bk.can_train("spear"):
		_fail("spydmann skulle vært låst i mørketiden")
		return false
	print("6 ok: brakker, føydale ting er låst")

	# 6b
	for h in 4:
		_finish(main.place_building(me, "house", _spot(2, tc.cell + Vector2i(-8, 6 - h * 3)), []))
	if not tc.train("feudal"):
		_fail("kunne ikke starte føydaltid: %s" % me.feudal_block_reason())
		return false
	if tc.can_train("worker") or tc.can_train("feudal"):
		_fail("rådhuset skulle vært opptatt med forskningen")
		return false
	if not await _wait_until(func() -> bool: return me.age == 1, 70.0):
		_fail("føydaltid ble ikke ferdig")
		return false
	for t: String in ["range", "stable", "tower"]:
		if me.build_block_reason(t) != "":
			_fail("%s er fortsatt låst: %s" % [t, me.build_block_reason(t)])
			return false
	print("6b ok: føydaltid")

	# 6c
	var rg := main.place_building(me, "range", _spot(3, tc.cell + Vector2i(8, 0)), [])
	var st := main.place_building(me, "stable", _spot(3, tc.cell + Vector2i(8, 6)), [])
	_finish(rg)
	_finish(st)
	var ok_train := bk.train("sword") and bk.train("spear") and rg.train("archer") and st.train("scout") and st.train("knight")
	if not ok_train:
		_fail("kunne ikke trene alle soldattypene")
		return false
	if not await _wait_until(func() -> bool: return me.military().size() == 5, 60.0):
		_fail("soldatene ble ikke ferdige (%d)" % me.military().size())
		return false
	var sword: Unit = null
	var archer: Unit = null
	for u in me.military():
		if u.type == "sword":
			sword = u
		elif u.type == "archer":
			archer = u
	print("6c ok: alle soldattyper")

	# 6d
	var D := Defs.UNITS
	var checks := [
		["spydmann mot ridder", Defs.damage(D.spear, D.knight), Defs.damage(D.sword, D.knight)],
		["ridder mot bueskytter", Defs.damage(D.knight, D.archer), Defs.damage(D.knight, D.sword)],
		["bueskytter mot sverdmann", Defs.damage(D.archer, D.sword), Defs.damage(D.archer, D.knight)],
	]
	for c in checks:
		if c[1] <= c[2]:
			_fail("styrketrekanten stemmer ikke: %s gir %d, sammenlignet med %d" % c)
			return false
	print("6d ok: styrketrekant ", checks)

	# 7
	var foe_tc := foe.town()
	var victim := main.spawn_unit(foe, "worker", foe_tc)
	victim.position = map.center_of(map.nearest_walkable(sword.cell() + Vector2i(3, 0)))
	victim.cmd_stop()
	var victim_ref: WeakRef = weakref(victim)
	if not await _wait_until(func() -> bool: return victim_ref.get_ref() == null, 30.0):
		_fail("sverdmannen angrep ikke fienden ved siden av")
		return false
	await _wait(3.0)  # la sverdmannen gå hjem
	var target := main.spawn_unit(foe, "worker", foe_tc)
	target.position = map.center_of(map.nearest_walkable(archer.cell() + Vector2i(0, -4)))
	target.cmd_stop()
	var target_ref: WeakRef = weakref(target)
	archer.cmd_attack_unit(target)
	var arrows_seen := [false]
	if not await _wait_until(func() -> bool:
		if not main._arrows.is_empty():
			arrows_seen[0] = true
		return target_ref.get_ref() == null, 30.0):
		_fail("bueskytteren drepte ikke målet")
		return false
	if not arrows_seen[0]:
		_fail("ingen piler ble skutt")
		return false
	print("7 ok: nærkamp og bueskyting")

	# 7b
	var tspot := _spot(1, tc.cell + Vector2i(-4, -4))
	var tower := main.place_building(me, "tower", tspot, [])
	_finish(tower)
	var tv := main.spawn_unit(foe, "worker", foe_tc)
	tv.position = map.center_of(map.nearest_walkable(tspot + Vector2i(4, 0)))
	tv.cmd_stop()
	var tv_ref: WeakRef = weakref(tv)
	if not await _wait_until(func() -> bool: return tv_ref.get_ref() == null, 30.0):
		_fail("tårnet skjøt ikke fienden")
		return false
	print("7b ok: tårnet skyter")

	# 8
	var hspot := _spot(2, map.tile_of(sword.position) + Vector2i(0, 4))
	var fh := main._add_building(foe, "house", hspot, true)
	var fh_ref: WeakRef = weakref(fh)
	sword.cmd_attack_building(fh)
	archer.cmd_attack_building(fh)
	if not await _wait_until(func() -> bool: return fh_ref.get_ref() == null, 200.0):
		_fail("fiendehuset ble ikke revet ")
		return false
	if not map.is_walkable(hspot):
		_fail("rutene under det revne huset er fortsatt stengt")
		return false
	print("8 ok: bygning revet")

	# 9
	await _wait(2.0)
	sword.cmd_stop()
	var foe_bk := main._add_building(foe, "barracks", _spot(3, foe_tc.cell + Vector2i(-6, 0)), true)
	var enemy := main.spawn_unit(foe, "sword", foe_bk)
	enemy.position = map.center_of(map.nearest_walkable(sword.cell() + Vector2i(-1, 0)))
	enemy.cmd_attack_unit(sword)
	var sref: WeakRef = weakref(sword)
	var eref: WeakRef = weakref(enemy)
	if not await _wait_until(func() -> bool: return sref.get_ref() == null or eref.get_ref() == null or sref.get_ref().state == Unit.S.ATTACK, 6.0):
		_fail("soldaten slo ikke tilbake")
		return false
	await _wait_until(func() -> bool: return sref.get_ref() == null or eref.get_ref() == null, 40.0)
	print("9 ok: slo tilbake")

	# 10
	for u in foe.units.duplicate():
		u.die()
	for b in foe.buildings.duplicate():
		b.die()
	main.hud.process_mode = Node.PROCESS_MODE_DISABLED  # sluttskjermen skal ikke pause testen
	if not await _wait_until(func() -> bool: return main.game_over, 5.0):
		_fail("seieren ble ikke registrert")
		return false
	if main.winner != 0:
		_fail("feil vinner: %d" % main.winner)
		return false
	get_tree().paused = false
	print("10 ok: seier")
	return true


func _part_b() -> bool:
	Main.ai_both = true
	Main.difficulty = 1
	get_tree().paused = false
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	main = get_tree().current_scene as Main
	_speed(12.0)
	var start_real := Time.get_ticks_msec()
	var limit := 24.0 * 60.0
	var next_report := 120.0
	while main.game_time < limit and not main.game_over:
		await _wait(1.0)
		if main.game_time > 660.0 and _b_ok():
			break
		if main.game_time >= next_report:
			next_report += 120.0
			var line := "  %s:" % _time(main.game_time)
			for p in main.players:
				var ai: AIController = null
				for a in main.ais:
					if a.player == p:
						ai = a
				line += "  [%s %s arb %d hær %d hus %d gård %d mil.bygg %d bølger %d]" % [Defs.TEAM_NAMES[p.team], Defs.AGES[p.age], p.count_units("worker"), p.military().size(),
					p.count_buildings("house", false), p.count_buildings("farm", false),
					p.count_buildings("barracks", false) + p.count_buildings("range", false) + p.count_buildings("stable", false), ai.waves_sent]
			var real := (Time.get_ticks_msec() - start_real) / 1000.0
			print(line, "  (%.1fx)" % (main.game_time / real))
	var real := (Time.get_ticks_msec() - start_real) / 1000.0
	print("B: %s spilltid på %.0f s (%.1fx). Vinner: %s" % [_time(main.game_time), real, main.game_time / real, str(main.winner)])
	for p in main.players:
		print("   ", Defs.TEAM_NAMES[p.team], " ", p.stats)
	var waves := 0
	for a in main.ais:
		waves += a.waves_sent
	for p in main.players:
		if p.stats.built < 3 and not p.defeated:
			_fail("%s bygde for lite (%d)" % [Defs.TEAM_NAMES[p.team], p.stats.built])
			return false
		if p.stats.trained < 15:
			_fail("%s trente for lite (%d)" % [Defs.TEAM_NAMES[p.team], p.stats.trained])
			return false
	if waves == 0:
		_fail("ingen AI angrep")
		return false
	if main.players[0].stats.kills + main.players[1].stats.kills < 5:
		_fail("nesten ingen kamp")
		return false
	for p in main.players:
		if p.defeated:
			continue
		if p.age < 1:
			_fail("%s nådde ikke føydaltid" % Defs.TEAM_NAMES[p.team])
			return false
		for t: String in ["lumber", "mill", "range"]:
			if p.count_buildings(t) == 0:
				_fail("%s bygde ikke %s" % [Defs.TEAM_NAMES[p.team], Defs.BUILDINGS[t].name.to_lower()])
				return false
		var mil_types := 0
		for k: String in p.stats.types:
			if k != "worker":
				mil_types += 1
		if mil_types < 2:
			_fail("%s trente bare %d soldattyper" % [Defs.TEAM_NAMES[p.team], mil_types])
			return false
	print("B ok")
	return true


func _time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## Har begge lag bygd, trent og kjempet nok til at del B er bestått?
func _b_ok() -> bool:
	var waves := 0
	for a in main.ais:
		waves += a.waves_sent
	for p in main.players:
		if p.stats.built < 3 or p.stats.trained < 15 or p.age < 1 or p.count_buildings("range") == 0:
			return false
	return waves > 0 and main.players[0].stats.kills + main.players[1].stats.kills >= 5
