class_name Player
extends RefCounted
## Én spiller (lag): ressurser, enheter og bygninger. Lag 0 er deg, lag 1 er fienden.

var team := 0
var color := Color.WHITE
var is_ai := false
var res := {"wood": 200, "food": 200, "gold": 100, "stone": 200}
var units: Array[Unit] = []
var buildings: Array[Building] = []
var gather_mult := 1.0
var defeated := false
var age := 0  # 0 = mørketid, 1 = føydaltid
## Statistikk (brukes i testen og på sluttskjermen). «types» teller trente enheter per type.
var stats := {"gathered": 0, "trained": 0, "built": 0, "kills": 0, "lost": 0, "types": {}}


func _init(t: int) -> void:
	team = t
	color = Defs.TEAM_COLORS[t]


func can_afford(cost: Dictionary) -> bool:
	for k: String in cost:
		if res[k] < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k: String in cost:
		res[k] -= cost[k]
	return true


func refund(cost: Dictionary) -> void:
	for k: String in cost:
		res[k] += cost[k]


func pop() -> int:
	return units.size()


## Folk som er under trening teller også, så du ikke kan sette flere i kø enn det er plass til
func pop_with_queue() -> int:
	var n := units.size()
	for b in buildings:
		for q in b.queue:
			if not Defs.is_tech(q):
				n += 1
	return n


func pop_cap() -> int:
	var cap := 0
	for b in buildings:
		if b.complete:
			cap += b.def.pop
	return mini(cap, Defs.POP_MAX)


func town() -> Building:
	for b in buildings:
		if b.type == "town":
			return b
	return null


func count_units(type: String) -> int:
	var n := 0
	for u in units:
		if u.type == type:
			n += 1
	return n


func count_buildings(type: String, include_unfinished := true) -> int:
	var n := 0
	for b in buildings:
		if b.type == type and (include_unfinished or b.complete):
			n += 1
	return n


func military() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.type != "worker":
			out.append(u)
	return out


func workers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.type == "worker":
			out.append(u)
	return out


func has_complete(type: String) -> bool:
	for b in buildings:
		if b.type == type and b.complete and not b.dead:
			return true
	return false


## Hvorfor en bygning ikke kan bygges ennå ("" hvis den kan)
func build_block_reason(type: String) -> String:
	var d: Dictionary = Defs.BUILDINGS[type]
	if age < d.age:
		return Defs.AGES[d.age]
	for need: String in d.get("requires", []):
		if not has_complete(need):
			return "Krever " + Defs.BUILDINGS[need].name.to_lower()
	return ""


## Er tidsalderen allerede forsket på eller i kø?
func researching(tech: String) -> bool:
	for b in buildings:
		if tech in b.queue:
			return true
	return false


## Hvorfor føydaltid ikke kan forskes ennå ("" hvis den kan)
func feudal_block_reason() -> String:
	if age >= 1 or researching("feudal"):
		return "Ferdig" if age >= 1 else "Forskes"
	var kinds := 0
	for t: String in Defs.FEUDAL_NEEDS:
		if has_complete(t):
			kinds += 1
	if kinds < 2:
		return "Krever 2 av: sagbruk, gruveleir, mølle, brakker"
	return ""


func count_class(cls: String) -> int:
	var n := 0
	for u in units:
		if u.def["class"] == cls:
			n += 1
	return n
