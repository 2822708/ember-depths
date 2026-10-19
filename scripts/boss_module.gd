class_name BossModule
extends RefCounted
## Boss skill data, plans, rhythm and resolution. No asynchronous orphan timers.
const NAMES := {"moss": "缠根古王", "lava": "熔心暴君", "frost": "霜冠守望者"}
const COLORS := {"moss": Color("8fc796"), "lava": Color("f29a62"), "frost": Color("9bcfe9")}
const LOADOUTS := {
	"moss": ["vines", "boss_summon", "boss_charge", "poison", "roots", "spikes"],
	"lava": ["magma", "boss_charge", "boss_pulse", "meteors", "vortex", "fireball"],
	"frost": ["frost_field", "frost_fan", "boss_pulse", "ice_storm", "ice_wall", "ice_orb", "boss_charge"]
}
const BIG_SKILLS := ["poison", "spikes", "meteors", "vortex", "ice_storm", "ice_wall"]
const FINAL_SKILLS := ["vines", "boss_summon", "boss_charge", "poison", "roots", "spikes", "magma", "boss_pulse", "meteors", "vortex", "fireball", "frost_field", "frost_fan", "ice_storm", "ice_wall", "ice_orb", "cataclysm"]
const WINDUPS := {"vines": 1.0, "magma": 0.9, "frost_field": 1.0, "frost_fan": 0.85, "boss_summon": 1.0, "boss_charge": 0.8, "boss_pulse": 0.95, "poison": 1.2, "roots": 0.85, "spikes": 1.1, "meteors": 1.2, "vortex": 1.0, "fireball": 0.85, "ice_storm": 1.2, "ice_wall": 1.0, "ice_orb": 0.85, "cataclysm": 1.4}
const AREAS := {
	"vines": {"radius": 130.0, "duration": 2.0, "warning": 0.9, "slow_duration": 2.0},
	"frost_field": {"radius": 145.0, "duration": 3.0, "warning": 0.9},
	"poison": {"radius": 330.0, "start_radius": 55.0, "duration": 4.0, "warning": 0.9},
	"spikes": {"radius": 48.0, "duration": 0.35, "warning": 0.8},
	"meteors": {"radius": 62.0, "duration": 0.4, "warning": 0.9},
	"ice_storm": {"radius": 50.0, "duration": 0.4, "warning": 0.9},
	"vortex": {"radius": 175.0, "duration": 3.0, "warning": 0.8},
	"ice_wall": {"radius": 120.0, "duration": 3.0, "warning": 0.9},
	"cataclysm": {"radius": 1200.0, "duration": 0.45, "warning": 2.0, "safe_radius": 95.0}
}
const MULTI_COUNTS := {"spikes": 6, "meteors": 7, "ice_storm": 9}
const HOMING := {"speed": 105.0, "turn_speed": 0.45, "lifetime": 3.0}
const COOLDOWN := 1.6
const PHASE_TWO_COOLDOWN := 1.1
const MINIMUM_SURVIVAL_SECONDS := {5: 8.0, 10: 12.0, 15: 16.0, 20: 25.0}

static func minimum_hp(floor_value: int) -> int:
	return ceili(float(MINIMUM_SURVIVAL_SECONDS.get(floor_value, 8.0)) * DungeonPlayer.MAX_HIT_DAMAGE / DungeonPlayer.MIN_FINAL_ATTACK_COOLDOWN)

static func incoming_multiplier(enemy: DungeonEnemy) -> float:
	if enemy.hp * 2 <= enemy.max_hp: return 0.90
	if enemy.hp > enemy.max_hp * 0.70: return 0.85
	return 1.0

static func title(enemy: DungeonEnemy) -> String:
	return "余烬之源 · 终焉王" if enemy.final_boss else NAMES[enemy.boss_theme]

static func update_phase(enemy: DungeonEnemy) -> void:
	if not enemy.boss_phase_two and enemy.hp * 2 <= enemy.max_hp:
		enemy.boss_phase_two = true
		enemy.ultimate_pending = enemy.final_boss
		enemy.attack_cooldown = minf(enemy.attack_cooldown, PHASE_TWO_COOLDOWN)
		enemy.game.effects.text(enemy.position + Vector2(-50, -65), "第二阶段", Color("f6b486"))
		enemy.game.play_sound("boss")

