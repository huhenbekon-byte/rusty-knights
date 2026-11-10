extends Control
## Табличка зарядов атаки под кнопкой удара: значок героя, три деления и «n / 3».

const PANEL := preload("res://ui_ammo.png")

var icon_tex: Texture2D
var ammo := 3.0
var max_ammo := 3


func _draw() -> void:
	draw_texture_rect(PANEL, Rect2(Vector2.ZERO, size), false)
	var h := size.y
	if icon_tex:
		var s := h * 0.95
		draw_texture_rect(icon_tex, Rect2(Vector2(h * 0.05, (h - s) * 0.5), Vector2(s, s)), false)
	# три деления: полные — светлые, копящееся — частично
	var x0 := h * 1.0
	var w := size.x * 0.33
	var gap := 6.0
	var seg := (w - gap * (max_ammo - 1)) / max_ammo
	var y := h * 0.34
	var sh := h * 0.32
	for i in max_ammo:
		var r := Rect2(x0 + i * (seg + gap), y, seg, sh)
		draw_rect(r, Color(0.06, 0.02, 0.03, 0.9))
		var f := clampf(ammo - i, 0.0, 1.0)
		if f > 0.0:
			var c := Color(1.0, 0.82, 0.45) if f >= 1.0 else Color(0.75, 0.45, 0.3)
			draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * f, r.size.y - 4)), c)
	var font := get_theme_default_font()
	var fs := int(h * 0.4)
	var txt := "%d / %d" % [int(floor(ammo)), max_ammo]
	var tx := x0 + w + 6.0
	draw_string_outline(font, Vector2(tx, h * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x - tx - h * 0.25, fs, 6, Color(0.1, 0.03, 0.04))
	draw_string(font, Vector2(tx, h * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x - tx - h * 0.25, fs, Color(1, 0.96, 0.92))
