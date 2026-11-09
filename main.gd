extends Node3D
## Главная сцена: двор замка, команды рыцарей, батарейки-кристаллы, интерфейс.
## Режим «Зарядка»: собирай кристаллы в центре и неси на свою станцию.
## Первая команда, набравшая WIN_SCORE, побеждает.

const KnightScript = preload("res://knight.gd")
const JoystickScript = preload("res://joystick.gd")
const TouchButtonScript = preload("res://touch_button.gd")
const ScoreBarScript = preload("res://score_bar.gd")

const HALF_W := 12.0
const HALF_L := 20.0
const WIN_SCORE := 10
const MAX_BATTERIES := 8
const CAM_OFFSET := Vector3(0, 11.5, 5.5)

# Карта верхней половины (24 x 20). Нижняя половина — зеркальная.
# '#' — каменный блок, 'b' — куст, '.' — трава
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

var team_colors := [Color(0.22, 0.52, 1.0), Color(0.95, 0.25, 0.22)]
var stations := [Vector3(0, 0, HALF_L - 3.0), Vector3(0, 0, -HALF_L + 3.0)]
var knights: Array = []
var batteries: Array = []
var score := [0, 0]
var game_over := false
var player

var _grid: Array = []          # строки полной карты
var _bushes: Array = []        # [{pos, mesh}]
var _mat_cache := {}
var _tex := {}
var _bush_mat: StandardMaterial3D
var _bush_mat_seen: StandardMaterial3D

var _camera: Camera3D
var _joystick
var _attack_btn
var _super_btn
var _score_bar
var _info: Label
var _result: Control
var _result_label: Label
var _battery_t := 1.0
var _hint_t := 6.0
var _super_key := false


func _ready() -> void:
	randomize()
	for tex_name in ["grass", "stone", "leaves"]:
		_tex[tex_name] = load("res://%s.png" % tex_name)
	_grid = MAP_TOP.duplicate()
	for i in range(MAP_TOP.size() - 1, -1, -1):
		var src: String = MAP_TOP[i]
		var rev := ""
		for j in range(src.length() - 1, -1, -1):
			rev += src[j]
		_grid.append(rev)
	_build_world()
	_build_arena()
	_spawn_knights()
	_build_ui()
	_setup_screenshots()


