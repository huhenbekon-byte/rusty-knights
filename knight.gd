extends CharacterBody3D
## Рыцарь: шлем с плюмажем, щит, меч. Управляется игроком или простым ИИ.
## Атака — волна меча, супер — «Веер клинков» из 7 волн.

const BoltScript = preload("res://bolt.gd")

var team := 0
var is_player := false
var autopilot := false   # игрок под управлением бота (меню, автоскриншоты)
var display_only := false  # витрина в меню: только модель, без логики
var _last_attacker = null
var main  # главная сцена (main.gd)
var spawn_pos := Vector3.ZERO

var hero := "knight"       # knight | archer
var max_hp := 100.0
var hp := 100.0
var speed := 5.0
var attack_range := 8.0    # с какого расстояния бот начинает бить
var keep_dist := 4.5       # на каком расстоянии бот держится от врага
var carried := 0
var super_charge := 0.0
var alive := true
var in_bush := false
var reveal_t := 0.0
var facing := Vector3(0, 0, -1)
var move_dir := Vector3.ZERO

var _attack_cd := 0.0
var _aim_hold := 0.0
var _since_hit := 10.0
var _respawn_t := 0.0
var _walk_t := 0.0
var _dust_t := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _stuck_t := 0.0
var _unstuck_t := 0.0
var _unstuck_dir := Vector3.ZERO

var _visual: Node3D
var _body: Node3D
var _sword: Node3D
var _legs: Array = []
var _hp_fill: MeshInstance3D
var _carry_label: Label3D


func _apply_hero_stats() -> void:
	if hero == "archer":
		max_hp = 75.0
		speed = 5.4
		attack_range = 11.0
		keep_dist = 7.0
	hp = max_hp


func _ready() -> void:
	_apply_hero_stats()
	if display_only:
		_build_visual()
		set_physics_process(false)
		return
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.3
	cs.shape = cap
	cs.position.y = 0.7
	add_child(cs)
	_build_visual()
	_build_hud()


# ---------------------------------------------------------------- модель

func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color,
		rot := Vector3.ZERO, scl := Vector3.ONE, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.material_override = main.toon(color, glow, true)
	parent.add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 16
	return m


func _boxm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _kite(parent: Node3D, scale_k: float, depth: float, z: float, color: Color) -> void:
	# щит-«капля»: выдавленный многоугольник
	var poly := CSGPolygon3D.new()
	var pts := PackedVector2Array([
		Vector2(-0.27, 0.28), Vector2(0.27, 0.28), Vector2(0.27, 0.02),
		Vector2(0.16, -0.26), Vector2(0.0, -0.46), Vector2(-0.16, -0.26), Vector2(-0.27, 0.02)])
	for i in pts.size():
		pts[i] = pts[i] * scale_k
	poly.polygon = pts
	poly.depth = depth
	poly.position.z = z
	poly.material = main.toon(color, false, true)
	parent.add_child(poly)