static func next_skill(enemy: DungeonEnemy) -> String:
	update_phase(enemy)
	var skills: Array = FINAL_SKILLS.duplicate() if enemy.final_boss else LOADOUTS[enemy.boss_theme].duplicate()
	if not enemy.boss_phase_two: skills.erase("cataclysm")
	if enemy.summon_budget <= 0: skills.erase("boss_summon")
	# Big -> small -> movement -> big. Each category rotates independently.
	var step := enemy.boss_skill_index
	enemy.boss_skill_index += 1
	var turn := step % 3
	if turn == 0:
		if enemy.ultimate_pending:
			enemy.ultimate_pending = false
			return "cataclysm"
		var big := skills.filter(func(id: String) -> bool: return id in BIG_SKILLS or id == "cataclysm")
		return big[(step / 3) % big.size()]
	if turn == 2:
		# Frost theme gets an ice dash with the same readable charge tell.
		return "boss_charge" if "boss_charge" in skills else "frost_fan"
	var small := skills.filter(func(id: String) -> bool: return id not in BIG_SKILLS and id not in ["boss_charge", "cataclysm"])
	return small[(step / 3) % small.size()]

static func plan(enemy: DungeonEnemy, skill: String) -> void:
	enemy.skill_points.clear()
	if skill in MULTI_COUNTS:
		# Spread marked strikes across the half-room around the committed target.
		for i in int(MULTI_COUNTS[skill]):
			var p := enemy.cast_position if i == 0 else Vector2(150 + (i % 4) * 180, 165 + (i / 4) * 150)
			if skill == "ice_storm" and i > 0:
				p += Vector2(enemy.game.rng.randf_range(-32, 32), enemy.game.rng.randf_range(-32, 32))
			enemy.skill_points.append(enemy.game.room.nearest_safe_position(p))
	elif skill == "cataclysm":
		enemy.skill_points.append(enemy.game.room.nearest_safe_position(enemy.cast_position))
	elif skill in ["vines", "poison"]:
		enemy.skill_points.append(enemy.position)
	else:
		enemy.skill_points.append(enemy.game.room.nearest_safe_position(enemy.cast_position))

static func resolve(enemy: DungeonEnemy, skill: String) -> void:
	var game: Node2D = enemy.game
	update_phase(enemy)
	game.play_sound("cast")
	match skill:
		"boss_charge": enemy.charge_timer = 0.65
		"boss_pulse":
			if enemy.position.distance_to(game.player.position) < 145 and enemy.has_sight(): game.player.take_damage(enemy.damage + 8)
			game.shake = maxf(game.shake, 5)
		"boss_summon":
			for i in 3:
				if enemy.summon_budget <= 0: break
				var child: DungeonEnemy = game.spawn_enemy(4, enemy.position + Vector2.from_angle(i * TAU / 3) * 65, true)
				if child != null:
					child.max_hp = roundi(child.max_hp * 1.5)
					child.hp = child.max_hp
					child.damage += 4
					enemy.summon_budget -= 1
		"magma", "frost_fan":
			var amount := 9 if enemy.final_boss else 7
			for i in amount:
				var direction := enemy.attack_target.rotated((i - (amount - 1) * 0.5) * 0.22)
				var shot: EnemyProjectile = game.spawn_projectile(enemy.position + direction * 25, direction, enemy.damage)
				shot.tint = Color("f29a62") if skill == "magma" else Color("9bcfe9")
				shot.velocity = direction * 175
				shot.slow_on_hit = skill == "frost_fan"
		"roots", "fireball", "ice_orb":
			var shot: EnemyProjectile = game.spawn_projectile(enemy.position + enemy.attack_target * 28, enemy.attack_target, enemy.damage)
			shot.velocity = enemy.attack_target * float(HOMING.speed)
			shot.homing_turn_speed = float(HOMING.turn_speed)
			shot.lifetime = float(HOMING.lifetime)
			shot.tint = COLORS[enemy.boss_theme]
			shot.slow_on_hit = skill != "fireball"
		_:
			if skill in AREAS:
				if skill == "cataclysm":
					# Remove old hazards/walls so the marked refuge remains reachable.
					game._clear_projectiles()
					game._clear_zones()
				for point in enemy.skill_points:
					var options: Dictionary = AREAS[skill].duplicate()
					var zone_kind: String = {"frost_field": "frost", "spikes": "spike", "meteors": "meteor", "ice_storm": "ice_spike"}.get(skill, skill)
					if skill == "cataclysm": options.safe_position = point
					game.spawn_zone(DungeonRoom.CENTER if skill == "cataclysm" else point, zone_kind, enemy.damage, options)
	game.effects.burst(enemy.position, COLORS[enemy.boss_theme], 22)
	enemy.attack_cooldown = PHASE_TWO_COOLDOWN if enemy.boss_phase_two else COOLDOWN

