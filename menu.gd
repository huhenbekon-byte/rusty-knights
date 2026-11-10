extends Control
## Главное меню: верхняя панель (настройки, профиль, монеты, кристаллы),
## вкладки снизу (Магазин, Задания, Арена, Герои, Кубки), всплывающие окна.

const IconScript = preload("res://icon.gd")
const KnightScript = preload("res://knight.gd")

const GOLD := Color(1.0, 0.78, 0.28)
const NAVY := Color(0.11, 0.12, 0.25)
const NAVY2 := Color(0.18, 0.2, 0.38)
const INK := Color(0.06, 0.05, 0.1)
const TABS := [
	["shop", "chest", "Магазин"], ["quests", "scroll", "Задания"], ["home", "swords", "Арена"],
	["heroes", "helm", "Герои"], ["road", "trophy", "Кубки"]]

var main
var page := "home"
var _content: Control
var _page_node: Control
var _nav := {}
var _badges := {}
var _coins_lbl: Label
var _gems_lbl: Label
var _troph_lbl: Label
var _name_lbl: Label
var _profile_helm
var _popups: Control
var _tick := 0.0
var _timer_labels: Array = []      # [[Label, Callable -> String]]
var _preview_pivot: Node3D
var _preview_skin := ""       # облик, который примеряют на витрине


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	var th := Theme.new()
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.75
	th.default_font = fv
	th.default_font_size = 28
	theme = th

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.13, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	add_child(dim)

	_content = Control.new()
	_content.anchor_right = 1.0
	_content.anchor_bottom = 1.0
	_content.offset_top = 132
	_content.offset_bottom = -176
	add_child(_content)
	_build_top()
	_build_nav()
	_popups = Control.new()
	_popups.anchor_right = 1.0
	_popups.anchor_bottom = 1.0
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
	Profile.changed.connect(_refresh_top)
	_refresh_top()
	show_page("home")


func _process(delta: float) -> void:
	if _preview_pivot and is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y += delta * 0.8
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for t in _timer_labels:
			if is_instance_valid(t[0]):
				t[0].text = (t[1] as Callable).call()


# ================================================================ детали интерфейса

func _sb(bg: Color, border := INK, bw := 5, radius := 22, shadow := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb


func _panel(parent: Control, rect: Rect2, bg := NAVY, border := INK, bw := 5) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, bw))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p


func _lbl(parent: Control, text: String, size: int, color := Color.WHITE, rect := Rect2(),
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rect.size != Vector2.ZERO:
		l.position = rect.position
		l.size = rect.size
	parent.add_child(l)
	return l


func _icon(parent: Control, kind: String, rect: Rect2, tint := Color.WHITE) -> Control:
	var ic = IconScript.new()
	ic.kind = kind
	ic.tint = tint
	ic.position = rect.position
	ic.size = rect.size
	parent.add_child(ic)
	return ic


func _btn(parent: Control, text: String, color: Color, rect: Rect2, font := 34) -> Button:
	var b: Button = main._make_button(text, color, font)
	b.position = rect.position
	b.size = rect.size
	parent.add_child(b)
	return b


## Кнопка с ценой: иконка валюты + число.
func _price_btn(parent: Control, cur: String, price: int, rect: Rect2, color := Color(0.3, 0.7, 0.35)) -> Button:
	var b := _btn(parent, "", color, rect, 32)
	if cur == "free":
		b.text = "БЕСПЛАТНО"
		b.add_theme_font_size_override("font_size", 26)
		return b
	var w := rect.size.x
	_icon(b, "coin" if cur == "coins" else "gem", Rect2(w * 0.5 - 62, rect.size.y / 2 - 20, 40, 40))
	_lbl(b, str(price), 32, Color.WHITE, Rect2(w * 0.5 - 18, 0, 90, rect.size.y), HORIZONTAL_ALIGNMENT_LEFT)
	return b


func _ribbon(parent: Control, text: String, y := 0.0, sub := "") -> void:
	var w := 520.0
	var x := (parent.size.x - w) / 2.0 if parent.size.x > 0 else 100.0
	var p := _panel(parent, Rect2(x, y, w, 76 if sub == "" else 96), NAVY2, GOLD, 5)
	_lbl(p, text, 40, Color(1, 0.95, 0.8), Rect2(0, 4, w, 56))
	if sub != "":
		_lbl(p, sub, 22, Color(0.75, 0.75, 0.95), Rect2(0, 56, w, 30))


func _bar(parent: Control, rect: Rect2, value: float, color := Color(0.4, 0.9, 0.45)) -> void:
	var bg := _panel(parent, rect, Color(0.05, 0.05, 0.1), INK, 3)
	var f := Panel.new()
	f.add_theme_stylebox_override("panel", _sb(color, Color(0, 0, 0, 0), 0, 10, 0))
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.position = Vector2(4, 4)
	f.size = Vector2(maxf(0.0, (rect.size.x - 8) * clampf(value, 0.0, 1.0)), rect.size.y - 8)
	bg.add_child(f)


func _scroll(parent: Control, rect: Rect2) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.position = rect.position
	sc.size = rect.size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.scroll_deadzone = 12
	parent.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.custom_minimum_size.x = rect.size.x
	sc.add_child(vb)
	return vb


func _card(vb: VBoxContainer, h: float, bg := NAVY, border := INK, bw := 5) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(vb.custom_minimum_size.x, h)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(holder)
	var p := _panel(holder, Rect2(10, 0, vb.custom_minimum_size.x - 20, h), bg, border, bw)
	return p


func _toast(text: String, color := Color(1, 0.6, 0.5)) -> void:
	var vs := get_viewport_rect().size
	var l := _lbl(self, text, 30, color, Rect2(0, 0, vs.x, 60))
	l.position.y = vs.y * 0.42
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 80, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)


