## Ytelsesmåling (kjøres for hånd): legg «B="*res://tools/bench.gd"» under [autoload] i override.cfg og start Godot uten skjerm.
extends Node
## Ytelsesmåling: 2 x (25 arbeidere + 60 soldater) i kamp og samling, sanntid.
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	Main.skip_menu = true
	Main.ai_both = true
	Main.seed_override = 777
	await get_tree().process_frame
	await get_tree().process_frame
	var m: Main = get_tree().current_scene
	for a in m.ais: a.set_process(false)
	for p in m.players:
		var tc := p.town()
		p.res = {"wood": 99999, "food": 99999, "gold": 99999, "stone": 99999}
		for i in 22: (m.spawn_unit(p, "worker", tc) as Worker).cmd_auto_gather(["wood","food","gold"][i % 3])
		var bk := m._add_building(p, "barracks", m.map.nearest_walkable(tc.cell + Vector2i(6 if p.team == 0 else -6, 0)), true)
		for i in 60: m.spawn_unit(p, "sword" if i % 2 == 0 else "archer", tc)
	for p in m.players:
		var other := m.players[1 - p.team].town().center()
		for u in p.military(): u.cmd_move(other, true)
	var phys := 0.0; var proc := 0.0; var n := 0; var worst := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 50000:
		await get_tree().physics_frame
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		phys += ph; proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0; n += 1
		worst = maxf(worst, ph)
		if n % 600 == 0:
			print("t=%ds enheter %d+%d  fysikk snitt %.2f ms  verst %.2f ms  prosess %.2f ms" % [(Time.get_ticks_msec()-t0)/1000, m.players[0].units.size(), m.players[1].units.size(), phys/n, worst, proc/n])
	get_tree().quit()
