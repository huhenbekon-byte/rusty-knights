extends CharacterBody3D
## Герой арены: рыцарь, лучница, молотобоец или маг. Управляется игроком или ИИ.
## Цвета и небольшой бонус берутся из облика (Profile.SKINS), бонус — только у игрока.

const BoltScript = preload("res://bolt.gd")

var team := 0
var is_player := false
var autopilot := false     # игрок под управлением бота (меню, автоскриншоты)
var display_only := false  # витрина в меню: только модель, без логики
var skin_id := ""          # облик для витрины; пусто — из профиля (игрок) или базовый (бот)
var role := "attack"       # для ИИ в «Захвате знамени»: attack | defend
var _last_attacker = null
var main                   # главная сцена (main.gd)
var spawn_pos := Vector3.ZERO

var hero := "knight"       # knight | archer | hammer | mage
var max_hp := 100.0
var hp := 100.0
var speed := 5.0
var dmg_mult := 1.0
var attack_range := 8.0    # с какого расстояния бот начинает бить
var keep_dist := 4.5       # на каком расстоянии бот держится от врага
var carried := 0           # бронзовые монеты с собой («Казна»)
var has_flag := false      # несёт вражеское знамя («Захват знамени»)
var super_charge := 0.0
var alive := true
var in_bush := false
var reveal_t := 0.0
var facing := Vector3(0, 0, -1)
var move_dir := Vector3.ZERO
var skin_cols := {}        # цвета облика

var _attack_cd := 0.0
var _aim_hold := 0.0
var _aware_t := 0.0        # сколько бот уже видит цель (реакция)
var _super_wait := 0.0
var _since_hit := 10.0
var _respawn_t := 0.0
var _walk_t := 0.0
var _idle_t := 0.0
var _dust_t := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _stuck_t := 0.0
var _unstuck_t := 0.0
var _unstuck_dir := Vector3.ZERO
var _leap_t := 0.0         # прыжок Молотобойца
var _leap_dir := Vector3.ZERO

var _visual: Node3D
var _body: Node3D
var _sword: Node3D         # оружие: меч, лук, молот или посох
var _legs: Array = []
var _cape: Node3D
var _hp_fill: MeshInstance3D
var _carry_label: Label3D

const BASE := {
	"knight": {"hp": 100.0, "speed": 5.0, "range": 8.0, "keep": 4.5},
	"archer": {"hp": 80.0, "speed": 5.4, "range": 11.0, "keep": 7.0},
	"hammer": {"hp": 130.0, "speed": 4.5, "range": 4.0, "keep": 1.4},
	"mage": {"hp": 75.0, "speed": 5.0, "range": 9.5, "keep": 6.0},
}


func _apply_hero_stats() -> void:
	var b: Dictionary = BASE.get(hero, BASE["knight"])
	max_hp = b.hp
	speed = b.speed
	attack_range = b.range
	keep_dist = b.keep
	var sid := skin_id
	if sid == "":
		sid = Profile.skin_of(hero) if is_player else Profile.default_skin(hero)
	var sk: Dictionary = Profile.skin_def(hero, sid)
	skin_cols = sk.get("cols", {})
	if is_player or display_only:
		var bonus: Dictionary = sk.get("bonus", {})
		max_hp *= 1.0 + float(bonus.get("hp", 0.0))
		speed *= 1.0 + float(bonus.get("speed", 0.0))
		dmg_mult = 1.0 + float(bonus.get("dmg", 0.0))
	if not is_player and not display_only:
		speed *= 0.93        # боты чуть медленнее игрока
		dmg_mult = 0.8       # и бьют слабее
	hp = max_hp


func _col(key: String, fallback: Color) -> Color:
	return skin_cols.get(key, fallback)


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


# ================================================================ детали модели

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