func _fmt_time(sec: int) -> String:
	return "%d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]


# ================================================================ верхняя панель

func _build_top() -> void:
	var top := Control.new()
	top.anchor_right = 1.0
	top.offset_bottom = 124
	add_child(top)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.16, 0.9)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bg)

	var gear := _btn(top, "", NAVY2, Rect2(14, 18, 92, 92))
	_icon(gear, "gear", Rect2(14, 14, 64, 64))
	gear.pressed.connect(_open_settings)

	var prof := _btn(top, "", NAVY2, Rect2(116, 18, 284, 92))
	_profile_helm = _icon(prof, "helm", Rect2(12, 12, 66, 66))
	_name_lbl = _lbl(prof, "", 26, Color.WHITE, Rect2(86, 8, 190, 40), HORIZONTAL_ALIGNMENT_LEFT)
	_icon(prof, "trophy", Rect2(86, 50, 32, 32))
	_troph_lbl = _lbl(prof, "", 26, GOLD, Rect2(124, 46, 150, 40), HORIZONTAL_ALIGNMENT_LEFT)
	prof.pressed.connect(_open_profile)

	var right := Control.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -310
	top.add_child(right)
	for spec in [["coin", 0], ["gem", 1]]:
		var y := 14.0 + float(spec[1]) * 52.0
		var chip := _panel(right, Rect2(80, y, 214, 46), Color(0.04, 0.04, 0.1, 0.9), INK, 3)
		_icon(chip, spec[0], Rect2(-18, -6, 56, 56))
		var l := _lbl(chip, "0", 28, Color.WHITE, Rect2(44, 0, 160, 46), HORIZONTAL_ALIGNMENT_LEFT)
		if spec[0] == "coin":
			_coins_lbl = l
		else:
			_gems_lbl = l


func _refresh_top() -> void:
	if not is_instance_valid(_coins_lbl):
		return
	_coins_lbl.text = str(Profile.amount("coins"))
	_gems_lbl.text = str(Profile.amount("gems"))
	_troph_lbl.text = str(int(Profile.data.trophies))
	_name_lbl.text = str(Profile.data.name)
	_profile_helm.tint = Profile.skin_tint("knight")
	_profile_helm.queue_redraw()
	if _badges.size() == TABS.size():
		_badges["quests"].visible = Profile.quests_ready_count() > 0
		_badges["road"].visible = Profile.road_ready_count() > 0
		_badges["shop"].visible = Profile.free_chest_left() == 0


# ================================================================ нижние вкладки

func _build_nav() -> void:
	var bar := Control.new()
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -168
	add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.16, 0.95)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_top = 22
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	var row := Control.new()
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.offset_left = -360
	row.offset_right = 360
	row.anchor_bottom = 1.0
	bar.add_child(row)
	var xs := [8, 148, 280, 440, 580]
	for i in TABS.size():
		var id: String = TABS[i][0]
		var center := id == "home"
		var w := 160.0 if center else 132.0
		var rect := Rect2(xs[i], 0 if center else 30, w, 160 if center else 128)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.position = rect.position
		b.size = rect.size
		row.add_child(b)
		var isz := 76.0 if center else 62.0
		_icon(b, TABS[i][1], Rect2((w - isz) / 2, 14 if center else 10, isz, isz))
		_lbl(b, TABS[i][2], 26 if center else 21, Color.WHITE, Rect2(0, rect.size.y - 50, w, 40))
		var badge := Panel.new()
		badge.add_theme_stylebox_override("panel", _sb(Color(0.95, 0.25, 0.2), INK, 3, 14, 0))
		badge.position = Vector2(w - 34, 4)
		badge.size = Vector2(26, 26)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.visible = false
		b.add_child(badge)
		_badges[id] = badge
		b.pressed.connect(func():
			main.sfx("click")
			show_page(id))
		_nav[id] = b
	_style_nav()


