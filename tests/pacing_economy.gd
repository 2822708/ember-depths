extends SceneTree
## Deterministic cap, skill and shop tests plus an actual generated 20-floor economy.
var game: Node2D
var failures: Array[String] = []

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func clear_arena() -> void:
	game._clear_projectiles()
	game._clear_zones()
	for enemy in game.enemies:
		enemy.cancel_mechanics()
		enemy.queue_free()
	game.enemies.clear()
	game.mode = "playing"
	game.rooms[game.room_index].kind = "combat"
	game.player.position = Vector2(448, 288)
	game.player.facing = Vector2.RIGHT
	game.player.hp = game.player.max_hp
	game.player.damage_multiplier = 1.0

func add_enemy(kind := 0, boss := false) -> DungeonEnemy:
	var enemy: DungeonEnemy = game.spawn_enemy(kind, Vector2(480, 288), false, boss)
	enemy.set_physics_process(false)
	enemy.position = Vector2(480, 288)
	return enemy

func open_shop() -> void:
	game.rooms[game.room_index].kind = "shop"
	game.reward_source = "shop"
	game.mode = "reward"

func wipe() -> void:
	var attempts := 0
	while not game.enemies.is_empty() and attempts < 4:
		for enemy in game.enemies.duplicate():
			enemy.set_physics_process(false)
			enemy.phase_active = false
			enemy.spawn_invulnerability = 0
			enemy.take_damage(99999999, Vector2.ZERO)
		attempts += 1
	verify(game.enemies.is_empty(), "Simulated combat clears every enemy and split child")

