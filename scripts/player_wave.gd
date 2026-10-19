class_name PlayerWave
extends Node2D

var game: Node2D
var velocity := Vector2.ZERO
var damage := 30
var life := 0.8
var hit: Dictionary = {}
var removed := false
var pulses := 1

func _ready() -> void:
	z_index = 6

func _physics_process(delta: float) -> void:
	if removed: return
	if game.mode != "playing": destroy(); return
	life -= delta
	var old := position
	position += velocity * delta
	var wall := PhysicsRayQueryParameters2D.create(global_position - velocity * delta, global_position, 1)
	if life <= 0 or not get_world_2d().direct_space_state.intersect_ray(wall).is_empty():
		destroy(); return
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_to(position) < 22 and not hit.has(enemy):
			hit[enemy] = true
			for pulse in pulses:
				if enemy.dead: break
				enemy.take_damage(damage, velocity.normalized() * 45)
	queue_redraw()

func destroy() -> void:
	if removed: return
	removed = true
	visible = false
	set_physics_process(false)
	game.player_waves.erase(self)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 15, Color(0.35, 0.85, 0.92, 0.12))
	draw_line(-velocity.normalized() * 20, velocity.normalized() * 20, Color("b8eff0"), 4)
	draw_line(-velocity.normalized() * 12, velocity.normalized() * 28, Color("6ecad9"), 2)