static func draw_warning(enemy: DungeonEnemy) -> void:
	if enemy.windup <= 0: return
	var progress := 1.0 - enemy.windup / enemy.windup_duration
	var color: Color = COLORS[enemy.boss_theme]
	var skill := enemy.action
	if skill in AREAS:
		for point in enemy.skill_points:
			var local_point := (point - enemy.position) / enemy.scale
			var radius: float = AREAS[skill].radius / enemy.scale.x
			if skill == "cataclysm":
				radius = float(AREAS[skill].safe_radius) / enemy.scale.x
				color = Color("8ce2b8")
			enemy.draw_circle(local_point, radius, Color(color, 0.1))
			enemy.draw_arc(local_point, radius, -PI / 2, -PI / 2 + TAU * progress, 48, color, 2)
	elif skill in ["roots", "fireball", "ice_orb"]:
		enemy.draw_line(Vector2.ZERO, enemy.attack_target * 170, Color(color, 0.6), 3)
		enemy.draw_circle(enemy.attack_target * 26, 8 + 6 * progress, color)

static func draw_body(c: DungeonEnemy) -> void:
	var color: Color = Color("fff0cf") if c.hurt > 0 else COLORS[c.boss_theme]
	var dark := color.darkened(0.65)
	var bob := floorf(sin(c.clock * 3) * 1.5)
	c.draw_circle(Vector2(0, 8), 27, Color(0, 0, 0, 0.3))
	PixelArt.block(c, -11, -12 + bob, 22, 16, Color("14212c"))
	PixelArt.block(c, -9, -14 + bob, 18, 16, dark)
	PixelArt.block(c, -13, -8 + bob, 5, 12, color.darkened(0.25))
	PixelArt.block(c, 8, -8 + bob, 5, 12, color.darkened(0.25))
	PixelArt.block(c, -7, -18 + bob, 14, 9, color)
	PixelArt.block(c, -5, -15 + bob, 10, 5, dark)
	PixelArt.block(c, -4, -14 + bob, 3, 1, Color("ffedbd"))
	PixelArt.block(c, 2, -14 + bob, 3, 1, Color("ffedbd"))
	PixelArt.block(c, -2, -6 + bob, 4, 5, Color("ffe8b5"))
	PixelArt.block(c, -8, 2 + bob, 5, 4, dark)
	PixelArt.block(c, 3, 2 + bob, 5, 4, dark)
	match c.boss_theme:
		"moss":
			for side in [-1, 1]:
				c.draw_polyline(PackedVector2Array([Vector2(side * 10, -30 + bob), Vector2(side * 23, -43 + bob), Vector2(side * 28, -56 + bob)]), color, 5)
				c.draw_line(Vector2(side * 22, -43 + bob), Vector2(side * 32, -42 + bob), color, 4)
		"lava":
			for side in [-1, 1]:
				c.draw_colored_polygon(PackedVector2Array([Vector2(side * 10, -32 + bob), Vector2(side * 26, -52 + bob), Vector2(side * 24, -25 + bob)]), color)
			PixelArt.block(c, -1, -12 + bob, 2, 12, Color("f6b864"))
		"frost":
			for i in 5:
				c.draw_colored_polygon(PackedVector2Array([Vector2(-17 + i * 7, -33 + bob), Vector2(-14 + i * 7, -51 - (i % 2) * 6 + bob), Vector2(-11 + i * 7, -33 + bob)]), color)
	if c.final_boss:
		c.draw_arc(Vector2(0, -18), 38, c.clock, c.clock + TAU * 0.8, 32, Color("edbf79"), 2)

