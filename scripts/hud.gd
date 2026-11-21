class_name Hud
extends CanvasLayer
## Ressurslinje øverst og panel nederst for det som er valgt. Store knapper for fingre.

var main: Node

var top: PanelContainer
var wood_label: Label
var pop_label: Label
var idle_btn: Button

var bottom: PanelContainer
var info: Label
var train_btn: Button
var gather_btn: Button
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
	wood_label = _label(30)
	pop_label = _label(30)
	hb.add_child(wood_label)
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
	gather_btn = _button("Hogg tre", func() -> void: main.auto_gather_selected())
	clear_btn = _button("Fjern valg", func() -> void: main.clear_selection())
	bh.add_child(train_btn)
	bh.add_child(gather_btn)
	bh.add_child(clear_btn)

	hint = _label(24)
	hint.text = "Trykk på en arbeider og så på et tre.  Dra for å flytte kartet, knip for å zoome.\nHold fingeren stille og dra for å velge flere.  Dobbelttrykk på en arbeider velger alle på skjermen."
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

	wood_label.text = "Tre: %d" % main.wood
	pop_label.text = "Folk: %d/%d" % [main.workers.size(), main.POP_CAP]
	var idle: int = main.idle_workers().size()
	idle_btn.text = "Ledige: %d" % idle
	idle_btn.disabled = idle == 0

	var sel: Array = main.selected
	var town: TownCenter = main.town
	if not sel.is_empty():
		bottom.visible = true
		train_btn.visible = false
		gather_btn.visible = true
		var carrying := 0
		for w: Worker in sel:
			carrying += w.carry
		if sel.size() == 1:
			info.text = "Arbeider\nBærer %d/%d tre" % [carrying, Worker.CAPACITY]
		else:
			info.text = "%d arbeidere valgt\nBærer %d tre" % [sel.size(), carrying]
	elif town.selected:
		bottom.visible = true
		train_btn.visible = true
		gather_btn.visible = false
		var q := ""
		if town.queue > 0:
			q = "\nTrener: %d  (%d %%)" % [town.queue, int(town.progress * 100)]
		info.text = "Rådhus" + q
		train_btn.text = "Tren arbeider\n(%d tre)" % main.WORKER_COST
		train_btn.disabled = not main.can_train()
	else:
		bottom.visible = false
	# Panelet skal alltid sitte midt nede selv om innholdet endrer bredde
	bottom.reset_size()
	bottom.position.x = (bottom.get_viewport_rect().size.x - bottom.size.x) * 0.5
	bottom.position.y = bottom.get_viewport_rect().size.y - bottom.size.y - 8
