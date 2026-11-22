class_name Hud
extends CanvasLayer
## Ressurslinje øverst, minikart oppe til høyre og panel nederst for det som er valgt.
## Store knapper for fingre. Har også startmeny, pausemeny og sluttskjerm.

const MAX_BUTTONS := 7


## Lite ikon for hver ressurs, tegnet i kode
class ResIcon extends Control:
	var kind := "wood"

	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"wood":
				draw_rect(Rect2(c + Vector2(-11, -2), Vector2(22, 8)), Color(0.55, 0.36, 0.18))
				draw_rect(Rect2(c + Vector2(-9, -9), Vector2(22, 8)), Color(0.65, 0.44, 0.22))
				draw_circle(c + Vector2(-9, -5), 4.0, Color(0.85, 0.7, 0.45))
			"food":
				for p in [Vector2(-5, 2), Vector2(5, 2), Vector2(0, -5)]:
					draw_circle(c + p, 6.0, Color(0.85, 0.15, 0.25))
				draw_circle(c + Vector2(-2, -7), 1.8, Color(1, 0.7, 0.75))
			"gold":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-6, -8), c + Vector2(6, -8), c + Vector2(12, 6)]), Color(1.0, 0.82, 0.2))
				draw_line(c + Vector2(-5, -5), c + Vector2(3, -5), Color(1, 1, 0.8), 2.0)
			"stone":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 7), c + Vector2(-9, -6), c + Vector2(2, -10), c + Vector2(12, -2), c + Vector2(10, 8)]), Color(0.72, 0.72, 0.70))
				draw_line(c + Vector2(-4, -4), c + Vector2(4, 2), Color(0.5, 0.5, 0.5), 1.5)
			"pop":
				draw_circle(c + Vector2(0, -6), 5.0, Color(0.93, 0.78, 0.62))
				draw_circle(c + Vector2(0, 6), 8.0, Color(0.3, 0.5, 0.95))


## Minikart: terreng, bygninger, enheter og hva kameraet ser. Trykk eller dra for å flytte kameraet.
class Minimap extends Control:
	const SCALE := 2.0
	var main: Main
	var tex: ImageTexture
	var img: Image
	var _dirty := false
	var _t := 0.0
	var _pings: Array = []  # [world_pos, age]

	func setup(m: Main) -> void:
		main = m
		custom_minimum_size = Vector2(GameMap.W, GameMap.H) * SCALE
		size = custom_minimum_size
		img = Image.create(GameMap.W, GameMap.H, false, Image.FORMAT_RGB8)
		for y in GameMap.H:
			for x in GameMap.W:
				img.set_pixel(x, y, main.map.minimap_color(y * GameMap.W + x))
		tex = ImageTexture.create_from_image(img)
		main.map.tile_changed.connect(func(c: Vector2i) -> void:
			img.set_pixel(c.x, c.y, main.map.minimap_color(c.y * GameMap.W + c.x))
			_dirty = true)

	func ping(p: Vector2) -> void:
		_pings.append([p, 0.0])

	func _process(delta: float) -> void:
		for p in _pings:
			p[1] += delta
		_pings = _pings.filter(func(p: Array) -> bool: return p[1] < 3.0)
		_t -= delta
		if _t <= 0.0:
			_t = 0.2
			if _dirty:
				_dirty = false
				tex.update(img)
			queue_redraw()

	func _draw() -> void:
		var s := SCALE / GameMap.TILE
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		for p in main.players:
			for b in p.buildings:
				var r := b.world_rect()
				draw_rect(Rect2(r.position * s, r.size * s).grow(1.0), p.color.lightened(0.2) if b.complete else p.color.darkened(0.3))
			for u in p.units:
				draw_rect(Rect2(u.position * s - Vector2(1.5, 1.5), Vector2(3, 3)), p.color.lightened(0.35))
		for pg in _pings:
			var a: float = 1.0 - pg[1] / 3.0
			draw_arc(pg[0] * s, 4.0 + 10.0 * fposmod(pg[1], 1.0), 0, TAU, 16, Color(1, 0.2, 0.2, a), 2.0)
		var vp := main.get_viewport_rect().size / main.cam.zoom.x
		var cr := Rect2((main.cam.position - vp * 0.5) * s, vp * s)
		draw_rect(cr.intersection(Rect2(Vector2.ZERO, size)), Color(1, 1, 1, 0.9), false, 1.5)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.60, 0.30), false, 2.0)

	func _gui_input(e: InputEvent) -> void:
		var pos := Vector2.INF
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pos = e.position
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			pos = e.position
		if pos != Vector2.INF:
			main.look_at_world(pos / SCALE * GameMap.TILE)
			accept_event()


