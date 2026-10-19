class_name DungeonEffects
extends Node2D

var particles: Array[Dictionary] = []
var numbers: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var font: Font = ThemeDB.fallback_font
const MAX_PARTICLES := 256
const MAX_NUMBERS := 48

func _ready() -> void:
	rng.randomize()
	z_index = 20

func burst(at: Vector2, color: Color, amount: int = 14) -> void:
	for i in mini(amount, maxi(0, MAX_PARTICLES - particles.size())):
		var angle := rng.randf_range(0, TAU)
		particles.append({"p": at, "v": Vector2.from_angle(angle) * rng.randf_range(25, 150),
			"life": rng.randf_range(0.25, 0.65), "max": 0.65, "color": color, "size": rng.randf_range(2, 5)})

func text(at: Vector2, value: String, color: Color) -> void:
	if numbers.size() >= MAX_NUMBERS: numbers.pop_front()
	numbers.append({"p": at, "life": 0.8, "text": value, "color": color})

func _process(delta: float) -> void:
	for p in particles:
		p.life -= delta
		p.p += p.v * delta
		p.v *= pow(0.08, delta)
	particles = particles.filter(func(p: Dictionary) -> bool: return p.life > 0)
	for n in numbers:
		n.life -= delta
		n.p.y -= delta * 36
	numbers = numbers.filter(func(n: Dictionary) -> bool: return n.life > 0)
	queue_redraw()

func _draw() -> void:
	for p in particles:
		var color: Color = p.color
		color.a = clampf(p.life / 0.25, 0, 1)
		draw_rect(Rect2(p.p, Vector2.ONE * p.size), color)
	for n in numbers:
		var color: Color = n.color
		color.a = minf(n.life * 3, 1)
		draw_string(font, n.p + Vector2(1, 2), n.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 19, Color(0.02, 0.03, 0.04, color.a))
		draw_string(font, n.p, n.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 19, color)
