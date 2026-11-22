class_name Defs
## Alle tall for enheter, bygninger og tidsaldre samlet på ett sted, så det er lett å justere balansen.
## Kostnad er en ordbok med ressurser. Tid er i sekunder. Rekkevidde er i ruter (0 = nærkamp).
##
## Enhetsklasser og styrketrekanten (som i Age of Empires):
##   bueskytter ("arch") slår fotfolk ("inf"), rytter ("cav") slår bueskytter, spydmann slår rytter.
## «armor» tar av for nærkampslag, «parmor» for piler. «bonus» er ekstra skade mot en klasse.

const POP_MAX := 200
const RES_ORDER := ["wood", "food", "gold", "stone"]
const RES_NAMES := {"wood": "Tre", "food": "Mat", "gold": "Gull", "stone": "Stein"}

const AGES := ["Mørketid", "Føydaltid"]

const UNITS := {
	"worker": {
		"name": "Arbeider", "class": "worker", "cost": {"food": 50}, "time": 10.0, "age": 0,
		"hp": 25, "atk": 3, "range": 0.0, "cooldown": 1.5, "armor": 0, "parmor": 0, "speed": 80.0, "sight": 5.0,
		"vs_building": 1.0, "bonus": {},
	},
	"sword": {
		"name": "Sverdmann", "class": "inf", "cost": {"food": 60, "gold": 20}, "time": 13.0, "age": 0,
		"hp": 45, "atk": 6, "range": 0.0, "cooldown": 1.2, "armor": 1, "parmor": 1, "speed": 72.0, "sight": 6.0,
		"vs_building": 2.0, "bonus": {},
	},
	"spear": {
		"name": "Spydmann", "class": "inf", "cost": {"food": 35, "wood": 25}, "time": 11.0, "age": 1,
		"hp": 45, "atk": 3, "range": 0.0, "cooldown": 1.5, "armor": 0, "parmor": 0, "speed": 74.0, "sight": 6.0,
		"vs_building": 1.0, "bonus": {"cav": 12},
	},
	"archer": {
		"name": "Bueskytter", "class": "arch", "cost": {"wood": 25, "gold": 45}, "time": 13.0, "age": 1,
		"hp": 30, "atk": 4, "range": 4.5, "cooldown": 1.6, "armor": 0, "parmor": 0, "speed": 80.0, "sight": 7.0,
		"vs_building": 0.4, "bonus": {"inf": 2},
	},
	"scout": {
		"name": "Speider", "class": "cav", "cost": {"food": 80}, "time": 15.0, "age": 1,
		"hp": 45, "atk": 4, "range": 0.0, "cooldown": 1.5, "armor": 0, "parmor": 2, "speed": 125.0, "sight": 10.0,
		"vs_building": 0.5, "bonus": {"arch": 3},
	},
	"knight": {
		"name": "Ridder", "class": "cav", "cost": {"food": 60, "gold": 75}, "time": 22.0, "age": 1,
		"hp": 100, "atk": 10, "range": 0.0, "cooldown": 1.8, "armor": 2, "parmor": 2, "speed": 105.0, "sight": 6.0,
		"vs_building": 1.0, "bonus": {"arch": 4},
	},
}

## Forskning (i dag bare tidsalderen). Settes i kø i en bygning som en enhet.
const TECHS := {
	"feudal": {"name": "Føydaltid", "cost": {"food": 500}, "time": 60.0, "age": 0, "gives_age": 1},
}