var main: Main

var top: PanelContainer
var res_labels := {}
var pop_label: Label
var age_label: Label
var idle_btn: Button
var army_btn: Button
var minimap: Minimap

var bottom: PanelContainer
var info: Label
var buttons: Array[Button] = []
var _actions: Array[Callable] = []
var _sig := ""

var hint: Label
var msg: Label
var _msg_t := 0.0
var _hint_time := 16.0
var _ui_t := 0.0

var overlay_panel: PanelContainer  # meny, pause og sluttskjerm
var _overlay_kind := ""
var _overlay_box: VBoxContainer


func _style(alpha := 0.78) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, alpha)
	sb.border_color = Color(0.75, 0.60, 0.30, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 72)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	return l


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	top = PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style())
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 6
	add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	top.add_child(hb)
	for k: String in Defs.RES_ORDER:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(ResIcon.new(k))
		var l := _label(28)
		l.custom_minimum_size = Vector2(62, 0)
		box.add_child(l)
		res_labels[k] = l
		hb.add_child(box)
	var pbox := HBoxContainer.new()
	pbox.add_child(ResIcon.new("pop"))
	pop_label = _label(28)
	pbox.add_child(pop_label)
	hb.add_child(pbox)
	age_label = _label(24)
	hb.add_child(age_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	idle_btn = _button("Ledige: 0", func() -> void: main.select_idle())
	idle_btn.custom_minimum_size = Vector2(150, 52)
	hb.add_child(idle_btn)
	army_btn = _button("Hær: 0", func() -> void: main.select_army())
	army_btn.custom_minimum_size = Vector2(130, 52)
	hb.add_child(army_btn)
	var pause_btn := _button("II", func() -> void: toggle_pause())
	pause_btn.custom_minimum_size = Vector2(60, 52)
	hb.add_child(pause_btn)

	minimap = Minimap.new()
	minimap.setup(main)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(minimap)

	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _style())
	add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bottom.add_child(bh)
	info = _label(24)
	info.custom_minimum_size = Vector2(250, 0)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(info)
	for i in MAX_BUTTONS:
		var idx := i
		var b := _button("", func() -> void: _press(idx))
		buttons.append(b)
		_actions.append(Callable())
		bh.add_child(b)

	hint = _label(24)
	hint.text = "Trykk på en arbeider og så på et tre, en bærbusk eller en gruve.  Dra for å flytte kartet, knip for å zoome.\nBygg hus for mer folk, sagbruk og gruveleir nær ressursene, og gå opp i føydaltid i rådhuset."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_bottom(hint, -20)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	msg = _label(30)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg.offset_top = 80
	msg.add_theme_color_override("font_outline_color", Color.BLACK)
	msg.add_theme_constant_override("outline_size", 7)
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(msg)

	overlay_panel = PanelContainer.new()
	overlay_panel.add_theme_stylebox_override("panel", _style(0.92))
	overlay_panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay_panel.visible = false
	add_child(overlay_panel)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 14)
	_overlay_box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_panel.add_child(_overlay_box)


func _center_bottom(c: Control, offset: float) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_bottom = offset


func _press(i: int) -> void:
	if _actions[i].is_valid():
		_actions[i].call()
	_ui_t = 0.0  # vis resultatet med en gang


# ---------------------------------------------------------------- meldinger

func dismiss_hint() -> void:
	_hint_time = minf(_hint_time, 2.0)


func message(text: String) -> void:
	msg.text = text
	msg.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_msg_t = 3.0


