class_name Worker
extends Unit
## Landsbyarbeider. Kan samle tre, mat (bær og gårder), gull og stein, bære det til nærmeste
## leveringsplass (rådhus, sagbruk, gruveleir, mølle), bygge og angripe. Bærer bare én
## ressurstype om gangen. Når en ressurs er tom, finner den selv nærmeste av samme type.
## Mat hentes helst fra en ledig gård i nærheten, ellers fra bærbusker.

const CAPACITY := 10
## Sekunder per enhet for hver ressurstype
const RATE := {"wood": 0.6, "food": 0.55, "gold": 0.75, "stone": 0.8}
const CARRY_COLOR := {
	"wood": Color(0.55, 0.36, 0.18), "food": Color(0.85, 0.15, 0.25),
	"gold": Color(1.0, 0.82, 0.2), "stone": Color(0.8, 0.8, 0.78),
}

var target := Vector2i(-1, -1)  # ressursruta arbeideren jobber på
var kind := ""  # hva arbeideren samler (eller sist samlet)
var carry := 0
var carry_kind := ""
var farm: Building = null  # gården arbeideren jobber på
var _gather_t := 0.0


func _init() -> void:
	type = "worker"


func is_gathering() -> bool:
	return state in [S.TO_RES, S.GATHER, S.TO_TOWN]


func is_building() -> bool:
	return state in [S.TO_BUILD, S.BUILD]


## Slipp gården når arbeideren får en annen ordre
func _clear_targets() -> void:
	super._clear_targets()
	_release_farm()


func _release_farm() -> void:
	if farm != null and is_instance_valid(farm) and farm.farmer == self:
		farm.farmer = null
	farm = null


func _farm_ok() -> bool:
	return farm != null and is_instance_valid(farm) and not farm.dead and farm.complete and farm.food > 0 \
		and (farm.farmer == null or farm.farmer == self)


func cmd_farm(b: Building) -> void:
	_clear_targets()
	attack_move = false
	kind = "food"
	farm = b
	_go_to_farm()


func _go_to_farm() -> void:
	if not _farm_ok():
		farm = null
		_find_resource()
		return
	farm.farmer = self
	if _set_path_to_cell(map.tile_of(farm.center())):
		state = S.TO_RES
	else:
		_release_farm()
		state = S.IDLE


func die() -> void:
	_release_farm()
	super.die()


func cmd_gather(res_cell: Vector2i) -> void:
	if not map.is_resource(res_cell):
		return
	_clear_targets()
	attack_move = false
	target = res_cell
	kind = map.kind_at(res_cell)
	_go_to_target()


## Samle nærmeste ressurs av en type («Tre/Mat/Gull/Stein»-knappene og nye arbeidere)
func cmd_auto_gather(what := "") -> void:
	_clear_targets()
	attack_move = false
	if what != "":
		kind = what
	if kind == "":
		kind = "wood"
	target = Vector2i(-1, -1)
	_find_resource()


func cmd_return() -> void:
	_clear_targets()
	if carry > 0:
		_go_town()
	else:
		var t := _dropsite("food")
		if t != null:
			cmd_move(t.center() + Vector2(0, GameMap.TILE * 2.2))


func cmd_build(b: Building) -> void:
	_clear_targets()
	attack_move = false
	target_building = b
	if b.complete or b.dead:
		state = S.IDLE
		return
	if _near_building(b):
		state = S.BUILD
	elif _set_path_to_rect(b.rect()):
		state = S.TO_BUILD
	else:
		state = S.IDLE


## Nærmeste bygning som tar imot ressursen
func _dropsite(what: String) -> Building:
	var best: Building = null
	var best_d := INF
	for b in player.buildings:
		if b.accepts(what):
			var d := position.distance_squared_to(b.center())
			if d < best_d:
				best_d = d
				best = b
	return best


func _near_building(b: Building) -> bool:
	return b.distance_to(position) <= BUILDING_REACH


func _target_ok() -> bool:
	if farm != null:
		return _farm_ok()
	return kind != "" and map.kind_at(target) == kind


func _go_to_target() -> void:
	if farm != null:
		_go_to_farm()
		return
	if not _set_path_to_rect(Rect2i(target, Vector2i.ONE)):
		_find_resource()
		return
	state = S.TO_RES


const KIND_TILE := {"wood": GameMap.T.TREE, "food": GameMap.T.BERRY, "gold": GameMap.T.GOLD, "stone": GameMap.T.STONE}


func _find_resource() -> void:
	if kind == "food":
		var f := _free_farm()
		if f != null:
			farm = f
			_go_to_farm()
			return
	farm = null
	var r := map.nearest_adjacent_tile(_start_cell(), KIND_TILE[kind])
	if r.is_empty() or not _set_path_to_cell(r.goal):
		if carry > 0:
			_go_town()
		else:
			state = S.IDLE
		return
	target = r.target
	state = S.TO_RES


## Nærmeste ledige, ferdige gård innen 14 ruter
func _free_farm() -> Building:
	var best: Building = null
	var best_d := (14.0 * GameMap.TILE) ** 2
	for b in player.buildings:
		if b.type == "farm" and b.complete and not b.dead and b.food > 0 and (b.farmer == null or b.farmer == self):
			var d := position.distance_squared_to(b.center())
			if d < best_d:
				best_d = d
				best = b
	return best


