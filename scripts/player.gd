class_name DungeonPlayer
extends CharacterBody2D

signal stats_changed
const MAX_BASE_DAMAGE := 90
const MAX_HIT_DAMAGE := 140
const MIN_FINAL_ATTACK_COOLDOWN := 0.30
const DAMAGE_UPGRADE_MULTIPLIER := 1.08
const FLOOR_DAMAGE_GROWTH := 0.09

var game: Node2D
var damage_floor := 1
var damage_upgrade_count := 0
var permanent_damage_bonus := 0
var max_hp := 100:
	set(value):
		if max_hp == value: return
		max_hp = value
		stats_changed.emit()
var hp := 100:
	set(value):
		if hp == value: return
		hp = value
		stats_changed.emit()
var damage := 25:
	set(value):
		if damage == value: return
		damage = value
		stats_changed.emit()
var speed := 180.0:
	set(value):
		if speed == value: return
		speed = value
		stats_changed.emit()
var attack_range := 92.0:
	set(value):
		if attack_range == value: return
		attack_range = value
		stats_changed.emit()
var attack_cooldown := 0.46:
	set(value):
		if attack_cooldown == value: return
		attack_cooldown = value
		stats_changed.emit()
var knockback := 80.0
var invulnerability := 0.0
var attack_timer := 0.0
var swing := 0.0
var swing_direction := Vector2.RIGHT
var facing := Vector2.RIGHT
var dash_timer := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector2.ZERO
var clock := 0.0
var moving := false
var sword_wave := 0
var dash_trail := 0
var lifesteal := 0.0
var berserk := 0:
	set(value):
		if berserk == value: return
		berserk = value
		stats_changed.emit()
var hazardproof := 0
var ward := 0
var ward_available := false
var damage_multiplier := 1.0
var no_dash := false
var oath := false
var blood := false
var slow_timer := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 8
	z_index = 5
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11
	collider.shape = shape
	add_child(collider)

func _physics_process(delta: float) -> void:
	clock += delta
	invulnerability = maxf(0, invulnerability - delta)
	attack_timer = maxf(0, attack_timer - delta)
	swing = maxf(0, swing - delta)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	dash_timer = maxf(0, dash_timer - delta)
	if game.mode != "playing" or hp <= 0:
		velocity = Vector2.ZERO
		queue_redraw()
		return
	slow_timer = maxf(0, slow_timer - delta)
	var aim := get_global_mouse_position() - global_position
	if aim.length_squared() > 0.01:
		facing = aim.normalized()
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	moving = direction.length_squared() > 0
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0:
		start_dash(direction)
	velocity = dash_direction * speed * 3.4 if dash_timer > 0 else direction * speed * (0.55 if slow_timer > 0 else 1.0)
	move_and_slide()
	game.room.apply_hazard(self)
	if Input.is_action_pressed("attack"):
		try_attack()
	game.check_door()
	queue_redraw()

func start_dash(direction: Vector2) -> void:
	# Snapshot this press's movement. Never reuse a previous dash's direction.
	if no_dash or dash_cooldown > 0 or game.mode != "playing": return
	dash_direction = direction.normalized() if direction.length_squared() > 0.01 else facing
	if dash_direction.length_squared() < 0.01: dash_direction = Vector2.RIGHT
	dash_timer = 0.16
	dash_cooldown = 1.25
	invulnerability = maxf(invulnerability, 0.22)
	game.effects.burst(position, Color("80cdc4"), 8)
	game.add_dash_trail(position)
	game.play_sound("dash")

