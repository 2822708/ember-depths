class_name DungeonEnemy
extends CharacterBody2D

var game: Node2D
var kind := 0
var hp := 45
var max_hp := 45
var speed := 65.0
var damage := 12
var dead := false
var is_minion := false
var is_boss := false
var hurt := 0.0
var knock := Vector2.ZERO
var windup := 0.0
var windup_duration := 0.48
var attack_cooldown := 0.7
var clock := 0.0
var path_timer := 0.0
var desired := Vector2.ZERO
var attack_target := Vector2.ZERO
var action := ""
var charge_timer := 0.0
var stun_timer := 0.0
var summon_budget := 4
var boss_skill_index := 0
var boss_theme := "moss"
var final_boss := false
var cast_position := Vector2.ZERO
var mechanic_clock := 0.0
var phase_warning := false
var phase_active := false
var heal_clock := 0.0
var shield_facing := Vector2.RIGHT
var spawn_invulnerability := 0.0
var shield_clock := 0.0
var shield_push_timer := 0.0
var heal_state := "idle"
var heal_progress := 0.0
var heal_ticks := 0
var heal_flash := 0.0
var heal_beam_timer := 0.0
var heal_targets: Array[DungeonEnemy] = []
var boss_phase_two := false
var ultimate_pending := false
var skill_points: Array[Vector2] = []
var active_slow_timer := 0.0
var active_slow_multiplier := 1.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8
	z_index = 4
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8 if is_minion else 12
	collider.shape = shape
	add_child(collider)
	if is_minion: scale = Vector2.ONE * 0.7
	elif is_boss: scale = Vector2.ONE * 1.45
	clock = randf() * 8
	attack_cooldown += randf() * 0.65
	boss_skill_index = randi_range(0, 2)
	if not is_boss and not is_minion:
		if kind == 6: mechanic_clock = randf() * float(EnemyCatalog.mechanic(kind).period)