func _style_nav() -> void:
	for id in _nav:
		var b: Button = _nav[id]
		var sel: bool = id == page
		var col := GOLD if id == "home" else (NAVY2.lightened(0.25) if sel else NAVY2)
		if id == "home" and not sel:
			col = GOLD.darkened(0.25)
		for st in ["normal", "hover", "pressed"]:
			var sb := _sb(col.darkened(0.1) if st == "pressed" else col, GOLD if sel and id != "home" else INK, 5, 20, 6)
			b.add_theme_stylebox_override(st, sb)


func show_page(id: String) -> void:
	page = id
	_style_nav()
	_timer_labels.clear()
	_preview_pivot = null
	if _page_node:
		_page_node.queue_free()
	_page_node = Control.new()
	_page_node.anchor_right = 1.0
	_page_node.anchor_bottom = 1.0
	_content.add_child(_page_node)
	# страница занимает колонку 700 px по центру
	var col := Control.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_bottom = 1.0
	col.offset_left = -350
	col.offset_right = 350
	_page_node.add_child(col)
	col.size = Vector2(700, get_viewport_rect().size.y - 132 - 176)
	match id:
		"home":
			_page_home(col)
		"heroes":
			_page_heroes(col)
		"shop":
			_page_shop(col)
		"quests":
			_page_quests(col)
		"road":
			_page_road(col)
	_refresh_top()


# ================================================================ Арена (режимы)