## Режим автоскриншотов: godot --path . -- --shots=/путь/к/папке
## Игрок управляется ботом, игра снимает 3 кадра и закрывается.
func _setup_screenshots() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	player.autopilot = true
	_hint_t = 0.0
	var times := [5.0, 11.0, 18.0]
	for i in times.size():
		await get_tree().create_timer(times[i] - (times[i - 1] if i > 0 else 0.0)).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [dir, i + 1])
		print("saved shot ", i + 1)
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
	env.background_color = Color(0.16, 0.36, 0.22)
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
	_box(Vector3(0, -0.25, 0), Vector3(HALF_W * 2 + 8, 0.5, HALF_L * 2 + 8), _textured("grass", Color.WHITE, 0.5), false)

	# живая изгородь по периметру (твёрдая)
	var hedge := _textured("leaves", Color(0.62, 0.78, 0.6), 1.0)
	var hh := 1.6
	_box(Vector3(0, hh / 2, -HALF_L - 1), Vector3(HALF_W * 2 + 4, hh, 2), hedge)
	_box(Vector3(0, hh / 2, HALF_L + 1), Vector3(HALF_W * 2 + 4, hh, 2), hedge)
	_box(Vector3(-HALF_W - 1, hh / 2, 0), Vector3(2, hh, HALF_L * 2), hedge)
	_box(Vector3(HALF_W + 1, hh / 2, 0), Vector3(2, hh, HALF_L * 2), hedge)

	# блоки и кусты по карте
	var stone := _textured("stone", Color.WHITE, 1.0)
	var cap := toon(Color(0.36, 0.7, 0.32))
	_bush_mat = _textured("leaves", Color.WHITE, 1.0)
	_bush_mat_seen = _bush_mat.duplicate() as StandardMaterial3D
	_bush_mat_seen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bush_mat_seen.albedo_color = Color(1, 1, 1, 0.45)
	for row in _grid.size():
		var line: String = _grid[row]
		for col in line.length():
			var p := _cell_pos(col, row)
			match line[col]:
				"#":
					_box(p + Vector3(0, 0.6, 0), Vector3(1, 1.2, 1), stone)
					if (col * 7 + row * 3) % 5 == 0:       # мох на некоторых блоках
						_box(p + Vector3(0, 1.23, 0), Vector3(0.7, 0.06, 0.7), cap, false)
				"b":
					var m := _box(p + Vector3(0, 0.55, 0), Vector3(1.02, 1.1, 1.02), _bush_mat, false)
					for k in 3:                              # пушистый верх
						var off := Vector3(randf_range(-0.3, 0.3), 1.1 + randf() * 0.1, randf_range(-0.3, 0.3))
						var t := MeshInstance3D.new()
						var sm := SphereMesh.new()
						sm.radius = randf_range(0.28, 0.36)
						sm.height = sm.radius * 1.5
						t.mesh = sm
						t.position = off
						t.material_override = _bush_mat
						m.add_child(t)
					_bushes.append({"pos": p, "mesh": m})

	# центр, где появляются кристаллы
	_disc(Vector3.ZERO, 2.3, toon(Color(0.86, 0.76, 0.5)))
	_disc(Vector3.ZERO, 1.9, toon(Color(0.95, 0.86, 0.58)), 0.08)

	# станции команд: каменный круг + арка со знаменем
	for t in 2:
		var s: Vector3 = stations[t]
		var col: Color = team_colors[t]
		var back := 1.0 if t == 0 else -1.0
		_disc(s, 1.8, toon(Color(0.85, 0.8, 0.72)))
		_disc(s, 1.45, toon(col, true), 0.09)
		for dx in [-1.5, 1.5]:
			_box(s + Vector3(dx, 1.2, 1.7 * back), Vector3(0.45, 2.4, 0.45), stone)
		_box(s + Vector3(0, 2.55, 1.7 * back), Vector3(3.5, 0.4, 0.5), stone)
		_box(s + Vector3(0, 1.7, 1.7 * back), Vector3(1.2, 1.3, 0.06), toon(col), false)


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
	for t in 2:
		var sgn := 1.0 if t == 0 else -1.0
		var spots := [Vector3(0, 0, 14.5 * sgn), Vector3(-3, 0, 15.5 * sgn), Vector3(3, 0, 15.5 * sgn)]
		for i in 3:
			var k = KnightScript.new()
			k.main = self
			k.team = t
			k.is_player = (t == 0 and i == 0)
			k.spawn_pos = spots[i]
			k.position = spots[i]
			k.facing = Vector3(0, 0, -sgn)
			add_child(k)
			knights.append(k)
			if k.is_player:
				player = k


func _spawn_battery(p: Vector3) -> void:
	var n := Node3D.new()
	var gem := MeshInstance3D.new()
	var pm := PrismMesh.new()                       # кристалл из двух пирамид
	pm.size = Vector3(0.32, 0.32, 0.32)
	gem.mesh = pm
	gem.material_override = toon(Color(0.35, 1.0, 0.6), true, true)
	gem.position.y = 0.16
	n.add_child(gem)
	var gem2 := MeshInstance3D.new()
	gem2.mesh = pm
	gem2.material_override = gem.material_override
	gem2.rotation.z = PI
	gem2.position.y = -0.16
	n.add_child(gem2)
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

	_score_bar = ScoreBarScript.new()
	_score_bar.colors = team_colors
	_score_bar.goal = WIN_SCORE
	_anchor(_score_bar, 0, 0, 1, 0, 20, 30, -20, 120)
	root.add_child(_score_bar)

	_info = _label(30, Color(1, 0.97, 0.8))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor(_info, 0, 0, 1, 0, 30, 130, -30, 230)
	root.add_child(_info)

	_joystick = JoystickScript.new()
	_anchor(_joystick, 0, 0.45, 0.6, 1, 0, 0, 0, 0)
	root.add_child(_joystick)

	_attack_btn = TouchButtonScript.new()
	_attack_btn.icon = "sword"
	_attack_btn.color = Color(0.95, 0.5, 0.18)
	_anchor(_attack_btn, 1, 1, 1, 1, -260, -330, -50, -120)
	root.add_child(_attack_btn)

	_super_btn = TouchButtonScript.new()
	_super_btn.icon = "star"
	_super_btn.color = Color(1.0, 0.8, 0.15)
	_anchor(_super_btn, 1, 1, 1, 1, -370, -510, -230, -370)
	_super_btn.pressed.connect(_on_super)
	root.add_child(_super_btn)

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
	var again = TouchButtonScript.new()
	again.label_text = "ЕЩЁ РАЗ"
	again.color = Color(0.3, 0.8, 0.4)
	_anchor(again, 0.5, 0.5, 0.5, 0.5, -120, 0, 120, 240)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	_result.add_child(again)