func has_sight() -> bool:
	var ray := PhysicsRayQueryParameters2D.create(global_position, game.player.global_position, 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _physics_process(delta: float) -> void:
	if dead or game.mode != "playing": return
	active_slow_timer = maxf(0, active_slow_timer - delta)
	clock += delta
	spawn_invulnerability = maxf(0, spawn_invulnerability - delta)
	if is_boss: BossModule.update_phase(self)
	_update_mechanics(delta)
	hurt = maxf(0, hurt - delta)
	# Advancing the timer by 1 / 0.9 also accelerates an already-running cooldown.
	attack_cooldown = maxf(0, attack_cooldown - delta / _cooldown_multiplier())
	stun_timer = maxf(0, stun_timer - delta)
	path_timer -= delta
	var offset: Vector2 = game.player.position - position
	var distance := offset.length()
	if kind == 7 and not is_boss:
		if path_timer <= 0:
			desired = _warden_direction()
			path_timer = 0.25
		velocity = Vector2.ZERO if heal_state != "idle" else desired.normalized() * speed * _pursuit_multiplier(distance) * _active_speed() + knock
		move_and_slide()
		knock = knock.move_toward(Vector2.ZERO, 500 * delta)
		queue_redraw()
		return
	if stun_timer > 0:
		velocity = Vector2.ZERO
	elif shield_push_timer > 0:
		shield_push_timer = maxf(0, shield_push_timer - delta)
		velocity = attack_target * float(EnemyCatalog.mechanic(kind).push_speed) * _active_speed() + knock
		move_and_slide()
		if distance < float(EnemyCatalog.mechanic(kind).push_radius): game.player.take_damage(damage)
	elif charge_timer > 0:
		var impacted := false
		charge_timer -= delta
		velocity = attack_target * (speed * (7.0 if is_boss else 4.8)) * _active_speed() + knock
		move_and_slide()
		if position.distance_to(game.player.position) < 34:
			impacted = true
			game.player.take_damage(damage)
			charge_timer = 0
		if get_slide_collision_count() > 0:
			impacted = true
			charge_timer = 0
			stun_timer = 0.6
			game.shake = maxf(game.shake, 3)
			game.effects.burst(position, Color("d9c39a"), 15)
		if impacted and kind == 1 and not is_boss: _charge_shock()
	elif windup > 0:
		windup -= delta
		velocity = knock
		move_and_slide()
		if windup <= 0: _resolve_action()
	else:
		if attack_cooldown <= 0:
			if is_boss and distance < 500:
				prepare(BossModule.next_skill(self))
			elif kind == 5 and shield_clock >= float(EnemyCatalog.mechanic(kind).interval) and distance < float(EnemyCatalog.mechanic(kind).trigger_distance):
				prepare("shield_push")
			elif kind == 3 and distance < 90:
				prepare("explode")
			elif kind == 0 and distance < 285 and has_sight():
				prepare("throw")
			elif kind == 1 and distance > 65 and distance < 320 and has_sight():
				prepare("charge")
			elif kind == 2 and distance < 380 and summon_budget > 0 and game.enemies.size() < game.MAX_ENEMIES:
				prepare("summon")
			elif distance < 43:
				prepare("melee")
		if windup <= 0:
			if path_timer <= 0:
				desired = game.room.next_direction(position, game.player.position)
				path_timer = 0.20 + randf() * 0.12
			var steering := desired
			if not is_boss and kind in [0, 2] and distance < 130:
				var retreat: Vector2 = position - offset.normalized() * 36
				if game.room.is_safe_cell(Vector2i(floor(retreat.x / 32), floor(retreat.y / 32))):
					steering = -offset.normalized()
			elif not is_boss and kind in [0, 2] and distance < 205 and has_sight():
				steering = Vector2.ZERO
			velocity = (steering + _separation()).normalized() * speed * _pursuit_multiplier(distance) * _active_speed() * (float(EnemyCatalog.mechanic(kind).move_multiplier) if kind == 6 and phase_active else 1.0) + knock
		else:
			velocity = knock
		move_and_slide()
	knock = knock.move_toward(Vector2.ZERO, 500 * delta)
	queue_redraw()

func _cooldown_multiplier() -> float:
	return float(EnemyCatalog.COMBAT.pressure_cooldown_multiplier) if float(game.player.hp) / game.player.max_hp < float(EnemyCatalog.COMBAT.pressure_health_fraction) else 1.0

func _active_speed() -> float:
	return active_slow_multiplier if active_slow_timer > 0 else 1.0

func _pursuit_multiplier(distance: float) -> float:
	return float(EnemyCatalog.COMBAT.pursuit_multiplier) if distance > float(EnemyCatalog.COMBAT.pursuit_distance) else 1.0

func _warden_direction() -> Vector2:
	# Follow the team's center rather than endlessly fleeing and abandoning allies.
	var center := Vector2.ZERO
	var count := 0
	for other in game.enemies:
		if other == self or not is_instance_valid(other) or other.dead: continue
		center += other.position
		count += 1
	if count > 0:
		center /= count
		if position.distance_to(center) > float(EnemyCatalog.mechanic(kind).follow_distance):
			return game.room.next_direction(position, center)
	# Keep the existing back-line role, but do not flee once the player is distant.
	if position.distance_to(game.player.position) < 130:
		return -game.room.next_direction(position, game.player.position)
	return Vector2.ZERO

func _update_mechanics(delta: float) -> void:
	if is_boss or is_minion or dead: return
	if kind == 5:
		shield_clock += delta
		var to_player: Vector2 = (game.player.position - position).normalized()
		if to_player.length_squared() > 0.01:
			# Radians per second: bounded even for an exactly opposite target direction.
			shield_facing = Vector2.from_angle(rotate_toward(shield_facing.angle(), to_player.angle(), float(EnemyCatalog.mechanic(kind).turn_speed) * delta))
	elif kind == 6:
		var data := EnemyCatalog.mechanic(kind)
		mechanic_clock += delta
		var period: float = data.period
		var active: bool = fposmod(mechanic_clock, period) >= period - float(data.duration)
		var warning: bool = not active and fposmod(mechanic_clock, period) >= period - float(data.duration) - float(data.warning)
		if active != phase_active:
			if phase_active and not active: _phase_ring()
			phase_active = active
			collision_layer = 0 if active else 4
		phase_warning = warning
	elif kind == 7: _update_warden(delta)

func _update_warden(delta: float) -> void:
	var data := EnemyCatalog.mechanic(kind)
	heal_flash = maxf(0, heal_flash - delta)
	heal_beam_timer = maxf(0, heal_beam_timer - delta)
	if heal_beam_timer <= 0: heal_targets.clear()
	# Slice across state boundaries, so a long frame cannot skip the windup.
	var remaining := delta
	while remaining > 0.00001:
		if heal_state == "idle":
			var step := minf(remaining, maxf(0, float(data.interval) - heal_clock))
			heal_clock += step
			remaining -= step
			if heal_clock < float(data.interval): break
			heal_clock = 0
			heal_progress = 0
			heal_state = "windup"
			knock = Vector2.ZERO
			game.play_sound("heal_charge")
		elif heal_state == "windup":
			var step := minf(remaining, float(data.windup) - heal_progress)
			heal_progress += step
			heal_clock += step
			remaining -= step
			if heal_progress < float(data.windup): break
			heal_state = "channel"
			heal_progress = 0
			heal_ticks = 0
			_heal_tick()
		else:
			var step := minf(remaining, float(data.channel) - heal_progress)
			heal_progress += step
			heal_clock += step
			remaining -= step
			if heal_ticks == 1 and heal_progress >= float(data.tick_interval): _heal_tick()
			if heal_progress < float(data.channel): break
			heal_state = "idle"
			heal_progress = 0
			heal_targets.clear()

func _heal_tick() -> void:
	if dead: return
	var data := EnemyCatalog.mechanic(kind)
	heal_ticks += 1
	heal_targets.clear()
	for other in game.enemies:
		if other == self or not is_instance_valid(other) or other.dead or other.hp >= other.max_hp: continue
		if position.distance_to(other.position) <= float(data.radius):
			var amount := mini(other.max_hp - other.hp, maxi(1, roundi(other.max_hp * float(data.heal_fraction))))
			other.hp += amount
			heal_targets.append(other)
			game.effects.text(other.position + Vector2(-12, -35), "+%d" % amount, Color("b7f4a6"))
			game.effects.burst(other.position, Color("92e49c"), 5)
	heal_beam_timer = float(data.beam_duration)
	game.play_sound("heal")

func cancel_mechanics() -> void:
	heal_state = "idle"
	heal_targets.clear()
	heal_beam_timer = 0
	heal_progress = 0
	visible = false
	collision_layer = 0
	set_physics_process(false)

func _charge_shock() -> void:
	var data: Dictionary = EnemyCatalog.SKILLS.charge
	game.spawn_zone(position, "shock", damage, {"radius": data.shock_radius, "warning": data.shock_warning, "duration": data.shock_duration})

func _phase_ring() -> void:
	var data := EnemyCatalog.mechanic(kind)
	for i in int(data.ring_count):
		var direction := Vector2.from_angle(i * TAU / int(data.ring_count))
		var shot: EnemyProjectile = game.spawn_projectile(position + direction * 20, direction, damage)
		shot.velocity = direction * float(data.ring_speed)
		shot.tint = Color("91c9dc")

func _separation() -> Vector2:
	var result := Vector2.ZERO
	for other in game.enemies:
		if other == self or not is_instance_valid(other) or other.dead: continue
		var away: Vector2 = position - other.position
		if away.length() < 29 and away.length() > 0: result += away.normalized() * 0.9
	return result

func prepare(next_action: String) -> void:
	action = next_action
	windup_duration = 0.82 if action == "boss_pulse" else (0.62 if action in ["boss_charge", "boss_summon"] else (float(EnemyCatalog.COMBAT.melee_windup) if action == "melee" else float(EnemyCatalog.TYPES[kind].windup)))
	if is_boss: windup_duration = BossModule.WINDUPS.get(action, 0.8)
	elif action == "shield_push": windup_duration = float(EnemyCatalog.mechanic(kind).warning)
	windup = windup_duration
	cast_position = game.player.position
	attack_target = (game.player.position - position).normalized()
	if attack_target == Vector2.ZERO: attack_target = Vector2.RIGHT
	if action == "shield_push": attack_target = shield_facing
	if is_boss: BossModule.plan(self, action)

func _resolve_action() -> void:
	if is_boss:
		BossModule.resolve(self, action)
		action = ""
		return
	match action:
		"throw":
			var data: Dictionary = EnemyCatalog.SKILLS.throw
			for i in int(data.count):
				var direction := attack_target.rotated(deg_to_rad(float(data.arc_degrees)) * (float(i) / (int(data.count) - 1) - 0.5))
				game.spawn_projectile(position + direction * 20, direction, damage)
			attack_cooldown = EnemyCatalog.COMBAT.throw_cooldown
		"charge":
			charge_timer = float(EnemyCatalog.SKILLS.charge.duration)
			attack_cooldown = EnemyCatalog.COMBAT.charge_cooldown
		"summon":
			for i in int(EnemyCatalog.SKILLS.summon.count):
				if summon_budget <= 0: break
				var child = game.spawn_enemy(4, position + Vector2((i - 1) * 45, 40), true)
				if child != null: summon_budget -= 1
			game.effects.burst(position, Color("b79aca"), 20)
			game.spawn_zone(position, "slow", 0, {"radius": EnemyCatalog.SKILLS.summon.slow_radius, "warning": EnemyCatalog.SKILLS.summon.warning, "duration": EnemyCatalog.SKILLS.summon.zone_duration, "slow_duration": EnemyCatalog.SKILLS.summon.slow_duration})
			attack_cooldown = float(EnemyCatalog.SKILLS.summon.cooldown)
		"explode":
			game.effects.burst(position, Color("efaa63"), 38)
			game.shake = maxf(game.shake, 5)
			if position.distance_to(game.player.position) < float(EnemyCatalog.SKILLS.explode.radius) and has_sight():
				game.player.take_damage(damage)
			game.spawn_zone(position, "fire", damage, {"radius": EnemyCatalog.SKILLS.explode.radius, "warning": EnemyCatalog.SKILLS.explode.fire_warning, "duration": EnemyCatalog.SKILLS.explode.fire_duration})
			_finish_death()
		"shield_push":
			shield_push_timer = float(EnemyCatalog.mechanic(kind).duration)
			shield_clock = 0
			attack_cooldown = float(EnemyCatalog.mechanic(kind).interval)
		"melee":
			game.effects.burst(position + attack_target * 22, EnemyCatalog.TYPES[kind].color, 7)
			if position.distance_to(game.player.position) < 57 and has_sight():
				game.player.take_damage(damage)
			attack_cooldown = EnemyCatalog.COMBAT.melee_cooldown
	action = ""

func take_damage(amount: int, push: Vector2) -> void:
	if dead or phase_active or spawn_invulnerability > 0: return
	var actual := amount
	if is_boss:
		actual = maxi(1, roundi(amount * BossModule.incoming_multiplier(self)))
		if BossModule.incoming_multiplier(self) < 1:
			game.effects.text(position + Vector2(-25, -52), "减伤", Color("a7c3d9"))
	var blocked := false
	if kind == 5 and not is_boss and not is_minion:
		var incoming := -push.normalized()
		var half_arc := deg_to_rad(float(EnemyCatalog.mechanic(kind).front_arc_degrees) * 0.5)
		if incoming.length_squared() > 0.01:
			var front := shield_facing.dot(incoming) >= cos(half_arc)
			var multiplier: float = (float(EnemyCatalog.mechanic(kind).push_front_multiplier) if shield_push_timer > 0 else float(EnemyCatalog.mechanic(kind).front_damage_multiplier)) if front else float(EnemyCatalog.mechanic(kind).back_damage_multiplier)
			actual = maxi(0 if shield_push_timer > 0 else 1, roundi(amount * multiplier))
			blocked = front
	if actual <= 0:
		if blocked:
			game.play_sound("block")
			game.effects.burst(position, Color("e4d6b2"), 6)
		return
	hp -= actual
	hurt = 0.15
	knock = push
	if kind == 7 and not is_boss and heal_state != "idle":
		knock = Vector2.ZERO
		heal_progress *= 1.0 - float(EnemyCatalog.mechanic(kind).setback)
		heal_flash = 0.18
		game.play_sound("heal_interrupt")
	if is_boss:
		BossModule.update_phase(self)
		game.hud_changed.emit()
	game.effects.text(position + Vector2(-7, -35), str(actual), Color("f5d69a"))
	game.effects.burst(position, Color("e4d6b2") if blocked else EnemyCatalog.TYPES[kind].color, 12 if blocked else 9)
	game.play_sound("block" if blocked else "hit")
	if hp <= 0: _finish_death()

func _finish_death() -> void:
	if dead: return
	dead = true
	cancel_mechanics()
	# Add children before removing the parent, so the room never clears early.
	if kind == 4 and not is_minion and not is_boss:
		for i in int(EnemyCatalog.SKILLS.split.count):
			var child: DungeonEnemy = game.spawn_enemy(4, position + Vector2(-30 if i == 0 else 30, 15), true)
			if child != null: child.spawn_invulnerability = float(EnemyCatalog.SKILLS.split.invulnerability)
	game.enemy_died(self)
	queue_free()

func _draw() -> void:
	var color: Color = EnemyCatalog.TYPES[kind].color
	if is_boss:
		draw_circle(Vector2.ZERO, 31, Color(0.94, 0.35, 0.28, 0.10 + sin(clock * 3.0) * 0.03))
		draw_arc(Vector2.ZERO, 29, -PI, 0, 24, Color("ef806d"), 3)
		BossModule.draw_warning(self)
	if windup > 0:
		var p := 1.0 - windup / windup_duration
		if action == "explode":
			var radius: float = EnemyCatalog.SKILLS.explode.radius
			draw_circle(Vector2.ZERO, radius, Color(0.95, 0.35, 0.15, 0.05 + p * 0.15))
			draw_arc(Vector2.ZERO, radius, -PI / 2, -PI / 2 + TAU * p, 48, color, 2)
		elif action in ["charge", "boss_charge"]:
			draw_line(Vector2.ZERO, attack_target * 185, Color(color, 0.25 + p * 0.3), 14)
			draw_line(Vector2.ZERO, attack_target * 185, Color(color, 0.8), 2)
		elif action == "throw":
			for i in int(EnemyCatalog.SKILLS.throw.count):
				var direction := attack_target.rotated(deg_to_rad(float(EnemyCatalog.SKILLS.throw.arc_degrees)) * (float(i) / (int(EnemyCatalog.SKILLS.throw.count) - 1) - 0.5))
				draw_line(direction * 18, direction * 150, Color(color, 0.5), 1)
			draw_circle(attack_target * 23, 5 + p * 5, Color(color, 0.6))
		elif action == "shield_push":
			draw_line(Vector2.ZERO, attack_target * 130, Color("c2d7dc", 0.35 + p * 0.4), 28)
			draw_line(Vector2.ZERO, attack_target * 130, Color("e5edcc"), 2)
		elif action == "boss_pulse":
			draw_circle(Vector2.ZERO, 145 / scale.x, Color(0.94, 0.35, 0.28, 0.06 + p * 0.12))
			draw_arc(Vector2.ZERO, 145 / scale.x, -PI / 2, -PI / 2 + TAU * p, 48, Color("ef806d"), 3)
		elif action == "boss_summon":
			draw_circle(Vector2.ZERO, 72, Color(0.75, 0.38, 0.75, 0.08 + p * 0.10))
			draw_arc(Vector2.ZERO, 72, -PI / 2, -PI / 2 + TAU * p, 32, Color("d5a7e1"), 3)
		elif action in ["vines", "frost_field"]:
			var target := (cast_position - position) / scale
			var tint := Color("8fc796") if action == "vines" else Color("9bcfe9")
			draw_circle(target, 65 / scale.x, Color(tint, 0.12))
			draw_arc(target, 65 / scale.x, 0, TAU * p, 32, tint, 2)
		elif action in ["magma", "frost_fan"]:
			for i in 7:
				draw_line(Vector2.ZERO, attack_target.rotated((i - 3) * 0.22) * 120, Color("e7b589"), 1)
		else:
			var radius := float(EnemyCatalog.SKILLS.summon.slow_radius) if action == "summon" else 43.0
			draw_circle(Vector2.ZERO, radius, Color(color, 0.10))
			draw_arc(Vector2.ZERO, radius, -PI / 2, -PI / 2 + TAU * p, 32, color, 2)
	if phase_active:
		modulate.a = 0.28 + sin(clock * 16.0) * 0.08
	elif phase_warning:
		modulate.a = 0.58 + sin(clock * 34.0) * 0.25
	else:
		modulate.a = 1.0
	if kind == 7 and not is_boss:
		draw_circle(Vector2.ZERO, 33 + sin(clock * 4.0) * 3, Color("a9e5a0", 0.08))
		draw_arc(Vector2.ZERO, 31 + sin(clock * 4.0) * 3, 0, TAU, 32, Color("a9e5a0", 0.6), 2)
		_draw_healing()
	if is_boss: BossModule.draw_body(self)
	else: PixelArt.monster(self, kind, clock, hurt > 0, windup > 0)
	if kind == 5 and not is_boss:
		var shield_pos := shield_facing * 16 + Vector2(0, -2)
		draw_circle(shield_pos, 11, Color("273940"))
		draw_arc(shield_pos, 10, 0, TAU, 16, Color("d0d8d0"), 3)
		draw_line(shield_pos - shield_facing.orthogonal() * 6, shield_pos + shield_facing.orthogonal() * 6, Color("94b3b7"), 3)
	if kind == 6 and phase_warning:
		draw_arc(Vector2.ZERO, 22, 0, TAU, 24, Color("b8efff"), 2)
	if kind == 6 and phase_active:
		for i in int(EnemyCatalog.mechanic(kind).ring_count):
			var direction := Vector2.from_angle(i * TAU / int(EnemyCatalog.mechanic(kind).ring_count))
			draw_line(direction * 22, direction * 70, Color("c3efff"), 2)
	if spawn_invulnerability > 0:
		draw_arc(Vector2.ZERO, 23, 0, TAU, 24, Color("c1f4b8"), 3)
	if kind == 4 and not is_minion and not is_boss:
		for side in [-1, 1]: draw_circle(Vector2(side * 21, -4), 4, Color("b4dfaa"))
	if hp < max_hp:
		draw_rect(Rect2(-16, -37, 32, 3), Color("14272d"))
		draw_rect(Rect2(-16, -37, 32 * float(hp) / max_hp, 3), color)

func _draw_healing() -> void:
	if dead or heal_state == "idle": return
	var data := EnemyCatalog.mechanic(kind)
	var progress := clampf(heal_progress / float(data.windup), 0.0, 1.0) if heal_state == "windup" else 1.0
	var color := Color("f18b78") if heal_flash > 0 else Color("8dec9c")
	var radius := float(data.radius) * progress
	draw_circle(Vector2.ZERO, radius, Color(color, 0.035 + progress * 0.065))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(color, 0.7), 2)
	var inner := radius * (0.90 + sin(clock * 7) * 0.025)
	draw_arc(Vector2.ZERO, inner, clock * 0.2, clock * 0.2 + TAU, 64, color, 1)
	for i in 8:
		var p := Vector2.from_angle(i * TAU / 8 + clock * 0.2) * inner
		draw_line(p - Vector2(5, 5), p + Vector2(5, -5), color, 2)
	if heal_state == "channel" and heal_beam_timer > 0:
		for target in heal_targets:
			if is_instance_valid(target) and not target.dead:
				draw_line(Vector2.ZERO, target.position - position, Color(color, 0.7), 3)
