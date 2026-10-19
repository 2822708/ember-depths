extends SceneTree
## Deterministic real-hit tests, without permanent damage or optional contracts.
## Natural floor growth plus capped 1.08 blessings, without optional contracts.

var game: Node2D
var failures: Array[String] = []

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func reset_arena(floor_value: int) -> void:
	for enemy in game.enemies.duplicate(): enemy.queue_free()
	game.enemies.clear()
	game._clear_projectiles()
	game.floor_number = floor_value
	game.permanent_damage = 0
	game.floor_rewards = 0
	game.rooms[game.room_index].kind = "combat"
	game.mode = "playing"
	game.room.set_locked(true)
	game.player.position = Vector2(448, 288)
	game.player.facing = Vector2.RIGHT
	game.player.rebuild_damage(floor_value, 0)
	game.player.damage_multiplier = 1.0
	game.player.max_hp = 100
	game.player.hp = 100
	game.player.invulnerability = 0
	game.player.sword_wave = 0
	game.player.ward_available = false
	game.player.blood = false

func add_enemy(kind: int, at: Vector2, boss := false) -> DungeonEnemy:
	var enemy: DungeonEnemy = game.spawn_enemy(kind, at, false, boss)
	enemy.set_physics_process(false)
	enemy.position = at
	return enemy