func alert(text: String, at: Vector2) -> void:
	msg.text = text
	msg.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_msg_t = 4.0
	minimap.ping(at)


## Om et trykk på skjermen treffer panelene (da skal ikke kartet reagere)
func blocks(pos: Vector2) -> bool:
	if overlay_panel.visible:
		return true
	for c: Control in [top, bottom, minimap]:
		if c.visible and c.get_global_rect().grow(4).has_point(pos):
			return true
	return false


# ---------------------------------------------------------------- menyer

func _clear_overlay() -> void:
	for c in _overlay_box.get_children():
		c.queue_free()


func _overlay_title(text: String, size := 52) -> void:
	var t := _label(size)
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(t)


func show_menu() -> void:
	_clear_overlay()
	_overlay_title("Riket")
	var sub := _label(24)
	sub.text = "Samle ressurser, bygg opp byen og knus den røde fienden.\nVelg vanskelighetsgrad:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	for i in Defs.DIFFICULTY.size():
		var d: Dictionary = Defs.DIFFICULTY[i]
		var b := _button(d.name, func() -> void: main.start_game(i))
		b.custom_minimum_size = Vector2(200, 80)
		row.add_child(b)
	_overlay_box.add_child(row)
	_show_overlay("menu")


func toggle_pause() -> void:
	if _overlay_kind == "pause":
		_overlay_kind = ""
		overlay_panel.visible = false
		get_tree().paused = false
		return
	if _overlay_kind != "":
		return  # startmeny eller sluttskjerm er oppe
	_clear_overlay()
	_overlay_title("Pause")
	var t := _label(24)
	t.text = "Tid: %s   Vanskelighetsgrad: %s" % [_time_text(main.game_time), Defs.DIFFICULTY[Main.difficulty].name]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var cont := _button("Fortsett", func() -> void: toggle_pause())
	cont.custom_minimum_size = Vector2(220, 80)
	row.add_child(cont)
	var ng := _button("Ny kamp", func() -> void: main.new_game())
	ng.custom_minimum_size = Vector2(220, 80)
	row.add_child(ng)
	_overlay_box.add_child(row)
	_show_overlay("pause")


func show_end(won: bool) -> void:
	_clear_overlay()
	_overlay_title("Seier!" if won else "Tap", 60)
	var s: Dictionary = main.me.stats
	var e: Dictionary = main.players[1].stats
	var t := _label(24)
	t.text = "Tid: %s\nDu: samlet %d, trente %d, bygde %d, drepte %d, mistet %d\nFienden: samlet %d, trente %d, drepte %d, mistet %d" % [
		_time_text(main.game_time), s.gathered, s.trained, s.built, s.kills, s.lost,
		e.gathered, e.trained, e.kills, e.lost]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(t)
	var ng := _button("Ny kamp", func() -> void: main.new_game())
	ng.custom_minimum_size = Vector2(260, 80)
	ng.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay_box.add_child(ng)
	_show_overlay("end")


func _show_overlay(kind: String) -> void:
	_overlay_kind = kind
	overlay_panel.visible = true
	get_tree().paused = true
	await get_tree().process_frame
	overlay_panel.reset_size()
	overlay_panel.position = (overlay_panel.get_viewport_rect().size - overlay_panel.size) * 0.5


