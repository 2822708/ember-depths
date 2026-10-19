class_name RoomGenerator
extends RefCounted
## A small connected tree, not a complicated dungeon algorithm.
## Every new room attaches to an existing room; connectivity is guaranteed.

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func generate(rng: RandomNumberGenerator, count: int, floor_number: int = 1, theme: String = "moss") -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	rooms.append(_make_room(Vector2i.ZERO, -1, rng))
	while rooms.size() < count:
		var parent: int = rng.randi_range(0, rooms.size() - 1)
		var direction: Vector2i = DIRECTIONS[rng.randi_range(0, 3)]
		var cell: Vector2i = rooms[parent].cell + direction
		var occupied := false
		for room in rooms:
			if room.cell == cell:
				occupied = true
		if occupied:
			continue
		var index := rooms.size()
		rooms.append(_make_room(cell, parent, rng))
		rooms[parent].doors[direction] = index
		rooms[index].doors[-direction] = parent
	rooms[0].cleared = true
	rooms[0].rewarded = true
	# A deepest room becomes the exit, so the player always fights before descending.
	var deepest := 1
	for i in range(1, rooms.size()):
		rooms[i].depth = rooms[rooms[i].parent].depth + 1
		if rooms[i].depth > rooms[deepest].depth:
			deepest = i
	rooms[deepest].exit = true
	var layouts := RoomCatalog.pool(floor_number)
	for room in rooms:
		room.variant = layouts[rng.randi_range(0, layouts.size() - 1)]
		room.theme = theme
	# The entrance stays free of hazards, including on deep floors.
	rooms[0].variant = 0
	rooms[0].kind = "entrance"
	rooms[deepest].kind = "boss" if floor_number % 5 == 0 else "combat"
	# Put optional rooms on side branches first; the exit always remains a fight.
	var candidates: Array[int] = []
	for i in range(1, rooms.size()):
		if i != deepest: candidates.append(i)
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var special := ["treasure", "cursed", "shop"]
	# Keep at least two ordinary combat rooms at small floor sizes.
	var slots := mini(3, maxi(0, rooms.size() - 4))
	for i in slots:
		var index := candidates[i]
		rooms[index].kind = special[(i + floor_number - 1) % special.size()]
		if rooms[index].kind in ["treasure", "shop"]: rooms[index].variant = 0
	return rooms

static func _make_room(cell: Vector2i, parent: int, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"cell": cell, "parent": parent, "depth": 0, "doors": {},
		"seed": rng.randi(), "cleared": false, "rewarded": false,
		"visited": false, "exit": false, "variant": 0, "kind": "combat", "stock": []
	}