func _cyl(top: float, bottom: float, h: float, seg := 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	return m


func _boxm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t


func _teeth(parent: Node3D, n: int, width: float, y: float, z: float, color: Color, depth := 0.04) -> void:
	for i in n:
		var tooth := PrismMesh.new()
		tooth.size = Vector3(width / n, 0.12, depth)
		_part(parent, tooth, Vector3(-width / 2.0 + width / n * (i + 0.5), y, z), color, Vector3(0, 0, PI))


func _kite(parent: Node3D, scale_k: float, depth: float, z: float, color: Color) -> void:
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


func _legs_pair(spread: float, hip: float, pants: Color, boot: Color, knee := Color.TRANSPARENT,
		thick := 0.1) -> void:
	for sx in [-spread, spread]:
		var leg := Node3D.new()
		leg.position = Vector3(sx, hip, 0)
		_visual.add_child(leg)
		_part(leg, _capsule(thick, hip - 0.04), Vector3(0, -(hip - 0.04) * 0.4, 0), pants)
		_part(leg, _cyl(thick + 0.015, thick + 0.025, 0.24), Vector3(0, -hip + 0.17, 0.01), boot)
		_part(leg, _boxm(Vector3(thick * 1.7, 0.09, 0.3)), Vector3(0, -hip + 0.045, 0.05), boot)
		if knee.a > 0.0:
			_part(leg, _sphere(thick * 0.95), Vector3(0, -hip * 0.32, 0.07), knee, Vector3.ZERO, Vector3(1, 1, 0.75))
		_legs.append(leg)


func _new_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_body = Node3D.new()
	_visual.add_child(_body)


func _build_visual() -> void:
	match hero:
		"archer":
			_build_archer()
		"hammer":
			_build_hammer()
		"mage":
			_build_mage()
		_:
			_build_knight()
	_finish_visual()


# ================================================================ Рыцарь

func _build_knight() -> void:
	_new_visual()
	var tc: Color = main.team_colors[team]
	var cloth := tc.darkened(0.3)
	var steel := _col("steel", Color(0.62, 0.64, 0.7))
	var dark_steel := _col("dark", Color(0.36, 0.37, 0.42))
	var under := Color(0.2, 0.17, 0.17)
	var leather := Color(0.32, 0.21, 0.14)
	var silver := Color(0.86, 0.87, 0.9)
	var black := Color(0.05, 0.04, 0.06)

	_legs_pair(0.15, 0.5, under, dark_steel, steel, 0.11)
	for leg in _legs:
		_part(leg, _cyl(0.12, 0.1, 0.26), Vector3(0, -0.3, 0.01), steel)

	_part(_body, _cyl(0.26, 0.3, 0.45), Vector3(0, 0.78, 0), dark_steel)
	_part(_body, _sphere(0.3), Vector3(0, 1.0, 0.0), steel, Vector3.ZERO, Vector3(1.05, 0.9, 0.85))
	for zs in [1.0, -1.0]:
		var zz: float = 0.315 * zs
		_part(_body, _boxm(Vector3(0.34, 0.66, 0.03)), Vector3(0, 0.72, zz), cloth)
		_teeth(_body, 3, 0.33, 0.34, zz, cloth, 0.03)
		_part(_body, _boxm(Vector3(0.05, 0.26, 0.02)), Vector3(0, 0.86, zz + 0.02 * zs), silver)
		_part(_body, _boxm(Vector3(0.18, 0.05, 0.02)), Vector3(0, 0.9, zz + 0.02 * zs), silver)
	_part(_body, _cyl(0.3, 0.3, 0.06), Vector3(0, 0.66, 0), leather)
	_part(_body, _boxm(Vector3(0.08, 0.07, 0.03)), Vector3(0, 0.66, 0.3), steel)
	for sx in [-1.0, 1.0]:
		for i in 3:
			var r := 0.17 - i * 0.025
			_part(_body, _sphere(r), Vector3(0.32 * sx, 1.16 - i * 0.08, 0), steel if i % 2 == 0 else cloth,
				Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
		_part(_body, _capsule(0.08, 0.36), Vector3(0.36 * sx, 0.92, 0.03), steel)
	# топфхельм
	_part(_body, _cyl(0.21, 0.23, 0.38), Vector3(0, 1.42, 0), steel)
	_part(_body, _cyl(0.17, 0.21, 0.06), Vector3(0, 1.63, 0), steel)
	_part(_body, _cyl(0.225, 0.225, 0.07), Vector3(0, 1.57, 0), cloth)
	_part(_body, _boxm(Vector3(0.03, 0.34, 0.03)), Vector3(0, 1.42, 0.225), dark_steel)
	_part(_body, _boxm(Vector3(0.34, 0.045, 0.04)), Vector3(0, 1.47, 0.21), black)
	for i in 3:
		for hx in [-0.08, 0.08]:
			_part(_body, _boxm(Vector3(0.035, 0.025, 0.03)), Vector3(hx, 1.37 - i * 0.045, 0.218), black)
	_part(_body, _cyl(0.24, 0.24, 0.04), Vector3(0, 1.25, 0), dark_steel)
	# щит
	var shield := Node3D.new()
	shield.position = Vector3(0.46, 0.88, 0.1)
	shield.rotation = Vector3(0, deg_to_rad(70), 0)
	_body.add_child(shield)
	_kite(shield, 1.12, 0.04, -0.02, dark_steel)
	_kite(shield, 1.0, 0.05, 0.0, cloth)
	_part(shield, _boxm(Vector3(0.06, 0.5, 0.02)), Vector3(0, -0.04, 0.03), silver)
	_part(shield, _boxm(Vector3(0.34, 0.06, 0.02)), Vector3(0, 0.08, 0.03), silver)
	# меч
	_sword = Node3D.new()
	_sword.position = Vector3(-0.42, 0.78, 0.12)
	_body.add_child(_sword)
	_part(_sword, _sphere(0.09), Vector3.ZERO, steel)
	_part(_sword, _boxm(Vector3(0.05, 0.05, 0.2)), Vector3(0, 0, -0.04), leather)
	_part(_sword, _boxm(Vector3(0.07, 0.07, 0.07)), Vector3(0, 0, -0.16), steel, Vector3(0, 0, PI / 4))
	_part(_sword, _boxm(Vector3(0.34, 0.05, 0.05)), Vector3(0, 0, 0.08), dark_steel)
	for gx in [-0.17, 0.17]:
		_part(_sword, _boxm(Vector3(0.06, 0.06, 0.06)), Vector3(gx, 0, 0.08), dark_steel, Vector3(0, PI / 4, 0))
	_part(_sword, _boxm(Vector3(0.085, 0.025, 0.82)), Vector3(0, 0, 0.51), Color(0.85, 0.87, 0.92))
	_part(_sword, _boxm(Vector3(0.02, 0.03, 0.7)), Vector3(0, 0, 0.47), Color(0.6, 0.62, 0.68))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.085, 0.1, 0.025)
	_part(_sword, tip, Vector3(0, 0, 0.97), Color(0.85, 0.87, 0.92), Vector3(PI / 2, 0, 0))


# ================================================================ Лучница

func _build_archer() -> void:
	_new_visual()
	var tc: Color = main.team_colors[team]
	var cloak := tc.darkened(0.25)
	var tunic := _col("tunic", Color(0.32, 0.58, 0.24))
	var trim := _col("trim", Color(1.0, 0.78, 0.3))
	var leather := _col("leather", Color(0.44, 0.27, 0.15))
	var dark := Color(0.22, 0.17, 0.14)
	var skin := Color(0.97, 0.8, 0.64)
	var hair := Color(0.45, 0.27, 0.14)
	var ink := Color(0.08, 0.06, 0.08)

	_legs_pair(0.12, 0.46, dark, leather, Color.TRANSPARENT, 0.09)
	for leg in _legs:                                   # отвороты сапог
		_part(leg, _cyl(0.125, 0.125, 0.05), Vector3(0, -0.21, 0.01), trim)

	# туника с подолом-«лепестками», пояс, перевязь, наплечник
	_part(_body, _cyl(0.21, 0.29, 0.4), Vector3(0, 0.66, 0), tunic)
	_teeth(_body, 4, 0.5, 0.45, 0.2, tunic, 0.06)
	_part(_body, _sphere(0.24), Vector3(0, 0.92, 0), tunic, Vector3.ZERO, Vector3(1, 0.9, 0.85))
	_part(_body, _cyl(0.245, 0.245, 0.06), Vector3(0, 0.64, 0), leather)
	_part(_body, _boxm(Vector3(0.08, 0.07, 0.03)), Vector3(0, 0.64, 0.25), trim)
	_part(_body, _boxm(Vector3(0.1, 0.1, 0.06)), Vector3(-0.2, 0.58, 0.16), leather)      # сумочка
	_part(_body, _boxm(Vector3(0.05, 0.52, 0.03)), Vector3(0.0, 0.9, 0.2), leather, Vector3(0, 0, deg_to_rad(35)))
	_part(_body, _sphere(0.11), Vector3(-0.27, 1.07, 0), leather, Vector3.ZERO, Vector3(1, 0.6, 1))
	# плащ сзади
	_cape = Node3D.new()
	_cape.position = Vector3(0, 1.1, -0.24)
	_body.add_child(_cape)
	_part(_cape, _boxm(Vector3(0.48, 0.74, 0.04)), Vector3(0, -0.36, 0), cloak)
	_teeth(_cape, 3, 0.48, -0.78, -0.01, cloak)
	_part(_cape, _boxm(Vector3(0.5, 0.04, 0.05)), Vector3(0, -0.01, 0.01), trim)
	# руки, наручи, перчатки
	for sx in [-1.0, 1.0]:
		_part(_body, _capsule(0.07, 0.34), Vector3(0.27 * sx, 0.88, 0.04), tunic)
		_part(_body, _cyl(0.08, 0.075, 0.12), Vector3(0.29 * sx, 0.79, 0.06), leather)
		_part(_body, _sphere(0.075), Vector3(0.3 * sx, 0.71, 0.08), leather)
	# лицо
	_part(_body, _sphere(0.19), Vector3(0, 1.27, 0.03), skin)
	for ex in [-0.07, 0.07]:
		_part(_body, _boxm(Vector3(0.045, 0.06, 0.02)), Vector3(ex, 1.28, 0.21), ink)
		_part(_body, _boxm(Vector3(0.06, 0.015, 0.02)), Vector3(ex, 1.33, 0.205), hair, Vector3(0, 0, 0.25 * signf(ex)))
	_part(_body, _boxm(Vector3(0.3, 0.08, 0.07)), Vector3(0, 1.39, 0.15), hair, Vector3(deg_to_rad(-15), 0, 0))
	for hx in [-1.0, 1.0]:                               # пряди по бокам
		_part(_body, _capsule(0.05, 0.22), Vector3(0.16 * hx, 1.2, 0.08), hair)
	# капюшон с каймой и острым концом
	_part(_body, _sphere(0.26), Vector3(0, 1.32, -0.09), cloak, Vector3.ZERO, Vector3(1.05, 1.0, 1.05))
	_part(_body, _torus(0.17, 0.21), Vector3(0, 1.3, 0.12), trim, Vector3(PI / 2, 0, 0))
	var point := _cyl(0.0, 0.11, 0.34, 12)
	_part(_body, point, Vector3(0, 1.48, -0.3), cloak, Vector3(-1.1, 0, 0))
	_part(_body, _cyl(0.24, 0.27, 0.1), Vector3(0, 1.12, -0.02), cloak)                  # ворот
	# колчан
	var quiver := Node3D.new()
	quiver.position = Vector3(0.14, 1.0, -0.33)
	quiver.rotation = Vector3(0, 0, -0.35)
	_body.add_child(quiver)
	_part(quiver, _cyl(0.09, 0.08, 0.46), Vector3.ZERO, leather)
	_part(quiver, _cyl(0.095, 0.095, 0.05), Vector3(0, 0.2, 0), trim)
	_part(quiver, _cyl(0.095, 0.095, 0.04), Vector3(0, -0.16, 0), trim)
	for j in 3:
		var ax := -0.04 + j * 0.04
		_part(quiver, _boxm(Vector3(0.02, 0.22, 0.02)), Vector3(ax, 0.32, 0), Color(0.75, 0.6, 0.4))
		var fl := PrismMesh.new()
		fl.size = Vector3(0.07, 0.1, 0.02)
		_part(quiver, fl, Vector3(ax, 0.46, 0), Color(0.97, 0.97, 0.95))
	# лук
	_sword = Node3D.new()
	_sword.position = Vector3(0.34, 0.84, 0.2)
	_body.add_child(_sword)
	var n := 9
	for j in n:
		var t := lerpf(-1.15, 1.15, float(j) / float(n - 1))
		_part(_sword, _boxm(Vector3(0.05, 0.12, 0.05)), Vector3(0, sin(t) * 0.42, cos(t) * 0.13),
			leather if absf(t) > 0.3 else trim, Vector3(-t, 0, 0))
	for e in [-1.0, 1.0]:
		_part(_sword, _sphere(0.035), Vector3(0, sin(1.15) * 0.42 * e, cos(1.15) * 0.13), trim)
	var chord := 2.0 * sin(1.15) * 0.42
	var string := _part(_sword, _boxm(Vector3(0.012, chord, 0.012)), Vector3(0, 0, cos(1.15) * 0.13), Color(0.95, 0.93, 0.85))
	string.material_override = main.toon(Color(0.95, 0.93, 0.85), false, false)


# ================================================================ Молотобоец

func _build_hammer() -> void:
	_new_visual()
	var tc: Color = main.team_colors[team]
	var cloth := tc.darkened(0.3)
	var steel := _col("steel", Color(0.4, 0.42, 0.5))
	var dark := _col("dark", Color(0.25, 0.26, 0.32))
	var fur := _col("fur", Color(0.88, 0.8, 0.64))
	var leather := Color(0.4, 0.25, 0.15)
	var pants := Color(0.24, 0.17, 0.14)
	var gold := Color(1.0, 0.72, 0.28)
	var eye := Color(0.45, 0.8, 1.0)

	_legs_pair(0.17, 0.46, pants, leather, steel, 0.12)
	for leg in _legs:                                   # ремешки на сапогах
		_part(leg, _cyl(0.145, 0.145, 0.04), Vector3(0, -0.3, 0.01), Color(0.3, 0.18, 0.1))

	_part(_body, _cyl(0.36, 0.33, 0.5), Vector3(0, 0.82, 0), steel)
	_part(_body, _sphere(0.36), Vector3(0, 1.0, 0.02), steel, Vector3.ZERO, Vector3(1.05, 0.8, 0.85))
	for i in 3:                                        # пластины на животе
		_part(_body, _boxm(Vector3(0.36 - i * 0.04, 0.05, 0.04)), Vector3(0, 0.88 - i * 0.08, 0.33), dark)
	for sgn in [-1.0, 1.0]:
		_part(_body, _boxm(Vector3(0.07, 0.62, 0.03)), Vector3(0, 0.98, 0.32), leather, Vector3(0, 0, deg_to_rad(32) * sgn))
	_part(_body, _sphere(0.06), Vector3(0, 0.98, 0.34), gold)
	_part(_body, _cyl(0.37, 0.37, 0.08), Vector3(0, 0.6, 0), leather)
	_part(_body, _boxm(Vector3(0.12, 0.1, 0.03)), Vector3(0, 0.6, 0.37), gold)
	for px in [-0.26, 0.26]:                            # сумки на поясе
		_part(_body, _boxm(Vector3(0.12, 0.13, 0.08)), Vector3(px, 0.54, 0.3), leather)
	_part(_body, _boxm(Vector3(0.3, 0.3, 0.03)), Vector3(0, 0.42, 0.33), cloth)
	_teeth(_body, 3, 0.3, 0.24, 0.33, cloth, 0.03)
	# плащ
	_cape = Node3D.new()
	_cape.position = Vector3(0, 1.13, -0.33)
	_body.add_child(_cape)
	_part(_cape, _boxm(Vector3(0.6, 0.82, 0.04)), Vector3(0, -0.41, 0), cloth)
	_teeth(_cape, 4, 0.6, -0.88, -0.01, cloth)
	_part(_cape, _boxm(Vector3(0.14, 0.14, 0.02)), Vector3(0, -0.27, -0.03), gold, Vector3(0, 0, PI / 4))
	# воротник и шарф
	for k in 12:
		var a := k * TAU / 12.0
		_part(_body, _sphere(0.1), Vector3(cos(a) * 0.3, 1.2 + 0.02 * sin(a * 3.0), sin(a) * 0.25), fur)
	_part(_body, _cyl(0.24, 0.27, 0.12), Vector3(0, 1.22, 0.02), cloth)
	_part(_body, _boxm(Vector3(0.12, 0.3, 0.04)), Vector3(0.12, 1.06, 0.3), cloth, Vector3(0, 0, -0.25))
	# наплечники, руки
	for sx in [-1.0, 1.0]:
		_part(_body, _sphere(0.2), Vector3(0.43 * sx, 1.13, 0), dark, Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
		_part(_body, _torus(0.15, 0.2), Vector3(0.43 * sx, 1.08, 0), gold)
		_part(_body, _sphere(0.04), Vector3(0.43 * sx, 1.27, 0), gold)
		_part(_body, _capsule(0.1, 0.4), Vector3(0.46 * sx, 0.88, 0.05), leather)
		_part(_body, _cyl(0.12, 0.115, 0.12), Vector3(0.47 * sx, 0.76, 0.08), dark)
		_part(_body, _sphere(0.11), Vector3(0.48 * sx, 0.66, 0.1), dark)
	# шлем
	_part(_body, _sphere(0.25), Vector3(0, 1.45, 0), dark, Vector3.ZERO, Vector3(1, 1.05, 1))
	_part(_body, _boxm(Vector3(0.36, 0.3, 0.08)), Vector3(0, 1.4, 0.2), steel)
	_part(_body, _boxm(Vector3(0.05, 0.3, 0.03)), Vector3(0, 1.4, 0.25), dark)
	_part(_body, _boxm(Vector3(0.3, 0.05, 0.03)), Vector3(0, 1.45, 0.25), Color(0.04, 0.04, 0.06))
	for ex in [-0.08, 0.08]:
		_part(_body, _boxm(Vector3(0.06, 0.035, 0.02)), Vector3(ex, 1.45, 0.265), eye, Vector3.ZERO, Vector3.ONE, true)
	for i in 4:                                        # заклёпки
		_part(_body, _sphere(0.022), Vector3(-0.15 + i * 0.1, 1.29, 0.245), gold)
	_part(_body, _torus(0.23, 0.27), Vector3(0, 1.36, 0), gold)
	_part(_body, _boxm(Vector3(0.05, 0.08, 0.3)), Vector3(0, 1.69, 0), gold)
	# молот
	_sword = Node3D.new()
	_sword.position = Vector3(-0.48, 0.72, 0.12)
	_body.add_child(_sword)
	_part(_sword, _cyl(0.035, 0.035, 0.9), Vector3(0, 0, 0.32), leather, Vector3(PI / 2, 0, 0))
	for k in 3:
		_part(_sword, _cyl(0.042, 0.042, 0.05), Vector3(0, 0, k * 0.12), Color(0.3, 0.18, 0.1), Vector3(PI / 2, 0, 0))
	_part(_sword, _boxm(Vector3(0.44, 0.32, 0.3)), Vector3(0, 0, 0.8), steel)
	for cx in [-1.0, 1.0]:
		_part(_sword, _boxm(Vector3(0.06, 0.36, 0.34)), Vector3(0.22 * cx, 0, 0.8), gold)
	_part(_sword, _boxm(Vector3(0.18, 0.16, 0.02)), Vector3(0, 0.0, 0.96), gold, Vector3(0, 0, PI / 4))
	_part(_sword, _sphere(0.05), Vector3(0, 0, -0.14), gold)


# ================================================================ Маг

## Маг: длинная мантия цвета команды с каймой облика, остроконечная шляпа с полями,
## пояс с книгой, посох со светящейся сферой.
func _build_mage() -> void:
	_new_visual()
	var tc: Color = main.team_colors[team]
	var robe := tc.darkened(0.25)
	var trim := _col("trim", Color(0.92, 0.84, 0.58))
	var orb := _col("orb", Color(1.0, 0.55, 0.15))
	var leather := Color(0.36, 0.22, 0.14)
	var skin := Color(0.96, 0.8, 0.66)
	var ink := Color(0.08, 0.06, 0.08)
	var wood := Color(0.42, 0.27, 0.15)

	# мантия до пола — ноги прячутся под ней (двигаем только носки сапог)
	for sx in [-0.11, 0.11]:
		var leg := Node3D.new()
		leg.position = Vector3(sx, 0.2, 0)
		_visual.add_child(leg)
		_part(leg, _boxm(Vector3(0.14, 0.08, 0.24)), Vector3(0, -0.16, 0.08), leather)
		_legs.append(leg)
	_part(_body, _cyl(0.24, 0.36, 0.86), Vector3(0, 0.47, 0), robe)
	_part(_body, _cyl(0.37, 0.37, 0.05), Vector3(0, 0.06, 0), trim)
	_part(_body, _boxm(Vector3(0.09, 0.8, 0.03)), Vector3(0, 0.5, 0.31), trim, Vector3(-0.15, 0, 0))
	_part(_body, _sphere(0.25), Vector3(0, 0.95, 0), robe, Vector3.ZERO, Vector3(1, 0.85, 0.85))
	_part(_body, _cyl(0.26, 0.26, 0.06), Vector3(0, 0.78, 0), leather)
	_part(_body, _sphere(0.045), Vector3(0, 0.78, 0.26), orb, Vector3.ZERO, Vector3.ONE, true)
	# книга на поясе
	_part(_body, _boxm(Vector3(0.16, 0.2, 0.06)), Vector3(0.24, 0.7, 0.12), Color(0.5, 0.16, 0.16), Vector3(0, 0.6, 0))
	_part(_body, _boxm(Vector3(0.12, 0.17, 0.065)), Vector3(0.245, 0.7, 0.125), Color(0.95, 0.9, 0.75), Vector3(0, 0.6, 0))
	# широкие рукава
	for sx in [-1.0, 1.0]:
		_part(_body, _cyl(0.1, 0.07, 0.36), Vector3(0.28 * sx, 0.92, 0.03), robe, Vector3(0, 0, 0.25 * sx))
		_part(_body, _torus(0.07, 0.11), Vector3(0.33 * sx, 0.75, 0.05), trim, Vector3(0, 0, 0.25 * sx))
		_part(_body, _sphere(0.065), Vector3(0.34 * sx, 0.7, 0.07), skin)
	# воротник-накидка
	_part(_body, _cyl(0.22, 0.32, 0.14), Vector3(0, 1.1, 0), trim)
	# голова, глаза, борода-клинышек
	_part(_body, _sphere(0.18), Vector3(0, 1.3, 0.02), skin)
	for ex in [-0.065, 0.065]:
		_part(_body, _boxm(Vector3(0.04, 0.055, 0.02)), Vector3(ex, 1.31, 0.19), ink)
	var beard := _cyl(0.0, 0.1, 0.18, 10)
	_part(_body, beard, Vector3(0, 1.15, 0.12), Color(0.85, 0.85, 0.88), Vector3(PI, 0, 0))
	# шляпа: широкие поля, лента, загнутый конус
	_part(_body, _cyl(0.36, 0.36, 0.04, 24), Vector3(0, 1.43, 0), robe)
	_part(_body, _cyl(0.2, 0.22, 0.08), Vector3(0, 1.48, 0), trim)
	_part(_body, _cyl(0.1, 0.2, 0.3), Vector3(0, 1.66, 0), robe)
	_part(_body, _cyl(0.0, 0.1, 0.26, 12), Vector3(0, 1.88, -0.07), robe, Vector3(-0.45, 0, 0))
	_part(_body, _sphere(0.04), Vector3(0, 2.0, -0.14), orb, Vector3.ZERO, Vector3.ONE, true)
	# посох
	_sword = Node3D.new()
	_sword.position = Vector3(-0.36, 0.72, 0.14)
	_body.add_child(_sword)
	_part(_sword, _cyl(0.03, 0.035, 1.5), Vector3(0, 0.22, 0), wood)
	for k in 3:
		_part(_sword, _cyl(0.04, 0.04, 0.04), Vector3(0, -0.05 + k * 0.08, 0), trim)
	for k in 3:                                        # «когти», держащие сферу
		var a := k * TAU / 3.0
		_part(_sword, _capsule(0.022, 0.18), Vector3(cos(a) * 0.07, 1.0, sin(a) * 0.07), wood,
			Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35))
	_part(_sword, _sphere(0.1), Vector3(0, 1.06, 0), orb, Vector3.ZERO, Vector3.ONE, true)


# ================================================================ общее

func _finish_visual() -> void:
	var tc: Color = main.team_colors[team]
	_visual.rotation.y = atan2(facing.x, facing.z)
	if display_only:
		return
	var ring := MeshInstance3D.new()
	ring.mesh = _torus(0.55, 0.68)
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
	var y := 2.35 if hero == "mage" else 2.15
	_bar_quad(Color(0.08, 0.06, 0.1, 0.85), Vector2(1.1, 0.2), 0, y)
	var bar_col: Color = Color(0.35, 0.95, 0.35) if is_player else (main.team_colors[team] as Color).lightened(0.2)
	_hp_fill = _bar_quad(bar_col, Vector2(1.0, 0.12), 1, y)
	_carry_label = Label3D.new()
	_carry_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_carry_label.position.y = y + 0.35
	_carry_label.font_size = 72
	_carry_label.outline_size = 16
	_carry_label.modulate = Color(1.0, 0.7, 0.4)
	_carry_label.no_depth_test = true
	_carry_label.visible = false
	add_child(_carry_label)


# ================================================================ цикл

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

	if _leap_t > 0.0:
		_leap_t -= delta
		velocity = _leap_dir * 13.0
		move_and_slide()
		position.y = 0.0
		if _leap_t <= 0.0:
			_sword.rotation.x = 0.7
			create_tween().tween_property(_sword, "rotation:x", 0.0, 0.3)
			main.ground_slam(self, global_position, 3.2, 42.0 * dmg_mult)
		return
	if is_player and not autopilot:
		move_dir = main.get_player_move()
	else:
		_think(delta)
	if move_dir.length() < 0.15:
		move_dir = Vector3.ZERO

	var spd := speed * (0.88 if has_flag else 1.0)
	velocity = Vector3(move_dir.x, 0, move_dir.z) * spd
	move_and_slide()
	position.y = 0.0
	in_bush = main.is_bush(global_position)
	if not is_player or autopilot:
		_check_stuck(delta)

	if _aim_hold <= 0.0 and move_dir != Vector3.ZERO:
		facing = move_dir.normalized()
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 14.0))
	_animate(delta)
	if move_dir != Vector3.ZERO and not in_bush:
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.22
			main.fx_burst(global_position + Vector3(0, 0.05, 0), Color(0.82, 0.78, 0.72, 0.7), 3, 0.9, 0.1, 0.35, 0.6)

	_hp_fill.scale.x = maxf(0.001, hp / max_hp)
	_carry_label.visible = carried > 0
	_carry_label.text = "+%d" % carried