func _update_ui() -> void:
	_score_bar.score = score
	_score_bar.queue_redraw()
	if game_over:
		_info.text = ""
	elif not player.alive:
		_info.text = "Рыцарь встаёт... %d" % int(ceil(player.respawn_left()))
	elif player.carried > 0:
		_info.text = "Кристаллов с собой: %d. Неси к синему знамени!" % player.carried
	elif _hint_t > 0.0:
		_info.text = "Собирай кристаллы в центре. В кустах тебя не видно!"
	else:
		_info.text = ""
	_super_btn.fill = player.super_charge
	_super_btn.enabled = player.super_charge >= 1.0
	_super_btn.queue_redraw()


# ---------------------------------------------------------------- игровой цикл

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_super_key = true


func _process(delta: float) -> void:
	_hint_t -= delta
	var target: Vector3 = player.global_position if player.alive else player.spawn_pos
	var cam_target := target + CAM_OFFSET
	cam_target.x = clampf(cam_target.x, -7.0, 7.0)
	_camera.position = _camera.position.lerp(cam_target, clampf(delta * 5.0, 0.0, 1.0))

	for b in batteries:
		b.rotation.y += delta * 2.5
		b.position.y = 0.55 + sin(Time.get_ticks_msec() * 0.004 + b.position.x) * 0.08

	# кусты рядом с игроком становятся полупрозрачными
	var pp: Vector3 = player.global_position
	for bush in _bushes:
		var near: bool = player.alive and player.in_bush and (bush.pos as Vector3).distance_to(pp) < 2.2
		bush.mesh.material_override = _bush_mat_seen if near else _bush_mat
		for c in bush.mesh.get_children():
			c.material_override = bush.mesh.material_override

	# враги в кустах скрыты от игрока
	for k in knights:
		if k.alive:
			k.visible = can_see(player.team, k)

	_update_ui()
	if game_over:
		return

	_battery_t -= delta
	if _battery_t <= 0.0:
		_battery_t = 3.0
		if batteries.size() < MAX_BATTERIES:
			var a := randf() * TAU
			var rad := randf() * 1.8
			_spawn_battery(Vector3(cos(a) * rad, 0, sin(a) * rad))

	_handle_player_combat()
	_handle_pickups()


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
		var st: Vector3 = stations[k.team]
		if k.carried > 0 and Vector2(st.x - kp.x, st.z - kp.z).length() < 1.8:
			score[k.team] += k.carried
			k.carried = 0
			if score[k.team] >= WIN_SCORE:
				_end_game(k.team)
				return


func _end_game(winner: int) -> void:
	game_over = true
	_result.visible = true
	_result_label.text = "ПОБЕДА!" if winner == player.team else "ПОРАЖЕНИЕ"
	_result_label.add_theme_color_override("font_color", team_colors[winner])


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


func on_knight_died(k) -> void:
	var count: int = k.carried
	k.carried = 0
	for i in count:
		var p: Vector3 = k.global_position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		p.x = clampf(p.x, -HALF_W + 0.8, HALF_W - 0.8)
		p.z = clampf(p.z, -HALF_L + 0.8, HALF_L - 0.8)
		_spawn_battery(p)