func _build_visual() -> void:
	if hero == "archer":
		_build_archer()
		_finish_visual()
		return
	_visual = Node3D.new()
	add_child(_visual)
	var tc: Color = main.team_colors[team]
	var cloth := tc.darkened(0.3)                    # накидка и щит — цвет команды
	var steel := Color(0.62, 0.64, 0.7)
	var dark_steel := Color(0.36, 0.37, 0.42)
	if is_player and hero == "knight":               # облик доспехов из профиля
		var sk: Array = Profile.skin_colors()
		steel = sk[0]
		dark_steel = sk[1]
	var under := Color(0.2, 0.17, 0.17)              # поддоспешник
	var leather := Color(0.32, 0.21, 0.14)
	var silver := Color(0.86, 0.87, 0.9)             # крест
	var black := Color(0.05, 0.04, 0.06)

	# ноги: поножи, наколенники, сабатоны
	for sx in [-0.15, 0.15]:
		var leg := Node3D.new()
		leg.position = Vector3(sx, 0.5, 0)
		_visual.add_child(leg)
		_part(leg, _capsule(0.11, 0.5), Vector3(0, -0.2, 0), under)
		_part(leg, _cyl(0.12, 0.1, 0.26), Vector3(0, -0.3, 0.01), steel)
		_part(leg, _sphere(0.1), Vector3(0, -0.12, 0.07), steel, Vector3.ZERO, Vector3(1, 1, 0.8))
		_part(leg, _boxm(Vector3(0.18, 0.09, 0.32)), Vector3(0, -0.46, 0.05), dark_steel)
		_legs.append(leg)

	_body = Node3D.new()
	_visual.add_child(_body)
	# корпус: кольчуга, кираса
	_part(_body, _cyl(0.26, 0.3, 0.45), Vector3(0, 0.78, 0), dark_steel)
	_part(_body, _sphere(0.3), Vector3(0, 1.0, 0.0), steel, Vector3.ZERO, Vector3(1.05, 0.9, 0.85))
	# длинная накидка спереди и сзади с рваным низом
	for zs in [1.0, -1.0]:
		var zz: float = 0.315 * zs
		_part(_body, _boxm(Vector3(0.34, 0.66, 0.03)), Vector3(0, 0.72, zz), cloth)
		for i in 3:
			var tooth := PrismMesh.new()
			tooth.size = Vector3(0.11, 0.1, 0.03)
			_part(_body, tooth, Vector3(-0.11 + i * 0.11, 0.34, zz), cloth, Vector3(0, 0, PI))
		# крест
		_part(_body, _boxm(Vector3(0.05, 0.26, 0.02)), Vector3(0, 0.86, zz + 0.02 * zs), silver)
		_part(_body, _boxm(Vector3(0.18, 0.05, 0.02)), Vector3(0, 0.9, zz + 0.02 * zs), silver)
	# пояс с пряжкой
	_part(_body, _cyl(0.3, 0.3, 0.06), Vector3(0, 0.66, 0), leather)
	_part(_body, _boxm(Vector3(0.08, 0.07, 0.03)), Vector3(0, 0.66, 0.3), steel)
	# многослойные наплечники и руки
	for sx in [-1.0, 1.0]:
		for i in 3:
			var r := 0.17 - i * 0.025
			_part(_body, _sphere(r), Vector3(0.32 * sx, 1.16 - i * 0.08, 0), steel if i % 2 == 0 else cloth,
				Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
		_part(_body, _capsule(0.08, 0.36), Vector3(0.36 * sx, 0.92, 0.03), steel)
	# топфхельм: цилиндр с плоским верхом, смотровая щель и дырочки для дыхания
	_part(_body, _cyl(0.21, 0.23, 0.38), Vector3(0, 1.42, 0), steel)
	_part(_body, _cyl(0.17, 0.21, 0.06), Vector3(0, 1.63, 0), steel)
	_part(_body, _cyl(0.225, 0.225, 0.07), Vector3(0, 1.57, 0), cloth)   # тканевый обод цвета команды
	_part(_body, _boxm(Vector3(0.03, 0.34, 0.03)), Vector3(0, 1.42, 0.225), dark_steel)
	_part(_body, _boxm(Vector3(0.34, 0.045, 0.04)), Vector3(0, 1.47, 0.21), black)
	for i in 3:                                       # дырочки для дыхания
		for hx in [-0.08, 0.08]:
			_part(_body, _boxm(Vector3(0.035, 0.025, 0.03)), Vector3(hx, 1.37 - i * 0.045, 0.218), black)
	_part(_body, _cyl(0.24, 0.24, 0.04), Vector3(0, 1.25, 0), dark_steel)

	# щит-«капля» на левой руке
	var shield := Node3D.new()
	shield.position = Vector3(0.46, 0.88, 0.1)
	shield.rotation = Vector3(0, deg_to_rad(70), 0)
	_body.add_child(shield)
	_kite(shield, 1.12, 0.04, -0.02, dark_steel)     # обод
	_kite(shield, 1.0, 0.05, 0.0, cloth)
	_part(shield, _boxm(Vector3(0.06, 0.5, 0.02)), Vector3(0, -0.04, 0.03), silver)
	_part(shield, _boxm(Vector3(0.34, 0.06, 0.02)), Vector3(0, 0.08, 0.03), silver)

	# длинный меч в правой руке
	_sword = Node3D.new()
	_sword.position = Vector3(-0.42, 0.78, 0.12)
	_body.add_child(_sword)
	_part(_sword, _sphere(0.09), Vector3.ZERO, steel)                               # перчатка
	_part(_sword, _boxm(Vector3(0.05, 0.05, 0.2)), Vector3(0, 0, -0.04), leather)   # рукоять
	_part(_sword, _boxm(Vector3(0.07, 0.07, 0.07)), Vector3(0, 0, -0.16), steel, Vector3(0, 0, PI / 4))
	_part(_sword, _boxm(Vector3(0.34, 0.05, 0.05)), Vector3(0, 0, 0.08), dark_steel)  # гарда
	for gx in [-0.17, 0.17]:
		_part(_sword, _boxm(Vector3(0.06, 0.06, 0.06)), Vector3(gx, 0, 0.08), dark_steel, Vector3(0, PI / 4, 0))
	_part(_sword, _boxm(Vector3(0.085, 0.025, 0.82)), Vector3(0, 0, 0.51), Color(0.85, 0.87, 0.92))
	_part(_sword, _boxm(Vector3(0.02, 0.03, 0.7)), Vector3(0, 0, 0.47), Color(0.6, 0.62, 0.68))  # дол
	var tip := PrismMesh.new()
	tip.size = Vector3(0.085, 0.1, 0.025)
	_part(_sword, tip, Vector3(0, 0, 0.97), Color(0.85, 0.87, 0.92), Vector3(PI / 2, 0, 0))

	_finish_visual()


## Лучница: капюшон и плащ цвета команды, зелёная туника, колчан за спиной, лук в левой руке.
func _build_archer() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var tc: Color = main.team_colors[team]
	var cloak := tc.darkened(0.25)
	var tunic := Color(0.32, 0.58, 0.24)
	var leather := Color(0.44, 0.27, 0.15)
	var dark := Color(0.22, 0.17, 0.14)
	var skin := Color(0.97, 0.8, 0.64)
	var hair := Color(0.45, 0.27, 0.14)
	var gold := Color(1.0, 0.78, 0.3)
	var ink := Color(0.08, 0.06, 0.08)

	# ноги в сапогах
	for sx in [-0.12, 0.12]:
		var leg := Node3D.new()
		leg.position = Vector3(sx, 0.46, 0)
		_visual.add_child(leg)
		_part(leg, _capsule(0.09, 0.42), Vector3(0, -0.18, 0), dark)
		_part(leg, _cyl(0.105, 0.115, 0.24), Vector3(0, -0.33, 0.01), leather)
		_part(leg, _boxm(Vector3(0.16, 0.08, 0.26)), Vector3(0, -0.43, 0.05), leather)
		_legs.append(leg)

	_body = Node3D.new()
	_visual.add_child(_body)
	# туника, пояс с пряжкой, перевязь
	_part(_body, _cyl(0.21, 0.29, 0.4), Vector3(0, 0.66, 0), tunic)
	_part(_body, _sphere(0.24), Vector3(0, 0.92, 0), tunic, Vector3.ZERO, Vector3(1, 0.9, 0.85))
	_part(_body, _cyl(0.245, 0.245, 0.06), Vector3(0, 0.64, 0), leather)
	_part(_body, _boxm(Vector3(0.08, 0.07, 0.03)), Vector3(0, 0.64, 0.25), gold)
	_part(_body, _boxm(Vector3(0.05, 0.52, 0.03)), Vector3(0.0, 0.9, 0.2), leather, Vector3(0, 0, deg_to_rad(35)))
	# плащ сзади с рваным краем
	_part(_body, _boxm(Vector3(0.48, 0.74, 0.04)), Vector3(0, 0.74, -0.25), cloak, Vector3(deg_to_rad(8), 0, 0))
	for i in 3:
		var tooth := PrismMesh.new()
		tooth.size = Vector3(0.16, 0.13, 0.04)
		_part(_body, tooth, Vector3(-0.16 + i * 0.16, 0.32, -0.29), cloak, Vector3(0, 0, PI))
	# руки и перчатки
	for sx in [-1.0, 1.0]:
		_part(_body, _capsule(0.07, 0.34), Vector3(0.27 * sx, 0.88, 0.04), tunic)
		_part(_body, _sphere(0.075), Vector3(0.3 * sx, 0.72, 0.08), leather)
	# лицо, глаза, чёлка
	_part(_body, _sphere(0.19), Vector3(0, 1.27, 0.03), skin)
	for ex in [-0.07, 0.07]:
		_part(_body, _boxm(Vector3(0.045, 0.06, 0.02)), Vector3(ex, 1.28, 0.21), ink)
	_part(_body, _boxm(Vector3(0.3, 0.08, 0.07)), Vector3(0, 1.39, 0.15), hair, Vector3(deg_to_rad(-15), 0, 0))
	# капюшон с золотой каймой и хвостиком
	_part(_body, _sphere(0.26), Vector3(0, 1.32, -0.09), cloak, Vector3.ZERO, Vector3(1.05, 1.0, 1.05))
	var trim := TorusMesh.new()
	trim.inner_radius = 0.17
	trim.outer_radius = 0.21
	_part(_body, trim, Vector3(0, 1.3, 0.12), gold, Vector3(PI / 2, 0, 0))
	_part(_body, _capsule(0.07, 0.32), Vector3(0, 1.48, -0.3), cloak, Vector3(-1.0, 0, 0))
	# колчан со стрелами за спиной
	var quiver := Node3D.new()
	quiver.position = Vector3(0.14, 1.0, -0.32)
	quiver.rotation = Vector3(0, 0, -0.35)
	_body.add_child(quiver)
	_part(quiver, _cyl(0.09, 0.08, 0.46), Vector3.ZERO, leather)
	_part(quiver, _cyl(0.095, 0.095, 0.05), Vector3(0, 0.2, 0), gold)
	for j in 3:
		var ax := -0.04 + j * 0.04
		_part(quiver, _boxm(Vector3(0.02, 0.22, 0.02)), Vector3(ax, 0.32, 0), Color(0.75, 0.6, 0.4))
		var fl := PrismMesh.new()
		fl.size = Vector3(0.07, 0.1, 0.02)
		_part(quiver, fl, Vector3(ax, 0.46, 0), Color(0.97, 0.97, 0.95))
	# лук в левой руке (тетива смотрит назад, дуга — вперёд)
	_sword = Node3D.new()
	_sword.position = Vector3(0.34, 0.84, 0.2)
	_body.add_child(_sword)
	var n := 9
	for j in n:
		var t := lerpf(-1.15, 1.15, float(j) / float(n - 1))
		var pos := Vector3(0, sin(t) * 0.42, cos(t) * 0.13)
		_part(_sword, _boxm(Vector3(0.05, 0.12, 0.05)), pos, leather if absf(t) > 0.3 else gold, Vector3(-t, 0, 0))
	var chord := 2.0 * sin(1.15) * 0.42
	var string := _part(_sword, _boxm(Vector3(0.012, chord, 0.012)), Vector3(0, 0, cos(1.15) * 0.13), Color(0.95, 0.93, 0.85))
	string.material_override = main.toon(Color(0.95, 0.93, 0.85), false, false)


func _finish_visual() -> void:
	var tc: Color = main.team_colors[team]
	_visual.rotation.y = atan2(facing.x, facing.z)
	if display_only:
		return

	# кольцо-маркер под героем
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.55
	t.outer_radius = 0.68
	ring.mesh = t
	ring.position.y = 0.03
	ring.scale.y = 0.3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.88, 0.3) if is_player else tc.lightened(0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not is_player:
		m.albedo_color.a = 0.55
	ring.material_override = m
	add_child(ring)


func _bar_quad(color: Color, size: Vector2, prio: int, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position.y = y
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = prio
	mi.material_override = m
	add_child(mi)
	return mi


func _build_hud() -> void:
	_bar_quad(Color(0.08, 0.06, 0.1, 0.85), Vector2(1.1, 0.2), 0, 2.15)
	var bar_col: Color = Color(0.35, 0.95, 0.35) if is_player else (main.team_colors[team] as Color).lightened(0.2)
	_hp_fill = _bar_quad(bar_col, Vector2(1.0, 0.12), 1, 2.15)
	_carry_label = Label3D.new()
	_carry_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_carry_label.position.y = 2.5
	_carry_label.font_size = 72
	_carry_label.outline_size = 16
	_carry_label.modulate = Color(0.45, 1, 0.65)
	_carry_label.no_depth_test = true
	_carry_label.visible = false
	add_child(_carry_label)


# ---------------------------------------------------------------- цикл

func _physics_process(delta: float) -> void:
	if not alive:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn()
		return
	if main.game_over:
		return

	_attack_cd -= delta
	_aim_hold -= delta
	_since_hit += delta
	reveal_t -= delta
	if _since_hit > 3.0:
		hp = minf(max_hp, hp + 20.0 * delta)

	if is_player and not autopilot:
		move_dir = main.get_player_move()
	else:
		_think(delta)
	if move_dir.length() < 0.15:
		move_dir = Vector3.ZERO

	velocity = Vector3(move_dir.x, 0, move_dir.z) * speed
	move_and_slide()
	position.y = 0.0
	in_bush = main.is_bush(global_position)
	if not is_player:
		_check_stuck(delta)

	if _aim_hold <= 0.0 and move_dir != Vector3.ZERO:
		facing = move_dir.normalized()
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 14.0))
	_animate(delta)
	# пыль из-под ног (в кустах не пылим, чтобы не выдавать засаду)
	if move_dir != Vector3.ZERO and not in_bush:
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.22
			main.fx_burst(global_position + Vector3(0, 0.05, 0), Color(0.82, 0.82, 0.95, 0.7), 3, 0.9, 0.1, 0.35, 0.6)

	_hp_fill.scale.x = maxf(0.001, hp / max_hp)
	_hp_fill.position.x = 0.0
	_carry_label.visible = carried > 0
	_carry_label.text = "+%d" % carried


