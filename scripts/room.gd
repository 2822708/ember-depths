class_name DungeonRoom
extends Node2D
signal presentation_changed
## Tile decoration and collision share the same blocked-cell dictionary.
## Native grid paths steer enemies around static pillars and dangerous tiles.

const TILE := 32
const WIDTH := 28
const HEIGHT := 18
const CENTER := Vector2(448, 288)
const DOOR_POINTS := {
	Vector2i.UP: Vector2(448, 26), Vector2i.RIGHT: Vector2(870, 288),
	Vector2i.DOWN: Vector2(448, 550), Vector2i.LEFT: Vector2(26, 288)
}

var data: Dictionary
var blocked: Dictionary = {}
var tiles: Array[Dictionary] = []
var torches: Array[Vector2] = []
var clock := 0.0
var locked := false
var show_exit := false:
	set(value):
		if show_exit == value: return
		show_exit = value
		if is_instance_valid(dynamic_layer): dynamic_layer.queue_redraw()
		presentation_changed.emit()
var collision_root: Node2D
var door_collision_root: Node2D
var rng := RandomNumberGenerator.new()
var hazards: Dictionary = {}
var pits: Dictionary = {}
var theme: Dictionary = RoomCatalog.THEMES.moss
var layout: Dictionary
var active := true
var static_viewport: SubViewport
var static_layer: RoomLayer
var dynamic_layer: RoomLayer
var painter: Node2D
var static_builds := 0
var cached_sprite: Sprite2D
var torch_glows: Array[Sprite2D] = []
var navigation_grid: AStarGrid2D

class GlowLayer extends Node2D:
	func _draw() -> void:
		for i in range(9, 0, -1):
			draw_circle(Vector2(90, 90), i * 9, Color(1, 1, 1, 0.007 + (9 - i) * 0.001))

class RoomLayer extends Node2D:
	var room: DungeonRoom
	var static_content := false

	func _draw() -> void:
		room.painter = self
		if static_content:
			room._draw_static()
		else:
			room._draw_dynamic()

func _ensure_render_layers() -> void:
	if is_instance_valid(static_viewport): return
	static_viewport = SubViewport.new()
	static_viewport.size = Vector2i(902, 588)
	static_viewport.transparent_bg = true
	static_viewport.world_2d = World2D.new()
	static_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(static_viewport)
	static_layer = RoomLayer.new()
	static_layer.room = self
	static_layer.static_content = true
	static_layer.position = Vector2(3, 3)
	static_viewport.add_child(static_layer)
	cached_sprite = Sprite2D.new()
	cached_sprite.texture = static_viewport.get_texture()
	cached_sprite.centered = false
	cached_sprite.position = Vector2(-3, -3)
	cached_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(cached_sprite)
	# Bake the nine translucent light circles once, then pulse four textured quads.
	var glow_viewport := SubViewport.new()
	glow_viewport.size = Vector2i(180, 180)
	glow_viewport.transparent_bg = true
	glow_viewport.world_2d = World2D.new()
	glow_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(glow_viewport)
	glow_viewport.add_child(GlowLayer.new())
	for p in torches:
		var glow := Sprite2D.new()
		glow.texture = glow_viewport.get_texture()
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		glow.position = p
		glow.modulate = theme.light
		add_child(glow)
		torch_glows.append(glow)
	dynamic_layer = RoomLayer.new()
	dynamic_layer.room = self
	add_child(dynamic_layer)