func _page_home(col: Control) -> void:
	_ribbon(col, "Выбери режим", 6)
	var h := col.size.y
	var vb := _scroll(col, Rect2(0, 96, 700, h - 96 - 150))
	for id in Profile.MODE_ORDER:
		_mode_card(vb, id)
	var m: Dictionary = Profile.MODES[Profile.data.mode]
	var go := _btn(col, "В БОЙ!", Color(0.95, 0.52, 0.16), Rect2(150, h - 140, 400, 120), 60)
	_lbl(go, m.name, 20, Color(1, 0.95, 0.8), Rect2(0, 84, 400, 30))
	go.pressed.connect(func():
		main.start_match())
	go.pivot_offset = Vector2(200, 60)
	var tw := go.create_tween().set_loops()
	tw.tween_property(go, "scale", Vector2(1.04, 1.04), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(go, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


func _mode_card(vb: VBoxContainer, id: String) -> void:
	var m: Dictionary = Profile.MODES[id]
	var sel: bool = Profile.data.mode == id
	var unlocked := Profile.mode_unlocked(id)
	var card := _card(vb, 262, NAVY, GOLD if sel else INK, 7 if sel else 5)
	var art := TextureRect.new()
	art.texture = load("res://mode_%s.png" % id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(12, 12)
	art.size = Vector2(card.size.x - 24, 180)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = true
	card.add_child(art)
	if not unlocked:
		art.modulate = Color(0.45, 0.45, 0.55)
	var plaque := _panel(card, Rect2(card.size.x / 2 - 170, -6, 340, 62), NAVY2, INK, 5)
	_lbl(plaque, m.name, 34, Color(1, 0.95, 0.85), Rect2(0, 0, 340, 58))
	var badge := _panel(card, Rect2(-6, -6, 84, 84), NAVY2, INK, 5)
	_icon(badge, "swords" if unlocked else "lock", Rect2(10, 10, 64, 64))
	var chip := _panel(card, Rect2(card.size.x / 2 - 80, 160, 160, 46), Color(0.06, 0.06, 0.14, 0.92), INK, 3)
	_icon(chip, "people", Rect2(14, 5, 36, 36))
	_lbl(chip, "3 на 3", 24, Color.WHITE, Rect2(54, 0, 100, 46), HORIZONTAL_ALIGNMENT_LEFT)
	var dl := _lbl(card, m.desc, 19, Color(0.85, 0.85, 1.0), Rect2(16, 200, card.size.x - 32, 58))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if sel:
		_icon(card, "check", Rect2(card.size.x - 74, 16, 56, 56))
	if not unlocked:
		var lock_text := "Скоро" if m.get("soon", false) else "Нужно %d" % int(m.trophies)
		var lp := _panel(card, Rect2(card.size.x / 2 - 130, 70, 260, 70), Color(0.05, 0.05, 0.1, 0.92), GOLD, 4)
		if not m.get("soon", false):
			_icon(lp, "trophy", Rect2(200, 14, 42, 42))
		_lbl(lp, lock_text, 32, GOLD, Rect2(10, 0, 190 if not m.get("soon", false) else 240, 70))
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.position = Vector2.ZERO
	hit.size = card.size
	card.add_child(hit)
	hit.pressed.connect(func():
		if unlocked:
			main.sfx("click")
			Profile.data.mode = id
			Profile.save()
			show_page("home")
		else:
			main.sfx("wall")
			_toast("Этот режим пока закрыт"))


# ================================================================ Герои

func _page_heroes(col: Control) -> void:
	_ribbon(col, "Герои", 6)
	var vb := _scroll(col, Rect2(0, 96, 700, col.size.y - 96))
	# 3D-витрина
	var show := _card(vb, 420, Color(0.09, 0.1, 0.2), GOLD, 5)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(8, 8)
	svc.size = show.size - Vector2(16, 16)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 4.3)
	cam.fov = 36
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.62, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.88, 1.0)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)
	_preview_pivot = Node3D.new()
	vp.add_child(_preview_pivot)
	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.85
	cyl.height = 0.16
	pedestal.mesh = cyl
	pedestal.position.y = -0.08
	pedestal.material_override = main.toon(Color(0.45, 0.42, 0.75), false, true)
	_preview_pivot.add_child(pedestal)
	var hid := str(Profile.data.get("hero", "knight"))
	var h: Dictionary = Profile.HEROES[hid]
	var shown_skin := _preview_skin if _preview_skin != "" and Profile.SKINS[hid].has(_preview_skin) else Profile.skin_of(hid)
	var k = KnightScript.new()
	k.main = main
	k.team = 0
	k.hero = hid
	k.skin_id = shown_skin
	k.is_player = true
	k.display_only = true
	k.facing = Vector3(0, 0, 1)
	_preview_pivot.add_child(k)
	_lbl(show, str(h.name).to_upper(), 40, Color.WHITE, Rect2(0, 330, show.size.x, 50))
	var sk: Dictionary = Profile.skin_def(hid, shown_skin)
	_lbl(show, "Облик: %s · %s" % [sk.name, Profile.bonus_text(hid, shown_skin)], 22, GOLD, Rect2(0, 372, show.size.x, 34))

	# выбор героя
	var row := _card(vb, 150, NAVY, INK, 5)
	var icons := {"knight": "helm", "archer": "bow", "hammer": "hammer", "mage": "star"}
	for i in Profile.HERO_ORDER.size():
		var id: String = Profile.HERO_ORDER[i]
		var sel: bool = id == hid
		var x := 14 + i * 166
		var hp := _panel(row, Rect2(x, 14, 154, 122), NAVY2, GOLD if sel else INK, 5 if sel else 4)
		var tint := Profile.skin_tint(id) if id == "knight" or id == "mage" else Color.WHITE
		_icon(hp, icons[id], Rect2(47, 6, 60, 60), tint)
		var nm := str(Profile.HEROES[id].name)
		_lbl(hp, nm, 19 if nm.length() > 8 else 20, Color.WHITE, Rect2(0, 66, 154, 28))
		if sel:
			_lbl(hp, "выбран", 18, Color(0.6, 1, 0.6), Rect2(0, 92, 154, 24))
		else:
			var pick := Button.new()
			pick.flat = true
			pick.focus_mode = Control.FOCUS_NONE
			pick.size = hp.size
			hp.add_child(pick)
			hp.mouse_filter = Control.MOUSE_FILTER_PASS
			pick.pressed.connect(func():
				main.sfx("click")
				Profile.data.hero = id
				Profile.save()
				_preview_skin = ""
				show_page("heroes"))

	# характеристики
	var stats := _card(vb, 190, NAVY, INK, 5)
	var rows := [["Здоровье", h.hp], ["Урон", h.dmg], ["Скорость", h.speed]]
	for i in rows.size():
		_lbl(stats, rows[i][0], 26, Color(0.9, 0.9, 1.0), Rect2(30, 18 + i * 46, 200, 40), HORIZONTAL_ALIGNMENT_LEFT)
		_bar(stats, Rect2(240, 26 + i * 46, 400, 26), float(rows[i][1]), GOLD)
	_lbl(stats, "Супер: " + str(h.super), 22, Color(1, 0.85, 0.45), Rect2(0, 150, stats.size.x, 32))

	# облики героя
	var head := Control.new()
	head.custom_minimum_size = Vector2(700, 96)
	vb.add_child(head)
	_lbl(head, "Облики", 34, Color(1, 0.95, 0.8), Rect2(0, 6, 700, 50))
	_lbl(head, "Нажми на облик, чтобы примерить. Бонус действует в бою.", 20, Color(0.75, 0.75, 0.95), Rect2(0, 54, 700, 34))
	var order: Array = Profile.SKIN_ORDER[hid]
	for pair in [[0, 1], [2, 3]]:
		var line := Control.new()
		line.custom_minimum_size = Vector2(700, 290)
		vb.add_child(line)
		for j in 2:
			_skin_card(line, hid, order[pair[j]], Vector2(10 + j * 345, 0), order[pair[j]] == shown_skin)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(700, 20)
	vb.add_child(pad)