func _animate(delta: float) -> void:
	var moving := move_dir != Vector3.ZERO
	if moving:
		_walk_t += delta * 11.0
	else:
		_walk_t = lerpf(_walk_t, round(_walk_t / PI) * PI, minf(1.0, delta * 10.0))
	var s := sin(_walk_t)
	_legs[0].rotation.x = s * 0.6
	_legs[1].rotation.x = -s * 0.6
	_body.position.y = absf(s) * 0.06
	_body.rotation.z = s * 0.04


# ---------------------------------------------------------------- бой

func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	if v.length() < 0.001:
		return facing
	return v.normalized()


func _spawn_wave(dir: Vector3, dmg: float, life: float, kind := "wave", spd := 16.0,
		pierce := false, radius := 0.65) -> void:
	var b = BoltScript.new()
	b.kind = kind
	b.speed = spd
	b.pierce = pierce
	b.hit_radius = radius
	b.main = main
	b.shooter = self
	b.team = team
	b.dir = dir
	b.damage = dmg
	b.life = life
	b.position = global_position + Vector3(0, 0.8, 0) + dir * 0.5
	main.add_child(b)


func _swing() -> void:
	reveal_t = 1.0
	var tw := create_tween()
	if hero == "archer":                      # натянуть лук и отпустить
		tw.tween_property(_sword, "position:z", 0.08, 0.07)
		tw.tween_property(_sword, "position:z", 0.26, 0.06)
		tw.tween_property(_sword, "position:z", 0.2, 0.12)
		return
	tw.tween_property(_sword, "rotation:y", 1.3, 0.06)
	tw.tween_property(_sword, "rotation:y", -0.9, 0.1)
	tw.tween_property(_sword, "rotation:y", 0.0, 0.18)


