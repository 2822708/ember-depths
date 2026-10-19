extends Node2D
## Only transient feedback rebuilds each frame; hidden outside active play.
var hud: Control
var clock := 0.0

func _process(delta: float) -> void:
	var game: Node2D = hud.game
	clock += delta
	visible = game.mode == "playing" and (game.hurt_flash > 0 or game.transition > 0 or float(game.player.hp) / game.player.max_hp <= 0.3)
	if visible: queue_redraw()

func _draw() -> void:
	var game: Node2D = hud.game
	var pulse := maxf(0, sin(clock * TAU / 0.85))
	var low: bool = game.player.hp > 0 and float(game.player.hp) / game.player.max_hp <= 0.3
	var strength: float = game.hurt_flash * 0.9 + (pulse * 0.16 if low else 0.0)
	if strength > 0:
		for i in 5:
			draw_rect(Rect2(42 + i * 5, 132 + i * 5, 896 - i * 10, 576 - i * 10), Color(0.8, 0.2, 0.16, strength * (1 - i * 0.16)), false, 5)
	if low:
		draw_string(hud.font, Vector2(642, 694), "生命垂危 · 留意攻击前摇", HORIZONTAL_ALIGNMENT_RIGHT, 278, 12, Color("e4a08a"))
	if game.transition > 0:
		draw_rect(Rect2(42, 132, 896, 576), Color(0.05, 0.10, 0.13, minf(game.transition * 1.8, 0.8)))