func _skin_card(parent: Control, hero: String, id: String, pos: Vector2, previewed: bool) -> void:
	var s: Dictionary = Profile.skin_def(hero, id)
	var worn: bool = Profile.skin_of(hero) == id
	var owned := Profile.owns_skin(hero, id)
	var c := _panel(parent, Rect2(pos, Vector2(335, 280)), NAVY2 if previewed else NAVY, GOLD if worn else (Color(0.6, 0.85, 1.0) if previewed else INK), 6 if worn or previewed else 5)
	# полоски цветов облика
	var cols: Array = (s.cols as Dictionary).values()
	for i in cols.size():
		var sw := Panel.new()
		sw.add_theme_stylebox_override("panel", _sb(cols[i], INK, 3, 10, 0))
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.position = Vector2(20, 18 + i * 34)
		sw.size = Vector2(46, 28)
		c.add_child(sw)
	var icons := {"knight": "helm", "archer": "bow", "hammer": "helm", "mage": "star"}
	_icon(c, icons[hero], Rect2(120, 12, 96, 96), Profile.skin_tint(hero, id))
	_lbl(c, s.name, 24, Color.WHITE, Rect2(0, 112, 335, 36))
	_lbl(c, Profile.bonus_text(hero, id), 19, Color(0.6, 1, 0.6) if not (s.bonus as Dictionary).is_empty() else Color(0.7, 0.7, 0.85), Rect2(0, 146, 335, 30))
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.size = Vector2(335, 180)
	c.add_child(tap)
	tap.pressed.connect(func():
		main.sfx("click")
		_preview_skin = id
		show_page("heroes"))
	var b: Button
	if worn:
		b = _btn(c, "НАДЕТ", Color(0.35, 0.35, 0.45), Rect2(40, 196, 255, 62), 28)
		b.disabled = true
	elif owned:
		b = _btn(c, "НАДЕТЬ", Color(0.3, 0.6, 0.9), Rect2(40, 196, 255, 62), 28)
		b.pressed.connect(func():
			Profile.wear_skin(hero, id)
			_preview_skin = ""
			show_page("heroes"))
	else:
		b = _price_btn(c, s.cur, int(s.price), Rect2(40, 196, 255, 62))
		b.pressed.connect(func():
			if Profile.buy_skin(hero, id):
				main.sfx("score")
				_preview_skin = ""
				show_page("heroes")
			else:
				_toast("Не хватает " + ("монет" if s.cur == "coins" else "кристаллов")))


# ================================================================ Магазин

