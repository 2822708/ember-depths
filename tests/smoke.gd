extends SceneTree

var failures: Array[String] = []

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var generator = load("res://scripts/room_generator.gd")
	var rng := RandomNumberGenerator.new()
	for seed_value in 150:
		rng.seed = seed_value
		var count := 5 + seed_value % 4
		var rooms: Array[Dictionary] = generator.generate(rng, count)
		verify(rooms.size() == count, "Room count matches request")
		var visited: Dictionary = {0: true}
		var frontier: Array[int] = [0]
		var head := 0
		var exit_count := 0
		for i in rooms.size():
			if rooms[i].exit:
				exit_count += 1
				verify(i != 0, "Exit is not the safe entrance")
			for direction in rooms[i].doors:
				var next: int = rooms[i].doors[direction]
				verify(rooms[next].doors.get(-direction, -1) == i, "Doors are bidirectional")
				verify(rooms[next].cell == rooms[i].cell + direction, "Doors join adjacent cells")
		while head < frontier.size():
			var current := frontier[head]
			head += 1
			for next in rooms[current].doors.values():
				if not visited.has(next):
					visited[next] = true
					frontier.append(next)
		verify(visited.size() == count, "All generated rooms are reachable")
		verify(exit_count == 1, "Exactly one exit exists")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.new_run()
	await physics_frame
	verify(game.mode == "playing" and game.player.hp == 100, "New run starts alive")
	var neighbor := 1
	for i in range(1, game.rooms.size()):
		if game.rooms[i].kind == "combat":
			neighbor = i
			break
	game._enter_room(neighbor, Vector2i.ZERO)
	await physics_frame
	verify(game.room.locked and not game.enemies.is_empty(), "Combat rooms lock and spawn enemies")
	var enemy = game.enemies[0]
	game.player.position = Vector2(400, 288)
	enemy.position = Vector2(460, 288)
	game.player.facing = Vector2.LEFT
	game.player.attack_timer = 0
	var old_hp: int = enemy.hp
	game.player.try_attack()
	verify(enemy.hp == old_hp, "Swing misses an enemy behind the player")
	game.player.facing = Vector2.RIGHT
	game.player.attack_timer = 0
	game.player.try_attack()
	verify(enemy.hp == old_hp - game.player.damage, "Swing hits an enemy in front")
	# Use public damage handling to verify that the final death triggers the reward flow.
	for target in game.enemies.duplicate():
		target.take_damage(9999, Vector2.ZERO)
	verify(game.mode == "clearing", "Last enemy starts room-clear flow")
	game._offer_reward()
	verify(game.choices.size() == 3, "Three upgrade options are offered")
	var ids: Dictionary = {}
	for upgrade in game.choices: ids[upgrade.id] = true
	verify(ids.size() == 3, "Reward options are distinct")
	# The reward transition is tested with a known upgrade, independently of RNG.
	game.choices[0] = game.UPGRADES[0]
	game.choose_reward(0)
	verify(game.mode == "playing" and not game.room.locked, "Choosing unlocks room and resumes play")
	verify(game.rooms[neighbor].rewarded, "Reward is marked claimed")
	game.choose_reward(0)
	verify(game.collected.size() == 1, "A reward cannot be claimed twice")
	game.player.ward = 1
	game.player.ward_available = true
	game.player.invulnerability = 0
	var ward_hp: int = game.player.hp
	game.player.take_damage(11)
	verify(game.player.hp == ward_hp and not game.player.ward_available, "Ward blocks the first hit")
	game.player.invulnerability = 0
	game.player.take_damage(11)
	verify(game.player.hp == ward_hp - 11, "Ward allows the second hit")
	var hp_before: int = game.player.hp
	game.player.invulnerability = 0
	game.player.take_damage(11)
	game.player.take_damage(11)
	verify(game.player.hp == hp_before - 11, "Invulnerability prevents immediate repeated damage")
	var build_damage: int = game.player.damage
	var build_size: int = game.collected.size()
	game.rooms[game.room_index].exit = true
	game.room.show_exit = true
	game.player.position = Vector2(448, 288)
	game.descend()
	verify(game.floor_number == 2, "Portal advances floor")
	verify(game.player.ward_available, "Ward recharges on a new floor")
	verify(game.player.damage > build_damage and game.collected.size() == build_size and game.damage_stacks == 1, "Floor growth increases damage while preserving collected upgrades")
	game.player.invulnerability = 0
	game.player.ward_available = false
	game.player.take_damage(9999)
	verify(game.mode == "dead", "Lethal damage ends the run")
	game.new_run()
	verify(game.floor_number == 1 and game.player.hp == 100 and game.collected.is_empty() and game.player.damage == 25, "Restart resets the entire build")
	await process_frame
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: 150 generation seeds; combat, reward, invulnerability, descent and restart")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
