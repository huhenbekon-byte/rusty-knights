extends Node
## Профиль игрока (autoload «Profile»): монеты, кристаллы, кубки, облики, задания,
## путь славы, статистика и настройки. Хранится в user://profile.json.

const SAVE_PATH := "user://profile.json"

## Облики: у каждого героя 4, свои цвета и небольшой бонус (только для игрока).
## bonus: hp / dmg / speed — доля прибавки (0.06 = +6%).
const SKINS := {
	"knight": {
		"steel": {"name": "Сталь", "price": 0, "cur": "coins", "bonus": {},
			"cols": {"steel": Color(0.62, 0.64, 0.7), "dark": Color(0.36, 0.37, 0.42)}},
		"bronze": {"name": "Бронза", "price": 150, "cur": "coins", "bonus": {"hp": 0.08},
			"cols": {"steel": Color(0.8, 0.55, 0.32), "dark": Color(0.48, 0.3, 0.17)}},
		"obsidian": {"name": "Вороная сталь", "price": 300, "cur": "coins", "bonus": {"speed": 0.06},
			"cols": {"steel": Color(0.27, 0.27, 0.34), "dark": Color(0.13, 0.13, 0.18)}},
		"gold": {"name": "Королевское золото", "price": 40, "cur": "gems", "bonus": {"dmg": 0.06, "hp": 0.05},
			"cols": {"steel": Color(1.0, 0.8, 0.32), "dark": Color(0.72, 0.5, 0.16)}},
	},
	"archer": {
		"forest": {"name": "Лесная", "price": 0, "cur": "coins", "bonus": {},
			"cols": {"tunic": Color(0.32, 0.58, 0.24), "trim": Color(1.0, 0.78, 0.3), "leather": Color(0.44, 0.27, 0.15)}},
		"snow": {"name": "Снежная", "price": 150, "cur": "coins", "bonus": {"speed": 0.06},
			"cols": {"tunic": Color(0.88, 0.92, 0.97), "trim": Color(0.72, 0.8, 0.92), "leather": Color(0.55, 0.45, 0.4)}},
		"night": {"name": "Ночная", "price": 300, "cur": "coins", "bonus": {"dmg": 0.06},
			"cols": {"tunic": Color(0.2, 0.18, 0.28), "trim": Color(0.72, 0.45, 1.0), "leather": Color(0.18, 0.14, 0.18)}},
		"royal": {"name": "Королевская", "price": 40, "cur": "gems", "bonus": {"dmg": 0.05, "hp": 0.05},
			"cols": {"tunic": Color(0.6, 0.12, 0.2), "trim": Color(1.0, 0.8, 0.3), "leather": Color(0.38, 0.2, 0.12)}},
	},
	"hammer": {
		"iron": {"name": "Железо", "price": 0, "cur": "coins", "bonus": {},
			"cols": {"steel": Color(0.4, 0.42, 0.5), "dark": Color(0.25, 0.26, 0.32), "fur": Color(0.88, 0.8, 0.64)}},
		"copper": {"name": "Медь", "price": 150, "cur": "coins", "bonus": {"hp": 0.08},
			"cols": {"steel": Color(0.74, 0.46, 0.28), "dark": Color(0.45, 0.26, 0.16), "fur": Color(0.6, 0.42, 0.28)}},
		"frost": {"name": "Ледяной", "price": 300, "cur": "coins", "bonus": {"speed": 0.06},
			"cols": {"steel": Color(0.72, 0.86, 0.96), "dark": Color(0.36, 0.5, 0.66), "fur": Color(0.97, 0.98, 1.0)}},
		"king": {"name": "Золотой король", "price": 40, "cur": "gems", "bonus": {"dmg": 0.06, "hp": 0.05},
			"cols": {"steel": Color(1.0, 0.8, 0.32), "dark": Color(0.62, 0.42, 0.14), "fur": Color(0.5, 0.15, 0.18)}},
	},
	"mage": {
		"apprentice": {"name": "Ученик", "price": 0, "cur": "coins", "bonus": {},
			"cols": {"trim": Color(0.92, 0.84, 0.58), "orb": Color(1.0, 0.55, 0.15)}},
		"flame": {"name": "Пламя", "price": 150, "cur": "coins", "bonus": {"dmg": 0.06},
			"cols": {"trim": Color(1.0, 0.45, 0.15), "orb": Color(1.0, 0.3, 0.08)}},
		"frost": {"name": "Иней", "price": 300, "cur": "coins", "bonus": {"hp": 0.08},
			"cols": {"trim": Color(0.62, 0.86, 1.0), "orb": Color(0.45, 0.82, 1.0)}},
		"star": {"name": "Звездочёт", "price": 40, "cur": "gems", "bonus": {"dmg": 0.05, "speed": 0.05},
			"cols": {"trim": Color(0.78, 0.62, 1.0), "orb": Color(0.82, 0.6, 1.0)}},
	},
}
const SKIN_ORDER := {
	"knight": ["steel", "bronze", "obsidian", "gold"],
	"archer": ["forest", "snow", "night", "royal"],
	"hammer": ["iron", "copper", "frost", "king"],
	"mage": ["apprentice", "flame", "frost", "star"],
}

