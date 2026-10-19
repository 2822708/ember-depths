class_name BossZone
extends Node2D
## Shared telegraphed hazards. Temporary wall colliders belong to this node.
var game: Node2D
var kind := "frost"
var damage := 10
var age := 0.0
var warning := 0.9
var duration := 4.5
var radius := 65.0
var start_radius := 0.0
var slow_duration := 0.18
var safe_position := Vector2.ZERO
var safe_radius := 95.0
var retired := false
var wall: StaticBody2D

func _ready() -> void:
	z_index = 2

func current_radius() -> float:
	if kind == "poison": return lerpf(start_radius, radius, clampf((age - warning) / duration, 0.0, 1.0))
	return radius

func is_safe(at: Vector2) -> bool:
	return kind == "cataclysm" and at.distance_to(safe_position) <= safe_radius

func _physics_process(delta: float) -> void:
	if retired or game.mode != "playing": return
	age += delta
	if age >= warning + duration:
		retire()
		return
	if age >= warning:
		if kind == "ice_wall" and wall == null: _build_wall()
		var player: DungeonPlayer = game.player
		if position.distance_to(player.position) <= current_radius() and not is_safe(player.position) and player.dash_timer <= 0:
			if kind in ["vines", "frost", "slow"]: player.slow_timer = maxf(player.slow_timer, slow_duration)
			if kind not in ["frost", "slow", "ice_wall"]: player.take_damage(damage)
	queue_redraw()

func _build_wall() -> void:
	wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	# Two short segments with a 96px central gap, never a closed cage.
	for side in [-1, 1]:
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(72, 18)
		collider.shape = shape
		collider.position = Vector2(side * 84, 0)
		wall.add_child(collider)
	add_child(wall)

func deactivate() -> void:
	retired = true
	visible = false
	set_physics_process(false)
	if is_instance_valid(wall): wall.collision_layer = 0

func retire() -> void:
	deactivate()
	game.zones.erase(self)
	queue_free()

func _draw() -> void:
	var color := Color("8fc796")
	if kind in ["frost", "ice_wall", "ice_spike"]: color = Color("9bcfe9")
	elif kind in ["fire", "meteor", "vortex", "shock"]: color = Color("f2a06b")
	elif kind == "cataclysm": color = Color("ee817c")
	var progress := clampf(age / maxf(warning, 0.01), 0.0, 1.0)
	var drawn_radius := current_radius() if age >= warning else radius
	if kind == "ice_wall":
		for side in [-1, 1]:
			draw_rect(Rect2(side * 84 - 36, -9, 72, 18), Color(color, 0.18 if age < warning else 0.8))
			draw_rect(Rect2(side * 84 - 36, -9, 72, 18), color, false, 2)
	else:
		draw_circle(Vector2.ZERO, drawn_radius, Color(color, 0.08 if age < warning else 0.18))
		draw_arc(Vector2.ZERO, drawn_radius, -PI / 2, -PI / 2 + TAU * progress, 48, color, 2)
		if kind in ["meteor", "spike", "ice_spike", "shock"]:
			draw_line(Vector2(-12, -12), Vector2(12, 12), color, 3)
			draw_line(Vector2(12, -12), Vector2(-12, 12), color, 3)
		if age >= warning and kind in ["fire", "vortex", "poison"]:
			for i in 8:
				var p := Vector2.from_angle(i * TAU / 8 + age) * drawn_radius * 0.65
				draw_line(p, p + Vector2(0, -12), color, 3)
	if kind == "cataclysm":
		var local_safe := safe_position - position
		draw_circle(local_safe, safe_radius, Color("4dceb2", 0.65))
		draw_arc(local_safe, safe_radius, 0, TAU, 40, Color("c5ffe2"), 4)
		draw_string(ThemeDB.fallback_font, local_safe + Vector2(-25, 0), "安全区", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
