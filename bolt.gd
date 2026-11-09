extends Node3D
## Волна меча: светящийся серп летит вперёд, гаснет о камень или ранит врага.
## Кусты пропускают волну.

var main  # главная сцена (main.gd)
var shooter  # рыцарь, выпустивший волну
var team := 0
var dir := Vector3.FORWARD
var damage := 20.0
var life := 0.6
var speed := 16.0


func _ready() -> void:
	var base: Color = main.team_colors[team]
	var c := base.lightened(0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.9
	# серп из трёх отрезков дугой
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.06, 0.1)
		mi.mesh = bm
		var a := (i - 1) * 0.55
		mi.position = Vector3(sin(a) * 0.35, 0, cos(a) * 0.35 - 0.35)
		mi.rotation.y = a + PI / 2.0
		mi.material_override = m
		add_child(mi)
	rotation.y = atan2(dir.x, dir.z)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		main.sfx("wall", global_position, -7.0)
		queue_free()
		return
	global_position = to

	for k in main.knights:
		if k.alive and k.team != team:
			var kp: Vector3 = k.global_position
			if Vector2(kp.x - to.x, kp.z - to.z).length() < 0.65:
				k.take_damage(damage, shooter)
				if is_instance_valid(shooter):
					shooter.add_charge(0.12)
				queue_free()
				return

	life -= delta
	if life <= 0.0:
		queue_free()
