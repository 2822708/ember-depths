extends SceneTree
## Real actor/skill integration checks with deterministic clock advancement.
var game: Node2D
var failures: Array[String] = []

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func add_enemy(kind: int, at: Vector2, boss := false) -> DungeonEnemy:
	var enemy: DungeonEnemy = game.spawn_enemy(kind, at, false, boss)
	enemy.set_physics_process(false)
	enemy.position = at
	return enemy

func reset_arena() -> void:
	game._clear_projectiles()
	game._clear_zones()
	for enemy in game.enemies:
		enemy.cancel_mechanics()
		enemy.queue_free()
	game.enemies.clear()
	game.floor_number = 1
	game.floor_rewards = 0
	game.rooms[game.room_index].kind = "combat"
	game.rooms[game.room_index].exit = false
	game.mode = "playing"
	game.player.position = Vector2(448, 288)
	game.player.facing = Vector2.RIGHT
	game.player.max_hp = 100
	game.player.hp = 100
	game.player.invulnerability = 0
	game.player.slow_timer = 0
	game.player.ward_available = false
	game.player.sword_wave = 0
	game.player.knockback = 80
	game.player.damage = 1
	game.player.damage_multiplier = 1
	# A living anchor prevents clear cleanup from erasing the skill being examined.
	add_enemy(0, Vector2(800, 460))

