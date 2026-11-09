extends Node
## Профиль игрока (autoload «Profile»): монеты, кристаллы, кубки, облики, задания,
## путь славы, статистика и настройки. Хранится в user://profile.json.

const SAVE_PATH := "user://profile.json"

const SKINS := {
	"steel": {"name": "Сталь", "steel": Color(0.62, 0.64, 0.7), "dark": Color(0.36, 0.37, 0.42), "price": 0, "cur": "coins"},
	"bronze": {"name": "Бронза", "steel": Color(0.8, 0.55, 0.32), "dark": Color(0.48, 0.3, 0.17), "price": 150, "cur": "coins"},
	"obsidian": {"name": "Вороная сталь", "steel": Color(0.27, 0.27, 0.34), "dark": Color(0.13, 0.13, 0.18), "price": 300, "cur": "coins"},
	"gold": {"name": "Королевское золото", "steel": Color(1.0, 0.8, 0.32), "dark": Color(0.72, 0.5, 0.16), "price": 40, "cur": "gems"},
}
const SKIN_ORDER := ["steel", "bronze", "obsidian", "gold"]

const HEROES := {
	"knight": {"name": "Рыцарь", "role": "Боец с мечом", "hp": 0.8, "dmg": 0.6, "speed": 0.6,
		"super": "«Веер клинков» — 7 волн разом"},
	"archer": {"name": "Лучница", "role": "Стрелок издалека", "hp": 0.55, "dmg": 0.5, "speed": 0.75,
		"super": "«Стрела ветра» — пробивает всех насквозь"},
}
const HERO_ORDER := ["knight", "archer"]

const MODES := {
	"charge": {"name": "Зарядка", "desc": "Собирай кристаллы в центре и неси к своему знамени.", "trophies": 0},
	"brawl": {"name": "Схватка", "desc": "Командный бой: первыми одолей 10 вражеских рыцарей.", "trophies": 30},
	"flag": {"name": "Захват знамени", "desc": "Укради вражеское знамя и принеси домой.", "soon": true},
}
const MODE_ORDER := ["charge", "brawl", "flag"]

const ROAD := [
	{"t": 10, "coins": 40},
	{"t": 30, "gems": 5, "note": "Открывается «Схватка»"},
	{"t": 60, "coins": 80},
	{"t": 100, "skin": "bronze"},
	{"t": 150, "gems": 10},
	{"t": 200, "coins": 150},
	{"t": 300, "skin": "obsidian"},
	{"t": 400, "gems": 20},
	{"t": 500, "coins": 300},
	{"t": 700, "skin": "gold"},
]

const QUEST_POOL := [
	{"id": "crystals", "text": "Сдай %d кристаллов", "goal": [8, 16], "reward": 45},
	{"id": "wins", "text": "Победи в %d матчах", "goal": [1, 3], "reward": 60},
	{"id": "kos", "text": "Одолей %d рыцарей", "goal": [5, 12], "reward": 45},
	{"id": "supers", "text": "Используй супер %d раз", "goal": [3, 6], "reward": 35},
	{"id": "hits", "text": "Попади волной %d раз", "goal": [25, 50], "reward": 35},
	{"id": "matches", "text": "Сыграй %d матча", "goal": [2, 4], "reward": 30},
]

const CHESTS := {
	"wood": {"name": "Деревянный сундук", "desc": "Немного монет. Бесплатно раз в 4 часа.", "price": 0, "cur": "free"},
	"iron": {"name": "Железный сундук", "desc": "Много монет, иногда кристаллы.", "price": 100, "cur": "coins"},
	"royal": {"name": "Королевский сундук", "desc": "Гора монет, кристаллы и шанс на облик.", "price": 30, "cur": "gems"},
}
const FREE_CHEST_COOLDOWN := 4 * 3600

signal changed

var data := {}


func _ready() -> void:
	load_data()


func _defaults() -> Dictionary:
	return {
		"name": "Сэр Рыцарь",
		"coins": 60, "gems": 5, "trophies": 0, "best_trophies": 0,
		"skins": ["steel"], "skin": "steel", "hero": "knight",
		"mode": "charge",
		"stats": {"matches": 0, "wins": 0, "crystals": 0, "kos": 0},
		"quests": [], "quest_day": "",
		"road_claimed": [],
		"free_chest_at": 0.0,
		"settings": {"sound": true, "music": true, "shake": true},
	}


func load_data() -> void:
	data = _defaults()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				if parsed[k] is Dictionary and data.get(k) is Dictionary:
					for kk in parsed[k]:
						data[k][kk] = parsed[k][kk]
				else:
					data[k] = parsed[k]
	ensure_quests()


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	changed.emit()


func reset() -> void:
	data = _defaults()
	ensure_quests()
	save()


# ---------------------------------------------------------------- валюта

func amount(cur: String) -> int:
	return int(data.get(cur, 0))


func add(cur: String, n: int) -> void:
	data[cur] = amount(cur) + n
	save()


func spend(cur: String, price: int) -> bool:
	if cur == "free" or price <= 0:
		return true
	if amount(cur) < price:
		return false
	data[cur] = amount(cur) - price
	save()
	return true


# ---------------------------------------------------------------- облики и режимы

func skin_colors() -> Array:
	var s: Dictionary = SKINS.get(data.skin, SKINS["steel"])
	return [s.steel, s.dark]