func _page_shop(col: Control) -> void:
	_ribbon(col, "Магазин", 6)
	var vb := _scroll(col, Rect2(0, 96, 700, col.size.y - 96))
	var tints := {"wood": Color(0.62, 0.38, 0.18), "iron": Color(0.5, 0.53, 0.62), "royal": Color(0.48, 0.22, 0.62)}
	for kind in ["wood", "iron", "royal"]:
		var c: Dictionary = Profile.CHESTS[kind]
		var card := _card(vb, 210, NAVY, INK, 5)
		_icon(card, "chest", Rect2(20, 26, 160, 160), tints[kind])
		_lbl(card, c.name, 32, Color(1, 0.95, 0.85), Rect2(196, 18, 470, 46), HORIZONTAL_ALIGNMENT_LEFT)
		var d := _lbl(card, c.desc, 21, Color(0.8, 0.8, 0.98), Rect2(196, 62, 470, 56), HORIZONTAL_ALIGNMENT_LEFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var b := _price_btn(card, c.cur, int(c.price), Rect2(196, 126, 290, 66))
		if kind == "wood":
			var left := Profile.free_chest_left()
			if left > 0:
				b.disabled = true
				b.text = ""
				var tl := _lbl(b, "", 26, Color(0.85, 0.85, 0.85), Rect2(0, 0, 290, 66))
				var fn := func() -> String:
					var l2 := Profile.free_chest_left()
					return "через " + _fmt_time(l2) if l2 > 0 else "Готово!"
				tl.text = fn.call()
				_timer_labels.append([tl, fn])
		b.pressed.connect(func(): _buy_chest(kind))

	# обмен кристаллов на монеты
	var ex := _card(vb, 150, NAVY, INK, 5)
	_icon(ex, "gem", Rect2(24, 34, 80, 80))
	_lbl(ex, "→", 44, Color.WHITE, Rect2(104, 40, 50, 70))
	_icon(ex, "coin", Rect2(150, 34, 80, 80))
	_lbl(ex, "10 кристаллов → 120 монет", 24, Color(0.9, 0.9, 1.0), Rect2(246, 14, 420, 50), HORIZONTAL_ALIGNMENT_LEFT)
	var eb := _price_btn(ex, "gems", 10, Rect2(246, 70, 260, 62))
	eb.pressed.connect(func():
		if Profile.spend("gems", 10):
			Profile.add("coins", 120)
			main.sfx("pickup")
			_toast("+120 монет", Color(1, 0.85, 0.35))
		else:
			_toast("Не хватает кристаллов"))


func _buy_chest(kind: String) -> void:
	var r := Profile.open_chest(kind)
	if r.is_empty():
		_toast("Пока нельзя" if kind == "wood" else "Не хватает " + ("монет" if kind == "iron" else "кристаллов"))
		return
	main.sfx("ready")
	var tints := {"wood": Color(0.62, 0.38, 0.18), "iron": Color(0.5, 0.53, 0.62), "royal": Color(0.48, 0.22, 0.62)}
	var box := _popup(Profile.CHESTS[kind].name, 560)
	var chest := _icon(box, "chest", Rect2(180, 90, 200, 200), tints[kind])
	chest.pivot_offset = Vector2(100, 100)
	chest.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(chest, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(chest, "scale", Vector2.ONE, 0.15)
	var y := 300.0
	if int(r.coins) > 0:
		_icon(box, "coin", Rect2(170, y, 56, 56))
		_lbl(box, "+%d" % int(r.coins), 40, GOLD, Rect2(236, y, 200, 56), HORIZONTAL_ALIGNMENT_LEFT)
		y += 64
	if int(r.gems) > 0:
		_icon(box, "gem", Rect2(170, y, 56, 56))
		_lbl(box, "+%d" % int(r.gems), 40, Color(0.6, 0.9, 1.0), Rect2(236, y, 200, 56), HORIZONTAL_ALIGNMENT_LEFT)
		y += 64
	if str(r.skin) != "":
		var hn := str(Profile.HEROES[r.skin_hero].name)
		_lbl(box, "Новый облик: %s (%s)!" % [Profile.skin_def(r.skin_hero, r.skin).name, hn], 24, Color(0.6, 1, 0.6), Rect2(0, y, 560, 50))
	var ok := _btn(box, "ЗАБРАТЬ", Color(0.3, 0.7, 0.35), Rect2(150, box.size.y - 100, 260, 76), 34)
	ok.pressed.connect(func():
		_close_popup()
		show_page(page))


# ================================================================ Задания

func _page_quests(col: Control) -> void:
	_ribbon(col, "Задания дня", 6)
	Profile.ensure_quests()
	var vb := _scroll(col, Rect2(0, 96, 700, col.size.y - 96))
	for i in Profile.data.quests.size():
		var q: Dictionary = Profile.data.quests[i]
		var card := _card(vb, 190, NAVY, GOLD if Profile.quest_ready(i) else INK, 5)
		_icon(card, "scroll", Rect2(20, 30, 110, 110))
		_lbl(card, q.text, 28, Color.WHITE, Rect2(146, 14, 520, 44), HORIZONTAL_ALIGNMENT_LEFT)
		_bar(card, Rect2(146, 66, 330, 34), float(q.progress) / float(q.goal))
		_lbl(card, "%d / %d" % [int(q.progress), int(q.goal)], 22, Color.WHITE, Rect2(146, 66, 330, 34))
		_icon(card, "coin", Rect2(490, 62, 42, 42))
		_lbl(card, "+%d" % int(q.reward), 28, GOLD, Rect2(538, 62, 120, 42), HORIZONTAL_ALIGNMENT_LEFT)
		if q.claimed:
			_icon(card, "check", Rect2(146, 116, 52, 52))
			_lbl(card, "Получено", 26, Color(0.6, 1, 0.6), Rect2(206, 116, 300, 52), HORIZONTAL_ALIGNMENT_LEFT)
		elif Profile.quest_ready(i):
			var b := _btn(card, "ЗАБРАТЬ", Color(0.3, 0.72, 0.35), Rect2(146, 112, 260, 64), 30)
			b.pressed.connect(func():
				var got := Profile.claim_quest(i)
				main.sfx("score")
				_toast("+%d монет" % got, Color(1, 0.85, 0.35))
				show_page("quests"))
		else:
			_lbl(card, "Играй, чтобы выполнить", 22, Color(0.7, 0.7, 0.9), Rect2(146, 112, 500, 60), HORIZONTAL_ALIGNMENT_LEFT)
	var foot := Control.new()
	foot.custom_minimum_size = Vector2(700, 70)
	vb.add_child(foot)
	var fl := _lbl(foot, "", 24, Color(0.75, 0.75, 0.95), Rect2(0, 10, 700, 50))
	var fn := func() -> String: return "Новые задания через " + _fmt_time(Profile.seconds_to_midnight())
	fl.text = fn.call()
	_timer_labels.append([fl, fn])


# ================================================================ Путь славы

func _page_road(col: Control) -> void:
	_ribbon(col, "Путь славы", 6)
	var top := _panel(col, Rect2(110, 96, 480, 96), Color(0.06, 0.06, 0.14, 0.92), GOLD, 4)
	_icon(top, "trophy", Rect2(110, 10, 76, 76))
	_lbl(top, str(int(Profile.data.trophies)), 54, GOLD, Rect2(196, 6, 200, 84), HORIZONTAL_ALIGNMENT_LEFT)
	var vb := _scroll(col, Rect2(0, 206, 700, col.size.y - 206))
	var best := int(Profile.data.best_trophies)
	for i in Profile.ROAD.size():
		var r: Dictionary = Profile.ROAD[i]
		var st := Profile.road_state(i)
		var card := _card(vb, 140, NAVY if st != "locked" else Color(0.08, 0.08, 0.15), GOLD if st == "ready" else INK, 5)
		var disc := _panel(card, Rect2(16, 16, 108, 108), NAVY2, GOLD if best >= int(r.t) else INK, 5)
		_icon(disc, "trophy", Rect2(30, 8, 48, 48))
		_lbl(disc, str(int(r.t)), 30, GOLD, Rect2(0, 56, 108, 44))
		var kind := "coin"
		var text := ""
		if r.has("coins"):
			text = "+%d монет" % int(r.coins)
		elif r.has("gems"):
			kind = "gem"
			text = "+%d кристаллов" % int(r.gems)
		elif r.has("skin"):
			kind = "helm"
			text = "Облик: " + str(Profile.skin_def(r.get("hero", "knight"), r.skin).name)
		_icon(card, kind, Rect2(140, 30, 64, 64), Profile.skin_tint(r.get("hero", "knight"), r.skin) if r.has("skin") else Color.WHITE)
		_lbl(card, text, 26, Color.WHITE if st != "locked" else Color(0.6, 0.6, 0.75), Rect2(214, 14, 290, 60), HORIZONTAL_ALIGNMENT_LEFT)
		if r.has("note"):
			_lbl(card, r.note, 19, GOLD, Rect2(214, 72, 290, 40), HORIZONTAL_ALIGNMENT_LEFT)
		match st:
			"claimed":
				_icon(card, "check", Rect2(560, 40, 60, 60))
			"ready":
				var b := _btn(card, "ЗАБРАТЬ", Color(0.3, 0.72, 0.35), Rect2(500, 36, 170, 66), 26)
				b.pressed.connect(func():
					Profile.claim_road(i)
					main.sfx("score")
					show_page("road"))
			_:
				_icon(card, "lock", Rect2(565, 40, 56, 56))


# ================================================================ всплывающие окна

func _popup(title: String, h := 520.0) -> Panel:
	_close_popup()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_popups.add_child(dim)
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.5
	holder.anchor_bottom = 0.5
	dim.add_child(holder)
	var box := _panel(holder, Rect2(-280, -h / 2, 560, h), NAVY, GOLD, 6)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var head := _panel(box, Rect2(60, -30, 440, 66), NAVY2, INK, 5)
	_lbl(head, title, 32, Color(1, 0.95, 0.8), Rect2(0, 0, 440, 62))
	var x := _btn(box, "", Color(0.85, 0.3, 0.25), Rect2(500, -24, 64, 64))
	_icon(x, "close", Rect2(14, 14, 36, 36))
	x.pressed.connect(_close_popup)
	box.scale = Vector2(0.85, 0.85)
	box.pivot_offset = Vector2(280, h / 2)
	create_tween().tween_property(box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return box


func _close_popup() -> void:
	for c in _popups.get_children():
		c.queue_free()
	Profile.save()


func _toggle_btn(box: Control, text: String, key: String, y: float) -> void:
	var on: bool = Profile.data.settings.get(key, true)
	var b := _btn(box, "%s: %s" % [text, "ВКЛ" if on else "ВЫКЛ"],
		Color(0.3, 0.65, 0.4) if on else Color(0.45, 0.42, 0.55), Rect2(80, y, 400, 72), 30)
	b.pressed.connect(func():
		Profile.data.settings[key] = not on
		Profile.save()
		main.apply_settings()
		_open_settings())


func _open_settings() -> void:
	var box := _popup("Настройки", 640)
	_toggle_btn(box, "Звук", "sound", 70)
	_toggle_btn(box, "Музыка", "music", 160)
	_toggle_btn(box, "Тряска камеры", "shake", 250)
	var tb := _btn(box, "Пройти обучение", Color(0.3, 0.5, 0.8), Rect2(80, 350, 400, 72), 28)
	tb.pressed.connect(func():
		Profile.data.tutorial_done = false
		_close_popup()
		main.start_match())
	var r := _btn(box, "Сбросить прогресс", Color(0.75, 0.25, 0.22), Rect2(80, 450, 400, 72), 28)
	r.pressed.connect(func():
		var c := _popup("Точно сбросить?", 380)
		_lbl(c, "Монеты, кубки, облики и задания\nпропадут навсегда.", 24, Color(0.9, 0.9, 1.0), Rect2(0, 60, 560, 110))
		var yes := _btn(c, "СБРОСИТЬ", Color(0.75, 0.25, 0.22), Rect2(40, 220, 230, 80), 28)
		var no := _btn(c, "ОТМЕНА", Color(0.35, 0.35, 0.5), Rect2(290, 220, 230, 80), 28)
		yes.pressed.connect(func():
			Profile.reset()
			main.apply_settings()
			_close_popup()
			show_page("home"))
		no.pressed.connect(_close_popup))
	_lbl(box, "Ржавые Рыцари · версия 0.9 альфа", 20, Color(0.6, 0.6, 0.8), Rect2(0, 550, 560, 40))


func _open_profile() -> void:
	var box := _popup("Профиль", 640)
	_icon(box, "helm", Rect2(220, 50, 120, 120), Profile.skin_tint("knight"))
	var name_edit := LineEdit.new()
	name_edit.text = str(Profile.data.name)
	name_edit.max_length = 16
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_size_override("font_size", 32)
	name_edit.add_theme_stylebox_override("normal", _sb(Color(0.05, 0.05, 0.12), GOLD, 3, 14, 0))
	name_edit.add_theme_stylebox_override("focus", _sb(Color(0.08, 0.08, 0.18), Color.WHITE, 3, 14, 0))
	name_edit.position = Vector2(90, 186)
	name_edit.size = Vector2(380, 66)
	box.add_child(name_edit)
	name_edit.text_changed.connect(func(t: String):
		Profile.data.name = t.strip_edges() if t.strip_edges() != "" else "Сэр Рыцарь")
	_lbl(box, "нажми, чтобы сменить имя", 18, Color(0.6, 0.6, 0.8), Rect2(0, 254, 560, 28))
	var st: Dictionary = Profile.data.stats
	var rows := [
		["Кубки (рекорд)", "%d (%d)" % [int(Profile.data.trophies), int(Profile.data.best_trophies)]],
		["Матчей сыграно", str(int(st.matches))],
		["Побед", str(int(st.wins))],
		["Бронзовых монет сдано", str(int(st.crystals))],
		["Рыцарей одолено", str(int(st.kos))],
	]
	for i in rows.size():
		var y := 296 + i * 58
		_lbl(box, rows[i][0], 26, Color(0.85, 0.85, 1.0), Rect2(50, y, 300, 50), HORIZONTAL_ALIGNMENT_LEFT)
		_lbl(box, rows[i][1], 28, GOLD, Rect2(330, y, 180, 50), HORIZONTAL_ALIGNMENT_RIGHT)
