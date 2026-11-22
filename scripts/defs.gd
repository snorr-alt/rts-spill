class_name Defs
## Alle tall for enheter og bygninger samlet på ett sted, så det er lett å justere balansen.
## Kostnad er en ordbok med ressurser. Tid er i sekunder. Rekkevidde er i ruter (0 = nærkamp).

const POP_MAX := 200
const RES_ORDER := ["wood", "food", "gold", "stone"]
const RES_NAMES := {"wood": "Tre", "food": "Mat", "gold": "Gull", "stone": "Stein"}

const UNITS := {
	"worker": {
		"name": "Arbeider", "cost": {"food": 50}, "time": 10.0,
		"hp": 25, "atk": 3, "range": 0.0, "cooldown": 1.5, "armor": 0, "speed": 80.0, "sight": 5.0,
		"vs_building": 1.0,
	},
	"sword": {
		"name": "Sverdmann", "cost": {"food": 60, "gold": 20}, "time": 13.0,
		"hp": 45, "atk": 6, "range": 0.0, "cooldown": 1.2, "armor": 1, "speed": 72.0, "sight": 6.0,
		"vs_building": 2.0,
	},
	"archer": {
		"name": "Bueskytter", "cost": {"wood": 25, "gold": 45}, "time": 13.0,
		"hp": 30, "atk": 4, "range": 4.5, "cooldown": 1.6, "armor": 0, "speed": 80.0, "sight": 7.0,
		"vs_building": 0.4,
	},
}

const BUILDINGS := {
	"town": {"name": "Rådhus", "size": 3, "hp": 2400, "cost": {}, "time": 60.0, "pop": 5, "trains": ["worker"]},
	"house": {"name": "Hus", "size": 2, "hp": 550, "cost": {"wood": 25}, "time": 15.0, "pop": 5, "trains": []},
	"barracks": {"name": "Brakker", "size": 3, "hp": 1200, "cost": {"wood": 175}, "time": 35.0, "pop": 0, "trains": ["sword", "archer"]},
}
## Hva arbeiderne kan bygge, i den rekkefølgen knappene vises
const BUILDABLE := ["house", "barracks"]

const TEAM_COLORS := [Color(0.20, 0.42, 0.92), Color(0.88, 0.20, 0.18)]
const TEAM_NAMES := ["Blå", "Rød"]

## Vanskelighetsgrader for fiende-AI-en
## gather: samlefart, first_attack: sekunder før første angrep, wave: soldater i første bølge
## (øker med 2 for hver bølge), extra: hvor mange flere soldater enn bølgen den holder hjemme,
## workers: maks arbeidere, mil_workers: arbeidere før den begynner med soldater
const DIFFICULTY := [
	{"name": "Lett", "gather": 0.8, "first_attack": 540.0, "wave": 3, "extra": 1, "workers": 14, "mil_workers": 10, "barracks": 1},
	{"name": "Normal", "gather": 1.0, "first_attack": 390.0, "wave": 5, "extra": 3, "workers": 18, "mil_workers": 12, "barracks": 1},
	{"name": "Vanskelig", "gather": 1.2, "first_attack": 270.0, "wave": 7, "extra": 6, "workers": 22, "mil_workers": 12, "barracks": 2},
]


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in RES_ORDER:
		if cost.has(k):
			parts.append("%d %s" % [cost[k], RES_NAMES[k].to_lower()])
	return ", ".join(parts)