func _animate(delta: float) -> void:
	var moving := move_dir != Vector3.ZERO
	if moving:
		_walk_t += delta * 11.0
		_idle_t = 0.0
	else:
		_walk_t = lerpf(_walk_t, round(_walk_t / PI) * PI, minf(1.0, delta * 10.0))
		_idle_t += delta
	var s := sin(_walk_t)
	_legs[0].rotation.x = s * 0.6
	_legs[1].rotation.x = -s * 0.6
	_body.position.y = absf(s) * 0.06 + sin(_idle_t * 2.2) * 0.012   # шаг + «дыхание» на месте
	_body.rotation.z = s * 0.04
	if _cape:                                           # плащ отлетает назад на бегу
		_cape.rotation.x = lerpf(_cape.rotation.x, 0.35 if moving else 0.05 + sin(_idle_t * 1.7) * 0.03, minf(1.0, delta * 6.0))


# ================================================================ бой

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
	b.charge = 0.0 if kind == "wind" else (0.08 if kind == "slam" else 0.12)
	b.tint = _col("orb", Color(1.0, 0.55, 0.15))
	b.main = main
	b.shooter = self
	b.team = team
	b.dir = dir
	b.damage = dmg * dmg_mult
	b.life = life
	b.position = global_position + Vector3(0, 0.8, 0) + dir * 0.5
	main.add_child(b)


