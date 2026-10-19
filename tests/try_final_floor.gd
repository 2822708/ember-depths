extends SceneTree
## TEMPORARY debug harness: jump straight into the floor-20 final boss with a
## fully-built character, so difficulty can be felt without a 20-floor run.
## This file is standalone and modifies no gameplay code. Delete it when done.

const TARGET_FLOOR := 20

func _initialize() -> void:
	call_deferred("run")

func settle(n: int = 4) -> void:
	for i in n: await process_frame

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	root.size = Vector2i(1280, 800)
	await settle()
	game.new_run()
	await settle()

	# --- Build the character the way a thorough 20-floor player would look. ---
	# Base damage is capped at 90 by MAX_BASE_DAMAGE; stack damage to the cap.
	for i in game.MAX_DAMAGE_STACKS:
		game.damage_stacks += 1
		game.player.damage = mini(DungeonPlayer.MAX_BASE_DAMAGE, roundi(game.player.damage * 1.15))
	# Haste: a realistic number of picks without reaching the floor.
	for i in 8:
		game.player.attack_cooldown = maxf(game.MIN_ATTACK_COOLDOWN, game.player.attack_cooldown * 0.93)
	# Vitals and utility blessings a real run would have.
	game.player.max_hp = 220
	game.player.hp = 220
	game.player.speed = 244
	game.player.attack_range = 140
	game.player.knockback = 235
	game.player.sword_wave = 1
	game.player.lifesteal = 0.01
	game.player.ward = 1
	game.player.ward_available = true
	# Both damage contracts (the strongest glass-cannon path).
	game.player.damage_multiplier = 1.4 * 1.6
	game.player.blood = true

	# --- Jump to the final floor. ---
	game.floor_number = TARGET_FLOOR
	game._generate_floor()
	await settle()

	# Find the exit room (the final boss lives there).
	var boss_index := 0
	for i in game.rooms.size():
		if game.rooms[i].exit: boss_index = i
	game._enter_room(boss_index, Vector2i.ZERO)
	await settle()

	var boss = null
	for e in game.enemies:
		if e.final_boss: boss = e
	if boss == null:
		for e in game.enemies:
			if e.is_boss: boss = e

	print("===== FLOOR %d FINAL ENCOUNTER =====" % TARGET_FLOOR)
	print("player: base_damage=%d  multiplier=%.2f  effective_hit=%d  (cap %d)" % [
		game.player.damage, game.player.damage_multiplier, game.player.effective_damage(), DungeonPlayer.MAX_HIT_DAMAGE])
	print("player: attack_cd=%.3f (%.2f atk/s)  hp=%d  speed=%d  range=%d" % [
		game.player.attack_cooldown, 1.0 / game.player.attack_cooldown, game.player.max_hp, int(game.player.speed), int(game.player.attack_range)])
	if boss != null:
		var hits: int = ceili(float(boss.max_hp) / game.player.effective_damage())
		var seconds: float = float(hits) * game.player.attack_cooldown
		print("FINAL BOSS: %s  hp=%d  damage=%d  -> %d hits, %.1f s of pure attacking" % [
			BossModule.title(boss), boss.max_hp, boss.damage, hits, seconds])
	print("enemies in room: ", game.enemies.size())
	print("=====================================")
	print("Controls are live in this window. Play it; close the window when done.")

	# Let the real game run so it can be played.
	game.mode = "playing"
	# The root MainLoop stays alive until the window is closed by the player,
	# so this file must never call quit().
	while true:
		await process_frame