func settle() -> void:
	if game.mode == "clearing": game._offer_reward()
	while game.mode == "reward" and game.reward_source != "shop":
		game.choices[0] = game.UPGRADES[3]
		game.choose_reward(0)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.new_run()
	game.player.set_physics_process(false)
	await physics_frame
	var checks := 0
	for base in [0.001, 0.03, 0.12, 0.30, 0.46, 1.0]:
		for oath in [false, true]:
			for berserk in [0, 1]:
				for hp in [1, 30, 31, 100]:
					game.player.attack_cooldown = base
					game.player.oath = oath
					game.player.berserk = berserk
					game.player.hp = hp
					verify(game.player.effective_attack_cooldown() >= 0.30, "Final cooldown floor holds for every modifier combination")
					checks += 1
	game.player.attack_cooldown = 1.0
	game.player.oath = true
	game.player.berserk = 1
	game.player.hp = 1
	verify(game.player.effective_attack_cooldown() == 0.5, "Oath and Berserk use a single half multiplier")
	for floor_value in [1, 10, 20]:
		for stacks in range(9):
			for permanent in [0, 10000]:
				game.player.rebuild_damage(floor_value, stacks, permanent)
				for contract in [1.0, 1.4, 1.6, 2.24, 100.0]:
					game.player.damage_multiplier = contract
					verify(game.player.damage <= 90 and game.player.effective_damage() <= 140, "Damage remains capped across floors, stacks and contracts")
	print("CAPS: cooldown combinations=%d; damage cases=270" % checks)
	for floor_value in [1, 10, 20]:
		game.player.rebuild_damage(floor_value, 0)
		game.player.damage_multiplier = 1
		game.player.oath = false
		game.player.berserk = 0
		game.player.attack_cooldown = 0.46
		print("DPS natural floor=%d damage=%d aps=%.3f dps=%.2f" % [floor_value, game.player.effective_damage(), 1.0 / game.player.effective_attack_cooldown(), game.player.effective_damage() / game.player.effective_attack_cooldown()])
		game.player.rebuild_damage(floor_value, 8)
		game.player.damage_multiplier = 2.24
		game.player.attack_cooldown = game.MIN_ATTACK_COOLDOWN
		print("DPS max floor=%d damage=%d aps=%.3f dps=%.2f" % [floor_value, game.player.effective_damage(), 1.0 / game.player.effective_attack_cooldown(), game.player.effective_damage() / game.player.effective_attack_cooldown()])

	game.new_run()
	game.player.set_physics_process(false)
	clear_arena()
	var anchor := add_enemy()
	var boss := add_enemy(1, true)
	boss.max_hp = 1000
	boss.hp = 1000
	boss.take_damage(100, Vector2.ZERO)
	verify(boss.hp == 915, "Boss above 70 percent reduces damage by 15 percent")
	boss.hp = 700
	boss.take_damage(100, Vector2.ZERO)
	verify(boss.hp == 600, "Boss at 70 percent takes normal damage")
	boss.hp = 500
	boss.take_damage(100, Vector2.ZERO)
	verify(boss.hp == 410 and boss.boss_phase_two, "Half-health damage reduction is 10 percent and phase two activates")
	boss.prepare("poison")
	boss._resolve_action()
	verify(is_equal_approx(boss.attack_cooldown, 1.1) and game.zones.size() == 1, "Ordinary phase-two boss has persistent large AoE at 1.1s cooldown")
	var zone: BossZone = game.zones[0]
	boss.take_damage(10, Vector2(80, 0))
	verify(not zone.retired and game.zones.has(zone), "Boss AoE persists after damage")
	for floor_value in [5, 10, 15, 20]:
		var min_seconds := 10000.0
		var min_hp := 99999999
		var max_hp := 0
		var max_seconds := 0.0
		for kind in EnemyCatalog.pool(floor_value):
			clear_arena()
			game.floor_number = floor_value
			anchor = add_enemy()
			boss = add_enemy(kind, true)
			var start_hp := boss.max_hp
			min_hp = mini(min_hp, start_hp)
			max_hp = maxi(max_hp, start_hp)
			var hits := 0
			while not boss.dead and hits < 1000:
				boss.take_damage(140, Vector2.ZERO)
				hits += 1
			var seconds := (hits - 1) * 0.30
			min_seconds = minf(min_seconds, seconds)
			max_seconds = maxf(max_seconds, seconds)
			verify(seconds >= float(BossModule.MINIMUM_SURVIVAL_SECONDS[floor_value]), "Boss minimum ideal melee TTK holds at floor %d kind %d" % [floor_value, kind])
		print("BOSS floor=%d HP=%d-%d ideal_melee_ttk=%.1f-%.1fs" % [floor_value, min_hp, max_hp, min_seconds, max_seconds])

	game.new_run()
	game.player.set_physics_process(false)
	clear_arena()
	key(KEY_Q)
	key(KEY_R)
	verify(game.player_waves.is_empty() and game.actives.cooldowns == [0.0, 0.0], "Unpurchased Q/R do nothing")
	open_shop()
	game.currency = 49
	verify(not game.actives.buy(0, 0) and game.currency == 49, "Unaffordable skill does not spend")
	game.currency = 5000
	for index in 4:
		verify(game.actives.buy(index, index % 2), "Each skill can be purchased")
	verify(game.actives.levels.size() == 4, "All four unlocks are run-owned")
	var price_table: Array[int] = []
	for floor_value in [1, 5, 10, 15, 20]:
		game.floor_number = floor_value
		price_table.append(game.shop_price(50))
		print("PRICE floor=%d passive=%d shock=%d ring=%d stasis=%d heal=%d upgrade2=%d upgrade3=%d" % [floor_value, game.shop_price(18), game.shop_price(50), game.shop_price(60), game.shop_price(70), game.shop_price(80), game.shop_price(90), game.shop_price(140)])
	verify(price_table == [50, 50, 63, 75, 88], "Price uses floor((floor-1)/5) and rounds up")
	game.floor_number = 1
	open_shop()
	game.player.hp = game.player.max_hp
	var before_consumable: int = game.currency
	verify(not game.actives.buy_consumable(0) and game.currency == before_consumable, "Full health potion cannot waste currency")
	game.player.hp = 10
	verify(game.actives.buy_consumable(0) and game.player.hp == 40, "Potion heals 30 percent")
	verify(game.actives.buy_consumable(1) and game.actives.tonic_ready, "Tonic is held for the next battle")
	verify(not game.actives.buy_consumable(1), "Tonic cannot stack in storage")
	verify(game.actives.buy_consumable(2) and game.player.ward_available, "Ward consumable arms one hit protection")
	game.rooms[game.room_index].kind = "combat"
	game.mode = "playing"
	anchor = add_enemy()
	game.actives.update(0.1)
	verify(game.actives.tonic_timer > 29 and not game.actives.tonic_ready, "Tonic activates in combat")
	game.actives.reset_transients()
	verify(game.actives.tonic_timer == 0, "Tonic ends on transient reset")
	for index in 4:
		open_shop()
		var item: Dictionary = ActiveSkills.TYPES[index]
		game.actives.equip(item.id, 0)
		clear_arena()
		anchor = add_enemy()
		anchor.max_hp = 10000
		anchor.hp = 10000
		anchor.position = game.player.position + Vector2(50, 0)
		game.player.damage = 25
		game.player.hp = 20
		key(KEY_Q)
		verify(game.actives.cooldowns[0] == float(item.cooldown), "Q casts purchased " + item.id)
		verify(not game.actives.cast(0), "Cooldown rejects repeated cast")
		if index == 0:
			var wave: PlayerWave = game.player_waves[0]
			wave.set_physics_process(false)
			wave._physics_process(0.075)
			verify(anchor.hp == 10000 - 75 and wave.pulses == 3, "Penetrating attack deals three capped packets")
		elif index == 1: verify(anchor.hp == 9975 and anchor.knock.length() > 200, "Ring damages and knocks back")
		elif index == 2: verify(anchor.active_slow_timer == 2 and anchor._active_speed() == 0.5, "Stasis halves enemy movement for two seconds")
		else: verify(game.player.hp == 50, "Rekindle heals 30 percent")
		game.actives.update(float(item.cooldown))
		verify(game.actives.cooldowns[0] == 0, "Cooldown expires while playing")
		open_shop()
		var cash: int = game.currency
		verify(game.actives.buy(index, 0) and game.actives.levels[item.id] == 2 and cash - game.currency == 90, "Level 2 costs 90")
		clear_arena()
		anchor = add_enemy()
		anchor.max_hp = 10000
		anchor.hp = 10000
		game.player.damage = 25
		game.player.hp = 20
		game.actives.cooldowns[0] = 0
		verify(game.actives.cast(0), "Upgraded skill casts")
		if index == 0: verify(game.player_waves[-1].damage == 33, "Level 2 wave damage improves about 30 percent")
		elif index == 1: verify(anchor.hp == 9967, "Level 2 ring damage improves about 30 percent")
		elif index == 2: verify(is_equal_approx(anchor.active_slow_timer, 2.6), "Level 2 stasis lasts 30 percent longer")
		else: verify(game.player.hp == 59, "Level 2 heal improves 30 percent")
		open_shop()
		cash = game.currency
		verify(game.actives.buy(index, 0) and cash - game.currency == 140 and game.actives.levels[item.id] == 3, "Level 3 costs 140")
		cash = game.currency
		verify(not game.actives.buy(index, 0) and cash == game.currency, "Maxed skill does not consume money")
	# R is a live skill key; Enter remains the sole restart key.
	open_shop()
	game.actives.equip("rekindle", 1)
	game.mode = "playing"
	game.player.hp = 10
	key(KEY_R)
	verify(game.player.hp > 10 and game.actives.cooldowns[1] == 20, "R casts slot two")
	game._enter_room(0, Vector2i.ZERO)
	verify(game.actives.cooldowns == [0.0, 0.0] and game.actives.tonic_timer == 0 and game.actives.levels.size() == 4, "Room reset clears active effects and cooldown, retains unlocks")
	game.actives.cooldowns[0] = 5
	game.actives.tonic_timer = 10
	game.die()
	verify(game.actives.cooldowns == [0.0, 0.0] and game.actives.tonic_timer == 0, "Death clears skill state")
	key(KEY_R)
	verify(game.mode == "dead", "R does not restart")
	key(KEY_ENTER)
	verify(game.mode == "playing" and game.actives.levels.is_empty(), "Enter starts fresh run and clears unlocks")
	game.actives.cooldowns[0] = 5
	game.mode = "victory"
	verify(game.actives.cooldowns == [0.0, 0.0], "Victory clears active state")

	# Generated floors, real spawn/kill income, side rooms and split minions.
	# Spending strategy: save for all four skills and their upgrades first;
	# then use potion/tonic/ward after fights, revisiting the existing shop.
	game.new_run()
	game.player.set_physics_process(false)
	game.rng.seed = 20261019
	var balances: Array[int] = []
	var total_income := 0
	var total_spent := 0
	for floor_value in range(1, 21):
		game.floor_number = floor_value
		game._generate_floor()
		var shop := -1
		for i in game.rooms.size():
			if game.rooms[i].kind == "shop": shop = i
		var income := 0
		var spent := 0
		var combat_order: Array[int] = []
		var exit_index := -1
		for i in range(1, game.rooms.size()):
			if game.rooms[i].exit: exit_index = i
			else: combat_order.append(i)
		if exit_index >= 0: combat_order.append(exit_index)
		for i in combat_order:
			if game.rooms[i].kind not in ["combat", "cursed", "boss"]: continue
			game.mode = "playing"
			game._enter_room(i, Vector2i.ZERO)
			var wallet: int = game.currency
			wipe()
			income += game.currency - wallet
			settle()
			if game.mode == "victory": continue
			# Explicit damage/buff consumption assumption, not a player AI.
			game.player.hp = maxi(1, game.player.hp - roundi(game.player.max_hp * 0.30))
			game.player.ward_available = false
			game.actives.tonic_ready = false
			if shop < 0: continue
			game.mode = "playing"
			game._enter_room(shop, Vector2i.ZERO)
			game.player.position = DungeonRoom.CENTER
			game.interact()
			wallet = game.currency
			for level in range(1, 4):
				for index in 4:
					if int(game.actives.levels.get(ActiveSkills.TYPES[index].id, 0)) < level:
						game.actives.buy(index, index % 2)
			var fully_upgraded := true
			for item in ActiveSkills.TYPES:
				if int(game.actives.levels.get(item.id, 0)) < 3: fully_upgraded = false
			if fully_upgraded:
				game.actives.buy_consumable(0)
				game.actives.buy_consumable(1)
				game.actives.buy_consumable(2)
			spent += wallet - game.currency
			game.leave_shop()
		balances.append(game.currency)
		total_income += income
		total_spent += spent
		print("ECONOMY floor=%02d income=%d spent=%d balance=%d" % [floor_value, income, spent, game.currency])
	verify(game.currency < 250 and total_spent > total_income * 0.85, "Active spending strategy consumes most currency over 20 floors")
	verify(game.actives.levels.size() == 4 and game.actives.levels.values().all(func(level: int) -> bool: return level == 3), "Economy permits all four skills to reach level three")
	print("ECONOMY total_income=%d spent=%d final=%d balances=%s" % [total_income, total_spent, game.currency, balances])
	print("ECONOMY final_skill_levels=%s; no-spending comparison=%d" % [game.actives.levels, total_income])
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: combat caps, boss reductions/survival, active purchases/casts/upgrades, keys/resets, scaled shop and 20-floor economy")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
