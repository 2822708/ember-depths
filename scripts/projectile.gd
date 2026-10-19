class_name EnemyProjectile
extends Node2D
## Swept wall and player tests prevent fast projectiles tunneling between frames.
var game: Node2D
var velocity := Vector2.ZERO
var damage := 10
var lifetime := 3.0
var removed := false
var trail: Array[Vector2] = []
var tint := Color("dc8c51")
var slow_on_hit := false
var homing_turn_speed := 0.0

func _ready() -> void:
	z_index = 6

func _physics_process(delta: float) -> void:
	if removed or game.mode != "playing": return
	lifetime -= delta
	if homing_turn_speed > 0:
		var aim: Vector2 = game.player.position - position
		if aim.length_squared() > 1:
			velocity = Vector2.from_angle(rotate_toward(velocity.angle(), aim.angle(), homing_turn_speed * delta)) * velocity.length()
	var next := position + velocity * delta
	var ray := PhysicsRayQueryParameters2D.create(global_position, game.world.to_global(next), 1)
	if lifetime <= 0 or not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		destroy()
		return
	var nearest := Geometry2D.get_closest_point_to_segment(game.player.position, position, next)
	if nearest.distance_to(game.player.position) < 17:
		if slow_on_hit and game.player.invulnerability <= 0 and game.player.dash_timer <= 0:
			game.player.slow_timer = maxf(game.player.slow_timer, 1.2)
		game.player.take_damage(damage)
		destroy()
		return
	trail.append(position)
	if trail.size() > 6: trail.pop_front()
	position = next
	queue_redraw()

func destroy() -> void:
	if removed: return
	removed = true
	visible = false
	set_physics_process(false)
	game.projectiles.erase(self)
	game.effects.burst(position, Color("e7ae70"), 4)
	queue_free()

func _draw() -> void:
	for i in trail.size():
		draw_circle(trail[i] - position, 2 + i * 0.3, Color(tint, float(i + 1) / 12))
	draw_circle(Vector2.ZERO, 12, Color(0.9, 0.4, 0.15, 0.10))
	draw_rect(Rect2(-5, -5, 10, 10), tint)
	draw_rect(Rect2(-2, -3, 5, 5), Color("ffe2a0"))