func try_attack(aim: Vector3) -> bool:
	if not alive or _attack_cd > 0.0:
		return false
	_attack_cd = 0.45 if is_player else 0.9
	facing = _flat(aim)
	_aim_hold = 0.35
	_swing()
	if hero == "archer":
		_attack_cd = 0.5 if is_player else 0.95
		_spawn_wave(facing, 17.0, 0.55, "arrow", 22.0)
	else:
		_spawn_wave(facing, 20.0, 0.6)
	main.sfx("swing", global_position, 0.0 if is_player else -4.0)
	return true


func try_super(aim: Vector3) -> bool:
	if not alive or super_charge < 1.0:
		return false
	super_charge = 0.0
	facing = _flat(aim)
	_aim_hold = 0.4
	_swing()
	if hero == "archer":
		# «Стрела ветра»: одна большая стрела, пробивает всех на пути
		_spawn_wave(facing, 42.0, 0.75, "wind", 24.0, true, 0.95)
	else:
		for i in 7:
			var a := deg_to_rad(-30.0 + i * 10.0)
			_spawn_wave(facing.rotated(Vector3.UP, a), 28.0, 0.75)
	main.sfx("super", global_position)
	if is_player:
		main.note("supers")
	main.fx_ring(global_position, main.team_colors[team], 3.4, 0.4)
	main.fx_burst(global_position + Vector3(0, 0.9, 0), Color(1, 0.9, 0.5), 18, 6.0, 0.07, 0.45, -4.0)
	if is_player:
		main.shake(0.3)
	return true


