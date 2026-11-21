class_name Hud
extends CanvasLayer
## Ressurslinje øverst og panel nederst for det som er valgt. Store knapper for fingre.

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


var main: Node

var top: PanelContainer
var res_labels := {}
var pop_label: Label
var idle_btn: Button

var bottom: PanelContainer
var info: Label
var train_btn: Button
var gather_btns := {}
var clear_btn: Button

var hint: Label
var _hint_time := 14.0


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
	b.custom_minimum_size = Vector2(190, 72)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	return l


func _ready() -> void:
	top = PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style())
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 6
	add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	top.add_child(hb)
	for k: String in main.RES_ORDER:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.add_child(ResIcon.new(k))
		var l := _label(30)
		l.custom_minimum_size = Vector2(70, 0)
		box.add_child(l)
		res_labels[k] = l
		hb.add_child(box)
	pop_label = _label(30)
	hb.add_child(pop_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	idle_btn = _button("Ledige: 0", func() -> void: main.select_idle())
	idle_btn.custom_minimum_size = Vector2(190, 56)
	hb.add_child(idle_btn)

	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _style())
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -8
	add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 14)
	bottom.add_child(bh)
	info = _label(26)
	info.custom_minimum_size = Vector2(300, 0)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(info)
	train_btn = _button("", func() -> void: main.train_worker())
	train_btn.custom_minimum_size = Vector2(280, 72)
	bh.add_child(train_btn)
	# Én knapp per ressurs: de valgte arbeiderne går til nærmeste av den typen
	for k: String in main.RES_ORDER:
		var b := _button(main.RES_NAMES[k], func() -> void: main.auto_gather_selected(k))
		b.custom_minimum_size = Vector2(118, 72)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gather_btns[k] = b
		bh.add_child(b)
	clear_btn = _button("Fjern valg", func() -> void: main.clear_selection())
	clear_btn.custom_minimum_size = Vector2(150, 72)
	bh.add_child(clear_btn)

	hint = _label(24)
	hint.text = "Trykk på en arbeider og så på et tre, en bærbusk eller en gruve.  Dra for å flytte kartet, knip for å zoome.\nHold fingeren stille og dra for å velge flere.  Dobbelttrykk på en arbeider velger alle på skjermen."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -20
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func dismiss_hint() -> void:
	_hint_time = minf(_hint_time, 3.0)


## Om et trykk på skjermen treffer panelene (da skal ikke kartet reagere)
func blocks(pos: Vector2) -> bool:
	for c: Control in [top, bottom]:
		if c.visible and c.get_global_rect().grow(4).has_point(pos):
			return true
	return false


func _process(delta: float) -> void:
	_hint_time -= delta
	hint.modulate.a = clampf(_hint_time, 0.0, 1.0)
	hint.visible = _hint_time > 0.0 and not bottom.visible

	for k: String in res_labels:
		res_labels[k].text = str(main.res[k])
	pop_label.text = "Folk: %d/%d" % [main.workers.size(), main.POP_CAP]
	var idle: int = main.idle_workers().size()
	idle_btn.text = "Ledige: %d" % idle
	idle_btn.disabled = idle == 0

	var sel: Array = main.selected
	var town: TownCenter = main.town
	var map: GameMap = main.map
	var sres: Vector2i = main.selected_res
	if not sel.is_empty():
		_show(false, true)
		if sel.size() == 1:
			var w: Worker = sel[0]
			var what := "Ledig"
			if not w.is_idle() and w.state != Worker.S.MOVE:
				what = "Samler " + main.RES_NAMES[w.kind].to_lower()
			info.text = "Arbeider – %s\nBærer %d/%d %s" % [what, w.carry, Worker.CAPACITY, main.RES_NAMES.get(w.carry_kind, "").to_lower()]
		else:
			var counts := {}
			for w: Worker in sel:
				if not w.is_idle() and w.state != Worker.S.MOVE:
					counts[w.kind] = counts.get(w.kind, 0) + 1
			var parts: PackedStringArray = []
			for k: String in main.RES_ORDER:
				if counts.has(k):
					parts.append("%d %s" % [counts[k], main.RES_NAMES[k].to_lower()])
			info.text = "%d arbeidere valgt\n%s" % [sel.size(), ", ".join(parts) if not parts.is_empty() else "Ledige"]
	elif map.is_resource(sres):
		_show(false, false)
		var t := map.tile_at(sres)
		info.text = "%s\n%d %s igjen" % [GameMap.NAMES[t], map.amount_at(sres), main.RES_NAMES[map.kind_at(sres)].to_lower()]
	elif town.selected:
		_show(true, false)
		var q := ""
		if town.queue > 0:
			q = "\nTrener: %d  (%d %%)" % [town.queue, int(town.progress * 100)]
		info.text = "Rådhus" + q
		train_btn.text = "Tren arbeider\n(%d mat)" % main.WORKER_COST
		train_btn.disabled = not main.can_train()
	else:
		bottom.visible = false
	# Panelet skal alltid sitte midt nede selv om innholdet endrer bredde
	bottom.reset_size()
	bottom.position.x = (bottom.get_viewport_rect().size.x - bottom.size.x) * 0.5
	bottom.position.y = bottom.get_viewport_rect().size.y - bottom.size.y - 8


func _show(train: bool, gather: bool) -> void:
	bottom.visible = true
	train_btn.visible = train
	for b: Button in gather_btns.values():
		b.visible = gather
