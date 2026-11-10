extends Node3D
## Главная сцена: двор замка, команды героев, режимы, интерфейс.
## «Казна» — собирай бронзовые монеты и неси к своему знамени (до 10),
## «Схватка» — командный бой (до 10), «Захват знамени» — укради вражеское знамя (до 3).

const KnightScript = preload("res://knight.gd")
const JoystickScript = preload("res://joystick.gd")
const TouchButtonScript = preload("res://touch_button.gd")
const ScoreBarScript = preload("res://score_bar.gd")
const MenuScript = preload("res://menu.gd")
const IconScript = preload("res://icon.gd")
const AmmoBarScript = preload("res://ammo_bar.gd")
const HERO_ICON := {"knight": "ic_sword", "archer": "ic_bow", "hammer": "ic_hammer", "mage": "ic_fire"}

const HALF_W := 12.0
const HALF_L := 20.0
const MAX_BATTERIES := 8
const CAM_OFFSET := Vector3(0, 11.5, 5.5)

# Карты верхней половины (24 x 20). Нижняя половина — зеркальная.
# '#' — каменный блок, 'b' — куст, 'w' — вода (не пройти, но стрелы летят над ней), '.' — пол
const MAP_TOP := [
	"bbbb................bbbb",
	"bb....................bb",
	"b......................b",
	"........................",
	"...##..............##...",
	"...##bb..........bb##...",
	".....bb....##....bb.....",
	"...........##...........",
	"bb....................bb",
	"bbb.....###..###.....bbb",
	"bb.......#....#.......bb",
	"........................",
	"...##.....bbbb.....##...",
	"...##b....bbbb....b##...",
	"....bb............bb....",
	"........................",
	"##.....b........b.....##",
	"#.....bb........bb.....#",
	"........##....##........",
	"........#......#........",
]

const MAP_FLOOD := [
	"bbb..................bbb",
	"bb....................bb",
	"........................",
	"........................",
	"..www..............www..",
	"..www..#........#..www..",
	".......#........#.......",
	"bb....................bb",
	"bbb....##......##....bbb",
	"........................",
	"....bb....wwww....bb....",
	"....bb....wwww....bb....",
	"........................",
	"##....b..........b....##",
	"#....bbb........bbb....#",
	"........................",
	"...ww....##..##....ww...",
	"...ww..............ww...",
	"bb.......b....b.......bb",
	"bbb......b....b......bbb",
]

const ARENAS := [
	{"name": "Двор замка", "map": MAP_TOP, "floor": Color(0.5, 0.48, 0.48), "stone": Color(1.0, 0.96, 1.04)},
	{"name": "Затопленный двор", "map": MAP_FLOOD, "floor": Color(0.44, 0.46, 0.5), "stone": Color(0.9, 1.0, 1.05)},
]