func add_charge(amount: float) -> void:
	var was_ready := super_charge >= 1.0
	super_charge = minf(1.0, super_charge + amount)
	if is_player and not was_ready and super_charge >= 1.0:
		main.sfx("ready")


func take_damage(amount: float, attacker) -> void:
	if not alive:
		return
	_last_attacker = attacker
	if attacker != null and is_instance_valid(attacker) and attacker == main.player:
		main.note("hits")
	hp -= amount
	_since_hit = 0.0
	main.sfx("hit", global_position, 0.0 if is_player else -2.0)
	main.fx_burst(global_position + Vector3(0, 1.0, 0), Color(1, 0.85, 0.4), 10, 4.0, 0.06, 0.35)
	main.fx_text(global_position + Vector3(0, 2.3, 0), "-%d" % int(amount),
		Color(1, 0.35, 0.3) if is_player else Color(1, 1, 1))
	if is_player:
		main.shake(0.35)
	reveal_t = maxf(reveal_t, 0.6)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.15).from(Vector3(1.2, 0.85, 1.2))
	if hp <= 0.0:
		_die()


func _die() -> void:
	alive = false
	visible = false
	collision_layer = 0
	_respawn_t = 3.0
	main.sfx("death", global_position)
	# доспехи разлетаются: сталь и ткань цвета команды
	main.fx_burst(global_position + Vector3(0, 0.9, 0),
		Color(0.44, 0.27, 0.15) if hero == "archer" else Color(0.62, 0.64, 0.7), 12, 6.0, 0.16, 1.1, -14.0)
	main.fx_burst(global_position + Vector3(0, 0.8, 0), (main.team_colors[team] as Color).darkened(0.3), 8, 4.5, 0.14, 1.0, -12.0)
	main.fx_ring(global_position, Color(0.8, 0.8, 0.9), 2.0, 0.5)
	main.shake(0.6, global_position)
	main.on_knight_died(self, _last_attacker)