func _time_text(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ---------------------------------------------------------------- panelet nederst

## Setter opp knappene: hver er [tekst, handling, aktiv]. Bygger bare om når tekstene endrer seg.
func _set_buttons(list: Array) -> void:
	var sig := ""
	for b in list:
		sig += b[0] + "|"
	if sig != _sig:
		_sig = sig
		for i in MAX_BUTTONS:
			buttons[i].visible = i < list.size()
			if i < list.size():
				buttons[i].text = list[i][0]
				buttons[i].custom_minimum_size.x = 150 if "\n" in list[i][0] else 112
	for i in list.size():
		_actions[i] = list[i][1]
		buttons[i].disabled = not list[i][2]


func _process(delta: float) -> void:
	if not is_inside_tree() or not is_instance_valid(main) or not main.is_inside_tree():
		return
	_hint_time -= delta
	hint.modulate.a = clampf(_hint_time, 0.0, 1.0)
	_msg_t -= delta
	msg.visible = _msg_t > 0.0
	msg.modulate.a = clampf(_msg_t, 0.0, 1.0)
	# Resten oppdateres 10 ganger i sekundet – det holder for øyet og sparer mye arbeid
	_ui_t -= delta
	if _ui_t > 0.0:
		return
	_ui_t = 0.1

	var me: Player = main.me
	for k: String in res_labels:
		res_labels[k].text = str(me.res[k])
	pop_label.text = "%d/%d" % [me.pop(), me.pop_cap()]
	age_label.text = Defs.AGES[me.age]
	pop_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if me.pop() >= me.pop_cap() else Color(1.0, 0.92, 0.75))
	var idle := main.idle_workers().size()
	idle_btn.text = "Ledige: %d" % idle
	idle_btn.disabled = idle == 0
	var army := me.military().size()
	army_btn.text = "Hær: %d" % army
	army_btn.disabled = army == 0

	minimap.position = Vector2(top.get_viewport_rect().size.x - minimap.size.x - 10, top.position.y + top.size.y + 6)

	_update_bottom()
	hint.visible = _hint_time > 0.0 and not bottom.visible and not overlay_panel.visible
	if bottom.visible:
		bottom.reset_size()
		var vs := bottom.get_viewport_rect().size
		# Smale skjermer: krymp panelet så alle knappene får plass
		var k := minf(1.0, (vs.x - 16.0) / bottom.size.x)
		bottom.scale = Vector2(k, k)
		var w := bottom.size * k
		bottom.position = Vector2((vs.x - w.x) * 0.5, vs.y - w.y - 8)


