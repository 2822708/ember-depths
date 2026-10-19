extends SceneTree
## Render real game scenes for visual QA. Does not change the shipped gameplay.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	root.size = Vector2i(1280, 800)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-title.png")
	game.new_run()
	var neighbor: int = game.rooms[0].doors.values()[0]
	game._enter_room(neighbor, Vector2i.ZERO)
	game.transition = 0
	game.player.position = Vector2(448, 332)
	game.player.facing = Vector2(1, -0.3).normalized()
	game.player.swing_direction = game.player.facing
	game.player.swing = 0.12
	# Freeze actors for a stable screenshot of the actual generated room.
	game.player.set_physics_process(false)
	for enemy in game.enemies: enemy.set_physics_process(false)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-game.png")
	game._offer_reward()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-reward.png")
	game.floor_number = 6
	game.rng.seed = 612
	game._generate_floor()
	neighbor = game.rooms[0].doors.values()[0]
	for theme in ["moss", "lava", "frost"]:
		game.floor_theme = theme
		game.rooms[neighbor].theme = theme
		game.rooms[neighbor].variant = 9
		game.rooms[neighbor].seed = 612
		game.mode = "playing"
		game._enter_room(neighbor, Vector2i.ZERO)
		for enemy in game.enemies:
			game.world.remove_child(enemy)
			enemy.queue_free()
		game.enemies.clear()
		var positions: Array[Vector2] = [Vector2(320, 160), Vector2(560, 180), Vector2(210, 400), Vector2(680, 400), Vector2(500, 390)]
		for i in 5:
			var enemy: DungeonEnemy = game.spawn_enemy(i, positions[i])
			enemy.set_physics_process(false)
			if i == 1: enemy.prepare("charge")
			if i == 3: enemy.prepare("explode")
		game.player.position = DungeonRoom.CENTER + Vector2(0, 40)
		game.player.hp = 100
		game.player.invulnerability = 0
		game.transition = 0
		game.room.clock = 2.1
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview-theme-%s.png" % theme)
	game.mode = "playing"
	game._enter_room(neighbor, Vector2i.ZERO)
	for enemy in game.enemies:
		game.world.remove_child(enemy)
		enemy.queue_free()
	game.enemies.clear()
	var mechanic_positions: Array[Vector2] = [Vector2(330, 250), Vector2(560, 250), Vector2(445, 390)]
	for i in 3:
		var enemy: DungeonEnemy = game.spawn_enemy(5 + i, mechanic_positions[i])
		enemy.set_physics_process(false)
		if enemy.kind == 6:
			enemy.mechanic_clock = 1.05
			enemy._update_mechanics(0.01)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-mechanics.png")
	quit(0)
