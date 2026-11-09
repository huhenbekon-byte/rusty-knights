extends Node3D
## Снаряд героя. kind:
##   wave  — волна меча рыцаря (светящийся серп),
##   arrow — стрела лучницы,
##   wind  — «Стрела ветра» (супер лучницы): большая, пробивает всех на пути.
## Гаснет о камень; кусты пропускают.

var main     # главная сцена (main.gd)
var shooter  # герой, выпустивший снаряд
var team := 0
var kind := "wave"
var dir := Vector3.FORWARD
var damage := 20.0
var life := 0.6
var speed := 16.0
var pierce := false
var hit_radius := 0.65
var _hit := []          # кого уже задели (для пробивающих)
var _trail_t := 0.0


func _glow_mat(c: Color, alpha := 0.9, energy := 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _piece(mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _ready() -> void:
	var base: Color = main.team_colors[team]
	match kind:
		"arrow":
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color(0.78, 0.6, 0.38)
			wood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color(0.9, 0.92, 0.97)
			steel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_piece(_box(Vector3(0.04, 0.04, 0.62)), Vector3.ZERO, wood)
			var head := PrismMesh.new()
			head.size = Vector3(0.12, 0.16, 0.04)
			_piece(head, Vector3(0, 0, 0.36), steel, Vector3(PI / 2, 0, 0))
			for sx in [-1.0, 1.0]:
				_piece(_box(Vector3(0.09, 0.02, 0.13)), Vector3(0.045 * sx, 0, -0.26), _glow_mat(base.lightened(0.4), 0.95, 1.2))
			# светящийся след цвета команды
			_piece(_box(Vector3(0.05, 0.05, 0.5)), Vector3(0, 0, -0.45), _glow_mat(base.lightened(0.45), 0.45))
		"wind":
			var c := Color(0.55, 1.0, 0.45)
			var m := _glow_mat(c, 0.9, 3.0)
			_piece(_box(Vector3(0.09, 0.09, 1.3)), Vector3.ZERO, m)
			var head := PrismMesh.new()
			head.size = Vector3(0.36, 0.42, 0.08)
			_piece(head, Vector3(0, 0, 0.82), m, Vector3(PI / 2, 0, 0))
			# вихрь вокруг стрелы
			for i in 4:
				var a := i * PI / 2.0
				_piece(_box(Vector3(0.05, 0.05, 0.7)), Vector3(cos(a) * 0.22, sin(a) * 0.22, -0.1),
					_glow_mat(c.lightened(0.3), 0.55, 2.0), Vector3(0, 0, a))
		_:
			var m := _glow_mat(base.lightened(0.5))
			# серп из трёх отрезков дугой
			for i in 3:
				var a := (i - 1) * 0.55
				_piece(_box(Vector3(0.32, 0.06, 0.1)), Vector3(sin(a) * 0.35, 0, cos(a) * 0.35 - 0.35), m, Vector3(0, a + PI / 2.0, 0))
	rotation.y = atan2(dir.x, dir.z)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		main.sfx("wall", global_position, -7.0)
		main.fx_burst(global_position, Color(0.6, 0.55, 0.9), 6, 2.5, 0.07, 0.35)
		queue_free()
		return
	global_position = to
	if kind == "wind":
		rotate_object_local(Vector3.FORWARD, delta * 14.0)
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = 0.05
			main.fx_burst(to, Color(0.6, 1.0, 0.5), 3, 1.2, 0.07, 0.35, 0.0)

	for k in main.knights:
		if k.alive and k.team != team and not (k in _hit):
			var kp: Vector3 = k.global_position
			if Vector2(kp.x - to.x, kp.z - to.z).length() < hit_radius:
				k.take_damage(damage, shooter)
				if is_instance_valid(shooter):
					shooter.add_charge(0.12 if not pierce else 0.0)
				if not pierce:
					queue_free()
					return
				_hit.append(k)

	life -= delta
	if life <= 0.0:
		queue_free()