func _update_bottom() -> void:
	var me: Player = main.me
	var sel: Array[Unit] = main.selected
	bottom.visible = true
	if main.placing != "":
		var d: Dictionary = Defs.BUILDINGS[main.placing]
		var ok: bool = main.map.can_place(main.place_cell, d.size)
		info.text = "Plasser %s\nDra kartet eller trykk der den skal stå" % d.name.to_lower()
		_set_buttons([["Plasser", main.confirm_placing, ok], ["Avbryt", main.cancel_placing, true]])
		return
	if not sel.is_empty():
		var workers: Array[Unit] = main.selected_workers()
		if not workers.is_empty() and main.build_menu:
			var mil: bool = main.build_page == 1
			info.text = "Bygg – %s\n%d arbeider%s" % ["militært" if mil else "økonomi", workers.size(), "e" if workers.size() > 1 else ""]
			var list: Array = []
			for t: String in (Defs.BUILD_MIL if mil else Defs.BUILD_ECO):
				var d: Dictionary = Defs.BUILDINGS[t]
				var why := me.build_block_reason(t)
				var line := Defs.cost_text(d.cost) if why == "" else why
				list.append(["%s\n%s" % [d.name, line], main.start_placing.bind(t), why == "" and me.can_afford(d.cost)])
			list.append(["Økonomi" if mil else "Militært", main.open_build_menu.bind(true, 0 if mil else 1), true])
			list.append(["Tilbake", main.open_build_menu.bind(false), true])
			_set_buttons(list)
			return
		info.text = _selection_text(sel)
		if not workers.is_empty():
			var list: Array = []
			for k: String in Defs.RES_ORDER:
				list.append([Defs.RES_NAMES[k], main.auto_gather_selected.bind(k), true])
			list.append(["Bygg", main.open_build_menu.bind(true), true])
			list.append(["Fjern valg", main.clear_selection, true])
			_set_buttons(list)
		else:
			_set_buttons([["Stopp", main.stop_selected, true], ["Fjern valg", main.clear_selection, true]])
		return
	var b: Building = main.selected_building
	if b != null:
		var text := "%s (%s)\nLiv %d/%d" % [b.display_name(), Defs.TEAM_NAMES[b.player.team].to_lower(), int(b.hp), int(b.max_hp)]
		if b.player != me:
			info.text = text
			_set_buttons([["Fjern valg", main.clear_selection, true]])
			return
		if not b.complete:
			info.text = "%s\nUnder bygging: %d %%" % [b.display_name(), int(b.progress * 100)]
			_set_buttons([["Fjern valg", main.clear_selection, true]])
			return
		if b.type == "farm":
			text = "Gård\n%d mat igjen – %s" % [b.food, "dyrkes" if b.farmer != null and is_instance_valid(b.farmer) else "ledig"]
		elif not b.def.get("drop", []).is_empty() and b.type != "town":
			var names: PackedStringArray = []
			for k: String in b.def.drop:
				names.append(Defs.RES_NAMES[k].to_lower())
			text += "\nLeveringsplass for " + " og ".join(names)
		elif b.type == "tower":
			text += "\nSkyter fiender innen %d ruter" % int(b.def.range)
		if not b.queue.is_empty():
			var first := Defs.item(b.queue[0])
			var verb := "Forsker" if Defs.is_tech(b.queue[0]) else "Trener"
			text += "\n%s %s (%d %%), %d i kø" % [verb, first.name.to_lower(), int(b.train_progress() * 100), b.queue.size()]
		elif b.trains_anything():
			text += "\nTrykk på kartet for samlingspunkt" if b.rally == Vector2.INF else "\nSamlingspunkt satt (trykk bygningen for å fjerne)"
		if b.trains_anything() and me.pop_with_queue() >= me.pop_cap() and me.pop_cap() < Defs.POP_MAX:
			text += "\nFolketallet er fullt – bygg hus!"
		if "feudal" in b.def.trains and me.age == 0 and not me.researching("feudal"):
			var why := me.feudal_block_reason()
			if why != "":
				text += "\nFøydaltid: " + why.to_lower()
		info.text = text
		var list: Array = []
		for u: String in b.def.trains:
			var d := Defs.item(u)
			if Defs.is_tech(u) and (me.age >= d.gives_age or me.researching(u)):
				continue
			var why := b.train_block_reason(u)
			var line := Defs.cost_text(d.cost)
			if why == Defs.AGES[1]:
				line = why
			list.append(["%s\n%s" % [d.name, line], b.train.bind(u), why == ""])
		if not b.queue.is_empty():
			list.append(["Avbryt", b.cancel_last, true])
		list.append(["Fjern valg", main.clear_selection, true])
		_set_buttons(list)
		return
	var e: Unit = main.selected_enemy
	if e != null:
		info.text = "%s (rød)\nLiv %d/%d" % [e.display_name(), int(e.hp), int(e.max_hp)]
		_set_buttons([["Fjern valg", main.clear_selection, true]])
		return
	var r: Vector2i = main.selected_res
	if main.map.is_resource(r):
		info.text = "%s\n%d %s igjen" % [GameMap.NAMES[main.map.tile_at(r)], main.map.amount_at(r), Defs.RES_NAMES[main.map.kind_at(r)].to_lower()]
		_set_buttons([["Fjern valg", main.clear_selection, true]])
		return
	bottom.visible = false


func _selection_text(sel: Array[Unit]) -> String:
	if sel.size() == 1:
		var u: Unit = sel[0]
		var line := "Liv %d/%d" % [int(u.hp), int(u.max_hp)]
		if u is Worker:
			var w := u as Worker
			var what := "ledig"
			if w.is_gathering():
				what = "samler " + Defs.RES_NAMES[w.kind].to_lower()
			elif w.is_building():
				what = "bygger"
			elif w.state == Unit.S.ATTACK:
				what = "angriper"
			elif w.state == Unit.S.MOVE:
				what = "går"
			line = "%s – bærer %d %s" % [what.capitalize(), w.carry, Defs.RES_NAMES.get(w.carry_kind, "").to_lower()]
			return "Arbeider (liv %d/%d)\n%s" % [int(u.hp), int(u.max_hp), line]
		return "%s\n%s" % [u.display_name(), line]
	var counts := {}
	for u in sel:
		counts[u.display_name()] = counts.get(u.display_name(), 0) + 1
	var parts: PackedStringArray = []
	for k: String in counts:
		parts.append("%d %s" % [counts[k], k.to_lower()])
	return "%d valgt\n%s" % [sel.size(), ", ".join(parts)]