func try_attack() -> void:
	if attack_timer > 0 or game.mode != "playing":
		return
	if blood:
		hp = maxi(0, hp - 1)
		if hp == 0:
			game.die()
			return
	attack_timer = effective_attack_cooldown()
	swing = 0.19
	swing_direction = facing
	game.play_sound("swing")
	for enemy in game.enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.dead or enemy.phase_active:
			continue
		var offset: Vector2 = enemy.position - position
		if offset.length() <= attack_range and (offset.length() < 28 or offset.normalized().dot(facing) > 0.30):
			var ray := PhysicsRayQueryParameters2D.create(global_position, enemy.global_position, 1)
			if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			enemy.take_damage(effective_damage(), offset.normalized() * knockback)
			game.shake = maxf(game.shake, 2.5)
	if sword_wave > 0 and game.wave_cooldown <= 0:
		game.spawn_player_wave(position + facing * 18, facing, mini(MAX_HIT_DAMAGE, effective_damage() + 6))
		game.wave_cooldown = 0.85

func effective_attack_cooldown() -> float:
	var result := attack_cooldown
	if oath or (berserk > 0 and float(hp) / max_hp <= 0.3): result *= 0.5
	return maxf(MIN_FINAL_ATTACK_COOLDOWN, result)

func effective_damage() -> int:
	var boost := 1.2 if is_instance_valid(game) and game.actives != null and game.actives.tonic_timer > 0 else 1.0
	return mini(MAX_HIT_DAMAGE, roundi(damage * damage_multiplier * boost))

func upgrade_damage() -> void:
	damage_upgrade_count = mini(damage_upgrade_count + 1, 8)
	rebuild_damage(damage_floor, damage_upgrade_count, permanent_damage_bonus)

func rebuild_damage(floor_value: int, stacks: int, permanent_bonus: int = 0) -> void:
	damage_floor = floor_value
	damage_upgrade_count = stacks
	permanent_damage_bonus = permanent_bonus
	var natural := 25.0 * (1.0 + FLOOR_DAMAGE_GROWTH * maxi(0, floor_value - 1))
	damage = mini(MAX_BASE_DAMAGE, roundi((natural + permanent_bonus) * pow(DAMAGE_UPGRADE_MULTIPLIER, stacks)))

func take_damage(amount: int) -> void:
	if invulnerability > 0 or game.mode != "playing":
		return
	if ward_available:
		ward_available = false
		invulnerability = 0.85
		game.hurt_flash = 0.18
		game.effects.text(position + Vector2(-25, -34), "守火", Color("a7c3d9"))
		return
	hp = maxi(0, hp - amount)
	invulnerability = 0.85
	game.hurt_flash = 0.45
	game.shake = 7
	game.effects.text(position + Vector2(-12, -34), "−%s" % amount, Color("ef8875"))
	game.effects.burst(position, Color("d96f60"), 12)
	game.play_sound("hurt")
	if hp <= 0:
		game.die()

func _draw() -> void:
	if game.actives != null and game.actives.visual_timer > 0:
		var active: ActiveSkills = game.actives
		draw_circle(Vector2.ZERO, active.visual_radius, Color(active.visual_color, 0.08))
		draw_arc(Vector2.ZERO, active.visual_radius, 0, TAU, 48, Color(active.visual_color, active.visual_timer / 0.35), 3)
	# Soft, layered cyan halo under the hero.
	for i in range(5, 0, -1):
		draw_circle(Vector2(0, -4), 20 + i * 10, Color(0.28, 0.68, 0.64, 0.012))
	if invulnerability > 0 and sin(clock * 35) > 0:
		modulate.a = 0.55
	else:
		modulate.a = 1
	PixelArt.hero(self, moving, clock, facing, invulnerability > 0.6)
	if dash_timer > 0:
		draw_arc(Vector2.ZERO, 21, 0, TAU, 24, Color("93e2d2"), 2)
	if swing > 0:
		var progress := 1.0 - swing / 0.19
		var angle := swing_direction.angle()
		var radius := attack_range * (0.56 + progress * 0.30)
		var alpha := sin(progress * PI)
		for i in range(3):
			draw_arc(Vector2(0, -6), radius - i * 6, angle - 1.0 + progress * 0.5,
				angle + 0.5 + progress * 0.65, 24, Color(0.64, 0.95, 0.89, alpha * (1 - i * 0.28)), 4 - i)