func _go_town() -> void:
	var t := _dropsite(carry_kind if carry_kind != "" else kind)
	if t == null or not _set_path_to_rect(t.rect()):
		state = S.IDLE
		return
	target_building = t
	state = S.TO_TOWN


func _adjacent_to(c: Vector2i) -> bool:
	var d := cell() - c
	return maxi(absi(d.x), absi(d.y)) <= 1


func _worker_state(delta: float) -> void:
	match state:
		S.TO_RES:
			if _follow(delta):
				var arrived := (_farm_ok() and farm.contains(position)) if farm != null else (_target_ok() and _adjacent_to(target))
				if arrived:
					# Bytter arbeideren ressurstype, mister den det den bar (som i Age of Empires)
					if carry_kind != kind:
						carry = 0
						carry_kind = kind
					state = S.GATHER
					_gather_t = 0.0
				else:
					_find_resource()
		S.GATHER:
			_gather(delta)
		S.TO_TOWN:
			if _follow(delta):
				var t := target_building
				if t != null and is_instance_valid(t) and not t.dead and _near_building(t):
					if carry > 0:
						player.res[carry_kind] += carry
						player.stats.gathered += carry
						carry = 0
					target_building = null
					if _target_ok():
						_go_to_target()
					else:
						_find_resource()
				else:
					_go_town()
		S.TO_BUILD:
			var b := target_building
			if b == null or not is_instance_valid(b) or b.dead or b.complete:
				_after_build()
			elif _follow(delta) or _near_building(b):
				if _near_building(b):
					state = S.BUILD
				elif not _set_path_to_rect(b.rect()):
					_after_build()
		S.BUILD:
			var b := target_building
			if b == null or not is_instance_valid(b) or b.dead or b.complete:
				_after_build()
				return
			facing = (b.center() - position).normalized()
			if b.build(delta):
				_after_build()


func _gather(delta: float) -> void:
	if not _target_ok():
		if carry < CAPACITY:
			_find_resource()
		else:
			_go_town()
		return
	var spot := farm.center() + Vector2(sin(_anim * 0.7) * 14.0, 6.0) if farm != null else map.center_of(target)
	facing = (spot - position).normalized() if spot.distance_to(position) > 1.0 else facing
	_gather_t += delta * player.gather_mult
	if _gather_t < RATE[kind]:
		return
	_gather_t = 0.0
	carry += farm.take_food() if farm != null else map.take(target)
	if carry >= CAPACITY:
		_go_town()
	elif not _target_ok():
		_find_resource()


## Når bygningen er ferdig: en ny gård blir dyrket av den som bygde den. Ellers hjelp til
## med en annen byggeplass i nærheten, eller samle igjen.
func _after_build() -> void:
	var built := target_building
	target_building = null
	if built != null and is_instance_valid(built) and built.type == "farm" and built.complete and built.farmer == null:
		cmd_farm(built)
		return
	for b in player.buildings:
		if not b.complete and not b.dead and b.distance_to(position) < GameMap.TILE * 8:
			cmd_build(b)
			return
	if kind != "":
		cmd_auto_gather()
	else:
		state = S.IDLE


func _after_fight() -> void:
	state = S.IDLE


func _draw_body(o: Vector2) -> void:
	# Lasten på ryggen i ressursens farge
	if carry > 0:
		var h := 2.0 + 8.0 * carry / CAPACITY
		var col: Color = CARRY_COLOR.get(carry_kind, Color.WHITE)
		draw_rect(Rect2(o + Vector2(-10, 2 - h), Vector2(6, h)), col)
		draw_rect(Rect2(o + Vector2(-10, 2 - h), Vector2(6, h)), col.darkened(0.4), false, 1.0)
	draw_circle(o, 6.0, player.color)
	draw_circle(o + Vector2(0, -7), 4.0, Color(0.93, 0.78, 0.62))
	var working := state == S.GATHER or state == S.BUILD or (state == S.ATTACK and _path.is_empty())
	if not working:
		return
	# Verktøyet svinger: øks for tre, hakke for gull og stein, hånd for bær, hammer for bygging
	var dir := facing
	var hand := o + Vector2(0, -2)
	if state == S.GATHER and kind == "food":
		var reach := hand + dir * (6.0 + 3.0 * absf(sin(_anim * 6.0)))
		draw_line(hand, reach, Color(0.93, 0.78, 0.62), 2.5)
		return
	var tip := hand + dir.rotated(sin(_anim * 10.0) * 0.9) * 11.0
	draw_line(hand, tip, Color(0.45, 0.30, 0.15), 2.0)
	if state == S.GATHER and kind == "wood":
		draw_circle(tip, 2.5, Color(0.75, 0.75, 0.8))
	elif state == S.BUILD:
		draw_rect(Rect2(tip - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 0.5, 0.55))
	else:
		var side := (tip - hand).normalized().orthogonal() * 4.0
		draw_line(tip - side, tip + side, Color(0.6, 0.6, 0.65), 2.5)