func resolve(enemy: DungeonEnemy, action: String) -> void:
	enemy.prepare(action)
	verify(enemy.windup > 0, action + " has a warning phase")
	enemy._physics_process(enemy.windup_duration + 0.001)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.new_run()
	game.player.set_physics_process(false)
	await physics_frame
	# Use the safe starting room's actual physics, without random combat pillars.
	reset_arena()
	var melee := add_enemy(4, game.player.position + Vector2(30, 0))
	melee.is_minion = true
	melee.hp = 10000
	melee.max_hp = 10000
	melee.attack_cooldown = 0
	for tick in 120:
		game.player.invulnerability = maxf(0, game.player.invulnerability - 1.0 / 60)
		if tick % 7 == 0:
			game.player.attack_timer = 0
			game.player.try_attack()
		melee._physics_process(1.0 / 60)
	verify(game.player.hp < 100, "Sustained real attacks do not prevent a melee enemy completing windup and dealing damage")
	melee.prepare("melee")
	var before_windup := melee.windup
	melee.take_damage(1, Vector2(80, 0))
	verify(melee.windup == before_windup and melee.knock == Vector2(80, 0), "Damage displaces without resetting windup")
	melee.charge_timer = 0.4
	melee.take_damage(1, Vector2.ZERO)
	verify(melee.charge_timer == 0.4, "Damage does not cancel charge")

	reset_arena()
	var thrower := add_enemy(0, Vector2(300, 288))
	resolve(thrower, "throw")
	verify(game.projectiles.size() == 3, "Thrower emits three projectiles")
	verify(is_equal_approx(absf(game.projectiles[0].velocity.angle_to(game.projectiles[2].velocity)), deg_to_rad(25)), "Shotgun total spread is 25 degrees")
	for shot in game.projectiles: verify(shot.damage <= thrower.damage * 1.5, "Shotgun respects skill damage limit")
	reset_arena()
	var charger := add_enemy(1, game.player.position + Vector2(-28, 0))
	resolve(charger, "charge")
	charger._physics_process(0.01)
	verify(game.zones.size() == 1 and game.zones[0].radius == 70 and game.zones[0].warning > 0, "Charger impact emits one telegraphed 70px shock")
	reset_arena()
	charger = add_enemy(1, Vector2(67, 220))
	charger.prepare("charge")
	charger.windup = 0
	charger.attack_target = Vector2.LEFT
	charger.charge_timer = 0.5
	for tick in 30:
		charger._physics_process(1.0 / 60)
		if charger.stun_timer > 0: break
	verify(charger.stun_timer == 0.6, "Charger wall stun stays 0.6 seconds")
	reset_arena()
	var summoner := add_enemy(2, Vector2(350, 288))
	resolve(summoner, "summon")
	verify(game.enemies.size() == 5 and game.zones.size() == 1, "Summoner adds three minions and slow zone")
	var slow: BossZone = game.zones[0]
	slow.set_physics_process(false)
	game.player.position = slow.position
	slow._physics_process(slow.warning + 0.01)
	verify(game.player.slow_timer == 2.0, "Summon slow lasts two seconds")
	reset_arena()
	var bomber := add_enemy(3, game.player.position + Vector2(80, 0))
	resolve(bomber, "explode")
	verify(bomber.dead and game.zones.size() == 1, "Bomber explodes and leaves fire")
	verify(game.zones[0].radius == 130 and game.zones[0].duration == 2 and game.zones[0].damage <= bomber.damage * 1.5, "Fire radius, duration and damage match data")
	reset_arena()
	var split := add_enemy(4, Vector2(350, 288))
	split.take_damage(9999, Vector2.ZERO)
	verify(game.enemies.size() == 3, "Split produces two children")
	for child in game.enemies:
		if not child.is_minion: continue
		var hp: int = child.hp
		child.take_damage(9999, Vector2.ZERO)
		verify(child.hp == hp and child.spawn_invulnerability == 0.5, "Split children receive half-second protected emergence")
		child._physics_process(0.51)
		child.take_damage(9999, Vector2.ZERO)
		verify(child.dead, "Split child protection expires")
	reset_arena()
	var guard := add_enemy(5, Vector2(350, 288))
	guard.shield_facing = Vector2.RIGHT
	resolve(guard, "shield_push")
	var guard_hp := guard.hp
	guard.take_damage(20, Vector2.LEFT * 80)
	verify(guard.hp == guard_hp and guard.shield_push_timer > 0, "Raised shield fully blocks the front")
	var guard_x := guard.position.x
	guard._physics_process(0.1)
	verify(guard.position.x > guard_x, "Shield push advances")
	guard.take_damage(20, Vector2.RIGHT * 80)
	verify(guard.hp == guard_hp - 20, "Shield push still exposes the back")
	reset_arena()
	var phase := add_enemy(6, Vector2(350, 288))
	phase.mechanic_clock = 1.0
	phase._update_mechanics(0.01)
	verify(phase.phase_warning, "Phase transition has warning")
	phase._update_mechanics(0.5)
	verify(phase.phase_active, "Phase is active before ring")
	phase._update_mechanics(1.01)
	verify(not phase.phase_active and game.projectiles.size() == 8, "Phase exit emits eight radial projectiles")

	reset_arena()
	var warden := add_enemy(7, Vector2(350, 288))
	var ally := add_enemy(1, Vector2(750, 288))
	ally.hp = 10
	warden.hp -= 10
	var warden_hp := warden.hp
	warden._update_mechanics(6.0)
	verify(warden.heal_state == "windup" and ally.hp == 10, "Six-second timer starts visible windup without healing")
	warden._update_mechanics(0.8)
	warden.take_damage(1, Vector2(80, 0))
	verify(is_equal_approx(warden.heal_progress, 0.4) and warden.heal_flash > 0 and warden.knock == Vector2.ZERO, "Damage halves windup progress, flashes, and cannot knock back casting warden")
	var warden_pos := warden.position
	warden._physics_process(0.1)
	verify(warden.position == warden_pos, "Warden stops moving during cast")
	warden._update_mechanics(0.71)
	verify(warden.heal_state == "channel" and warden.heal_ticks == 1 and ally.hp > 10, "Healing starts only after full windup")
	var after_first := ally.hp
	verify(warden.heal_targets.has(ally) and warden.heal_beam_timer > 0, "Channel creates target beams")
	warden._update_mechanics(1.0)
	verify(warden.heal_ticks == 2 and ally.hp > after_first, "Channel heals more than once")
	verify(warden.hp == warden_hp - 1 and game.player.hp == 100, "Warden never heals itself or player")
	var progress := warden.heal_progress
	warden.take_damage(1, Vector2.ZERO)
	verify(is_equal_approx(warden.heal_progress, progress * 0.5), "Damage also halves channel progress")
	var ally_hp := ally.hp
	warden.take_damage(9999, Vector2.ZERO)
	warden._update_mechanics(10)
	verify(warden.dead and not warden.visible and warden.heal_targets.is_empty() and ally.hp == ally_hp, "Death terminates cast, beams and healing immediately")

	reset_arena()
	var boss := add_enemy(1, Vector2(350, 288), true)
	for theme in BossModule.LOADOUTS:
		verify(BossModule.LOADOUTS[theme].size() >= 6, theme + " has six or more skills")
		boss.boss_theme = theme
		boss.boss_skill_index = 0
		var last := ""
		for i in 36:
			var skill := BossModule.next_skill(boss)
			verify(skill != last, "Boss rhythm avoids consecutive repeats")
			last = skill
	verify(BossModule.FINAL_SKILLS.size() >= 12, "Final boss has at least twelve skills")
	for skill in BossModule.FINAL_SKILLS:
		game._clear_projectiles()
		game._clear_zones()
		boss.prepare(skill)
		verify(boss.windup > 0, "Boss telegraph exists: " + skill)
		if skill in BossModule.AREAS: verify(not boss.skill_points.is_empty(), "Ground target plan: " + skill)
		boss._resolve_action()
		for shot in game.projectiles: shot.set_physics_process(false)
		for zone in game.zones:
			zone.set_physics_process(false)
			verify(zone.warning > 0, "Zone retains readable warning: " + skill)
		if skill in ["roots", "fireball", "ice_orb"]:
			var shot: EnemyProjectile = game.projectiles[0]
			var angle := shot.velocity.angle()
			game.player.position = shot.position + Vector2.DOWN * 150
			shot._physics_process(0.1)
			verify(absf(angle_difference(angle, shot.velocity.angle())) <= 0.04501 and shot.lifetime <= 3, "Homing turns weakly and has bounded lifetime")
		if skill == "ice_wall":
			var wall_zone: BossZone = game.zones[0]
			wall_zone._physics_process(wall_zone.warning + 0.01)
			verify(is_instance_valid(wall_zone.wall) and wall_zone.wall.get_child_count() == 2, "Ice wall creates two segments with escape gap")
			wall_zone.deactivate()
			verify(wall_zone.wall.collision_layer == 0, "Cleared wall stops blocking immediately")
		if skill == "cataclysm":
			var ultimate: BossZone = game.zones[0]
			game.player.position = ultimate.safe_position
			game.player.invulnerability = 0
			var hp: int = game.player.hp
			ultimate._physics_process(ultimate.warning + 0.01)
			verify(game.player.hp == hp and ultimate.is_safe(game.player.position), "Full-room ultimate has a damage-free safe refuge")
			game.player.position = Vector2(65, 65)
			if ultimate.is_safe(game.player.position): game.player.position = Vector2(820, 460)
			ultimate._physics_process(0.01)
			verify(game.player.hp < hp, "Ultimate damages outside refuge")
	boss.final_boss = true
	boss.hp = boss.max_hp / 2
	BossModule.update_phase(boss)
	verify(boss.boss_phase_two and boss.ultimate_pending, "Half HP activates phase two once")
	boss.prepare("magma")
	boss._resolve_action()
	verify(is_equal_approx(boss.attack_cooldown, 1.1), "Phase two cooldown is 1.1 seconds")
	boss.boss_skill_index = 0
	verify(BossModule.next_skill(boss) == "cataclysm", "Phase two schedules dodgeable ultimate")
	boss.take_damage(1, Vector2(80, 0))
	verify(boss.knock == Vector2(80, 0), "Boss has no knockback damage reduction")

	# Exercise actual room transition cleanup, including walls and player waves.
	warden = add_enemy(7, Vector2(400, 288))
	warden._update_mechanics(7.3)
	var wall: BossZone = game.spawn_zone(Vector2(350, 288), "ice_wall", 0)
	wall._physics_process(1.0)
	game.spawn_player_wave(Vector2(300, 300), Vector2.RIGHT, 10)
	game.spawn_projectile(Vector2(300, 300), Vector2.RIGHT, 10)
	game._enter_room(0, Vector2i.ZERO)
	verify(game.projectiles.is_empty() and game.player_waves.is_empty() and game.zones.is_empty(), "Room transition clears all projectile/zone registries")
	verify(warden.heal_state == "idle" and warden.heal_targets.is_empty() and not warden.visible, "Room transition cancels heal circles and beams")
	verify(wall.retired and wall.wall.collision_layer == 0, "Room transition disables temporary wall collider")
	await process_frame
	reset_arena()
	for i in 170: game.spawn_projectile(Vector2(350, 288), Vector2.RIGHT, 1)
	for i in 40: game.spawn_zone(Vector2(350, 288), "fire", 1)
	verify(game.projectiles.size() == 160 and game.zones.size() == 36, "Simultaneous projectile/zone counts are bounded")
	game._clear_projectiles()
	game._clear_zones()
	var transient: EnemyProjectile = game.spawn_projectile(Vector2(350, 288), Vector2.RIGHT, 1)
	transient._physics_process(3.01)
	verify(transient.removed and game.projectiles.is_empty(), "Projectiles expire without leaks")
	var transient_zone: BossZone = game.spawn_zone(Vector2(350, 288), "poison", 1, {"duration": 1.0, "warning": 0.5, "radius": 200.0, "start_radius": 30.0})
	transient_zone.age = 1.0
	verify(is_equal_approx(transient_zone.current_radius(), 115.0), "Poison expands gradually after warning")
	transient_zone._physics_process(1.0)
	verify(transient_zone.retired and game.zones.is_empty(), "Areas retire after duration")
	game.spawn_projectile(Vector2(350, 288), Vector2.RIGHT, 1)
	game.spawn_player_wave(Vector2(350, 288), Vector2.RIGHT, 1)
	game.spawn_zone(Vector2(350, 288), "fire", 1)
	for i in 100: game.effects.burst(Vector2(350, 288), Color.WHITE, 20)
	for i in 100: game.effects.text(Vector2(350, 288), "1", Color.WHITE)
	verify(game.effects.particles.size() <= 256 and game.effects.numbers.size() <= 48, "Cosmetic bursts cannot grow without bound")
	for enemy in game.enemies.duplicate(): enemy.take_damage(99999, Vector2.ZERO)
	verify(game.mode == "clearing" and game.zones.is_empty() and game.projectiles.is_empty() and game.player_waves.is_empty(), "Last kill clears every skill registry immediately")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: sustained attacks, all eight enemy skills, all boss skills/telegraphs, phase two, heal channel/setbacks/death, safe ultimate and transition cleanup")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
