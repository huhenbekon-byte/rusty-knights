extends Control
## Векторные иконки интерфейса — рисуются кодом, без картинок.
## kind: coin, gem, crystal, trophy, chest, scroll, swords, helm, bow, gear, lock, people, play, star, check, close

var kind := "coin"
var tint := Color.WHITE       # цвет корпуса (шлем — облик, сундук — тип)
const OUT := Color(0.08, 0.06, 0.1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _c() -> Vector2:
	return size / 2.0


func _s() -> float:
	return minf(size.x, size.y) / 2.0


func _pts(pts: Array, rot := 0.0, scl := 1.0, off := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_c() + ((p as Vector2).rotated(rot) * scl + off) * _s())
	return out


func _poly(pts: Array, col: Color, rot := 0.0, scl := 1.0, off := Vector2.ZERO, outline := true) -> void:
	var arr := _pts(pts, rot, scl, off)
	draw_colored_polygon(arr, col)
	if outline:
		var closed := arr.duplicate()
		closed.append(arr[0])
		draw_polyline(closed, OUT, maxf(2.0, _s() * 0.09), true)


func _circle(p: Vector2, r: float, col: Color, outline := true) -> void:
	if outline:
		draw_circle(_c() + p * _s(), r * _s() + maxf(2.0, _s() * 0.07), OUT)
	draw_circle(_c() + p * _s(), r * _s(), col)


func _line(a: Vector2, b: Vector2, col: Color, w := 0.06) -> void:
	draw_line(_c() + a * _s(), _c() + b * _s(), col, maxf(1.5, w * _s()), true)


func _rect(x0: float, y0: float, x1: float, y1: float, col: Color, outline := true) -> void:
	_poly([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], col, 0.0, 1.0, Vector2.ZERO, outline)


func _sword(rot: float, off: Vector2) -> void:
	var blade := [Vector2(-0.1, -0.2), Vector2(0.1, -0.2), Vector2(0.1, -0.85), Vector2(0, -1.0), Vector2(-0.1, -0.85)]
	var guard := [Vector2(-0.32, -0.2), Vector2(0.32, -0.2), Vector2(0.32, -0.06), Vector2(-0.32, -0.06)]
	var grip := [Vector2(-0.06, -0.06), Vector2(0.06, -0.06), Vector2(0.06, 0.3), Vector2(-0.06, 0.3)]
	_poly(blade, Color(0.86, 0.9, 0.97), rot, 0.95, off)
	_poly(grip, Color(0.45, 0.28, 0.16), rot, 0.95, off)
	_poly(guard, Color(1.0, 0.78, 0.28), rot, 0.95, off)
	_circle(off + Vector2(0, 0.36).rotated(rot) * 0.95, 0.09, Color(1.0, 0.78, 0.28))


func _draw() -> void:
	match kind:
		"coin":
			_circle(Vector2.ZERO, 0.86, Color(1.0, 0.76, 0.2))
			_circle(Vector2.ZERO, 0.6, Color(1.0, 0.87, 0.42), false)
			_rect(-0.12, -0.38, 0.12, 0.38, Color(0.86, 0.58, 0.12), false)
			_circle(Vector2(-0.35, -0.4), 0.12, Color(1, 1, 0.85, 0.8), false)
		"gem", "crystal":
			var col := Color(0.5, 0.85, 1.0) if kind == "gem" else Color(0.4, 1.0, 0.6)
			var pts := [Vector2(-0.5, -0.72), Vector2(0.5, -0.72), Vector2(0.9, -0.22), Vector2(0, 0.9), Vector2(-0.9, -0.22)]
			_poly(pts, col)
			var lc := col.lightened(0.55)
			_line(Vector2(-0.9, -0.22), Vector2(0.9, -0.22), lc)
			_line(Vector2(-0.3, -0.22), Vector2(0, 0.9), lc)
			_line(Vector2(0.3, -0.22), Vector2(0, 0.9), lc)
			_line(Vector2(-0.5, -0.72), Vector2(-0.3, -0.22), lc)
			_line(Vector2(0.5, -0.72), Vector2(0.3, -0.22), lc)
		"trophy":
			var g := Color(1.0, 0.78, 0.22)
			draw_arc(_c() + Vector2(-0.58, -0.42) * _s(), 0.26 * _s(), PI * 0.5, PI * 1.5, 16, OUT, 0.2 * _s())
			draw_arc(_c() + Vector2(0.58, -0.42) * _s(), 0.26 * _s(), -PI * 0.5, PI * 0.5, 16, OUT, 0.2 * _s())
			draw_arc(_c() + Vector2(-0.58, -0.42) * _s(), 0.26 * _s(), PI * 0.5, PI * 1.5, 16, g, 0.1 * _s())
			draw_arc(_c() + Vector2(0.58, -0.42) * _s(), 0.26 * _s(), -PI * 0.5, PI * 0.5, 16, g, 0.1 * _s())
			_poly([Vector2(-0.62, -0.82), Vector2(0.62, -0.82), Vector2(0.5, -0.12), Vector2(0.18, 0.18),
				Vector2(-0.18, 0.18), Vector2(-0.5, -0.12)], g)
			_rect(-0.1, 0.18, 0.1, 0.52, g.darkened(0.1))
			_rect(-0.48, 0.52, 0.48, 0.84, g.darkened(0.2))
			_rect(-0.3, -0.7, -0.16, -0.25, Color(1, 1, 0.8, 0.7), false)
		"chest":
			var body := tint if tint != Color.WHITE else Color(0.62, 0.38, 0.18)
			var band := Color(1.0, 0.78, 0.28)
			_poly([Vector2(-0.88, -0.42), Vector2(-0.62, -0.72), Vector2(0.62, -0.72), Vector2(0.88, -0.42),
				Vector2(0.88, -0.1), Vector2(-0.88, -0.1)], body.lightened(0.12))
			_rect(-0.88, -0.1, 0.88, 0.76, body)
			for bx in [-0.55, 0.55]:
				_rect(bx - 0.08, -0.7, bx + 0.08, 0.76, band, false)
			_rect(-0.16, -0.26, 0.16, 0.14, band)
			_circle(Vector2(0, -0.08), 0.05, OUT, false)
		"scroll":
			_rect(-0.6, -0.68, 0.6, 0.68, Color(0.97, 0.88, 0.66))
			_rect(-0.74, -0.86, 0.74, -0.6, Color(0.85, 0.68, 0.42))
			_rect(-0.74, 0.6, 0.74, 0.86, Color(0.85, 0.68, 0.42))
			for i in 4:
				var y := -0.38 + i * 0.22
				_line(Vector2(-0.4, y), Vector2(0.4 - (0.25 if i == 3 else 0.0), y), Color(0.45, 0.3, 0.2), 0.07)
			_circle(Vector2(0.38, 0.42), 0.15, Color(0.85, 0.2, 0.2))
		"swords":
			_sword(-0.75, Vector2(0.0, 0.02))
			_sword(0.75, Vector2(0.0, 0.02))
		"helm":
			var st := tint if tint != Color.WHITE else Color(0.72, 0.75, 0.82)
			_poly([Vector2(-0.58, -0.72), Vector2(0.58, -0.72), Vector2(0.66, 0.78), Vector2(-0.66, 0.78)], st)
			_poly([Vector2(-0.46, -0.9), Vector2(0.46, -0.9), Vector2(0.58, -0.72), Vector2(-0.58, -0.72)], st.lightened(0.15))
			_rect(-0.05, -0.72, 0.05, 0.78, st.darkened(0.3), false)
			_rect(-0.52, -0.2, 0.52, -0.06, OUT, false)
			for i in 3:
				for hx in [-0.24, 0.24]:
					_rect(hx - 0.05, 0.12 + i * 0.16, hx + 0.05, 0.2 + i * 0.16, OUT, false)
		"gear":
			var pts := []
			for i in 8:
				var b := i * TAU / 8.0
				pts.append(Vector2.from_angle(b - 0.3) * 0.66)
				pts.append(Vector2.from_angle(b - 0.17) * 0.95)
				pts.append(Vector2.from_angle(b + 0.17) * 0.95)
				pts.append(Vector2.from_angle(b + 0.3) * 0.66)
			_poly(pts, Color(0.8, 0.82, 0.9))
			_circle(Vector2.ZERO, 0.3, Color(0.22, 0.22, 0.35))
		"lock":
			draw_arc(_c() + Vector2(0, -0.22) * _s(), 0.38 * _s(), PI, TAU, 24, OUT, 0.26 * _s())
			draw_arc(_c() + Vector2(0, -0.22) * _s(), 0.38 * _s(), PI, TAU, 24, Color(0.7, 0.72, 0.8), 0.12 * _s())
			_rect(-0.62, -0.22, 0.62, 0.82, Color(0.55, 0.57, 0.68))
			_circle(Vector2(0, 0.2), 0.13, OUT, false)
			_rect(-0.05, 0.25, 0.05, 0.52, OUT, false)
		"people":
			for spec in [[-0.48, Color(0.65, 0.68, 0.8)], [0.48, Color(0.65, 0.68, 0.8)], [0.0, Color.WHITE]]:
				var x: float = spec[0]
				var sc := 0.85 if x != 0.0 else 1.0
				var body := []
				for i in 13:
					var a := PI + i * PI / 12.0
					body.append(Vector2(x + cos(a) * 0.38 * sc, 0.72 + sin(a) * 0.5 * sc))
				_poly(body, spec[1])
				_circle(Vector2(x, -0.12 - (0.0 if x == 0.0 else -0.06)), 0.24 * sc, spec[1])
		"bow":
			var arc := PackedVector2Array()
			for i in 17:
				var t := lerpf(-1.25, 1.25, float(i) / 16.0)
				arc.append(_c() + Vector2(-0.35 + cos(t) * 0.75, sin(t) * 0.85) * _s())
			draw_polyline(arc, OUT, 0.32 * _s(), true)
			draw_polyline(arc, Color(0.62, 0.38, 0.2), 0.18 * _s(), true)
			var top := arc[0]
			var bot := arc[arc.size() - 1]
			draw_line(top, bot, Color(0.95, 0.93, 0.85), maxf(1.5, 0.05 * _s()), true)
			_rect(0.3, -0.12, 0.48, 0.12, Color(1.0, 0.78, 0.28))
			_line(Vector2(-0.6, 0), Vector2(0.75, 0), OUT, 0.14)
			_line(Vector2(-0.6, 0), Vector2(0.75, 0), Color(0.85, 0.7, 0.45), 0.07)
			_poly([Vector2(0.95, 0), Vector2(0.72, -0.12), Vector2(0.72, 0.12)], Color(0.9, 0.92, 0.97))
		"play":
			_poly([Vector2(-0.42, -0.62), Vector2(0.62, 0), Vector2(-0.42, 0.62)], Color.WHITE)
		"star":
			var pts := []
			for i in 10:
				pts.append(Vector2.from_angle(-PI / 2 + i * PI / 5) * (0.92 if i % 2 == 0 else 0.42))
			_poly(pts, tint if tint != Color.WHITE else Color(1.0, 0.82, 0.25))
		"check":
			draw_polyline(_pts([Vector2(-0.6, 0.0), Vector2(-0.15, 0.48), Vector2(0.65, -0.5)]), OUT, 0.42 * _s(), true)
			draw_polyline(_pts([Vector2(-0.6, 0.0), Vector2(-0.15, 0.48), Vector2(0.65, -0.5)]), Color(0.45, 1, 0.5), 0.24 * _s(), true)
		"close":
			for a in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]:
				_line(a, -a, OUT, 0.42)
			for a in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]:
				_line(a, -a, Color.WHITE, 0.22)