func _invalidate_static() -> void:
	_ensure_render_layers()
	static_builds += 1
	static_layer.queue_redraw()
	static_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func configure(room_data: Dictionary) -> void:
	navigation_grid = null
	data = room_data
	blocked.clear()
	tiles.clear()
	hazards.clear()
	pits.clear()
	layout = RoomCatalog.LAYOUTS[int(data.variant)]
	theme = RoomCatalog.THEMES[data.get("theme", "moss")]
	rng.seed = data.seed
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			var edge := x == 0 or x == WIDTH - 1 or y == 0 or y == HEIGHT - 1
			var opening := false
			if y == 0 and x in [13, 14] and data.doors.has(Vector2i.UP): opening = true
			if y == HEIGHT - 1 and x in [13, 14] and data.doors.has(Vector2i.DOWN): opening = true
			if x == 0 and y in [8, 9] and data.doors.has(Vector2i.LEFT): opening = true
			if x == WIDTH - 1 and y in [8, 9] and data.doors.has(Vector2i.RIGHT): opening = true
			if edge and not opening:
				blocked[cell] = true
			tiles.append({"cell": cell, "tone": rng.randf_range(-0.015, 0.02),
				"moss": rng.randf() < 0.10, "crack": rng.randf() < 0.12, "offset": rng.randi_range(3, 22)})
	for p in layout.pillars:
		for dx in 2:
			for dy in 2:
				blocked[p + Vector2i(dx, dy)] = true
	for rect in layout.walls:
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				blocked[Vector2i(x, y)] = true
	for hazard in layout.hazards:
		var rect: Rect2i = hazard.rect
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var cell := Vector2i(x, y)
				if blocked.has(cell): continue
				hazards[cell] = hazard.kind
				if hazard.kind == "pit":
					blocked[cell] = true
					pits[cell] = true
	torches = [Vector2(176, 35), Vector2(720, 35), Vector2(32, 176), Vector2(864, 400)]
	_build_tile_collision()
	_invalidate_static()

func set_locked(value: bool) -> void:
	if locked == value: return
	locked = value
	_rebuild_door_collision()
	_invalidate_static()
	presentation_changed.emit()

func _build_tile_collision() -> void:
	if is_instance_valid(collision_root):
		remove_child(collision_root)
		collision_root.queue_free()
	collision_root = Node2D.new()
	add_child(collision_root)
	for cell in blocked:
		_collider(Vector2(cell) * TILE + Vector2.ONE * 16, Vector2.ONE * 32, 8 if pits.has(cell) else 1)
	_rebuild_door_collision()

func _rebuild_door_collision() -> void:
	if is_instance_valid(door_collision_root):
		door_collision_root.queue_free()
	door_collision_root = null
	door_collision_root = Node2D.new()
	add_child(door_collision_root)
	if locked:
		for direction in data.doors:
			var point: Vector2 = DOOR_POINTS[direction]
			_collider(point, Vector2(64, 36) if direction.x == 0 else Vector2(36, 64), 1, door_collision_root)

func _collider(at: Vector2, size: Vector2, layer: int = 1, parent: Node2D = null) -> void:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = layer
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	(parent if parent != null else collision_root).add_child(body)

func spawn_point(avoid: Vector2) -> Vector2:
	for attempt in 200:
		var cell := Vector2i(rng.randi_range(3, 24), rng.randi_range(3, 14))
		var p := Vector2(cell) * TILE + Vector2.ONE * 16
		if is_safe_cell(cell) and p.distance_to(avoid) > 160:
			return p
	return nearest_safe_position(Vector2(320, 160))