func owns_skin(id: String) -> bool:
	return id in data.skins


func buy_skin(id: String) -> bool:
	if owns_skin(id):
		return true
	var s: Dictionary = SKINS[id]
	if not spend(s.cur, s.price):
		return false
	data.skins.append(id)
	data.skin = id
	save()
	return true


func wear_skin(id: String) -> void:
	if owns_skin(id):
		data.skin = id
		save()


func mode_unlocked(id: String) -> bool:
	var m: Dictionary = MODES[id]
	return not m.get("soon", false) and int(data.trophies) >= int(m.get("trophies", 0))


# ---------------------------------------------------------------- сундуки

func free_chest_left() -> int:
	return maxi(0, int(float(data.free_chest_at) + FREE_CHEST_COOLDOWN - Time.get_unix_time_from_system()))


func open_chest(kind: String) -> Dictionary:
	var c: Dictionary = CHESTS[kind]
	if kind == "wood":
		if free_chest_left() > 0:
			return {}
		data.free_chest_at = Time.get_unix_time_from_system()
	elif not spend(c.cur, c.price):
		return {}
	var r := {"coins": 0, "gems": 0, "skin": ""}
	match kind:
		"wood":
			r.coins = randi_range(15, 40)
		"iron":
			r.coins = randi_range(70, 170)
			if randf() < 0.35:
				r.gems = randi_range(2, 5)
		"royal":
			r.coins = randi_range(150, 320)
			r.gems = randi_range(4, 10)
			var missing := []
			for id in SKIN_ORDER:
				if not owns_skin(id):
					missing.append(id)
			if not missing.is_empty() and randf() < 0.3:
				r.skin = missing.pick_random()
				data.skins.append(r.skin)
	data.coins = amount("coins") + r.coins
	data.gems = amount("gems") + r.gems
	save()
	return r


# ---------------------------------------------------------------- задания

func seconds_to_midnight() -> int:
	var t := Time.get_time_dict_from_system()
	return 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))


func ensure_quests() -> void:
	var today := Time.get_date_string_from_system()
	if data.quest_day == today and data.quests.size() == 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today)
	var pool := QUEST_POOL.duplicate()
	var qs := []
	for i in 3:
		var q: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var goal := rng.randi_range(q.goal[0], q.goal[1])
		qs.append({"id": q.id, "text": q.text % goal, "goal": goal, "progress": 0,
			"reward": int(q.reward), "claimed": false})
	data.quests = qs
	data.quest_day = today
	save()


func progress(id: String, n := 1) -> void:
	ensure_quests()
	for q in data.quests:
		if q.id == id and not q.claimed:
			q.progress = mini(int(q.goal), int(q.progress) + n)


func quest_ready(i: int) -> bool:
	var q: Dictionary = data.quests[i]
	return not q.claimed and int(q.progress) >= int(q.goal)


func claim_quest(i: int) -> int:
	if not quest_ready(i):
		return 0
	var q: Dictionary = data.quests[i]
	q.claimed = true
	data.coins = amount("coins") + int(q.reward)
	save()
	return int(q.reward)


# ---------------------------------------------------------------- путь славы

func road_state(i: int) -> String:
	if i in data.road_claimed or float(i) in data.road_claimed:
		return "claimed"
	return "ready" if int(data.best_trophies) >= int(ROAD[i].t) else "locked"


func claim_road(i: int) -> Dictionary:
	if road_state(i) != "ready":
		return {}
	var r: Dictionary = ROAD[i]
	if r.has("coins"):
		data.coins = amount("coins") + int(r.coins)
	if r.has("gems"):
		data.gems = amount("gems") + int(r.gems)
	if r.has("skin") and not owns_skin(r.skin):
		data.skins.append(r.skin)
	data.road_claimed.append(i)
	save()
	return r


func road_ready_count() -> int:
	var n := 0
	for i in ROAD.size():
		if road_state(i) == "ready":
			n += 1
	return n


func quests_ready_count() -> int:
	var n := 0
	for i in data.quests.size():
		if quest_ready(i):
			n += 1
	return n


# ---------------------------------------------------------------- итог матча

## st: {"crystals", "kos", "hits", "supers"} игрока за матч.
func match_result(win: bool, st: Dictionary) -> Dictionary:
	var dt := 8 if win else -3
	var before := int(data.trophies)
	data.trophies = maxi(0, before + dt)
	data.best_trophies = maxi(int(data.best_trophies), int(data.trophies))
	var coins := (20 if win else 8) + int(st.get("kos", 0)) * 2 + int(st.get("crystals", 0))
	data.coins = amount("coins") + coins
	data.stats.matches = int(data.stats.matches) + 1
	data.stats.crystals = int(data.stats.crystals) + int(st.get("crystals", 0))
	data.stats.kos = int(data.stats.kos) + int(st.get("kos", 0))
	if win:
		data.stats.wins = int(data.stats.wins) + 1
		progress("wins")
	progress("matches")
	progress("crystals", int(st.get("crystals", 0)))
	progress("kos", int(st.get("kos", 0)))
	progress("hits", int(st.get("hits", 0)))
	progress("supers", int(st.get("supers", 0)))
	save()
	return {"trophies": int(data.trophies) - before, "coins": coins}
