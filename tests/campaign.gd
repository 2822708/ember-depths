extends SceneTree
## End-to-end reward, shop, contracts, themed skills, victory and audio regressions.
var failures: Array[String] = []
var game: Node2D

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func pick(id: String) -> void:
	game.choices.clear()
	for upgrade in game.UPGRADES:
		if upgrade.id == id: game.choices.append(upgrade)
	game.mode = "reward"
	game.pending_rewards = 1
	game.reward_source = "combat"
	game.choose_reward(0)

func wipe_enemies() -> void:
	var attempts := 0
	while not game.enemies.is_empty() and attempts < 5:
		for enemy in game.enemies.duplicate():
			# Frozen-actor flow test advances the new split spawn grace explicitly.
			enemy.spawn_invulnerability = maxf(0, enemy.spawn_invulnerability - 0.5)
			enemy.take_damage(9999999, Vector2.ZERO)
		attempts += 1
	verify(game.enemies.is_empty(), "All enemies and split children can be cleared")

func drain_rewards() -> void:
	if game.mode == "clearing": game._offer_reward()
	while game.mode == "reward":
		game.choices[0] = game.UPGRADES[3]
		game.choose_reward(0)

func prepare_room(kind: String) -> void:
	game.mode = "playing"
	game.rooms[1].kind = kind
	game.rooms[1].variant = 0
	game.rooms[1].cleared = false
	game.rooms[1].rewarded = false
	game.rooms[1].exit = false
	game._enter_room(1, Vector2i.ZERO)
	game.player.position = DungeonRoom.CENTER
	for enemy in game.enemies: enemy.set_physics_process(false)

