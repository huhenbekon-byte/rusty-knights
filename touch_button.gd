extends Control
## Круглая сенсорная кнопка в стиле «металл и красное дерево»: рамка с шипами (frame),
## серебряный значок (icon_tex), кольцо заряда (fill), подпись-табличка (tag, например «ULT»).
## Работает одновременно с джойстиком (мультитач).

signal pressed

var frame: Texture2D
var icon_tex: Texture2D
var tag := ""            # табличка под кнопкой
var glow := false        # красное свечение, когда кнопка готова («ульта»)
var fill := 1.0          # заполнение кольца (заряд, перезарядка)
var enabled := true
var _touch := -1
var _press_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_held() -> bool:
	return _touch != -1


func _process(delta: float) -> void:
	_press_t = maxf(0.0, _press_t - delta)
	if glow and enabled or _press_t > 0.0:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_touch = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and _hit(event.position):
			_touch = event.index
			_press_t = 0.12
			if enabled:
				pressed.emit()
			queue_redraw()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			queue_redraw()


func _hit(p: Vector2) -> bool:
	var c := global_position + size * 0.5
	return p.distance_to(c) <= minf(size.x, size.y) * 0.5


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var pressed_k := 0.94 if (_touch != -1 or _press_t > 0.0) else 1.0
	var rr := r * pressed_k
	var t := Time.get_ticks_msec() / 1000.0

	# свечение готовой «ульты»: мягкие красные круги и вращающиеся дуги
	if glow and enabled:
		var pulse := 0.5 + 0.5 * sin(t * 4.0)
		for i in 5:
			draw_circle(c, rr * (1.02 + i * 0.07 + pulse * 0.04), Color(1.0, 0.12, 0.15, 0.09 - i * 0.015))
		for i in 3:
			var a0 := t * (1.6 + i * 0.5) + i * 2.1
			draw_arc(c, rr * (0.52 + i * 0.07), a0, a0 + 2.0, 24, Color(1.0, 0.3, 0.3, 0.55), 4.0, true)

	var mod := Color(1, 1, 1) if enabled else Color(0.55, 0.5, 0.52)
	if frame:
		draw_texture_rect(frame, Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, mod)
	else:
		draw_circle(c, rr * 0.8, Color(0.35, 0.06, 0.08))

	# кольцо заряда по ободку
	if fill < 1.0:
		draw_arc(c, rr * 0.73, 0.0, TAU, 64, Color(0, 0, 0, 0.55), rr * 0.09, true)
		if fill > 0.01:
			draw_arc(c, rr * 0.73, -PI / 2.0, -PI / 2.0 + TAU * fill, 64, Color(1.0, 0.72, 0.3, 0.95), rr * 0.07, true)

	if icon_tex:
		var s := rr * 1.06
		draw_texture_rect(icon_tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, mod)

	if tag != "":
		var font := get_theme_default_font()
		var fs := int(r * 0.24)
		var w := r * 0.78
		var h := r * 0.34
		var p := Vector2(c.x - w * 0.5, c.y + r * 0.78)
		var pts := PackedVector2Array([p + Vector2(h * 0.35, 0), p + Vector2(w - h * 0.35, 0), p + Vector2(w, h * 0.5),
			p + Vector2(w - h * 0.35, h), p + Vector2(h * 0.35, h), p + Vector2(0, h * 0.5)])
		draw_colored_polygon(pts, Color(0.08, 0.04, 0.05))
		var inner := PackedVector2Array()
		var mid := p + Vector2(w, h) * 0.5
		for q in pts:
			inner.append(mid + (q - mid) * 0.82)
		draw_colored_polygon(inner, Color(0.42, 0.07, 0.1) if enabled else Color(0.25, 0.2, 0.22))
		var line := pts.duplicate()
		line.append(pts[0])
		draw_polyline(line, Color(0.75, 0.72, 0.75), 2.5, true)
		draw_string(font, Vector2(p.x, p.y + h * 0.5 + fs * 0.36), tag, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(1, 0.95, 0.95))
