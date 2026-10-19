extends SceneTree
## Integration regression coverage for geometry, hazards, new combat and capped rewards.

var failures: Array[String] = []
var game: Node2D

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func reset_arena() -> void:
	game._clear_projectiles()
	for enemy in game.enemies:
		game.world.remove_child(enemy)
		enemy.queue_free()
	game.enemies.clear()
	game.mode = "playing"
	game.room.set_locked(true)
	game.player.hp = game.player.max_hp
	game.player.invulnerability = 0
	game.player.position = Vector2(550, 288)
	game.player.dash_timer = 0

func add_enemy(kind: int, at: Vector2) -> DungeonEnemy:
	var enemy: DungeonEnemy = game.spawn_enemy(kind, at)
	enemy.set_physics_process(false)
	enemy.position = at
	enemy.attack_cooldown = 0
	return enemy

func run() -> void:
	# Every safe tile must connect to the center, not just the room graph.
	for variant in RoomCatalog.LAYOUTS.size():
		var room := DungeonRoom.new()
		var doors: Dictionary = {Vector2i.UP: 0, Vector2i.RIGHT: 0, Vector2i.DOWN: 0, Vector2i.LEFT: 0}
		room.configure({"variant": variant, "theme": "moss", "seed": 17, "doors": doors})
		root.add_child(room)
		var reached: Dictionary = {Vector2i(14, 9): true}
		var queue: Array[Vector2i] = [Vector2i(14, 9)]
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			for direction in RoomGenerator.DIRECTIONS:
				var next: Vector2i = cell + direction
				if room.is_safe_cell(next) and not reached.has(next):
					reached[next] = true
					queue.append(next)
		for y in range(1, 17):
			for x in range(1, 27):
				var cell := Vector2i(x, y)
				if room.is_safe_cell(cell): verify(reached.has(cell), "All safe tiles connect in layout %d" % variant)
		for direction in doors:
			var landing: Vector2 = DungeonRoom.DOOR_POINTS[direction] - Vector2(direction) * 68
			var cell := Vector2i(floor(landing.x / 32), floor(landing.y / 32))
			verify(reached.has(cell), "Door landing connects in layout %d" % variant)
		for i in 12:
			var spawn := room.spawn_point(DungeonRoom.CENTER)
			verify(room.is_safe_cell(Vector2i(floor(spawn.x / 32), floor(spawn.y / 32))), "Spawn avoids solids and hazards")
		room.queue_free()
	var rng := RandomNumberGenerator.new()
	verify(not RoomCatalog.pool(1000).is_empty(), "Infinite-depth runs keep a valid room pool")
	for floor_number in range(1, 10):
		for seed_value in 40:
			rng.seed = seed_value
			var rooms := RoomGenerator.generate(rng, 8, floor_number, "frost")
			for i in range(1, rooms.size()):
				if rooms[i].kind in ["treasure", "shop"]:
					verify(rooms[i].variant == 0, "Noncombat rooms use safe layouts")
				else: verify(rooms[i].variant in RoomCatalog.pool(floor_number), "Layouts respect depth pool")
				verify(rooms[i].theme == "frost", "All rooms share floor theme")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var low_hp: float = float(EnemyCatalog.TYPES[0].hp) * game.enemy_hp_growth(3)
	var high_hp: float = float(EnemyCatalog.TYPES[0].hp) * game.enemy_hp_growth(13)
	verify(high_hp / low_hp > 5.0, "Enemy HP follows exponential depth scaling")
	verify(game.enemy_hp_growth(30) < pow(1.18, 29), "Deep enemy HP growth softens after floor 24")
	game.new_run()
	verify(game.floor_rewards == 0, "Floor starts with zero room rewards")
	game.floor_number = 5
	game._generate_floor()
	var boss_index := 0
	for i in game.rooms.size():
		if game.rooms[i].exit: boss_index = i
	game._enter_room(boss_index, Vector2i.ZERO)
	var boss_found := false
	for enemy in game.enemies:
		if enemy.is_boss: boss_found = true
	verify(boss_found, "Every fifth floor has a boss in its exit room")
	var boss_enemy: DungeonEnemy = null
	for enemy in game.enemies:
		if enemy.is_boss: boss_enemy = enemy
	verify(boss_enemy != null and boss_enemy.max_hp > 3.0 * EnemyCatalog.TYPES[boss_enemy.kind].hp, "Boss has a distinct high-health profile")
	if boss_enemy != null:
		boss_enemy.set_physics_process(false)
		boss_enemy.position = game.player.position + Vector2(120, 0)
		boss_enemy.attack_cooldown = 0
		boss_enemy._physics_process(0.01)
		verify(boss_enemy.action in BossModule.LOADOUTS[boss_enemy.boss_theme] and boss_enemy.windup > 0, "Boss telegraphs a theme-specific attack")
	game.new_run()
	game.player.set_physics_process(false)
	game._enter_room(game.rooms[0].doors.values()[0], Vector2i.ZERO)
	await physics_frame
	reset_arena()
	var thrower := add_enemy(0, Vector2(350, 288))
	thrower._physics_process(0.01)
	verify(thrower.action == "throw" and thrower.windup > 0, "Ranged enemy telegraphs before throwing")
	thrower._physics_process(0.7)
	verify(game.projectiles.size() == 3, "Throw produces a three-shot fan")
	reset_arena()
	var shot: EnemyProjectile = game.spawn_projectile(Vector2(500, 288), Vector2.RIGHT, 10)
	await physics_frame
	shot.set_physics_process(false)
	var before: int = game.player.hp
	shot._physics_process(0.3)
	verify(shot.removed and game.player.hp == before - 10, "Swept projectile hits player")
	var wall_shot: EnemyProjectile = game.spawn_projectile(Vector2(70, 220), Vector2.LEFT, 10)
	wall_shot.set_physics_process(false)
	wall_shot._physics_process(0.5)
	verify(wall_shot.removed, "Projectile stops at a solid wall")
	reset_arena()
	var charger := add_enemy(1, Vector2(350, 288))
	charger._physics_process(0.01)
	verify(charger.action == "charge" and charger.windup > 0, "Charger telegraphs")
	var direction := charger.attack_target
	game.player.position.y += 80
	charger._physics_process(0.8)
	verify(charger.charge_timer > 0 and charger.attack_target == direction, "Charge commits to telegraphed direction")
	var x := charger.position.x
	charger._physics_process(0.05)
	verify(charger.position.x > x, "Charge physically moves toward committed target")
	reset_arena()
	var summoner := add_enemy(2, Vector2(350, 288))
	summoner._physics_process(0.01)
	verify(summoner.action == "summon", "Summoner casts")
	summoner._physics_process(1.1)
	verify(game.enemies.size() == 4 and summoner.summon_budget == 1, "Summoning creates three bounded minions")
	for enemy in game.enemies:
		if enemy != summoner: verify(enemy.is_minion, "Summoned enemies cannot split")
	reset_arena()
	var bomber := add_enemy(3, Vector2(490, 288))
	bomber._physics_process(0.01)
	verify(bomber.action == "explode" and not bomber.dead, "Bomber gives a fuse warning")
	before = game.player.hp
	bomber._physics_process(1.0)
	verify(bomber.dead and game.player.hp == before - bomber.damage, "Explosion damages player and consumes bomber")
	reset_arena()
	var splitter := add_enemy(4, Vector2(400, 288))
	splitter.take_damage(9999, Vector2.ZERO)
	verify(game.enemies.size() == 2 and game.mode == "playing" and game.room.locked, "Final splitting parent does not clear room before children die")
	game.spawn_projectile(Vector2(120, 220), Vector2.RIGHT, 10)
	for enemy in game.enemies.duplicate():
		var hp_before: int = enemy.hp
		enemy.take_damage(9999, Vector2.ZERO)
		verify(enemy.hp == hp_before, "Split children resist damage during their spawn warning")
		enemy._physics_process(0.5)
		enemy.take_damage(9999, Vector2.ZERO)
	verify(game.mode == "clearing" and game.projectiles.is_empty(), "Killing all children clears room and pending projectiles")
	# Damage is differentiated by archetype even at the same floor.
	reset_arena()
	var damages: Dictionary = {}
	for i in 5:
		var enemy := add_enemy(i, Vector2(400, 288))
		damages[enemy.damage] = true
	verify(damages.size() == 5, "Each archetype has distinct damage")
	reset_arena()
	game.player.facing = Vector2.LEFT
	game.player.dash_cooldown = 0
	game.player.start_dash(Vector2.ZERO)
	verify(game.player.dash_direction == Vector2.LEFT, "Stationary dash uses current aim")
	game.player.dash_cooldown = 0
	game.player.start_dash(Vector2.RIGHT)
	verify(game.player.dash_direction == Vector2.RIGHT, "Next moving dash replaces stationary direction")
	game.player.dash_timer = 0
	game.player.invulnerability = 0
	# Test real hazard damage and its invulnerability/dash escape rules.
	game.room.hazards[Vector2i(14, 9)] = "lava"
	game.room.active = true
	game.player.position = DungeonRoom.CENTER
	before = game.player.hp
	game.room.apply_hazard(game.player)
	game.room.apply_hazard(game.player)
	verify(game.player.hp == before - 14 and game.hurt_flash > 0, "Lava damages once per invulnerability window and signals hurt feedback")
	game.player.invulnerability = 0
	game.player.dash_timer = 0.1
	game.room.apply_hazard(game.player)
	verify(game.player.hp == before - 14, "Dashing avoids ground hazard damage")
	game.player.dash_timer = 0
	game.room.hazards[Vector2i(14, 9)] = "spikes"
	game.room.clock = 1.1
	before = game.player.hp
	game.room.apply_hazard(game.player)
	verify(game.player.hp == before, "Spike warning phase does not damage")
	game.room.clock = 1.8
	game.room.apply_hazard(game.player)
	verify(game.player.hp == before - 18, "Raised spikes damage the player")
	game.player.attack_cooldown = 0.302
	for upgrade in game.available_upgrades():
		if upgrade.id == "haste":
			verify("0.7%" in upgrade.desc and "上限" in upgrade.desc, "Near-cap haste displays actual benefit")
	game.player.attack_cooldown = game.MIN_ATTACK_COOLDOWN
	for i in 80:
		game._offer_reward()
		var ids: Dictionary = {}
		for upgrade in game.choices:
			verify(upgrade.id != "haste", "Capped haste is excluded from rewards")
			ids[upgrade.id] = true
		verify(ids.size() == 3, "Filtering haste preserves three distinct choices")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: 10 room geometries, 360 depth pools, hazards, 5 enemy behaviors, projectiles, split/clear ordering, dash and capped haste")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
