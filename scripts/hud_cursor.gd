extends Node2D
## Geometry is retained; moving the node never rebuilds the rest of the HUD.
var hud: Control

func _process(_delta: float) -> void:
	visible = hud.game.mode == "playing"
	position = hud.get_global_mouse_position()

func _draw() -> void:
	draw_arc(Vector2.ZERO, 7, 0, TAU, 16, Color(0.8, 0.91, 0.85, 0.65), 1)
	draw_circle(Vector2.ZERO, 1.5, Color("dfb879"))