func _swing() -> void:
	reveal_t = 1.0
	var tw := create_tween()
	match hero:
		"hammer":
			tw.tween_property(_sword, "rotation:x", -1.9, 0.12)
			tw.tween_property(_sword, "rotation:x", 0.7, 0.08)
			tw.tween_property(_sword, "rotation:x", 0.0, 0.25)
		"archer":
			tw.tween_property(_sword, "position:z", 0.08, 0.07)
			tw.tween_property(_sword, "position:z", 0.26, 0.06)
			tw.tween_property(_sword, "position:z", 0.2, 0.12)
		"mage":
			tw.tween_property(_sword, "rotation:x", 0.6, 0.08)
			tw.tween_property(_sword, "rotation:x", 0.0, 0.2)
		_:
			tw.tween_property(_sword, "rotation:y", 1.3, 0.06)
			tw.tween_property(_sword, "rotation:y", -0.9, 0.1)
			tw.tween_property(_sword, "rotation:y", 0.0, 0.18)


func try_attack(aim: Vector3) -> bool:
	if not alive or _attack_cd > 0.0 or _leap_t > 0.0:
		return false
	var bot := not is_player or autopilot
	facing = _flat(aim)
	_aim_hold = 0.35
	_swing()
	match hero:
		"archer":
			_attack_cd = 1.2 if bot else 0.5
			_spawn_wave(facing, 17.0, 0.6, "arrow", 22.0)
		"hammer":
			_attack_cd = 1.4 if bot else 0.8
			_spawn_wave(facing, 26.0, 0.26, "slam", 13.0, true, 1.05)
		"mage":
			_attack_cd = 1.5 if bot else 0.75
			_spawn_wave(facing, 20.0, 0.85, "fire", 11.0)
		_:
			_attack_cd = 1.15 if bot else 0.45
			_spawn_wave(facing, 20.0, 0.6)
	main.sfx("swing", global_position, 0.0 if is_player else -4.0)
	return true