func is_safe_cell(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.x <= 26 and cell.y >= 1 and cell.y <= 16 and not blocked.has(cell) and not hazards.has(cell)

func nearest_safe_position(at: Vector2) -> Vector2:
	var best := CENTER
	var distance := INF
	for y in range(2, 16):
		for x in range(2, 26):
			var cell := Vector2i(x, y)
			if not is_safe_cell(cell): continue
			var p := Vector2(cell) * TILE + Vector2.ONE * 16
			if p.distance_squared_to(at) < distance:
				distance = p.distance_squared_to(at)
				best = p
	return best

func spike_phase(cell: Vector2i) -> float:
	return fmod(clock + (cell.x + cell.y) % 3 * 0.12, 3.0)

func apply_hazard(actor: DungeonPlayer) -> void:
	if not active or actor.dash_timer > 0 or actor.hazardproof > 0: return
	var cell := Vector2i(floor(actor.position.x / TILE), floor(actor.position.y / TILE))
	var kind: String = hazards.get(cell, "")
	if kind == "lava": actor.take_damage(14)
	elif kind == "spikes" and spike_phase(cell) >= 1.7: actor.take_damage(18)

func next_direction(from: Vector2, to: Vector2) -> Vector2:
	var start := Vector2i(floor(from.x / TILE), floor(from.y / TILE))
	var goal := Vector2i(floor(to.x / TILE), floor(to.y / TILE))
	if not is_safe_cell(start):
		return (nearest_safe_position(from) - from).normalized()
	if not is_safe_cell(goal):
		var safe := nearest_safe_position(to)
		goal = Vector2i(floor(safe.x / TILE), floor(safe.y / TILE))
	if start == goal:
		return (to - from).normalized()
	# Native grid search avoids repeated interpreted full-room BFS under swarms.
	if navigation_grid == null:
		navigation_grid = AStarGrid2D.new()
		navigation_grid.region = Rect2i(1, 1, 26, 16)
		navigation_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		navigation_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		navigation_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		navigation_grid.update()
		for y in range(1, 17):
			for x in range(1, 27):
				navigation_grid.set_point_solid(Vector2i(x, y), not is_safe_cell(Vector2i(x, y)))
	var path := navigation_grid.get_id_path(start, goal)
	if path.size() < 2: return Vector2.ZERO
	var step: Vector2i = path[1]
	return (Vector2(step) * TILE + Vector2.ONE * 16 - from).normalized()

func _process(delta: float) -> void:
	if active:
		clock += delta
		for glow in torch_glows:
			glow.scale = Vector2.ONE * (1 + sin(clock * 6 + glow.position.x) * 0.07)
			glow.modulate = theme.light
		if is_instance_valid(dynamic_layer): dynamic_layer.queue_redraw()

func _draw_static() -> void:
	painter.draw_rect(Rect2(-3, -3, 902, 582), Color("253a40"))
	painter.draw_rect(Rect2(0, 0, 896, 576), Color("101d25"))
	for tile in tiles:
		var cell: Vector2i = tile.cell
		var p := Vector2(cell) * TILE
		var tone: float = tile.tone
		if hazards.has(cell):
			_draw_hazard(p, cell, hazards[cell])
		elif blocked.has(cell):
			_draw_wall(p, tone, cell)
		else:
			var base: Color = theme.floor
			var color := Color(base.r + tone, base.g + tone, base.b + tone)
			painter.draw_rect(Rect2(p + Vector2.ONE, Vector2(30, 30)), color)
			painter.draw_line(p + Vector2(2, 1), p + Vector2(30, 1), Color(0.20, 0.29, 0.30, 0.20))
			if tile.crack:
				painter.draw_line(p + Vector2(tile.offset, 6), p + Vector2(tile.offset - 3, 14), Color("101e26"), 1)
				painter.draw_line(p + Vector2(tile.offset - 3, 14), p + Vector2(tile.offset + 3, 19), Color("101e26"), 1)
			if tile.moss:
				painter.draw_rect(Rect2(p + Vector2(tile.offset, 23), Vector2(5, 3)), Color(theme.detail, 0.45))
				painter.draw_rect(Rect2(p + Vector2(tile.offset + 4, 20), Vector2(3, 2)), Color(theme.detail, 0.6))
	# An inlaid geometric crest gives the room a visual center.
	for radius in [62, 76]:
		painter.draw_arc(CENTER, radius, 0, TAU, 48, Color(theme.crest, 0.7), 1)
	var diamond := PackedVector2Array([CENTER + Vector2(0, -48), CENTER + Vector2(48, 0), CENTER + Vector2(0, 48), CENTER + Vector2(-48, 0), CENTER + Vector2(0, -48)])
	painter.draw_polyline(diamond, theme.crest, 2)
	for direction in data.doors:
		_draw_door(direction)
	_draw_room_feature()
	# Edge shading, kept transparent so enemies remain readable.
	for i in range(9):
		var inset := float(i * 7)
		var alpha := 0.012 * (9 - i)
		painter.draw_rect(Rect2(inset, inset, 896 - inset * 2, 576 - inset * 2), Color(0, 0, 0, alpha), false, 7)

func _draw_dynamic() -> void:
	for p in torches:
		_draw_torch(p)
	if show_exit:
		_draw_portal()
	for cell in hazards:
		_draw_hazard_dynamic(Vector2(cell) * TILE, cell, hazards[cell])
	# Slowly drifting embers.
	for i in 18:
		var x := fmod(i * 137.7 + sin(clock * 0.23 + i) * 18, 820) + 38
		var fall: bool = data.get("theme", "moss") == "frost"
		var y := fmod(clock * (8 + i % 5) + i * 37, 490) + 36 if fall else 540 - fmod(clock * (8 + i % 5) + i * 37, 490)
		painter.draw_rect(Rect2(x, y, 3 if fall else 2, 2), Color(theme.dust, 0.2 + 0.15 * sin(clock + i)))

func _draw_room_feature() -> void:
	var kind: String = data.get("kind", "combat")
	if kind == "treasure":
		painter.draw_rect(Rect2(CENTER - Vector2(26, 17), Vector2(52, 34)), Color("61472f"))
		painter.draw_rect(Rect2(CENTER - Vector2(26, 17), Vector2(52, 12)), Color("b68c54"))
		painter.draw_rect(Rect2(CENTER - Vector2(4, 7), Vector2(8, 16)), Color("efd18d"))
	elif kind == "shop":
		painter.draw_rect(Rect2(CENTER - Vector2(33, 18), Vector2(66, 36)), Color("42575d"))
		painter.draw_rect(Rect2(CENTER - Vector2(36, 22), Vector2(72, 8)), Color("d1ab70"))
		for i in 3:
			painter.draw_circle(CENTER + Vector2(-20 + i * 20, -28), 6, Color("8ec8b7"))
	elif kind == "cursed":
		painter.draw_arc(CENTER, 51, 0, TAU, 32, Color("c18bb8"), 3)
		for i in 5:
			var at := CENTER + Vector2.from_angle(i * TAU / 5) * 51
			painter.draw_line(at, CENTER + Vector2.from_angle((i + 2) * TAU / 5) * 51, Color("9b668f"), 2)

func _draw_wall(p: Vector2, tone: float, cell: Vector2i) -> void:
	painter.draw_rect(Rect2(p + Vector2(0, 8), Vector2(32, 30)), Color(0.015, 0.027, 0.04, 0.6))
	painter.draw_rect(Rect2(p, Vector2(32, 32)), Color("17252d"))
	var wall: Color = theme.wall
	painter.draw_rect(Rect2(p + Vector2(1, 1), Vector2(30, 12)), wall.lightened(tone))
	painter.draw_line(p + Vector2(2, 1), p + Vector2(29, 1), wall.lightened(0.18), 2)
	painter.draw_rect(Rect2(p + Vector2(1, 15), Vector2(14, 15)), wall.darkened(0.28))
	painter.draw_rect(Rect2(p + Vector2(17, 15), Vector2(14, 15)), wall.darkened(0.20))
	if (cell.x * 7 + cell.y * 3) % 9 == 0:
		painter.draw_rect(Rect2(p + Vector2(2, 2), Vector2(7, 3)), theme.detail)

func _draw_door(direction: Vector2i) -> void:
	var p: Vector2 = DOOR_POINTS[direction]
	var horizontal := direction.x == 0
	var size := Vector2(62, 30) if horizontal else Vector2(30, 62)
	painter.draw_rect(Rect2(p - size / 2, size), Color("0a151e"))
	var color := Color("d77e68") if locked else Color("8fc6ad")
	for i in range(4, 0, -1):
		painter.draw_circle(p, 12 + i * 9, Color(color, 0.015))
	if locked:
		for i in 5:
			var offset := float(i * 12 - 24)
			var a := p + Vector2(offset, -16) if horizontal else p + Vector2(-16, offset)
			var b := a + Vector2(0, 32) if horizontal else a + Vector2(32, 0)
			painter.draw_line(a, b, Color("846a5a"), 3)
	else:
		var tip := p + Vector2(direction) * 7
		var base := p - Vector2(direction) * 5
		var side := Vector2(direction).orthogonal() * 6
		painter.draw_polyline(PackedVector2Array([base + side, tip, base - side]), color, 2)

func _draw_torch(p: Vector2) -> void:
	painter.draw_rect(Rect2(p + Vector2(-5, -1), Vector2(10, 15)), Color("1b232b"))
	painter.draw_rect(Rect2(p + Vector2(-3, -1), Vector2(6, 9)), Color("9a6843"))
	painter.draw_rect(Rect2(p + Vector2(-4, -11), Vector2(8, 11)), theme.light)
	painter.draw_rect(Rect2(p + Vector2(-2, -14 - floor(sin(clock * 12) * 2)), Vector2(4, 12)), theme.light.lightened(0.55))

func _draw_hazard(p: Vector2, cell: Vector2i, kind: String) -> void:
	match kind:
		"pit":
			painter.draw_rect(Rect2(p, Vector2.ONE * 32), Color("060c17"))
			painter.draw_rect(Rect2(p + Vector2(4, 6), Vector2(24, 26)), Color("0b1122"))
			if not pits.has(cell + Vector2i.UP):
				painter.draw_line(p, p + Vector2(32, 0), theme.wall.lightened(0.1), 3)
			if not pits.has(cell + Vector2i.LEFT):
				painter.draw_line(p, p + Vector2(0, 32), theme.wall, 3)
			if not pits.has(cell + Vector2i.DOWN):
				painter.draw_line(p + Vector2(0, 31), p + Vector2(32, 31), Color("323447"), 2)
		"lava":
			painter.draw_rect(Rect2(p, Vector2.ONE * 32), Color(0.65, 0.20, 0.10))
		"spikes":
			painter.draw_rect(Rect2(p + Vector2.ONE, Vector2.ONE * 30), Color("29323a"))
			for x in [8, 23]:
				for y in [10, 25]:
					painter.draw_circle(p + Vector2(x, y), 4, Color("101a21"))

func _draw_hazard_dynamic(p: Vector2, cell: Vector2i, kind: String) -> void:
	match kind:
		"pit":
			var depth := sin(clock * 0.8 + cell.x) * 0.1 + 0.12
			painter.draw_rect(Rect2(p + Vector2(12, 16), Vector2(3, 2)), Color(0.35, 0.35, 0.6, depth))
		"lava":
			var pulse := sin(clock * 3 + cell.x + cell.y) * 0.1
			painter.draw_rect(Rect2(p, Vector2.ONE * 32), Color(0.65 + pulse, 0.20, 0.10))
			for i in 3:
				var x := fmod(cell.x * 11 + i * 9 + sin(clock + i) * 3, 27)
				var y := fmod(cell.y * 7 + i * 13, 27)
				painter.draw_rect(Rect2(p + Vector2(x, y), Vector2(8, 3)), Color("f2ac54"))
			painter.draw_rect(Rect2(p + Vector2.ONE, Vector2.ONE * 30), Color("cc6334"), false, 1)
		"spikes":
			var phase := spike_phase(cell)
			if phase > 1.1:
				painter.draw_rect(Rect2(p + Vector2.ONE, Vector2.ONE * 30), Color(0.9, 0.3, 0.2, 0.15 + sin(clock * 14) * 0.08))
			if phase >= 1.7:
				for x in [8, 23]:
					for y in [10, 25]:
						painter.draw_colored_polygon(PackedVector2Array([p + Vector2(x - 4, y + 2), p + Vector2(x, y - 9), p + Vector2(x + 4, y + 2)]), Color("d6b69e"))

func _draw_portal() -> void:
	var p := CENTER
	for i in range(8, 0, -1):
		painter.draw_circle(p, 18 + i * 7, Color(0.3, 0.8, 0.73, 0.015))
	painter.draw_circle(p, 30, Color("102c32"))
	for i in 3:
		painter.draw_arc(p, 25 + i * 6, clock * (0.5 if i % 2 == 0 else -0.4) + i * 2,
			clock * (0.5 if i % 2 == 0 else -0.4) + i * 2 + PI * 1.5, 32, Color("8ccebc"), 2)
	var diamond := PackedVector2Array([p + Vector2(0, -13), p + Vector2(9, 0), p + Vector2(0, 13), p + Vector2(-9, 0)])
	painter.draw_colored_polygon(diamond, Color("c5e0b4"))