func _respawn() -> void:
	global_position = spawn_pos
	hp = max_hp
	alive = true
	visible = true
	collision_layer = 2
	_visual.scale = Vector3.ONE
	main.fx_ring(spawn_pos, main.team_colors[team], 1.8, 0.5)
	main.fx_burst(spawn_pos + Vector3(0, 0.3, 0), (main.team_colors[team] as Color).lightened(0.5), 14, 3.0, 0.06, 0.7, 3.0)
	if is_player:
		main.sfx("respawn")


func respawn_left() -> float:
	return maxf(0.0, _respawn_t)


# ---------------------------------------------------------------- ИИ

func _think(delta: float) -> void:
	if _unstuck_t > 0.0:
		_unstuck_t -= delta
		move_dir = _unstuck_dir
		return

	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe = -_strafe
		_strafe_t = randf_range(0.8, 2.0)

	var enemy = main.nearest_enemy(self, attack_range)
	if enemy:
		var to_e: Vector3 = enemy.global_position - global_position
		if _attack_cd <= 0.0:
			try_attack(to_e.rotated(Vector3.UP, deg_to_rad(randf_range(-9.0, 9.0))))
		if super_charge >= 1.0:
			try_super(to_e)

	var home: Vector3 = main.stations[team]
	var target := Vector3.ZERO
	if carried >= 3 or (carried > 0 and main.batteries.is_empty()) or hp < 35.0:
		target = home
	elif enemy and carried == 0:
		var to2: Vector3 = enemy.global_position - global_position
		to2.y = 0.0
		var d := to2.length()
		var side := Vector3(-to2.z, 0, to2.x).normalized() * _strafe
		var approach := to2.normalized() * clampf((d - keep_dist) * 0.5, -1.0, 1.0)
		move_dir = (approach + side * 0.8).normalized()
		return
	elif main.mode == "brawl":
		# «Схватка»: ищем ближайшего видимого врага по всей арене
		var far = main.nearest_enemy(self, 60.0)
		if far:
			target = far.global_position
		elif hp < max_hp:
			target = home
	else:
		var bat = main.nearest_battery(global_position)
		if bat:
			target = bat.global_position
	var v := target - global_position
	v.y = 0.0
	move_dir = v.normalized() if v.length() > 0.4 else Vector3.ZERO


func _check_stuck(delta: float) -> void:
	if move_dir == Vector3.ZERO or _unstuck_t > 0.0:
		_stuck_t = 0.0
		return
	if get_real_velocity().length() < speed * 0.3:
		_stuck_t += delta
		if _stuck_t > 0.35:
			_stuck_t = 0.0
			_unstuck_t = 0.7
			var turn := PI / 2.0 if randf() < 0.5 else -PI / 2.0
			_unstuck_dir = move_dir.rotated(Vector3.UP, turn)
	else:
		_stuck_t = 0.0