func try_super(aim: Vector3) -> bool:
	if not alive or super_charge < 1.0 or _leap_t > 0.0:
		return false
	super_charge = 0.0
	facing = _flat(aim)
	_aim_hold = 0.4
	_swing()
	match hero:
		"hammer":
			_leap_t = 0.32
			_leap_dir = facing
			var tw := create_tween()
			tw.tween_property(_visual, "position:y", 1.1, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(_visual, "position:y", 0.0, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			_sword.rotation.x = -1.9
		"archer":
			_spawn_wave(facing, 40.0, 0.75, "wind", 24.0, true, 0.95)
		"mage":
			# «Метеор»: точка удара впереди, через миг — взрыв по большой площади
			var dist := 6.0
			if aim.length() > 0.5:
				dist = clampf(Vector2(aim.x, aim.z).length(), 2.5, 7.0)
			main.meteor(self, global_position + facing * dist, 2.8, 48.0 * dmg_mult, _col("orb", Color(1.0, 0.55, 0.15)))
		_:
			for i in 7:
				var a := deg_to_rad(-30.0 + i * 10.0)
				_spawn_wave(facing.rotated(Vector3.UP, a), 26.0, 0.75)
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
	super_charge = minf(1.0, super_charge + amount * (0.75 if not is_player else 1.0))
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
	main.fx_text(global_position + Vector3(0, 2.3, 0), "-%d" % int(round(amount)),
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
	_leap_t = 0.0
	_respawn_t = 3.0
	main.sfx("death", global_position)
	var debris := Color(0.62, 0.64, 0.7)
	if hero == "archer" or hero == "mage":
		debris = Color(0.44, 0.27, 0.15)
	main.fx_burst(global_position + Vector3(0, 0.9, 0), debris, 12, 6.0, 0.16, 1.1, -14.0)
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
	_visual.position.y = 0.0
	_aware_t = 0.0
	main.fx_ring(spawn_pos, main.team_colors[team], 1.8, 0.5)
	main.fx_burst(spawn_pos + Vector3(0, 0.3, 0), (main.team_colors[team] as Color).lightened(0.5), 14, 3.0, 0.06, 0.7, 3.0)
	if is_player:
		main.sfx("respawn")


func respawn_left() -> float:
	return maxf(0.0, _respawn_t)


# ================================================================ ИИ

func _go(target: Vector3) -> void:
	var v := target - global_position
	v.y = 0.0
	move_dir = v.normalized() if v.length() > 0.4 else Vector3.ZERO


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
		_aware_t += delta
	else:
		_aware_t = 0.0
	# бот реагирует не сразу и целится неточно
	if enemy and _aware_t > 0.45:
		var to_e: Vector3 = enemy.global_position - global_position
		if _attack_cd <= 0.0:
			try_attack(to_e.rotated(Vector3.UP, deg_to_rad(randf_range(-16.0, 16.0))))
		if super_charge >= 1.0:
			_super_wait += delta
			if _super_wait > 1.2:
				_super_wait = 0.0
				try_super(to_e)

	var home: Vector3 = main.stations[team]
	# «Захват знамени»: несущий — домой, защитник — у своего знамени или в погоню
	if main.mode == "flag":
		if has_flag:
			_go(home)
			return
		var chase = main.flag_thief(team)
		if chase and (role == "defend" or global_position.distance_to(chase.global_position) < 9.0):
			_go(chase.global_position)
			return
	if hp < 35.0 and not has_flag:
		_go(home)
		return
	if main.mode == "charge" and (carried >= 3 or (carried > 0 and main.batteries.is_empty())):
		_go(home)
		return
	if enemy and carried == 0:
		var to2: Vector3 = enemy.global_position - global_position
		to2.y = 0.0
		var d := to2.length()
		var side := Vector3(-to2.z, 0, to2.x).normalized() * _strafe
		var approach := to2.normalized() * clampf((d - keep_dist) * 0.5, -1.0, 1.0)
		move_dir = (approach + side * 0.8).normalized()
		return
	match main.mode:
		"brawl":
			var far = main.nearest_enemy(self, 60.0)
			if far:
				_go(far.global_position)
			else:
				_go(home)
		"flag":
			if role == "defend":
				_go(home + (main.stations[1 - team] - home).normalized() * 3.0)
			else:
				_go(main.flag_target(team))
		_:
			var bat = main.nearest_battery(global_position)
			_go(bat.global_position if bat else Vector3.ZERO)


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
