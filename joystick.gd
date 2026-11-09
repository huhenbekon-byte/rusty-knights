extends Control
## Плавающий джойстик: появляется там, где коснулся палец. Поддерживает мультитач.

const RADIUS := 110.0

var output := Vector2.ZERO
var _touch := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var local: Vector2 = event.position - global_position
		if event.pressed and _touch == -1 and Rect2(Vector2.ZERO, size).has_point(local):
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


func _draw() -> void:
	var idle := _touch == -1
	var c := Vector2(size.x * 0.45, size.y * 0.62) if idle else _center
	var k := c if idle else _knob
	draw_circle(c, RADIUS, Color(1, 0.97, 0.88, 0.16))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 0.95, 0.8, 0.6), 5.0)
	draw_circle(k, 50.0, Color(0.08, 0.06, 0.1, 0.35))
	draw_circle(k, 46.0, Color(1, 0.95, 0.82, 0.85))
	draw_arc(k, 30.0, 0.0, TAU, 32, Color(0.8, 0.62, 0.3, 0.9), 4.0)
