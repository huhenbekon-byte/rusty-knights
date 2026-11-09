extends Control
## Круглая сенсорная кнопка с иконкой («sword», «star») или текстом.
## Работает одновременно с джойстиком (мультитач).

signal pressed

var label_text := ""
var icon := ""
var color := Color.WHITE
var fill := 1.0        # заполнение кольца (заряд супера)
var enabled := true
var _touch := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_held() -> bool:
	return _touch != -1


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_touch = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and _hit(event.position):
			_touch = event.index
			if enabled:
				pressed.emit()
			queue_redraw()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			queue_redraw()


func _hit(p: Vector2) -> bool:
	var c := global_position + size * 0.5
	return p.distance_to(c) <= minf(size.x, size.y) * 0.5


func _rot(points: Array, c: Vector2, a: float, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(c + (p as Vector2).rotated(a) * s)
	return out


func _draw_sword(c: Vector2, s: float, col: Color) -> void:
	var a := -PI / 4.0
	var outline := Color(0.1, 0.07, 0.08)
	var blade := [Vector2(-0.12, -0.15), Vector2(0.12, -0.15), Vector2(0.12, -0.8), Vector2(0, -0.98), Vector2(-0.12, -0.8)]
	var guard := [Vector2(-0.38, -0.15), Vector2(0.38, -0.15), Vector2(0.38, 0.0), Vector2(-0.38, 0.0)]
	var grip := [Vector2(-0.07, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.4), Vector2(-0.07, 0.4)]
	var off := Vector2(0, 0.28)
	for part in [blade, guard, grip]:
		var shifted := []
		for p in part:
			shifted.append(p + off)
		var poly := _rot(shifted, c, a, s)
		draw_colored_polygon(poly, outline)
	for pair in [[blade, col], [guard, Color(1, 0.82, 0.3)], [grip, Color(0.5, 0.3, 0.18)]]:
		var shifted2 := []
		for p in pair[0]:
			shifted2.append(p + off)
		draw_colored_polygon(_rot(shifted2, c, a, s * 0.86), pair[1])
	draw_circle(c + (Vector2(0, 0.72)).rotated(a) * s, s * 0.1, Color(1, 0.82, 0.3))


func _draw_star(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := s if i % 2 == 0 else s * 0.45
		var ang := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(c + (p - c) * 1.15)
	draw_colored_polygon(outer, Color(0.1, 0.07, 0.08))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var alpha := 0.95 if enabled else 0.5
	var base := color
	base.a = alpha * (0.95 if _touch != -1 else 0.75)
	draw_circle(c, r, Color(0.08, 0.06, 0.1, 0.55 * alpha))
	draw_circle(c, r - 6.0, base)
	draw_circle(c + Vector2(0, -r * 0.12), r * 0.72, Color(1, 1, 1, 0.12 * alpha))
	if fill < 1.0:
		draw_arc(c, r - 5.0, 0.0, TAU, 48, Color(0, 0, 0, 0.35), 10.0)
		if fill > 0.01:
			draw_arc(c, r - 5.0, -PI / 2.0, -PI / 2.0 + TAU * fill, 48, Color(1, 1, 1, 0.95), 10.0)
	else:
		draw_arc(c, r - 4.0, 0.0, TAU, 48, Color(1, 1, 1, alpha), 6.0)
	var icol := Color(1, 1, 1, alpha)
	match icon:
		"sword":
			_draw_sword(c, r * 0.62, icol)
		"star":
			_draw_star(c, r * 0.5, icol)
		_:
			var font := get_theme_default_font()
			var fs := int(r * 0.3)
			draw_string(font, Vector2(0, c.y + fs * 0.35), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, icol)