## drop: hvilke ressurser som kan leveres der. walkable: kan gås over (gården).
## requires: bygninger som må stå ferdig først. age: tidsalderen som trengs.
const BUILDINGS := {
	"town": {"name": "Rådhus", "size": 3, "hp": 2400, "cost": {}, "time": 60.0, "pop": 5, "age": 0,
		"trains": ["worker", "feudal"], "drop": ["wood", "food", "gold", "stone"]},
	"house": {"name": "Hus", "size": 2, "hp": 550, "cost": {"wood": 25}, "time": 15.0, "pop": 5, "age": 0, "trains": []},
	"lumber": {"name": "Sagbruk", "size": 2, "hp": 600, "cost": {"wood": 100}, "time": 20.0, "pop": 0, "age": 0,
		"trains": [], "drop": ["wood"]},
	"mining": {"name": "Gruveleir", "size": 2, "hp": 600, "cost": {"wood": 100}, "time": 20.0, "pop": 0, "age": 0,
		"trains": [], "drop": ["gold", "stone"]},
	"mill": {"name": "Mølle", "size": 2, "hp": 600, "cost": {"wood": 100}, "time": 20.0, "pop": 0, "age": 0,
		"trains": [], "drop": ["food"]},
	"farm": {"name": "Gård", "size": 2, "hp": 300, "cost": {"wood": 60}, "time": 10.0, "pop": 0, "age": 0,
		"trains": [], "walkable": true, "food": 250, "requires": ["mill"]},
	"barracks": {"name": "Brakker", "size": 3, "hp": 1200, "cost": {"wood": 175}, "time": 35.0, "pop": 0, "age": 0,
		"trains": ["sword", "spear"]},
	"range": {"name": "Skytebane", "size": 3, "hp": 1200, "cost": {"wood": 175}, "time": 35.0, "pop": 0, "age": 1,
		"trains": ["archer"], "requires": ["barracks"]},
	"stable": {"name": "Stall", "size": 3, "hp": 1200, "cost": {"wood": 175}, "time": 35.0, "pop": 0, "age": 1,
		"trains": ["scout", "knight"], "requires": ["barracks"]},
	"tower": {"name": "Tårn", "size": 1, "hp": 700, "cost": {"wood": 25, "stone": 125}, "time": 40.0, "pop": 0, "age": 1,
		"trains": [], "atk": 5, "range": 7.0, "cooldown": 2.0, "sight": 9.0, "bonus": {}},
}
## Byggemenyen har to sider, i denne rekkefølgen
const BUILD_ECO := ["house", "lumber", "mining", "mill", "farm"]
const BUILD_MIL := ["barracks", "range", "stable", "tower"]
## Føydaltid krever to ulike av disse bygningene (som i Age of Empires II)
const FEUDAL_NEEDS := ["lumber", "mining", "mill", "barracks"]

const TEAM_COLORS := [Color(0.20, 0.42, 0.92), Color(0.88, 0.20, 0.18)]
const TEAM_NAMES := ["Blå", "Rød"]

## Vanskelighetsgrader for fiende-AI-en
## gather: samlefart, first_attack: sekunder før første angrep, wave: soldater i første bølge
## (øker med 2 for hver bølge), extra: hvor mange flere soldater enn bølgen den holder hjemme,
## workers: maks arbeidere, mil_workers: arbeidere før den begynner med soldater,
## feudal_workers: arbeidere før den går opp i føydaltid, towers: tårn den bygger
const DIFFICULTY := [
	{"name": "Lett", "gather": 0.8, "first_attack": 540.0, "wave": 3, "extra": 1, "workers": 16, "mil_workers": 10,
		"barracks": 1, "feudal_workers": 14, "towers": 0, "stable": false},
	{"name": "Normal", "gather": 1.0, "first_attack": 420.0, "wave": 5, "extra": 3, "workers": 22, "mil_workers": 12,
		"barracks": 1, "feudal_workers": 16, "towers": 1, "stable": true},
	{"name": "Vanskelig", "gather": 1.2, "first_attack": 300.0, "wave": 7, "extra": 6, "workers": 26, "mil_workers": 12,
		"barracks": 2, "feudal_workers": 16, "towers": 2, "stable": true},
]


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in RES_ORDER:
		if cost.has(k):
			parts.append("%d %s" % [cost[k], RES_NAMES[k].to_lower()])
	return ", ".join(parts)


## Enhet eller forskning – samme oppslag for begge, så bygningskøen kan holde begge deler
static func item(id: String) -> Dictionary:
	return UNITS[id] if UNITS.has(id) else TECHS[id]


static func is_tech(id: String) -> bool:
	return TECHS.has(id)


## Skade fra en angriper (enhet eller tårn) mot en enhet: angrep + bonus – rustning, minst 1
static func damage(attacker: Dictionary, target: Dictionary) -> float:
	var atk: float = attacker.atk + attacker.get("bonus", {}).get(target["class"], 0)
	var arm: float = target.parmor if attacker.get("range", 0.0) > 0.0 else target.armor
	return maxf(1.0, atk - arm)
