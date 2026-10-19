extends SceneTree
## Uses the real Compatibility renderer. Run WITHOUT --headless.
var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func clear_actors() -> void:
	game._clear_projectiles()
	game._clear_zones()
	for enemy in game.enemies:
		enemy.cancel_mechanics()
		enemy.queue_free()
	game.enemies.clear()
	game.effects.particles.clear()
	game.effects.numbers.clear()
	game.mode = "playing"
	game.transition = 0
	game.player.invulnerability = 100
	game.player.position = Vector2(448, 330)

func add_enemy(kind: int, at: Vector2, boss := false) -> DungeonEnemy:
	var enemy: DungeonEnemy = game.spawn_enemy(kind, at, false, boss)
	enemy.set_physics_process(false)
	enemy.position = at
	return enemy

func capture(name: String) -> void:
	game.hud_changed.emit()
	for enemy in game.enemies: enemy.queue_redraw()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-skills-%s.png" % name)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	root.size = Vector2i(1280, 800)
	await process_frame
	game.new_run()
	game.player.set_physics_process(false)
	clear_actors()
	var warden := add_enemy(7, Vector2(448, 230))
	for i in 6:
		var ally := add_enemy(i, Vector2(200 + (i % 3) * 245, 160 + (i / 3) * 230))
		ally.hp = maxi(1, ally.max_hp - 25)
	warden._update_mechanics(6.9)
	await capture("heal-windup")
	warden._update_mechanics(0.31)
	await capture("heal-channel")
	for theme in ["moss", "lava", "frost"]:
		clear_actors()
		game.floor_number = 10
		var boss := add_enemy(1, Vector2(448, 220), true)
		boss.boss_theme = theme
		var action: String = {"moss": "spikes", "lava": "meteors", "frost": "ice_storm"}[theme]
		boss.prepare(action)
		await capture(theme + "-warning")
	clear_actors()
	game.floor_number = 20
	game.player.rebuild_damage(20, 8)
	var final_boss := add_enemy(1, Vector2(448, 230), true)
	final_boss.hp = final_boss.max_hp / 3
	BossModule.update_phase(final_boss)
	final_boss.prepare("cataclysm")
	final_boss._resolve_action()
	for zone in game.zones: zone.set_physics_process(false)
	await capture("final-refuge")
	# Fixed stress snapshot at simultaneous hazard caps. Physics stays active.
	clear_actors()
	for i in 18:
		var enemy := add_enemy(i % 8, Vector2(180 + (i % 6) * 100, 150 + (i / 6) * 110))
		enemy.set_physics_process(true)
	for i in 160:
		var shot: EnemyProjectile = game.spawn_projectile(Vector2(448, 230), Vector2.from_angle(i * TAU / 160), 1)
		shot.velocity *= 0.1
	for i in 36:
		game.spawn_zone(Vector2(200 + (i % 6) * 100, 140 + (i / 6) * 60), "fire", 1, {"warning": 1.0, "duration": 5.0, "radius": 40.0})
	var frame_ms: Array[float] = []
	var cpu_max := 0.0
	var tick := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		if i >= 10:
			frame_ms.append((now - tick) / 1000.0)
			cpu_max = maxf(cpu_max, (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		tick = now
	frame_ms.sort()
	print("RENDER_STRESS: 18 enemies / 160 shots / 36 zones initially; frame_p50=%.2fms frame_p95=%.2fms cpu_max=%.2fms" % [frame_ms[frame_ms.size() / 2], frame_ms[int(frame_ms.size() * 0.95)], cpu_max])
	game._enter_room(0, Vector2i.ZERO)
	for i in 3: await process_frame
	print("RENDER_CLEANUP: shots=%d player_waves=%d zones=%d" % [game.projectiles.size(), game.player_waves.size(), game.zones.size()])
	quit(0)
