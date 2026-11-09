extends Control
## Табло: два знамени с делениями и щит-герб посередине.

var colors: Array = [Color.BLUE, Color.RED]
var goal := 10
var score := [0, 0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _banner(rect: Rect2, col: Color, filled: int, from_right: bool) -> void:
	draw_rect(rect.grow(4), Color(0.1, 0.07, 0.08, 0.85))
	draw_rect(rect, col.darkened(0.6))
	var gap := 4.0
	var w := (rect.size.x - gap * (goal + 1)) / goal
	for i in goal:
		var idx := goal - 1 - i if from_right else i
		var x := rect.position.x + gap + idx * (w + gap)
		var r := Rect2(x, rect.position.y + gap, w, rect.size.y - gap * 2)
		draw_rect(r, col if i < filled else col.darkened(0.45))
		if i < filled:
			draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), col.lightened(0.45))


func _draw() -> void:
	var c := Vector2(size.x / 2, size.y / 2)
	var bw := size.x / 2 - 70
	var bh := 30.0
	_banner(Rect2(c.x - 60 - bw, c.y - bh / 2, bw, bh), colors[0], score[0], true)
	_banner(Rect2(c.x + 60, c.y - bh / 2, bw, bh), colors[1], score[1], false)
	# щит-герб
	var pts := PackedVector2Array([
		c + Vector2(-46, -44), c + Vector2(46, -44), c + Vector2(46, 4),
		c + Vector2(0, 50), c + Vector2(-46, 4)])
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(c + (p - c) * 1.12)
	draw_colored_polygon(outer, Color(0.1, 0.07, 0.08))
	draw_colored_polygon(pts, Color(0.95, 0.78, 0.3))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.8)
	draw_colored_polygon(inner, Color(0.55, 0.38, 0.2))
	var font := get_theme_default_font()
	draw_string_outline(font, Vector2(c.x - 60, c.y + 16), str(goal), HORIZONTAL_ALIGNMENT_CENTER, 120, 40, 8, Color(0.1, 0.07, 0.08))
	draw_string(font, Vector2(c.x - 60, c.y + 16), str(goal), HORIZONTAL_ALIGNMENT_CENTER, 120, 40, Color.WHITE)
	# цифры счёта под знамёнами
	for t in 2:
		var x := c.x - 60 - bw / 2 if t == 0 else c.x + 60 + bw / 2
		var s := str(score[t])
		draw_string_outline(font, Vector2(x - 50, c.y + 62), s, HORIZONTAL_ALIGNMENT_CENTER, 100, 34, 8, Color(0.1, 0.07, 0.08))
		draw_string(font, Vector2(x - 50, c.y + 62), s, HORIZONTAL_ALIGNMENT_CENTER, 100, 34, (colors[t] as Color).lightened(0.3))
