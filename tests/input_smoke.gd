extends SceneTree
## Exercise Godot's input dispatch, rather than calling movement/reward methods directly.

var failures: Array[String] = []

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	key(KEY_ENTER, true)
	await process_frame
	key(KEY_ENTER, false)
	verify(game.mode == "playing", "Enter starts a run through input dispatch")
	var initial: Vector2 = game.player.position
	key(KEY_D, true)
	for i in 12: await physics_frame
	key(KEY_D, false)
	verify(game.player.position.x > initial.x + 15, "D input moves the player right")
	key(KEY_ESCAPE, true)
	await process_frame
	key(KEY_ESCAPE, false)
	verify(game.mode == "paused", "Escape pauses the game")
	var paused_position: Vector2 = game.player.position
	key(KEY_W, true)
	for i in 8: await physics_frame
	key(KEY_W, false)
	verify(game.player.position.distance_to(paused_position) < 0.01, "Movement is frozen while paused")
	key(KEY_ESCAPE, true)
	await process_frame
	key(KEY_ESCAPE, false)
	verify(game.mode == "playing", "Escape resumes the game")
	game.player.attack_timer = 0
	var attack := InputEventMouseButton.new()
	attack.button_index = MOUSE_BUTTON_LEFT
	attack.pressed = true
	Input.parse_input_event(attack)
	Input.flush_buffered_events()
	for i in 3: await physics_frame
	attack = InputEventMouseButton.new()
	attack.button_index = MOUSE_BUTTON_LEFT
	attack.pressed = false
	Input.parse_input_event(attack)
	Input.flush_buffered_events()
	verify(game.player.attack_timer > 0, "Left mouse input triggers an attack")
	key(KEY_SPACE, true)
	for i in 2: await physics_frame
	key(KEY_SPACE, false)
	verify(game.player.dash_cooldown > 0, "Space input starts a dodge")
	# A second dash must use current movement, not the previous stationary aim.
	game.player.dash_timer = 0
	game.player.dash_cooldown = 0
	key(KEY_W, true)
	key(KEY_SPACE, true)
	for i in 2: await physics_frame
	key(KEY_SPACE, false)
	key(KEY_W, false)
	verify(game.player.dash_direction.dot(Vector2.UP) > 0.99, "Moving dash after a stationary dash uses the new movement direction")
	game._offer_reward()
	var chosen_id: String = game.choices[1].id
	key(KEY_2, true)
	await process_frame
	key(KEY_2, false)
	verify(game.mode == "playing" and game.collected.size() == 1 and game.collected[0].id == chosen_id, "Number 2 selects the second upgrade")
	game.die()
	key(KEY_R, true)
	await process_frame
	key(KEY_R, false)
	verify(game.mode == "dead", "R no longer restarts after death")
	key(KEY_ENTER, true)
	await process_frame
	key(KEY_ENTER, false)
	verify(game.mode == "playing" and game.player.hp == 100 and game.collected.is_empty(), "Enter restarts after death")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: Enter, WASD, pause/resume, mouse attack, dodge, upgrade hotkey and restart input")
		quit(0)
	else:
		print("FAIL: ", failures)
		quit(1)