func real_hit_count(enemy: DungeonEnemy) -> int:
	var hits := 0
	while not enemy.dead and hits < 1000:
		game.player.attack_timer = 0
		game.player.try_attack()
		hits += 1
	return hits

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.permanent_damage = 0
	game.new_run()
	game.player.set_physics_process(false)
	game._enter_room(game.rooms[0].doors.values()[0], Vector2i.ZERO)
	for enemy in game.enemies: enemy.set_physics_process(false)
	await physics_frame
	# Fixed scenario: 0 upgrades on entry to floor 1; all eight damage upgrades
	# from the first four floors by floor 5. No treasure/shop/contract assumptions.
	for floor_value in [1, 5, 10, 20]:
		reset_arena(floor_value)
		if floor_value > 1:
			for i in 8: game.player.upgrade_damage()
		var enemy := add_enemy(0, game.player.position + Vector2(35, 0))
		var health := enemy.max_hp
		var damage: int = game.player.effective_damage()
		var hits := real_hit_count(enemy)
		verify(hits == ceili(float(health) / damage), "Real melee hits match HP/damage at floor %d" % floor_value)
		if floor_value == 1: verify(damage == 25 and hits >= 2 and hits <= 3, "Floor 1 target window")
		if floor_value == 5: verify(damage == 63 and hits == 2, "Floor 5 natural growth and eight blessings: 63 damage")
		if floor_value == 10: verify(damage == 84 and hits == 3, "Floor 10 natural growth and eight blessings: 84 damage")
		if floor_value == 20: verify(damage == 90, "Floor 20 natural damage obeys revised base cap 90")
		game.mode = "playing"
		# Bomber is the existing lowest-HP base archetype (not pooled on floor 1).
		var low := add_enemy(3, game.player.position + Vector2(35, 0))
		var low_hp := low.max_hp
		var low_hits := real_hit_count(low)
		var boss_hits := 0
		if floor_value > 1:
			game.mode = "playing"
			var boss := add_enemy(0, game.player.position + Vector2(35, 0), true)
			boss_hits = real_hit_count(boss)
		print("BALANCE floor=%d damage=%d thrower_hp=%d hits=%d low_hp=%d low_hits=%d boss_hits=%d" % [floor_value, damage, health, hits, low_hp, low_hits, boss_hits])
		if floor_value == 20:
			game.mode = "playing"
			var standard := add_enemy(2, game.player.position + Vector2(35, 0))
			var standard_hp := standard.max_hp
			var standard_hits := real_hit_count(standard)
			game.mode = "playing"
			var guardian := add_enemy(1, game.player.position + Vector2(35, 0), true)
			var guardian_hp := guardian.max_hp
			var guardian_hits := real_hit_count(guardian)
			verify(standard_hits == 13 and guardian_hits >= 140, "New cap, boss health and reduction extend floor 20 battles")
			print("FLOOR20 standard_hp=%d hits=%d boss_hp=%d hits=%d damage=%d" % [standard_hp, standard_hits, guardian_hp, guardian_hits, damage])
	game.damage_stacks = 8
	game.floor_number = 20
	game._generate_floor()
	verify(game.player.damage == 90, "Generate floor rebuilds natural damage with all blessing stacks")
	game._generate_floor()
	verify(game.player.damage == 90, "Regenerating a floor does not compound damage growth")
	game.permanent_damage = 0
	game.new_run()
	verify(game.player.damage == 25 and game.damage_stacks == 0, "New run resets natural growth and stacks")

	reset_arena(4)
	game.player.damage = 25
	var guard := add_enemy(5, game.player.position + Vector2(35, 0))
	guard.shield_facing = Vector2.RIGHT
	var angle_sum := 0.0
	for i in 120:
		var before := guard.shield_facing
		guard._update_mechanics(1.0 / 60)
		angle_sum += absf(before.angle_to(guard.shield_facing))
	verify(angle_sum < PI and is_equal_approx(angle_sum, 1.1), "Shield rotation limited to 0.55 rad/s, 63 degrees over two seconds")
	var hp_before := guard.hp
	game.player.attack_timer = 0
	game.player.try_attack()
	verify(guard.hp == hp_before - 25, "Real player attack from rear bypasses shield after two seconds")

	reset_arena(5)
	var warden := add_enemy(7, Vector2(150, 288))
	var ally := add_enemy(0, Vector2(650, 288))
	verify(warden._warden_direction().dot(Vector2.RIGHT) > 0, "Warden follows distant allies instead of abandoning them")
	verify(warden.max_hp == int(85 * game.enemy_hp_growth(5)), "Warden HP scales from new 85 base")
	warden.take_damage(9999, Vector2.ZERO)
	ally.take_damage(9999, Vector2.ZERO)
	verify(game.enemies.is_empty() and game.mode == "clearing", "Thicker warden remains killable and room clears")

	reset_arena(4)
	var attacker := add_enemy(5, game.player.position + Vector2(30, 0))
	attacker.prepare("melee")
	verify(is_equal_approx(attacker.windup_duration, 0.36), "Melee windup is 0.36 seconds")
	for action in ["melee", "throw", "charge"]:
		attacker.action = action
		attacker._resolve_action()
		verify(is_equal_approx(attacker.attack_cooldown, float(EnemyCatalog.COMBAT[action + "_cooldown"])), "Updated cooldown for " + action)
	attacker.charge_timer = 0
	attacker.windup = 0
	attacker.attack_cooldown = 1.0
	game.player.hp = 29
	attacker._physics_process(0.09)
	verify(is_equal_approx(attacker.attack_cooldown, 0.9), "Low-health cooldown duration is multiplied by 0.9")
	game.player.hp = 30
	verify(is_equal_approx(attacker._cooldown_multiplier(), 1.0), "Pressure starts strictly below 30 percent health")
	verify(is_equal_approx(attacker._pursuit_multiplier(201), 1.15) and is_equal_approx(attacker._pursuit_multiplier(200), 1.0), "Pursuit boost only beyond 200px")

	# Five overlapping attackers for 3 seconds. At floor 4 each shield guard
	# deals 16. Existing 0.85s i-frames permit at most ceil(3/0.85)=4 hits => 64.
	reset_arena(4)
	for i in 5:
		var enemy := add_enemy(5, game.player.position + Vector2(30, 0))
		enemy.attack_cooldown = 0
	for tick in 180:
		game.player.invulnerability = maxf(0, game.player.invulnerability - 1.0 / 60)
		for enemy in game.enemies: enemy._physics_process(1.0 / 60)
	var taken: int = 100 - game.player.hp
	verify(taken > 0 and taken <= 64 and game.player.hp > 0, "Five attackers in 3s remain within i-frame bound (64 damage), actual=%d" % taken)
	print("PRESSURE 5 guards / 3s damage=%d max=64" % taken)
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: real-hit balance, shield turn/rear hit, warden follow/clear, cooldowns, pursuit, pressure i-frames")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
