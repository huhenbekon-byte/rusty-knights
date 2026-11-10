extends Control
## Плавающий джойстик: появляется там, где коснулся палец. Поддерживает мультитач.
## Основа — тёмный круг с металлическим ободом, ручка — маленькая кнопка с шипами.

const RADIUS := 110.0
const KNOB_TEX := preload("res://ui_btn_small.png")

var output := Vector2.ZERO
var _touch := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
var blockers: Array = []   # кнопки поверх зоны джойстика: касание по ним — не джойстик


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var local: Vector2 = event.position - global_position
		if event.pressed and _touch == -1 and Rect2(Vector2.ZERO, size).has_point(local) and not _blocked(event.position):
			_touch = event.index
			_center = local
			_knob = local
			output = Vector2.ZERO
			queue_redraw()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			output = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch:
		var d: Vector2 = (event.position - global_position) - _center
		d = d.limit_length(RADIUS)
		_knob = _center + d
		output = d / RADIUS
		queue_redraw()


func _blocked(p: Vector2) -> bool:
	for b in blockers:
		if is_instance_valid(b) and b.is_visible_in_tree() and b._hit(p):
			return true
	return false


func _draw() -> void:
	var idle := _touch == -1
	var c := Vector2(size.x * 0.45, size.y * 0.62) if idle else _center
	var k := c if idle else _knob
	var a := 0.55 if idle else 0.9
	draw_circle(c, RADIUS, Color(0.12, 0.03, 0.05, 0.35 * a))
	draw_arc(c, RADIUS, 0.0, TAU, 64, Color(0.06, 0.04, 0.05, 0.8 * a), 12.0, true)
	draw_arc(c, RADIUS, 0.0, TAU, 64, Color(0.7, 0.67, 0.7, a), 6.0, true)
	if not idle and output.length() > 0.1:      # стрелка-подсказка направления
		var dir := output.normalized()
		var tip := c + dir * (RADIUS - 4.0)
		var side := Vector2(-dir.y, dir.x) * 16.0
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 22.0 + side, tip - dir * 22.0 - side]), Color(1.0, 0.35, 0.3, 0.9))
	var ks := 64.0
	draw_texture_rect(KNOB_TEX, Rect2(k - Vector2(ks, ks), Vector2(ks, ks) * 2.0), false, Color(1, 1, 1, 0.65 + 0.35 * a))