## Каменный блок: верх — плитка stone_top (повёрнута случайно), стенки — одна из четырёх
## плиток атласа stone_side (по блоку случайно). size — размер блока в метрах.
const STONE_SHADER := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform sampler2D top_tex : source_color, filter_linear_mipmap;
uniform sampler2D side_tex : source_color, filter_linear_mipmap;
uniform vec3 size = vec3(1.0, 1.2, 1.0);
uniform vec3 tint = vec3(1.0);
varying vec3 lv;
varying vec3 ln;
varying vec3 cen;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	lv = VERTEX;
	ln = NORMAL;
	cen = MODEL_MATRIX[3].xyz;
}
void fragment() {
	vec3 rep = max(vec3(1.0), round(size));
	vec3 q = (lv / size + 0.5) * rep;
	vec3 col;
	if (ln.y > 0.5) {
		vec2 uv0 = q.xz;
		vec2 uv = fract(uv0);
		float r = floor(hash(floor(cen.xz * 2.0) + floor(uv0) * 7.0) * 4.0);
		if (r == 1.0) uv = vec2(1.0 - uv.y, uv.x);
		else if (r == 2.0) uv = 1.0 - uv;
		else if (r == 3.0) uv = vec2(uv.y, 1.0 - uv.x);
		col = textureGrad(top_tex, uv, dFdx(uv0), dFdy(uv0)).rgb;
	} else {
		vec2 uv0 = abs(ln.x) > 0.5 ? vec2(q.z, q.y) : vec2(q.x, q.y);
		vec2 cell = floor(uv0);
		vec2 uv = fract(uv0);
		uv.y = 1.0 - uv.y;
		float k = floor(hash(floor(cen.xz * 2.0) + cell * 3.1 + ln.xz * 5.0) * 4.0);
		vec2 off = vec2(mod(k, 2.0), floor(k / 2.0)) * 0.5;
		uv = off + clamp(uv, 0.004, 0.996) * 0.5;
		col = textureGrad(side_tex, uv, dFdx(uv0) * 0.5, dFdy(uv0) * 0.5).rgb * 0.9;
	}
	ALBEDO = col * tint;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float w = sin(wp.x * 2.6 + TIME * 1.4) * sin(wp.z * 2.1 - TIME * 1.1)
		+ 0.5 * sin((wp.x + wp.z) * 4.0 + TIME * 2.3);
	vec3 deep = vec3(0.16, 0.42, 0.72);
	vec3 light = vec3(0.42, 0.74, 0.95);
	ALBEDO = mix(deep, light, smoothstep(0.15, 1.2, w));
}
"""

var team_colors := [Color(0.22, 0.52, 1.0), Color(0.95, 0.25, 0.22)]
var stations := [Vector3(0, 0, HALF_L - 3.0), Vector3(0, 0, -HALF_L + 3.0)]
var knights: Array = []
var batteries: Array = []
var score := [0, 0]
var win_score := 10
var flags: Array = []       # «Захват знамени»: [{node, state, carrier, pos, t}] по командам
var game_over := false
var player

var _grid: Array = []          # строки полной карты
var _bushes: Array = []        # [{pos, mesh}]
var _mat_cache := {}
var _tex := {}
var _bush_mat: StandardMaterial3D
var _bush_mat_seen: StandardMaterial3D
const SFX_NAMES := ["swing", "hit", "wall", "death", "pickup", "score", "ready",
	"super", "win", "lose", "click", "respawn", "slam"]
var _sfx := {}
var _sfx_pool: Array = []
var _sfx_next := 0
var _music: AudioStreamPlayer
var _sprite_mats: Array = []
var _sprite_mats_seen: Array = []
const BUSH_SPRITES := 6        # спрайтов в bushes.png (в ряд по 256x256)

var _camera: Camera3D
var _joystick
var _attack_btn
var _super_btn
var _dash_btn
var _ammo_bar
var _exit_box: Control
var _score_bar
var _info: Label
var _result: Control
var _result_label: Label
var _battery_t := 1.0
var _hint_t := 6.0
var _super_key := false

static var in_game := false    # false — показываем меню, на фоне дерутся боты
var sound_on := true
var music_on := true
var _shake := 0.0
var _hud: Control
var _menu: Control
var shake_on := true
var mode := "charge"
var match_stats := {"crystals": 0, "kos": 0, "hits": 0, "supers": 0}
var arena: Dictionary = ARENAS[0]

# обучение в первом бою
var tutorial := false
var _tut_step := 0
var _tut_t := 0.0
var _tut_moved := 0.0
var _tut_attacks := 0
var _tut_super := false
var _tut_dash := false


func _ready() -> void:
	randomize()
	for tex_name in ["floor", "stone_top", "stone_side", "leaves", "bushes", "props", "plate_center", "plate_station"]:
		_tex[tex_name] = load("res://%s.png" % tex_name)
	_load_settings()
	mode = str(Profile.data.mode)
	if not Profile.mode_unlocked(mode):
		mode = "charge"
	# тестовый запуск сразу в бой: -- --play=режим:герой (профиль не сохраняется)
	var play := _arg("--play=")
	if play != "":
		var parts := play.split(":")
		mode = parts[0]
		if parts.size() > 1:
			Profile.data.hero = parts[1]
		in_game = true
	# обучение — в самом первом бою (или по кнопке в настройках)
	tutorial = in_game and (not bool(Profile.data.get("tutorial_done", false)) or "--tutorial" in OS.get_cmdline_user_args())
	if play != "" and not ("--tutorial" in OS.get_cmdline_user_args()):
		tutorial = false
	if tutorial:
		mode = "charge"
	# арены по очереди от боя к бою; за меню — случайная
	var ai := randi() % ARENAS.size()
	if in_game:
		ai = int(Profile.data.get("arena_i", 0)) % ARENAS.size()
		if not tutorial:
			Profile.data.arena_i = ai + 1
		else:
			ai = 0
	if _arg("--arena=") != "":
		ai = int(_arg("--arena=")) % ARENAS.size()
	arena = ARENAS[ai]
	var top: Array = arena.map
	_grid = top.duplicate()
	for i in range(top.size() - 1, -1, -1):
		var src: String = top[i]
		var rev := ""
		for j in range(src.length() - 1, -1, -1):
			rev += src[j]
		_grid.append(rev)
	win_score = 3 if mode == "flag" else 10
	_build_world()
	_build_arena()
	_spawn_knights()
	if tutorial:                                  # в обучении враги бьют слабее
		for k in knights:
			if k.team != 0:
				k.dmg_mult *= 0.6
	if mode == "flag":
		_spawn_flags()
	_build_ui()
	_setup_audio()
	var shots := _arg("--shots=")
	if shots != "":
		_setup_screenshots(shots)
	elif not in_game:
		_open_menu()


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


## Режим автоскриншотов: godot --path . -- --shots=/путь/к/папке
## Кадр 1 — главное меню, кадры 2–3 — бой (игрок под управлением бота).
func _setup_screenshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var tab := _arg("--tab=")
	if tab != "":                                   # снимок одной вкладки меню
		_open_menu()
		_menu.show_page(tab)
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/tab_%s.png" % [dir, tab])
		get_tree().quit()
		return
	if in_game:                                     # тестовый бой: сразу в бой, игрок — бот
		player.autopilot = true
		if _arg("--nohud") != "" or "--nohud" in OS.get_cmdline_user_args():
			_hud.visible = false
		var secs := float(_arg("--secs=")) if _arg("--secs=") != "" else 30.0
		var t_list := [secs * 0.17, secs * 0.4, secs * 0.67, secs]
		for i in t_list.size():
			await get_tree().create_timer(t_list[i] - (t_list[i - 1] if i > 0 else 0.0)).timeout
			if DisplayServer.get_name() != "headless":   # без экрана кадр не сохранить
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/play_%d.png" % [dir, i + 1])
			print("score ", score, " game_over ", game_over)
		if game_over:
			print("winner shown")
		get_tree().quit()
		return
	_open_menu()
	var times := [3.0, 9.0, 16.0]
	for i in times.size():
		await get_tree().create_timer(times[i] - (times[i - 1] if i > 0 else 0.0)).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [dir, i + 1])
		print("saved shot ", i + 1)
		if i == 0:
			_menu.visible = false
			_hud.visible = true
			_hint_t = 0.0
	get_tree().quit()


# ---------------------------------------------------------------- материалы

## Мультяшный материал: двухтоновое освещение, по желанию — тёмный контур.
func toon(color: Color, glow := false, outline := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), glow, outline]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.6
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.4
	if outline:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = Color(0.12, 0.09, 0.1)
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = 0.025
		m.next_pass = o
	_mat_cache[key] = m
	return m


## Материал куста-спрайта: кусочек атласа bushes.png, всегда смотрит в камеру.
func _bush_sprite_mat(i: int, seen: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex["bushes"]
	m.uv1_scale = Vector3(1.0 / BUSH_SPRITES, 1, 1)
	m.uv1_offset = Vector3(float(i) / BUSH_SPRITES, 0, 0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if seen:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.4)
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	return m


## Материал плиты (центр, площадки у знамён): картинка целиком на верхней грани диска.
func _plate(tex_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex[tex_name]
	m.albedo_color = Color(0.85, 0.85, 0.9)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func _textured(tex_name: String, tint := Color.WHITE, uv := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex[tex_name]
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


# ---------------------------------------------------------------- мир

func _box(pos: Vector3, size: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.add_child(mi)
		body.position = pos
		add_child(body)
	else:
		mi.position = pos
		add_child(mi)
	return mi


func _disc(pos: Vector3, radius: float, mat: Material, h := 0.06) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = h
	mi.mesh = cm
	mi.position = pos + Vector3(0, h / 2, 0)
	mi.material_override = mat
	add_child(mi)
	return mi


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.95, 1.0)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 56.0
	add_child(_camera)
	var start: Vector3 = stations[0]
	_camera.position = start + CAM_OFFSET
	_camera.look_at(start)


func _cell_pos(col: int, row: int) -> Vector3:
	return Vector3(-HALF_W + col + 0.5, 0, -HALF_L + row + 0.5)


func _build_arena() -> void:
	# трава двора
	# пол: атлас 4x4 плитки = 4 м
	# пол: плитка песчаника (картинка 3:2 ≈ 6 x 4 м), шире арены — под декорациями тоже пол
	# светлая плитка под ярким светом выгорает в белый — приглушаем, чтобы цвет был как на картинке
	var floor_mat := _textured("floor", arena.floor, 1.0)
	if _tex["floor"] == null:
		push_warning("floor.png не найден — загрузи его в репозиторий")
	floor_mat.uv1_scale = Vector3(1.0 / 6.0, 1.0 / 6.0, 1.0 / 4.0)
	_box(Vector3(0, -0.25, 0), Vector3(HALF_W * 2 + 24, 0.5, HALF_L * 2 + 20), floor_mat, false)

	# живая изгородь по периметру (твёрдая)
	var hedge := _textured("leaves", Color(0.75, 0.85, 0.75), 0.7)
	var hh := 1.6
	_box(Vector3(0, hh / 2, -HALF_L - 0.5), Vector3(HALF_W * 2 + 2, hh, 1), hedge)
	_box(Vector3(0, hh / 2, HALF_L + 0.5), Vector3(HALF_W * 2 + 2, hh, 1), hedge)
	_box(Vector3(-HALF_W - 0.5, hh / 2, 0), Vector3(1, hh, HALF_L * 2), hedge)
	_box(Vector3(HALF_W + 0.5, hh / 2, 0), Vector3(1, hh, HALF_L * 2), hedge)

	# блоки и кусты по карте
	var stone := _stone_mat(Vector3(1, 1.2, 1))
	var water_mat := ShaderMaterial.new()
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	water_mat.shader = wsh
	var rim := toon(Color(0.42, 0.4, 0.46))
	_bush_mat = _textured("leaves", Color(0.7, 0.8, 0.7), 1.0)
	_bush_mat_seen = _bush_mat.duplicate() as StandardMaterial3D
	_bush_mat_seen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bush_mat_seen.albedo_color = Color(0.7, 0.8, 0.7, 0.4)
	for i in BUSH_SPRITES:
		_sprite_mats.append(_bush_sprite_mat(i, false))
		_sprite_mats_seen.append(_bush_sprite_mat(i, true))
	for row in _grid.size():
		var line: String = _grid[row]
		for col in line.length():
			var p := _cell_pos(col, row)
			match line[col]:
				"#":
					_box(p + Vector3(0, 0.6, 0), Vector3(1, 1.2, 1), stone)
				"w":
					# вода: героев не пускает (слой 4), снаряды пролетают (они видят только слой 1)
					_box(p + Vector3(0, 0.03, 0), Vector3(1, 0.04, 1), water_mat, false)
					var body := StaticBody3D.new()
					body.collision_layer = 4
					body.collision_mask = 0
					var cs := CollisionShape3D.new()
					var shape := BoxShape3D.new()
					shape.size = Vector3(1, 2, 1)
					cs.shape = shape
					body.add_child(cs)
					body.position = p + Vector3(0, 1, 0)
					add_child(body)
					# каменный бортик там, где вода граничит с полом
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if _cell(col + d.x, row + d.y) != "w":
							var off := Vector3(d.x * 0.47, 0.06, d.y * 0.47)
							var sz := Vector3(0.08 if d.x != 0 else 1.0, 0.12, 0.08 if d.y != 0 else 1.0)
							_box(p + off, sz, rim, false)
				"b":
					# низкое основание из листвы + нарисованный куст-спрайт, повёрнутый к камере
					var m := _box(p + Vector3(0, 0.15, 0), Vector3(0.98, 0.3, 0.98), _bush_mat, false)
					var idx := (col * 7 + row * 13) % BUSH_SPRITES
					var spr := MeshInstance3D.new()
					var q := QuadMesh.new()
					q.size = Vector2(1.45, 1.45)
					spr.mesh = q
					spr.position = Vector3(0, 0.55, 0)
					spr.material_override = _sprite_mats[idx]
					spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					m.add_child(spr)
					_bushes.append({"pos": p, "mesh": m, "sprite": spr, "idx": idx})

	# центр, где появляются кристаллы
	_disc(Vector3.ZERO, 2.3, toon(Color(0.36, 0.33, 0.5)))
	_disc(Vector3.ZERO, 2.05, _plate("plate_center"), 0.08)      # круглая плита с узором

	# станции команд: каменный круг + арка со знаменем
	for t in 2:
		var s: Vector3 = stations[t]
		var col: Color = team_colors[t]
		var back := 1.0 if t == 0 else -1.0
		_disc(s, 1.8, _plate("plate_station"))                      # плита с ромбом
		var glow := MeshInstance3D.new()                              # светящееся кольцо команды
		var ring := TorusMesh.new()
		ring.inner_radius = 1.5
		ring.outer_radius = 1.72
		ring.rings = 40
		glow.mesh = ring
		glow.scale.y = 0.15
		glow.position = s + Vector3(0, 0.07, 0)
		glow.material_override = toon(col, true)
		add_child(glow)
		for dx in [-1.5, 1.5]:
			_box(s + Vector3(dx, 1.2, 1.7 * back), Vector3(0.45, 2.4, 0.45), _stone_mat(Vector3(0.45, 2.4, 0.45)))
		_box(s + Vector3(0, 2.55, 1.7 * back), Vector3(3.5, 0.4, 0.5), _stone_mat(Vector3(3.5, 0.4, 0.5)))
		_box(s + Vector3(0, 1.7, 1.7 * back), Vector3(1.2, 1.3, 0.06), toon(col), false)
	_build_decor()


# ---------------------------------------------------------------- декорации за картой

## Предметы из props.png (атлас 8 x 4 клетки по 256 px). Индекс -> размер в метрах.
## 0-3 стены, 4 стена со знаменем, 5 флагшток, 6 забор, 7 ящик, 8 бочка, 9 ящик с бочкой,
## 10 колья, 11 факел, 12 жаровня, 13 груда камней, 14 камень, 15-16 плиты, 17 трава,
## 18 куст, 19 сухое дерево, 20 надгробие, 21 череп, 22 телега, 23-27 обрывы с травой
## 28 большой камень, 29 камень, 30 галька, 31 камень с травой, 32 колонна, 33 руина,
## 34 руина со мхом, 35 арка, 36 блок, 37 стена со знаменем-2, 38 руина-2, 39 частокол,
## 40 груда камней-2, 41 стела со щитом, 42 каменные шпили  (атлас 8 x 6)
const PROP_SIZES := [3.0, 3.0, 3.0, 3.4, 2.9, 2.6, 1.8, 1.1,
	1.0, 1.7, 1.6, 1.5, 1.5, 1.9, 1.3, 1.3,
	1.3, 0.7, 1.8, 2.8, 1.4, 0.8, 1.9, 2.6,
	2.6, 2.6, 2.6, 2.6, 2.0, 1.5, 0.5, 1.4,
	1.9, 2.0, 2.2, 2.8, 1.5, 2.6, 2.2, 1.7,
	1.9, 1.6, 2.0]
var _prop_mats := {}


func _prop_mat(i: int) -> StandardMaterial3D:
	if not _prop_mats.has(i):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex["props"]
		m.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 6.0, 1)
		m.uv1_offset = Vector3(float(i % 8) / 8.0, float(i / 8) / 6.0, 0)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_prop_mats[i] = m
	return _prop_mats[i]


func _prop(i: int, pos: Vector3, scl := 1.0) -> void:
	var s: float = float(PROP_SIZES[i]) * scl
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	mi.mesh = q
	mi.position = Vector3(pos.x, s * 0.5 - 0.02, pos.z)
	mi.material_override = _prop_mat(i)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# крепостные стены за дальними краями, в середине — стена со знаменем, по бокам жаровни
	for zs in [-1.0, 1.0]:
		var z: float = (HALF_L + 2.2) * zs
		var x := -17.0
		var k := 0
		while x <= 17.0:
			var wall: int = [0, 33, 1, 34, 2, 38, 3, 35][k % 8]
			if absf(x) < 1.0:
				wall = 4 if zs < 0 else 37
			_prop(wall, Vector3(x, 0, z))
			x += 3.4
			k += 1
		for tx in [-4.6, 4.6]:
			_prop(12, Vector3(tx, 0, z - 0.9 * zs))
		for tx in [-2.6, 2.6]:
			_prop(5, Vector3(tx, 0, z - 1.3 * zs), 0.9)
	# вдоль боковых изгородей — ящики, бочки, камни, деревья, телеги
	var side := [7, 8, 9, 13, 14, 15, 18, 19, 20, 22, 10, 12, 11, 6,
		28, 29, 31, 32, 36, 39, 40, 41, 42]
	for xs in [-1.0, 1.0]:
		var z := -HALF_L + 0.5
		while z < HALF_L:
			var idx: int = side[rng.randi_range(0, side.size() - 1)]
			var x: float = (HALF_W + 1.6 + rng.randf_range(-0.1, 0.4)) * xs
			_prop(idx, Vector3(x, 0, z), rng.randf_range(0.85, 1.1))
			if idx == 20:                                   # у надгробия череп
				_prop(21, Vector3(x - 0.8 * xs, 0, z + 0.5), 0.9)
			elif rng.randf() < 0.35:                        # трава и камешки между крупными
				_prop([17, 30, 16, 31][rng.randi_range(0, 3)], Vector3(x + rng.randf_range(-0.6, 0.6), 0, z + 1.2), 0.7)
			z += rng.randf_range(2.3, 3.4)
		# дальше — земляные обрывы с травой
		var z2 := -HALF_L - 1.0
		while z2 < HALF_L + 1.0:
			_prop([23, 24, 25][rng.randi_range(0, 2)], Vector3((HALF_W + 3.6) * xs, 0, z2))
			z2 += 2.5
	# углы
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_prop(19, Vector3((HALF_W + 2.2) * c.x, 0, (HALF_L + 1.0) * c.y))
		_prop(13, Vector3((HALF_W + 1.3) * c.x, 0, (HALF_L + 0.2) * c.y), 0.9)


var _stone_mats := {}
var _stone_shader: Shader


func _stone_mat(size: Vector3) -> ShaderMaterial:
	var key := str(size)
	if not _stone_mats.has(key):
		if _stone_shader == null:
			_stone_shader = Shader.new()
			_stone_shader.code = STONE_SHADER
		var m := ShaderMaterial.new()
		m.shader = _stone_shader
		m.set_shader_parameter("top_tex", _tex["stone_top"])
		m.set_shader_parameter("side_tex", _tex["stone_side"])
		m.set_shader_parameter("size", size)
		var t: Color = arena.stone
		m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
		_stone_mats[key] = m
	return _stone_mats[key]


func _cell(col: int, row: int) -> String:
	if row < 0 or row >= _grid.size():
		return "#"
	var line: String = _grid[row]
	if col < 0 or col >= line.length():
		return "#"
	return line[col]


## Свободное место рядом с точкой (не в камне и не в воде) — туда падают монеты.
func _free_spot(p: Vector3) -> Vector3:
	for r in 4:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector3(dx, 0, dz)
				var c := _cell(int(floor(q.x + HALF_W)), int(floor(q.z + HALF_L)))
				if c == "." or c == "b":
					return Vector3(floor(q.x + HALF_W) - HALF_W + 0.5, 0, floor(q.z + HALF_L) - HALF_L + 0.5)
	return Vector3.ZERO


func is_bush(pos: Vector3) -> bool:
	var col := int(floor(pos.x + HALF_W))
	var row := int(floor(pos.z + HALF_L))
	if row < 0 or row >= _grid.size():
		return false
	var line: String = _grid[row]
	if col < 0 or col >= line.length():
		return false
	return line[col] == "b"


## Видит ли команда `viewer_team` рыцаря `k`. В кустах рыцаря видно
## только вблизи или сразу после выстрела.
func can_see(viewer_team: int, k) -> bool:
	if k.team == viewer_team or not k.in_bush or k.reveal_t > 0.0:
		return true
	for o in knights:
		if o.alive and o.team == viewer_team and o.global_position.distance_to(k.global_position) < 2.6:
			return true
	return false


func _spawn_knights() -> void:
	# составы: у игрока выбранный герой, остальные — случайные разные герои
	var all := ["knight", "archer", "hammer", "mage"]
	var ph := str(Profile.data.get("hero", "knight"))
	var rest := all.duplicate()
	rest.erase(ph)
	rest.shuffle()
	var enemies := all.duplicate()
	enemies.shuffle()
	var comps := [[ph, rest[0], rest[1]], [enemies[0], enemies[1], enemies[2]]]
	for t in 2:
		var sgn := 1.0 if t == 0 else -1.0
		var spots := [Vector3(0, 0, 14.5 * sgn), Vector3(-3, 0, 15.5 * sgn), Vector3(3, 0, 15.5 * sgn)]
		for i in 3:
			var k = KnightScript.new()
			k.main = self
			k.team = t
			k.is_player = (t == 0 and i == 0)
			k.hero = comps[t][i]
			k.role = "defend" if i == 2 else "attack"
			k.spawn_pos = spots[i]
			k.position = spots[i]
			k.facing = Vector3(0, 0, -sgn)
			add_child(k)
			knights.append(k)
			if k.is_player:
				player = k


## Бронзовая монета («Казна»): стоит на ребре и крутится.
func _spawn_battery(p: Vector3) -> void:
	var n := Node3D.new()
	var coin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.26
	cm.height = 0.07
	cm.radial_segments = 20
	coin.mesh = cm
	coin.rotation.x = PI / 2
	coin.material_override = toon(Color(0.85, 0.52, 0.25), true, true)
	n.add_child(coin)
	var face := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.17
	fm.bottom_radius = 0.17
	fm.height = 0.08
	face.mesh = fm
	face.rotation.x = PI / 2
	face.material_override = toon(Color(1.0, 0.68, 0.38), true, false)
	n.add_child(face)
	n.position = Vector3(p.x, 0.55, p.z)
	add_child(n)
	batteries.append(n)


# ---------------------------------------------------------------- интерфейс

func _anchor(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, o_r: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = o_r
	c.offset_bottom = ob


func _label(font_size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.1))
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(root, 0, 0, 1, 1, 0, 0, 0, 0)
	layer.add_child(root)
	_hud = root

	_score_bar = ScoreBarScript.new()
	_score_bar.colors = team_colors
	_score_bar.goal = win_score
	_anchor(_score_bar, 0, 0, 1, 0, 20, 30, -20, 120)
	root.add_child(_score_bar)

	_info = _label(30, Color(1, 0.97, 0.8))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor(_info, 0, 0, 1, 0, 112, 160, -112, 270)
	root.add_child(_info)

	if in_game:                                    # название арены в начале боя
		var an := _label(54, Color(1, 0.85, 0.4), arena.name)
		_anchor(an, 0, 0.3, 1, 0.3, 0, -50, 0, 50)
		root.add_child(an)
		var sub := _label(28, Color(0.9, 0.9, 1.0), "ОБУЧЕНИЕ" if tutorial else str(Profile.MODES[mode].name))
		_anchor(sub, 0, 0.3, 1, 0.3, 0, 40, 0, 90)
		root.add_child(sub)
		var tw := create_tween().set_parallel(true)
		for l in [an, sub]:
			tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(2.2)
		tw.chain().tween_callback(func():
			an.queue_free()
			sub.queue_free())

	_joystick = JoystickScript.new()
	_anchor(_joystick, 0, 0.45, 0.6, 1, 0, 0, 0, 0)
	root.add_child(_joystick)

	var hero_icon: Texture2D = load("res://%s.png" % HERO_ICON.get(str(player.hero), "ic_sword"))
	_attack_btn = TouchButtonScript.new()
	_attack_btn.frame = load("res://ui_btn.png")
	_attack_btn.icon_tex = hero_icon
	_anchor(_attack_btn, 1, 1, 1, 1, -250, -340, -30, -120)
	root.add_child(_attack_btn)

	_ammo_bar = AmmoBarScript.new()
	_ammo_bar.icon_tex = hero_icon
	_anchor(_ammo_bar, 1, 1, 1, 1, -280, -108, -14, -36)
	root.add_child(_ammo_bar)

	_super_btn = TouchButtonScript.new()
	_super_btn.frame = load("res://ui_btn_ult.png")
	_super_btn.icon_tex = hero_icon
	_super_btn.tag = "ULT"
	_anchor(_super_btn, 1, 1, 1, 1, -420, -520, -244, -344)
	_super_btn.pressed.connect(_on_super)
	root.add_child(_super_btn)

	_dash_btn = TouchButtonScript.new()
	_dash_btn.frame = load("res://ui_btn_small.png")
	_dash_btn.icon_tex = load("res://ic_dash.png")
	_anchor(_dash_btn, 1, 1, 1, 1, -186, -506, -50, -370)
	_dash_btn.pressed.connect(_on_dash)
	root.add_child(_dash_btn)

	# джойстик не перехватывает касания по кнопкам
	_joystick.blockers = [_attack_btn, _super_btn, _dash_btn]

	var exit_btn := TouchButtonScript.new()
	exit_btn.frame = load("res://ui_btn_small.png")
	exit_btn.icon_tex = load("res://ic_back.png")
	_anchor(exit_btn, 0, 0, 0, 0, 14, 128, 104, 218)
	exit_btn.pressed.connect(_ask_exit)
	root.add_child(exit_btn)
	_joystick.blockers.append(exit_btn)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(dim, 0, 0, 1, 1, 0, 0, 0, 0)
	_result = dim
	_result.visible = false
	root.add_child(_result)
	_result_label = _label(84, Color.WHITE)
	_anchor(_result_label, 0, 0.35, 1, 0.35, 0, -70, 0, 70)
	_result.add_child(_result_label)
	_result.mouse_filter = Control.MOUSE_FILTER_STOP
	var again := _make_button("ЕЩЁ РАЗ", Color(0.3, 0.75, 0.35), 52)
	_anchor(again, 0.5, 0.5, 0.5, 0.5, -210, 20, 210, 150)
	again.pressed.connect(start_match)
	_result.add_child(again)
	var to_menu := _make_button("В МЕНЮ", Color(0.45, 0.42, 0.62), 40)
	_anchor(to_menu, 0.5, 0.5, 0.5, 0.5, -170, 180, 170, 280)
	to_menu.pressed.connect(go_to_menu)
	_result.add_child(to_menu)


func _update_ui() -> void:
	_score_bar.score = score
	_score_bar.queue_redraw()
	if game_over:
		_info.text = ""
	elif not player.alive:
		_info.text = "Возрождение... %d" % int(ceil(player.respawn_left()))
	elif tutorial and _tut_step < 6:
		_info.text = _tutorial_text()
	elif player.carried > 0:
		_info.text = "Бронзовых монет с собой: %d. Неси к синему знамени!" % player.carried
	elif player.has_flag:
		_info.text = "Знамя у тебя! Неси к своему знамени!"
	elif mode == "flag" and flag_thief(player.team) != null:
		_info.text = "Наше знамя украли! Догони вора!"
	elif _hint_t > 0.0:
		match mode:
			"brawl":
				_info.text = "Схватка! Одолей 10 вражеских героев."
			"flag":
				_info.text = "Укради красное знамя и принеси к своему. До 3 очков!"
			_:
				_info.text = "Собирай бронзовые монеты в центре. В кустах тебя не видно!"
	else:
		_info.text = ""
	_super_btn.fill = player.super_charge
	_super_btn.enabled = player.super_charge >= 1.0
	_super_btn.glow = _super_btn.enabled
	_super_btn.queue_redraw()
	_dash_btn.fill = 1.0 - player.dash_cd / player.DASH_CD
	_dash_btn.enabled = player.dash_cd <= 0.0
	_dash_btn.queue_redraw()
	_attack_btn.enabled = player.ammo >= 1.0
	_attack_btn.queue_redraw()
	_ammo_bar.ammo = player.ammo
	_ammo_bar.queue_redraw()


# ---------------------------------------------------------------- игровой цикл

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_super_key = true
		elif event.physical_keycode == KEY_SHIFT:
			_on_dash()


func _process(delta: float) -> void:
	_hint_t -= delta
	var target: Vector3 = player.global_position if player.alive else player.spawn_pos
	var cam_target := target + CAM_OFFSET
	cam_target.x = clampf(cam_target.x, -8.5, 8.5)
	_camera.position = _camera.position.lerp(cam_target, clampf(delta * 5.0, 0.0, 1.0))
	if _shake > 0.0:                                 # тряска камеры
		_camera.position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * _shake * 0.35
		_shake = maxf(0.0, _shake - delta * 2.5)

	for b in batteries:
		b.rotation.y += delta * 2.5
		b.position.y = 0.55 + sin(Time.get_ticks_msec() * 0.004 + b.position.x) * 0.08

	# кусты рядом с игроком становятся полупрозрачными
	var pp: Vector3 = player.global_position
	for bush in _bushes:
		var near: bool = player.alive and player.in_bush and (bush.pos as Vector3).distance_to(pp) < 2.2
		bush.mesh.material_override = _bush_mat_seen if near else _bush_mat
		bush.sprite.material_override = _sprite_mats_seen[bush.idx] if near else _sprite_mats[bush.idx]

	# враги в кустах скрыты от игрока
	for k in knights:
		if k.alive:
			k.visible = can_see(player.team, k)

	_update_ui()
	if game_over:
		return

	_battery_t -= delta
	if mode == "charge" and _battery_t <= 0.0:
		_battery_t = 3.0
		if batteries.size() < MAX_BATTERIES:
			var a := randf() * TAU
			var rad := randf() * 1.8
			_spawn_battery(Vector3(cos(a) * rad, 0, sin(a) * rad))

	_handle_player_combat()
	if tutorial:
		_update_tutorial(delta)
	_handle_pickups()
	if mode == "flag":
		_update_flags(delta)


## Шаги обучения: ходьба → атака → супер → монеты → кусты.
func _tutorial_text() -> String:
	match _tut_step:
		0:
			return "Двигай джойстик слева — так ходит твой герой"
		1:
			return "Жми большую кнопку справа — атака! (%d/3)" % mini(_tut_attacks, 3)
		2:
			return "Кнопка с бегущим человечком — рывок. Попробуй!"
		3:
			return "Ульта готова! Жми светящуюся кнопку ULT — мощный удар"
		4:
			return "Подбирай бронзовые монеты в центре и неси к синему знамени"
		_:
			return "В кустах тебя не видно. Первыми сдайте 10 монет — победа!"


func _update_tutorial(delta: float) -> void:
	_tut_t += delta
	var next := false
	match _tut_step:
		0:
			if player.alive:
				_tut_moved += Vector2(player.velocity.x, player.velocity.z).length() * delta
			next = _tut_moved > 4.0
		1:
			next = _tut_attacks >= 3
		2:
			next = _tut_dash or _tut_t > 20.0
		3:
			next = _tut_super or _tut_t > 25.0
		4:
			next = score[0] > 0 or _tut_t > 40.0
		5:
			next = _tut_t > 7.0
	if next:
		_tut_step += 1
		_tut_t = 0.0
		if _tut_step < 6:
			sfx("ready")
		if _tut_step == 3:                          # дарим полный супер, чтобы попробовать
			player.super_charge = 1.0
	# подсвечиваем нужную кнопку
	var pulse := 1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.01)
	for b in [_attack_btn, _dash_btn, _super_btn]:
		b.pivot_offset = b.size / 2.0
		b.scale = Vector2.ONE
	if _tut_step == 1:
		_attack_btn.scale = Vector2(pulse, pulse)
	elif _tut_step == 2:
		_dash_btn.scale = Vector2(pulse, pulse)
	elif _tut_step == 3:
		_super_btn.scale = Vector2(pulse, pulse)


func _handle_player_combat() -> void:
	if _super_key:
		_super_key = false
		_on_super()
	if not player.alive:
		return
	if _attack_btn.is_held() or Input.is_physical_key_pressed(KEY_SPACE):
		player.try_attack(_player_aim())


func _player_aim() -> Vector3:
	var e = nearest_enemy(player, 9.0)
	if e:
		return e.global_position - player.global_position
	return player.facing


func _on_dash() -> void:
	if player.alive and not game_over:
		player.try_dash()


## Кнопка «назад» в бою: спросить, точно ли выйти (выход — поражение).
func _ask_exit() -> void:
	if game_over or _exit_box:
		return
	sfx("click")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_anchor(dim, 0, 0, 1, 1, 0, 0, 0, 0)
	_hud.add_child(dim)
	_exit_box = dim
	var l := _label(46, Color.WHITE, "Выйти из боя?")
	_anchor(l, 0, 0.36, 1, 0.36, 0, -60, 0, 0)
	dim.add_child(l)
	var sub := _label(26, Color(1, 0.8, 0.75), "" if tutorial else "Выход засчитается как поражение")
	_anchor(sub, 0, 0.36, 1, 0.36, 0, 0, 0, 44)
	dim.add_child(sub)
	var yes := _make_button("ВЫЙТИ", Color(0.72, 0.16, 0.18), 40)
	_anchor(yes, 0.5, 0.5, 0.5, 0.5, -300, 0, -20, 110)
	dim.add_child(yes)
	var no := _make_button("ОСТАТЬСЯ", Color(0.3, 0.6, 0.38), 40)
	_anchor(no, 0.5, 0.5, 0.5, 0.5, 20, 0, 300, 110)
	dim.add_child(no)
	no.pressed.connect(func():
		dim.queue_free()
		_exit_box = null)
	yes.pressed.connect(func():
		if tutorial:
			Profile.data.tutorial_done = true
			Profile.save()
		elif in_game:
			Profile.match_result(false, match_stats)
		go_to_menu())


func _on_super() -> void:
	if player.alive and not game_over:
		player.try_super(_player_aim())


func _handle_pickups() -> void:
	for k in knights:
		if not k.alive:
			continue
		var kp: Vector3 = k.global_position
		for i in range(batteries.size() - 1, -1, -1):
			var b: Node3D = batteries[i]
			if Vector2(b.position.x - kp.x, b.position.z - kp.z).length() < 0.9:
				k.carried += 1
				batteries.remove_at(i)
				b.queue_free()
				sfx("pickup", kp, 0.0 if k.is_player else -5.0)
				fx_burst(b.position, Color(1.0, 0.7, 0.35), 10, 2.5, 0.06, 0.5, 2.0)
		var st: Vector3 = stations[k.team]
		if k.carried > 0 and Vector2(st.x - kp.x, st.z - kp.z).length() < 1.8:
			fx_text(st + Vector3(0, 2.8, 0), "+%d" % k.carried, Color(1.0, 0.72, 0.4), 90)
			if k.is_player:
				note("crystals", k.carried)
			score[k.team] += k.carried
			k.carried = 0
			sfx("score", null, 0.0 if k.team == player.team else -6.0)
			fx_ring(st, team_colors[k.team], 3.0, 0.6)
			fx_burst(st + Vector3(0, 0.3, 0), (team_colors[k.team] as Color).lightened(0.4), 24, 5.0, 0.08, 0.8, -6.0)
			if score[k.team] >= win_score:
				_end_game(k.team)
				return


func _end_game(winner: int) -> void:
	game_over = true
	if not in_game:                 # бой ботов за меню — просто начинаем заново
		get_tree().create_timer(2.5).timeout.connect(_restart_background)
		return
	if tutorial:
		Profile.data.tutorial_done = true
	var win: bool = winner == player.team
	var res := Profile.match_result(win, match_stats)
	_result.visible = true
	_result_label.text = "ПОБЕДА!" if win else "ПОРАЖЕНИЕ"
	_result_label.add_theme_color_override("font_color", team_colors[winner])
	_show_rewards(res)
	_music.volume_db = -26.0
	sfx("win" if win else "lose")


## Строки наград на экране итога: кубки, монеты, выполненные задания.
func _show_rewards(res: Dictionary) -> void:
	var box := Control.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.35
	box.anchor_bottom = 0.35
	_result.add_child(box)
	var rows := [["trophy", "%+d" % int(res.trophies), Color(1, 0.8, 0.3)],
		["coin", "+%d" % int(res.coins), Color(1, 0.88, 0.45)]]
	for i in rows.size():
		var ic = IconScript.new()
		ic.kind = rows[i][0]
		ic.position = Vector2(-120, 80 + i * 70)
		ic.size = Vector2(60, 60)
		box.add_child(ic)
		var l := _label(46, rows[i][2], rows[i][1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector2(-48, 80 + i * 70)
		l.size = Vector2(220, 60)
		box.add_child(l)
	var done := Profile.quests_ready_count()
	if done > 0:
		var q := _label(28, Color(0.6, 1, 0.6), "Заданий выполнено: %d — забери награду в меню!" % done)
		q.position = Vector2(-340, 230)
		q.size = Vector2(680, 50)
		box.add_child(q)


## Учёт действий игрока для заданий (только в настоящем матче).
func note(stat: String, n := 1) -> void:
	if in_game and not game_over:
		match_stats[stat] = int(match_stats.get(stat, 0)) + n


# ---------------------------------------------------------------- звук

func _setup_audio() -> void:
	for n in SFX_NAMES:
		_sfx[n] = load("res://sfx_%s.wav" % n)
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.stream = load("res://music.wav")
	_music.volume_db = -11.0
	add_child(_music)
	_music.finished.connect(func(): _music.play())   # музыка по кругу
	_music.play()
	_music.stream_paused = not music_on


## Проиграть звук. pos — где он прозвучал (дальше от игрока — тише), null — без затухания.
func sfx(sound: String, pos = null, volume := 0.0) -> void:
	if not _sfx.has(sound) or not sound_on:
		return
	if not in_game and _menu and _menu.visible and sound != "click":
		volume -= 9.0                                 # бой за меню звучит тише
	if pos != null and player:
		var d: float = (pos as Vector3).distance_to(player.global_position)
		if d > 16.0:
			return
		volume -= d * 1.1
	var p: AudioStreamPlayer = null
	for cand in _sfx_pool:
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _sfx_pool[_sfx_next]
		_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _sfx[sound]
	p.volume_db = volume
	p.pitch_scale = randf_range(0.93, 1.07) if sound in ["swing", "hit", "wall", "pickup"] else 1.0
	p.play()


# ---------------------------------------------------------------- для рыцарей

func get_player_move() -> Vector3:
	var v := Vector2.ZERO
	if _joystick:
		v = _joystick.output
	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if kb != Vector2.ZERO:
		v = kb.normalized()
	return Vector3(v.x, 0, v.y)


func nearest_enemy(me, max_dist: float):
	var best = null
	var best_d := max_dist
	for k in knights:
		if k.alive and k.team != me.team and can_see(me.team, k):
			var d: float = k.global_position.distance_to(me.global_position)
			if d < best_d:
				best_d = d
				best = k
	return best


func nearest_battery(pos: Vector3):
	var best = null
	var best_d := INF
	for b in batteries:
		var d: float = b.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


# ---------------------------------------------------------------- «Захват знамени»

func _make_flag(t: int) -> Node3D:
	var n := Node3D.new()
	var col: Color = team_colors[t]
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.05
	pm.height = 2.6
	pole.mesh = pm
	pole.position.y = 1.3
	pole.material_override = toon(Color(0.42, 0.28, 0.16), false, true)
	n.add_child(pole)
	var cloth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.75, 0.9)
	cloth.mesh = bm
	cloth.position = Vector3(0, 2.15, 0.47)
	cloth.material_override = toon(col, true, true)
	n.add_child(cloth)
	var tip := PrismMesh.new()
	tip.size = Vector3(0.9, 0.3, 0.05)
	var tail := MeshInstance3D.new()
	tail.mesh = tip
	tail.position = Vector3(0, 1.64, 0.47)
	tail.rotation = Vector3(0, PI / 2, PI)
	tail.material_override = cloth.material_override
	n.add_child(tail)
	var cross_v := MeshInstance3D.new()
	var cv := BoxMesh.new()
	cv.size = Vector3(0.06, 0.45, 0.1)
	cross_v.mesh = cv
	cross_v.position = Vector3(0, 2.15, 0.47)
	cross_v.material_override = toon(Color(1.0, 0.85, 0.4), false, false)
	n.add_child(cross_v)
	var cross_h := MeshInstance3D.new()
	var ch := BoxMesh.new()
	ch.size = Vector3(0.06, 0.1, 0.4)
	cross_h.mesh = ch
	cross_h.position = Vector3(0, 2.25, 0.47)
	cross_h.material_override = cross_v.material_override
	n.add_child(cross_h)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.09
	km.height = 0.18
	knob.mesh = km
	knob.position.y = 2.65
	knob.material_override = toon(Color(1.0, 0.8, 0.3), true, true)
	n.add_child(knob)
	add_child(n)
	return n


func _spawn_flags() -> void:
	for t in 2:
		var home: Vector3 = stations[t]
		var n := _make_flag(t)
		n.position = home
		flags.append({"node": n, "state": "home", "carrier": null, "pos": home, "t": 0.0})


func _flag_home(t: int) -> void:
	var f: Dictionary = flags[t]
	if f.carrier != null and is_instance_valid(f.carrier):
		f.carrier.has_flag = false
	f.state = "home"
	f.carrier = null
	f.pos = stations[t]
	f.node.position = stations[t]
	f.node.scale = Vector3.ONE
	fx_ring(stations[t], team_colors[t], 2.2, 0.5)


func _drop_flag(k) -> void:
	for t in flags.size():
		var f: Dictionary = flags[t]
		if f.carrier == k:
			k.has_flag = false
			f.state = "dropped"
			f.carrier = null
			f.pos = Vector3(k.global_position.x, 0, k.global_position.z)
			f.node.position = f.pos
			f.node.scale = Vector3.ONE
			f.t = 8.0
			fx_text(f.pos + Vector3(0, 3.0, 0), "Знамя упало!", team_colors[t], 60)


func _update_flags(delta: float) -> void:
	for t in flags.size():
		var f: Dictionary = flags[t]
		match f.state:
			"carried":
				var c = f.carrier
				f.pos = c.global_position
				f.node.position = c.global_position + Vector3(0, 0.1, 0) - (c.facing as Vector3) * 0.3
				f.node.scale = Vector3(0.75, 0.75, 0.75)
				# донёс до своего знамени, и своё знамя дома — очко
				var own: Dictionary = flags[c.team]
				var st: Vector3 = stations[c.team]
				if own.state == "home" and Vector2(st.x - f.pos.x, st.z - f.pos.z).length() < 1.8:
					score[c.team] += 1
					fx_text(st + Vector3(0, 3.0, 0), "ЗНАМЯ ЗАХВАЧЕНО!", team_colors[c.team], 80)
					fx_burst(st + Vector3(0, 0.5, 0), (team_colors[c.team] as Color).lightened(0.4), 30, 6.0, 0.09, 0.9, -6.0)
					sfx("score")
					shake(0.4, st)
					_flag_home(t)
					if score[c.team] >= win_score:
						_end_game(c.team)
						return
				continue
			"dropped":
				f.t -= delta
				if f.t <= 0.0:
					_flag_home(t)
					continue
			_:
				f.node.rotation.y = sin(Time.get_ticks_msec() * 0.0015) * 0.3
		for k in knights:
			if not k.alive:
				continue
			var kp: Vector3 = k.global_position
			if Vector2(kp.x - f.pos.x, kp.z - f.pos.z).length() > 1.1:
				continue
			if k.team != t and not k.has_flag:
				f.state = "carried"
				f.carrier = k
				k.has_flag = true
				sfx("pickup", kp)
				fx_text(kp + Vector3(0, 3.0, 0), "Знамя украдено!", team_colors[k.team], 64)
				break
			elif k.team == t and f.state == "dropped":
				sfx("respawn", kp)
				_flag_home(t)
				break


## Кто несёт знамя команды team (или null).
func flag_thief(t: int):
	if flags.size() < 2:
		return null
	var f: Dictionary = flags[t]
	return f.carrier if f.state == "carried" else null


## Куда идти атакующему: к вражескому знамени, а если его уже несёт свой — к своей базе.
func flag_target(t: int) -> Vector3:
	var e: Dictionary = flags[1 - t]
	if e.state == "carried":
		return stations[t]
	return e.pos


# ---------------------------------------------------------------- огонь мага

## Взрыв огненного шара: урон врагам в радиусе. Возвращает число задетых.
func explode(attacker, t: int, pos: Vector3, radius: float, dmg: float, color: Color) -> int:
	var hits := 0
	for k in knights:
		if k.alive and k.team != t and Vector2(k.global_position.x - pos.x, k.global_position.z - pos.z).length() < radius:
			k.take_damage(dmg, attacker if is_instance_valid(attacker) else null)
			hits += 1
	sfx("slam", pos, -9.0)
	fx_ring(Vector3(pos.x, 0, pos.z), color, radius, 0.35)
	fx_burst(pos, color.lightened(0.3), 16, 4.0, 0.1, 0.45, 1.0)
	fx_burst(pos, Color(0.3, 0.25, 0.25, 0.8), 8, 2.0, 0.16, 0.6, 1.5)
	return hits


## «Метеор» мага: метка на земле, через 0.7 с падает огненный шар и взрывается.
func meteor(attacker, pos: Vector3, radius: float, dmg: float, color: Color) -> void:
	pos.x = clampf(pos.x, -HALF_W + 0.5, HALF_W - 0.5)
	pos.z = clampf(pos.z, -HALF_L + 0.5, HALF_L - 0.5)
	pos.y = 0.0
	var t: int = attacker.team
	var mark := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.15
	tm.outer_radius = radius
	tm.rings = 40
	mark.mesh = tm
	mark.scale.y = 0.1
	mark.position = pos + Vector3(0, 0.06, 0)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(color.r, color.g, color.b, 0.7)
	mark.material_override = mm
	add_child(mark)
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	rock.mesh = sm
	rock.material_override = toon(color, true, true)
	rock.position = pos + Vector3(2.5, 10.0, -2.5)
	add_child(rock)
	var tw := create_tween()
	tw.tween_property(rock, "position", pos + Vector3(0, 0.4, 0), 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		mark.queue_free()
		rock.queue_free()
		if game_over:
			return
		var hits := 0
		for k in knights:
			if k.alive and k.team != t and Vector2(k.global_position.x - pos.x, k.global_position.z - pos.z).length() < radius:
				k.take_damage(dmg, attacker if is_instance_valid(attacker) else null)
				hits += 1
		sfx("slam", pos)
		fx_ring(pos, color, radius, 0.45)
		fx_ring(pos, Color(1, 0.9, 0.6), radius * 0.6, 0.6)
		fx_burst(pos + Vector3(0, 0.3, 0), color.lightened(0.3), 30, 7.0, 0.12, 0.8, -6.0)
		fx_burst(pos + Vector3(0, 0.2, 0), Color(0.35, 0.3, 0.3, 0.8), 14, 3.0, 0.2, 0.8, 1.0)
		shake(0.7, pos))


## «Удар по земле» Молотобойца: урон всем врагам в радиусе, волна, камни, тряска.
func ground_slam(attacker, pos: Vector3, radius: float, dmg: float) -> void:
	for k in knights:
		if k.alive and k.team != attacker.team and k.global_position.distance_to(pos) < radius:
			k.take_damage(dmg, attacker)
	sfx("slam", pos)
	fx_ring(pos, Color(0.45, 0.75, 1.0), radius, 0.4)
	fx_ring(pos, Color(0.8, 0.7, 0.55), radius * 0.6, 0.55)
	fx_burst(pos + Vector3(0, 0.2, 0), Color(0.5, 0.48, 0.62), 18, 6.0, 0.16, 0.9, -14.0)
	fx_burst(pos + Vector3(0, 0.1, 0), Color(0.82, 0.74, 0.6, 0.8), 14, 3.0, 0.2, 0.7, 0.5)
	shake(0.7, pos)


func on_knight_died(k, killer = null) -> void:
	if k.has_flag:
		_drop_flag(k)
	if killer != null and is_instance_valid(killer) and killer == player:
		note("kos")
	if mode == "brawl" and not game_over:
		var t := 1 - int(k.team)
		score[t] += 1
		fx_text(stations[t] + Vector3(0, 2.8, 0), "+1", team_colors[t], 80)
		if score[t] >= win_score:
			_end_game(t)
	var count: int = k.carried
	k.carried = 0
	for i in count:
		var p: Vector3 = k.global_position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		p.x = clampf(p.x, -HALF_W + 0.8, HALF_W - 0.8)
		p.z = clampf(p.z, -HALF_L + 0.8, HALF_L - 0.8)
		_spawn_battery(_free_spot(p))


# ---------------------------------------------------------------- эффекты

var _fx_mats := {}


func _fx_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _fx_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fx_mats[key] = m
	return _fx_mats[key]


## Взрыв частиц: искры, обломки, пыль. gravity < 0 — падают, > 0 — всплывают.
func fx_burst(pos: Vector3, color: Color, amount := 12, speed := 4.0, size := 0.08,
		life := 0.5, gravity := -9.0) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, size)
	mesh.material = _fx_mat(color)
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.color = color
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## Расходящееся кольцо по земле (супер, сдача кристаллов, возрождение).
func fx_ring(pos: Vector3, color: Color, radius := 2.5, time := 0.45) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.85
	t.outer_radius = 1.0
	t.rings = 32
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color.lightened(0.3)
	mi.material_override = m
	mi.position = Vector3(pos.x, 0.08, pos.z)
	mi.scale = Vector3(0.2, 0.05, 0.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Всплывающий текст над головой (урон, очки).
func fx_text(pos: Vector3, text: String, color: Color, size := 64) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(randf_range(-0.25, 0.25), 0, 0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + 1.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


## Тряска камеры; сильнее, если событие близко к игроку.
func shake(amount: float, pos = null) -> void:
	if not shake_on:
		return
	if pos != null and player:
		amount *= clampf(1.0 - (pos as Vector3).distance_to(player.global_position) / 10.0, 0.0, 1.0)
	_shake = maxf(_shake, amount)


# ---------------------------------------------------------------- меню

func _make_button(text: String, color: Color, font_size := 44) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.1))
	b.add_theme_constant_override("outline_size", 10)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var c := color
		if state == "hover":
			c = color.lightened(0.1)
		elif state == "pressed":
			c = color.darkened(0.15)
		sb.bg_color = c
		sb.set_corner_radius_all(26)
		sb.set_border_width_all(6)
		sb.border_color = Color(0.1, 0.07, 0.1)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 0 if state == "pressed" else 8
		sb.shadow_offset = Vector2(0, 6)
		if state == "pressed":
			sb.content_margin_top = 6
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func(): sfx("click"))
	return b


func _open_menu() -> void:
	player.autopilot = true
	_hud.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_menu = MenuScript.new()
	_menu.main = self
	layer.add_child(_menu)


func _restart_background() -> void:
	if not in_game and is_inside_tree():
		get_tree().reload_current_scene()


func start_match() -> void:
	in_game = true
	get_tree().reload_current_scene()


func go_to_menu() -> void:
	in_game = false
	get_tree().reload_current_scene()


## Применить настройки профиля (звук, музыка, тряска).
func apply_settings() -> void:
	var st: Dictionary = Profile.data.settings
	sound_on = st.get("sound", true)
	music_on = st.get("music", true)
	shake_on = st.get("shake", true)
	if _music:
		_music.stream_paused = not music_on


func _load_settings() -> void:
	apply_settings()
