extends SceneTree

var failures: Array[String] = []
var game: Node2D

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func clear_arena() -> void:
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy):
			game.enemies.erase(enemy)
			enemy.queue_free()
	game.mode = "playing"
	game.room.set_locked(true)
	game.player.position = Vector2(550, 288)
	game.player.hp = game.player.max_hp
	game.player.invulnerability = 0

func add_enemy(kind: int, at: Vector2) -> DungeonEnemy:
	var enemy: DungeonEnemy = game.spawn_enemy(kind, at)
	enemy.set_physics_process(false)
	enemy.position = at
	return enemy

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.new_run()
	game.player.set_physics_process(false)
	game._enter_room(game.rooms[0].doors.values()[0], Vector2i.ZERO)
	await physics_frame
	clear_arena()

	var guard := add_enemy(5, Vector2(400, 288))
	guard.shield_facing = Vector2.RIGHT
	var guard_hp := guard.hp
	guard.take_damage(100, Vector2(-100, 0))
	verify(guard.hp == guard_hp - 10, "Shield guard reduces frontal damage by 90%")
	guard.shield_facing = Vector2.LEFT
	guard_hp = guard.hp
	guard.take_damage(100, Vector2(-100, 0))
	verify(guard.hp == guard_hp - 100, "Shield guard takes normal damage from behind")

	clear_arena()
	var phase := add_enemy(6, Vector2(400, 288))
	phase.mechanic_clock = 1.5
	phase._update_mechanics(0.01)
	var phase_hp := phase.hp
	phase.take_damage(20, Vector2.ZERO)
	verify(phase.phase_active and phase.hp == phase_hp and phase.collision_layer == 0, "Phase walker is untargetable and invulnerable during phase")
	phase.mechanic_clock = 0.1
	phase._update_mechanics(0.01)
	phase.take_damage(20, Vector2.ZERO)
	verify(not phase.phase_active and phase.hp < phase_hp, "Phase walker can be damaged after phase ends")

	clear_arena()
	var warden := add_enemy(7, Vector2(400, 288))
	var nearby := add_enemy(0, Vector2(819, 288))
	var boundary := add_enemy(0, Vector2(820, 288))
	var distant := add_enemy(0, Vector2(821, 288))
	verify(warden.max_hp == 85, "Warden base HP is 85")
	warden.hp -= 10
	nearby.hp -= 10
	boundary.hp -= 10
	distant.hp -= 10
	warden.heal_clock = 5.99
	warden._update_mechanics(0.02)
	verify(warden.heal_state == "windup" and nearby.hp == nearby.max_hp - 10, "Warden must wind up before healing")
	warden._update_mechanics(1.2)
	verify(warden.hp == warden.max_hp - 10, "Warden never heals itself")
	verify(nearby.hp == nearby.max_hp - 10 + roundi(nearby.max_hp * 0.04), "Warden heals another enemy in radius")
	verify(boundary.hp == boundary.max_hp - 10 + roundi(boundary.max_hp * 0.04), "Warden heals at exactly 420px radius")
	verify(distant.hp == distant.max_hp - 10, "Warden does not heal outside 420px radius")
	var healed_hp := nearby.hp
	warden.take_damage(9999, Vector2.ZERO)
	nearby.hp -= 5
	warden._update_mechanics(3.1)
	verify(nearby.hp == healed_hp - 5, "Killed warden stops healing")
	for enemy in game.enemies.duplicate(): enemy.take_damage(9999, Vector2.ZERO)
	verify(game.enemies.is_empty() and game.mode in ["clearing", "playing"], "Mechanic enemies can all be killed and removed")

	verify(EnemyCatalog.pool(3).size() == 5, "Mechanics are absent before unlock floors")
	verify(EnemyCatalog.pool(4).has(5), "Shield guard enters pool at floor 4")
	verify(EnemyCatalog.pool(4).size() == 6 and not EnemyCatalog.pool(4).has(6) and not EnemyCatalog.pool(4).has(7), "Only shield guard is added at floor 4")
	verify(EnemyCatalog.pool(5).has(7) and not EnemyCatalog.pool(5).has(6), "Warden enters pool at floor 5")
	verify(EnemyCatalog.pool(6).has(6), "Phase walker enters pool at floor 6")
	for i in range(5, 8):
		verify(EnemyCatalog.TYPES[i].hp == [52, 46, 85][i - 5] and EnemyCatalog.TYPES[i].damage < EnemyCatalog.TYPES[3].damage, "Mechanic archetype %d follows the explicit revised HP and low-damage profile" % i)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: shield direction, phase windows, warden healing/death, clear handling, depth pools")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
