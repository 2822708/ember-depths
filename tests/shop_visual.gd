extends SceneTree
var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	game.hud_changed.emit()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview-economy-%s.png" % name)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	root.size = Vector2i(1280, 800)
	await process_frame
	game.new_run()
	game.player.set_physics_process(false)
	game.floor_number = 10
	game._generate_floor()
	var shop := 0
	for i in game.rooms.size():
		if game.rooms[i].kind == "shop": shop = i
	game._enter_room(shop, Vector2i.ZERO)
	game.transition = 0
	game.currency = 650
	game.player.position = DungeonRoom.CENTER
	game.interact()
	game.actives.buy(0, 0)
	game.actives.buy(1, 1)
	game.actives.buy(0, 0)
	game.shop_page = 1
	await capture("actives")
	game.shop_page = 2
	await capture("consumables")
	game.shop_page = 0
	await capture("passives")
	game.leave_shop()
	game.actives.cast(1)
	game.actives.cast(0)
	game.actives.update(0.5)
	game.player.queue_redraw()
	await capture("slots")
	print("PASS: shop pages and cooldown HUD rendered")
	game._clear_projectiles()
	game._clear_zones()
	game.queue_free()
	await process_frame
	quit(0)
