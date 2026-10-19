class_name PixelArt
extends RefCounted
## Original sprites drawn on a two-pixel grid. No third-party art dependency.

static func block(c: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	c.draw_rect(Rect2(x * 2, y * 2, w * 2, h * 2), color)

static func hero(c: CanvasItem, moving: bool, time: float, facing: Vector2, hurt: bool) -> void:
	var step: float = sin(time * 14) * 1.5 if moving else 0.0
	c.draw_circle(Vector2(0, 5), 15, Color(0, 0, 0, 0.25))
	var cape := Color("ae5748") if not hurt else Color.WHITE
	var dark := Color("263b43") if not hurt else Color.WHITE
	block(c, -6, -8, 12, 14, Color("121e29"))
	block(c, -7, -5, 3, 12, cape)
	block(c, 4, -5, 3, 12, cape)
	block(c, -4, 1 + step, 3, 5, dark)
	block(c, 1, 1 - step, 3, 5, dark)
	block(c, -4, -6, 8, 9, Color("779495") if not hurt else Color.WHITE)
	block(c, -3, -6, 2, 7, Color("b9d4c1"))
	block(c, -4, -1, 8, 2, Color("b89058"))
	block(c, -6, -15, 12, 10, dark)
	block(c, -4, -16, 8, 2, Color("668084"))
	block(c, -5, -13, 10, 6, Color("243139"))
	block(c, -3, -12, 6, 4, Color("dfc4a0") if not hurt else Color.WHITE)
	var eye_x: float = 1 if facing.x >= 0 else -3
	block(c, eye_x, -11, 2, 1, Color("122734"))
	block(c, -5, -7, 10, 2, cape)
	block(c, -1, -7, 2, 2, Color("efd28f"))
	# Sword rests toward the mouse between swings.
	var hand := facing * 19 + Vector2(0, -3)
	c.draw_line(hand, hand + facing * 17, Color("172932"), 7)
	c.draw_line(hand, hand + facing * 17, Color("b6e6df"), 3)
	c.draw_line(hand - facing.orthogonal() * 5, hand + facing.orthogonal() * 5, Color("dbb36f"), 3)

static func monster(c: CanvasItem, kind: int, time: float, hurt: bool, attacking: bool, boss: bool = false) -> void:
	var bob: float = floor(sin(time * 5) * 2)
	c.draw_circle(Vector2(0, 7), 15, Color(0, 0, 0, 0.25))
	var base: Color = EnemyCatalog.TYPES[kind].color
	var shade := base.darkened(0.4)
	if hurt:
		base = Color("fff0cf")
		shade = Color.WHITE
	block(c, -7, -6 + bob, 14, 11, Color("152831"))
	block(c, -6, -8 + bob, 12, 11, shade)
	block(c, -4, -10 + bob, 8, 3, base)
	block(c, -5, -6 + bob, 10, 6, base)
	block(c, -6, 2 + bob, 4, 2, shade)
	block(c, 2, 2 + bob, 4, 2, shade)
	var eyes := Color("ffe2ad") if not attacking else Color("ff6f61")
	block(c, -4, -6 + bob, 2, 2, eyes)
	block(c, 2, -6 + bob, 2, 2, eyes)
	block(c, -2, -2 + bob, 4, 1, Color("223c42"))
	if boss:
		block(c, -10, -15 + bob, 4, 7, Color("ef806d"))
		block(c, 6, -15 + bob, 4, 7, Color("ef806d"))
		block(c, -7, -13 + bob, 14, 3, Color("f2c477"))
		block(c, -2, -10 + bob, 4, 4, Color("fff0b0"))
	if kind == 1:
		block(c, -8, -13 + bob, 3, 7, Color("dcc7a1"))
		block(c, 5, -13 + bob, 3, 7, Color("dcc7a1"))
	elif kind == 0:
		block(c, 7, -8 + bob, 2, 13, Color("957652"))
		block(c, 6, -10 + bob, 4, 4, Color("ffc67d"))
	elif kind == 2:
		block(c, -7, -2 + bob, 14, 8, shade)
		block(c, -2, -14 + bob, 4, 6, Color("d3b3e2"))
		block(c, -1, 0 + bob, 2, 4, Color("e4c7ef"))
	elif kind == 3:
		block(c, -3, -9 + bob, 6, 10, Color("f3bd6f") if not hurt else Color.WHITE)
		block(c, -1, -7 + bob, 2, 5, Color("ffe5ac"))
		block(c, -9, 1 + bob, 3, 2, shade)
		block(c, 6, 1 + bob, 3, 2, shade)
	elif kind == 4:
		block(c, -8, 1 + bob, 16, 4, shade)
		block(c, -2, -8 + bob, 3, 3, Color("b4dfaa"))
	elif kind == 5:
		block(c, -8, -14 + bob, 16, 4, Color("c4d1ca"))
		block(c, -9, -12 + bob, 18, 14, Color("566f78"))
		block(c, -7, -10 + bob, 14, 10, Color("91adb2"))
		block(c, -3, -8 + bob, 6, 5, Color("d0d8c8"))
	elif kind == 6:
		block(c, -8, -2 + bob, 16, 6, Color("b6e7f0"))
		block(c, -3, -15 + bob, 6, 5, Color("e0fbff"))
		block(c, -2, -5 + bob, 4, 5, Color("edfaff"))
	elif kind == 7:
		block(c, -8, -13 + bob, 16, 4, Color("d8d9ac"))
		block(c, -10, -10 + bob, 20, 3, Color("546b4d"))
		block(c, -5, -7 + bob, 10, 9, Color("a6c89b"))
		block(c, -2, -15 + bob, 4, 3, Color("e3d29a"))