func run() -> void:
	var rng := RandomNumberGenerator.new()
	for floor_value in range(1, 21):
		for seed_value in 12:
			rng.seed = seed_value
			var rooms := RoomGenerator.generate(rng, mini(4 + floor_value, 8), floor_value)
			var kinds: Dictionary = {}
			for room in rooms:
				kinds[room.kind] = true
				if room.exit: verify(room.kind == ("boss" if floor_value % 5 == 0 else "combat"), "Exit remains a combat encounter")
			if floor_value >= 3:
				verify(kinds.has("treasure") and kinds.has("shop") and kinds.has("cursed"), "Deep floors contain all three special room types")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.new_run()
	game.player.set_physics_process(false)
	game.set_process(false)
	# Only the first two ordinary clears reserve rewards; later exits still open.
	for i in 4:
		prepare_room("combat")
		var before: int = game.collected.size()
		wipe_enemies()
		verify(game.mode == ("clearing" if i < 2 else "playing"), "Ordinary clear respects floor quota")
		drain_rewards()
		verify(game.collected.size() == before + (1 if i < 2 else 0), "Only first two ordinary clears award blessings")
		if i >= 2: verify(not game.room.locked and game.rooms[1].rewarded, "Quota-exhausted room opens without a reward")
	verify(game.floor_rewards == 2, "Floor reserves exactly two ordinary choices")
	game.rooms[1].exit = true
	game._enter_room(1, Vector2i.ZERO)
	verify(game.room.show_exit, "Revisiting quota-exhausted exit retains its portal")
	prepare_room("combat")
	wipe_enemies()
	drain_rewards()
	prepare_room("cursed")
	verify(game.enemies[0].max_hp >= 35, "Cursed enemies remain combat-capable")
	var base_stats: Dictionary = EnemyCatalog.TYPES[game.enemies[0].kind]
	verify(game.enemies[0].max_hp == roundi(int(base_stats.hp * game.enemy_hp_growth(game.floor_number)) * 1.4), "Cursed room scales enemy HP by 40 percent")
	var before: int = game.collected.size()
	wipe_enemies()
	verify(game.pending_rewards == 2, "Cursed clear queues two rewards")
	game._offer_reward()
	game.choices[0] = game.UPGRADES[0]
	game.choose_reward(0)
	verify(game.mode == "reward" and game.room.locked and game.pending_rewards == 1, "First cursed choice keeps room locked for the second")
	drain_rewards()
	verify(game.collected.size() == before + 2 and not game.room.locked, "Second cursed choice completes the encounter")
	verify(game.floor_rewards == 2, "Extra cursed choices do not consume or reset ordinary quota")
	prepare_room("treasure")
	verify(game.enemies.is_empty() and not game.room.locked, "Treasure room has no combat or locked doors")
	before = game.collected.size()
	game.interact()
	drain_rewards()
	game.interact()
	verify(game.collected.size() == before + 1 and game.mode == "playing", "Treasure grants exactly one extra blessing")
	verify(game.floor_rewards == 2, "Treasure does not reset ordinary quota")
	prepare_room("shop")
	verify(game.enemies.is_empty(), "Shop is peaceful")
	game.currency = 0
	game.interact()
	var stock: Array = game.choices.duplicate(true)
	game.choose_reward(0)
	verify(game.mode == "reward" and game.collected.size() == before + 1 and game.currency == 0, "Unaffordable purchase cannot claim a blessing")
	game.leave_shop()
	game.interact()
	verify(game.choices == stock, "Leaving and returning does not reroll shop stock")
	game.currency = game.SHOP_COST
	game.player.damage = DungeonPlayer.MAX_BASE_DAMAGE
	game.choices[0] = game.UPGRADES[0]
	game.choose_reward(0)
	verify(game.currency == game.SHOP_COST and not game.rooms[1].rewarded, "Stale capped damage card cannot charge shop currency")
	game.choices[0] = game.UPGRADES[3]
	game.choose_reward(0)
	verify(game.currency == 0 and game.mode == "playing" and game.rooms[1].rewarded, "Purchase spends currency and claims stock once")
	before = game.collected.size()
	game.interact()
	verify(game.collected.size() == before and game.in_shop(), "Purchased shop reopens for active/consumable purchases without duplicating passive")
	game.choose_reward(0)
	verify(game.collected.size() == before, "Claimed passive cannot be bought twice")
	game.leave_shop()
	game.new_run()
	game.player.set_physics_process(false)
	verify(game.floor_rewards == 0, "New floor/run resets ordinary reward budget")
	for i in game.MAX_DAMAGE_STACKS: pick("damage")
	verify(game.damage_stacks == 8 and game.player.damage == 46, "Eight 1.08 damage upgrades multiply natural base, rounded once")
	verify(not game.available_upgrades().any(func(item: Dictionary) -> bool: return item.id == "damage"), "Maxed damage leaves the reward pool")
	var stacks_before: int = game.collected.size()
	pick("damage")
	verify(game.collected.size() == stacks_before and game.damage_stacks == 8, "Stale damage reward cannot bypass stack limit")
	game.mode = "playing"
	pick("glass")
	pick("blood")
	verify(game.player.effective_damage() == 103, "Maximum new-run damage including both contracts remains bounded")
	game.player.damage = 10000
	verify(game.player.effective_damage() == 140, "Final damage hard cap also covers unexpected base values")
	game.permanent_damage = 10000
	game.new_run()
	verify(game.player.damage == 90 and game.damage_stacks == 0 and game.player.effective_damage() == 90, "Permanent progression cannot bypass base damage cap")
	game.permanent_damage = 0
	game.new_run()
	pick("glass")
	verify(game.player.max_hp == 75 and game.player.hp == 75 and game.player.effective_damage() == 35, "Glass contract trades maximum health for multiplicative damage")
	pick("oath")
	game.player.start_dash(Vector2.RIGHT)
	verify(game.player.dash_timer == 0 and is_equal_approx(game.player.effective_attack_cooldown(), 0.30), "Oath respects final attack floor and prevents dashing")
	pick("blood")
	game.player.hp = 2
	game.player.attack_timer = 0
	game.player.ward_available = true
	game.player.invulnerability = 100
	game.player.try_attack()
	verify(game.player.hp == 1 and game.player.ward_available, "Blood cost bypasses invulnerability without consuming Ward")
	game.player.attack_timer = 0
	game.player.try_attack()
	verify(game.mode == "dead", "Blood cost can end the run")
	game.new_run()
	verify(not game.player.no_dash and not game.player.blood and game.player.damage_multiplier == 1.0, "New run resets all contracts")
	game.player.set_physics_process(false)
	# Exercise each theme's actual resolution, not only skill ID tables.
	prepare_room("combat")
	for enemy in game.enemies:
		game.world.remove_child(enemy)
		enemy.queue_free()
	game.enemies.clear()
	var boss: DungeonEnemy = game.spawn_enemy(0, Vector2(350, 288), false, true)
	boss.set_physics_process(false)
	game.player.position = Vector2(500, 288)
	for theme in ["moss", "lava", "frost"]:
		boss.boss_theme = theme
		boss.boss_skill_index = 0
		var visited_skills: Dictionary = {}
		for step in 36:
			var chosen := BossModule.next_skill(boss)
			verify(chosen in BossModule.LOADOUTS[theme], "Theme chooses only its own skill loadout")
			visited_skills[chosen] = true
		verify(visited_skills.size() == BossModule.LOADOUTS[theme].size(), "Theme rhythm eventually visits every skill")
	game._clear_projectiles()
	boss.prepare("magma")
	boss._resolve_action()
	verify(game.projectiles.size() == 7, "Magma skill emits seven lava projectiles")
	game._clear_projectiles()
	boss.prepare("frost_fan")
	boss._resolve_action()
	verify(game.projectiles.size() == 7 and game.projectiles[0].slow_on_hit, "Frost fan creates slowing projectiles")
	boss.prepare("vines")
	boss._resolve_action()
	verify(game.zones.size() == 1 and game.zones[0].kind == "vines", "Moss skill creates a vine zone")
	var vine: BossZone = game.zones[0]
	vine.set_physics_process(false)
	game.player.position = vine.position
	game.player.hp = 100
	game.player.invulnerability = 0
	vine._physics_process(0.3)
	verify(game.player.hp == 100, "Vine zone warning never damages early")
	vine._physics_process(0.7)
	verify(game.player.hp < 100 and game.player.slow_timer > 0, "Active vines damage and slow")
	game._clear_zones()
	boss.prepare("frost_field")
	boss._resolve_action()
	var ice: BossZone = game.zones[0]
	ice.set_physics_process(false)
	game.player.position = ice.position
	game.player.slow_timer = 0
	ice._physics_process(1.0)
	verify(game.player.slow_timer > 0, "Frost field slows on activation")
	game._clear_zones()
	verify(game.player.slow_timer == 0, "Clearing zones removes slow effects")
	game.floor_number = 20
	game._generate_floor()
	var exit_index := 0
	for i in game.rooms.size():
		if game.rooms[i].exit: exit_index = i
	game._enter_room(exit_index, Vector2i.ZERO)
	var final_boss: DungeonEnemy = null
	for enemy in game.enemies:
		enemy.set_physics_process(false)
		if enemy.final_boss: final_boss = enemy
	verify(final_boss != null, "Floor 20 spawns the final boss")
	if final_boss != null:
		var skills: Dictionary = {}
		for i in 90: skills[BossModule.next_skill(final_boss)] = true
		verify(skills.size() >= 12, "Final boss rhythm covers at least twelve skills")
		final_boss.hp = final_boss.max_hp / 3
		final_boss.prepare("magma")
		final_boss._resolve_action()
		verify(final_boss.attack_cooldown < 2 and game.projectiles.size() == 9, "Final boss phase two has faster casts and denser projectiles")
	wipe_enemies()
	verify(game.mode == "victory" and game.zones.is_empty() and game.projectiles.is_empty(), "Final encounter clears into victory")
	game.descend()
	verify(game.floor_number == 20, "Victory cannot generate floor 21")
	# Walk every generated floor through real clear/reward/portal transitions.
	game.new_run()
	game.player.set_physics_process(false)
	var all_rewards := 0
	var expected_rewards := 0
	for floor_value in range(1, 21):
		verify(game.floor_number == floor_value, "Portal campaign advances in order")
		verify(game.floor_rewards == 0, "Each new floor restores exactly its ordinary quota")
		var ordinary_rooms := 0
		for data in game.rooms:
			if data.kind in ["combat", "boss"] and not (floor_value == 20 and data.exit): ordinary_rooms += 1
			if data.kind == "cursed": expected_rewards += 2
			if data.kind == "treasure": expected_rewards += 1
		expected_rewards += mini(ordinary_rooms, game.REWARDS_PER_FLOOR)
		var exit_room := 0
		for i in range(1, game.rooms.size()):
			if game.rooms[i].exit:
				exit_room = i
				continue
			game._enter_room(i, Vector2i.ZERO)
			for enemy in game.enemies: enemy.set_physics_process(false)
			var kind: String = game.rooms[i].kind
			if kind == "treasure":
				game.player.position = DungeonRoom.CENTER
				game.interact()
			elif kind == "shop": continue
			else: wipe_enemies()
			drain_rewards()
		game._enter_room(exit_room, Vector2i.ZERO)
		for enemy in game.enemies: enemy.set_physics_process(false)
		wipe_enemies()
		verify(game.floor_rewards <= game.REWARDS_PER_FLOOR, "Full exploration never exceeds ordinary floor quota")
		if floor_value < 20:
			drain_rewards()
			verify(game.room.show_exit, "Claiming exit reward opens portal")
			game.player.position = DungeonRoom.CENTER
			game.interact()
		else: verify(game.mode == "victory", "Complete 20-floor campaign reaches victory")
		all_rewards = game.collected.size()
		await process_frame
	verify(all_rewards == expected_rewards, "Twenty floors award exactly two ordinary choices plus finite special-room extras")
	var bank := SoundBank.new()
	var unique: Dictionary = {}
	for event in SoundBank.PRESETS:
		var sound := bank.stream_for(event)
		verify(sound.data.size() > 1000 and sound == bank.stream_for(event), "Audio events synthesize once and reuse streams")
		var peak := 0
		for i in range(0, sound.data.size(), 2): peak = maxi(peak, absi(sound.data.decode_s16(i)))
		verify(peak > 0 and peak < 32767, "Event audio is non-silent and does not clip")
		unique[hash(sound.data)] = true
	verify(unique.size() == SoundBank.PRESETS.size(), "Events have distinct synthesized sound data")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: bounded floor rewards, capped multiplicative damage, room types, shop economy, contracts, theme skills, 20-floor victory and event audio")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