const HEROES := {
	"knight": {"name": "Рыцарь", "role": "Боец с мечом", "hp": 0.8, "dmg": 0.6, "speed": 0.6,
		"super": "«Веер клинков» — 7 волн разом"},
	"archer": {"name": "Лучница", "role": "Стрелок издалека", "hp": 0.55, "dmg": 0.5, "speed": 0.75,
		"super": "«Стрела ветра» — пробивает всех насквозь"},
	"hammer": {"name": "Молотобоец", "role": "Танк ближнего боя", "hp": 1.0, "dmg": 0.85, "speed": 0.4,
		"super": "«Удар по земле» — прыжок и удар по кругу"},
	"mage": {"name": "Маг", "role": "Огонь по площади", "hp": 0.6, "dmg": 0.7, "speed": 0.6,
		"super": "«Метеор» — взрыв по большой площади"},
}
const HERO_ORDER := ["knight", "archer", "hammer", "mage"]

const MODES := {
	"charge": {"name": "Казна", "desc": "Собирай бронзовые монеты в центре и неси в казну у знамени.", "trophies": 0},
	"brawl": {"name": "Схватка", "desc": "Командный бой: первыми одолей 10 вражеских рыцарей.", "trophies": 30},
	"flag": {"name": "Захват знамени", "desc": "Укради вражеское знамя и принеси к своему. До 3 очков.", "trophies": 60},
}
const MODE_ORDER := ["charge", "brawl", "flag"]

const ROAD := [
	{"t": 10, "coins": 40},
	{"t": 30, "gems": 5, "note": "Открывается «Схватка»"},
	{"t": 60, "coins": 80, "note": "Открывается «Захват знамени»"},
	{"t": 100, "skin": "bronze", "hero": "knight"},
	{"t": 150, "gems": 10},
	{"t": 200, "skin": "snow", "hero": "archer"},
	{"t": 300, "skin": "copper", "hero": "hammer"},
	{"t": 400, "gems": 20},
	{"t": 500, "skin": "flame", "hero": "mage"},
	{"t": 700, "coins": 400},
]

const QUEST_POOL := [
	{"id": "crystals", "text": "Сдай %d бронзовых монет", "goal": [8, 16], "reward": 45},
	{"id": "wins", "text": "Победи в %d матчах", "goal": [1, 3], "reward": 60},
	{"id": "kos", "text": "Одолей %d рыцарей", "goal": [5, 12], "reward": 45},
	{"id": "supers", "text": "Используй супер %d раз", "goal": [3, 6], "reward": 35},
	{"id": "hits", "text": "Попади по врагам %d раз", "goal": [25, 50], "reward": 35},
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
		"skins": {"knight": ["steel"], "archer": ["forest"], "hammer": ["iron"], "mage": ["apprentice"]},
		"skin": {"knight": "steel", "archer": "forest", "hammer": "iron", "mage": "apprentice"},
		"hero": "knight",
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
				elif k == "skins" and parsed[k] is Array:          # старый формат: только рыцарь
					data.skins["knight"] = parsed[k]
				elif k == "skin" and parsed[k] is String:
					data.skin["knight"] = parsed[k]
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

func default_skin(hero: String) -> String:
	return SKIN_ORDER[hero][0]


func skin_of(hero: String) -> String:
	var id := str(data.skin.get(hero, default_skin(hero)))
	return id if SKINS[hero].has(id) else default_skin(hero)


func skin_def(hero: String, id: String) -> Dictionary:
	return SKINS.get(hero, SKINS["knight"]).get(id, SKINS[hero][default_skin(hero)])


## Главный цвет облика — для иконок в меню.
func skin_tint(hero: String, id := "") -> Color:
	var c: Dictionary = skin_def(hero, id if id != "" else skin_of(hero)).cols
	for key in ["steel", "tunic", "trim"]:
		if c.has(key):
			return c[key]
	return Color.WHITE


func skin_colors() -> Array:
	return [skin_tint("knight")]


## Текст бонуса облика: «+8% здоровья» и т. п.
func bonus_text(hero: String, id: String) -> String:
	var b: Dictionary = skin_def(hero, id).get("bonus", {})
	var parts := []
	for key in ["hp", "dmg", "speed"]:
		if b.has(key):
			parts.append("+%d%% %s" % [int(round(float(b[key]) * 100.0)), {"hp": "здоровья", "dmg": "урона", "speed": "скорости"}[key]])
	return "без бонуса" if parts.is_empty() else ", ".join(parts)


func owns_skin(hero: String, id: String) -> bool:
	return id in data.skins.get(hero, [])


func _give_skin(hero: String, id: String) -> void:
	if not data.skins.has(hero):
		data.skins[hero] = [default_skin(hero)]
	if not owns_skin(hero, id):
		data.skins[hero].append(id)


func buy_skin(hero: String, id: String) -> bool:
	if owns_skin(hero, id):
		return true
	var s: Dictionary = SKINS[hero][id]
	if not spend(s.cur, int(s.price)):
		return false
	_give_skin(hero, id)
	data.skin[hero] = id
	save()
	return true


func wear_skin(hero: String, id: String) -> void:
	if owns_skin(hero, id):
		data.skin[hero] = id
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
	var r := {"coins": 0, "gems": 0, "skin": "", "skin_hero": ""}
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
			for h in SKIN_ORDER:
				for id in SKIN_ORDER[h]:
					if not owns_skin(h, id):
						missing.append([h, id])
			if not missing.is_empty() and randf() < 0.3:
				var pick: Array = missing.pick_random()
				_give_skin(pick[0], pick[1])
				r.skin = pick[1]
				r.skin_hero = pick[0]
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
	if r.has("skin"):
		_give_skin(r.get("hero", "knight"), r.skin)
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
