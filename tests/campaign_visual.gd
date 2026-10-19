extends SceneTree
## Actual renderer screenshots of new gameplay/UI paths.
var game: Node2D

func _initialize() -> void:
	call_deferred("capture")

func save_preview(filename: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + filename)

func capture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	root.size = Vector2i(1280, 800)
	await process_frame
	game.new_run()
	game.set_process(false)
	game.player.set_physics_process(false)
	game.muted = true
	game.floor_number = 10
	game.rng.seed = 2026
	game._generate_floor()
	var exit_index := 0
	for i in game.rooms.size():
		if game.rooms[i].exit: exit_index = i
	for theme in ["moss", "lava", "frost"]:
		game.floor_theme = theme
		game.rooms[exit_index].theme = theme
		game.rooms[exit_index].variant = 0
		game._enter_room(exit_index, Vector2i.ZERO)
		game.player.position = Vector2(540, 350)
		game.transition = 0
		for enemy in game.enemies:
			enemy.set_physics_process(false)
			if enemy.is_boss:
				enemy.position = Vector2(430, 240)
				enemy.prepare(BossModule.LOADOUTS[theme][0])
		await save_preview("preview-boss-%s.png" % theme)
	game.rooms[1].kind = "shop"
	game.rooms[1].variant = 0
	game.rooms[1].exit = false
	game.rooms[1].cleared = false
	game.rooms[1].rewarded = false
	game._enter_room(1, Vector2i.ZERO)
	game.player.position = DungeonRoom.CENTER
	game.transition = 0
	game.currency = 24
	game.interact()
	game.choices.clear()
	for id in ["glass", "oath", "blood"]:
		for upgrade in game.UPGRADES:
			if upgrade.id == id: game.choices.append(upgrade)
	game.hud_changed.emit()
	await save_preview("preview-shop.png")
	game.collected.assign(game.UPGRADES)
	game.leave_shop()
	game.hud_changed.emit()
	await save_preview("preview-blessings.png")
	game.floor_number = 20
	game.mode = "victory"
	game.kills = 280
	game.elapsed = 1680
	await save_preview("preview-victory.png")
	quit(0)
