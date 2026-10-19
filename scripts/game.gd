extends Node2D

signal hud_changed
## Owns run state; actors own combat, the room owns geometry, HUD owns presentation.

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const RoomScript = preload("res://scripts/room.gd")
const EffectsScript = preload("res://scripts/effects.gd")
const HudScript = preload("res://scripts/hud.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const WaveScript = preload("res://scripts/player_wave.gd")
const WORLD_ORIGIN := Vector2(42, 132)
const MIN_ATTACK_COOLDOWN := 0.30
const MAX_ENEMIES := 18
const FINAL_FLOOR := 20
const REWARDS_PER_FLOOR := 2
const MAX_DAMAGE_STACKS := 8
const SHOP_COST := 18
const SINGLE_UPGRADES := ["sword_wave", "dash_trail", "lifesteal", "berserk", "hazardproof", "ward", "glass", "oath", "blood"]
const UPGRADES: Array[Dictionary] = [
	{"id": "damage", "name": "淬火之刃", "tag": "锋芒", "desc": "基础伤害 ×1.08 · 最多 8 次", "detail": "随楼层成长，基础上限 90，单段伤害上限 140。", "color": Color("e6aa70")},
	{"id": "haste", "name": "疾风余响", "tag": "迅捷", "desc": "攻击冷却缩短 7%", "detail": "剑锋未落，下一击已至。", "color": Color("8fbab4")},
	{"id": "speed", "name": "逐影之靴", "tag": "身法", "desc": "移动速度 +8", "detail": "在怪物的包围中穿行。", "color": Color("a6c8a0")},
	{"id": "health", "name": "生命余烬", "tag": "生机", "desc": "生命上限 +12 · 恢复 12", "detail": "尚未熄灭的火，会护你前行。", "color": Color("db8d7d")},
	{"id": "reach", "name": "月弧剑气", "tag": "延展", "desc": "攻击距离 +8", "detail": "让剑光抵达更远的黑暗。", "color": Color("acafd8")},
	{"id": "force", "name": "山岳之势", "tag": "重击", "desc": "击退强度 +8", "detail": "改变敌人位置，不中断它的攻击。", "color": Color("d1bf8f")}
	,{"id": "sword_wave", "name": "月蚀剑气", "tag": "质变", "desc": "挥剑时发射一束远程剑气", "detail": "近身之外，剑光仍在延伸。", "color": Color("91c9dc")}
	,{"id": "dash_trail", "name": "灼痕步", "tag": "质变", "desc": "闪避留下短暂灼热轨迹", "detail": "让逃生路线也成为陷阱。", "color": Color("e39267")}
	,{"id": "lifesteal", "name": "余烬汲取", "tag": "质变", "desc": "击杀恢复最大生命 1%", "detail": "每一次终结都带回一点温度。", "color": Color("d78980")}
	,{"id": "berserk", "name": "残火狂舞", "tag": "质变", "desc": "生命低于 30% 时攻速翻倍", "detail": "濒临熄灭时，剑锋反而更快。", "color": Color("e07a68")}
	,{"id": "hazardproof", "name": "踏焰者", "tag": "质变", "desc": "免疫岩浆与尖刺伤害", "detail": "危险地形成为你的道路。", "color": Color("e6a55c")}
	,{"id": "ward", "name": "守火誓约", "tag": "质变", "desc": "每层第一次受伤完全免疫", "detail": "火种替你承受最初的恶意。", "color": Color("a7c3d9")}
	,{"id": "glass", "name": "碎玉之刃", "tag": "契约", "desc": "伤害 +40% · 最大生命 -25%", "detail": "全局伤害倍率，本局仅一次。", "color": Color("dba4c1")}
	,{"id": "oath", "name": "不退誓言", "tag": "契约", "desc": "攻速翻倍 · 永久失去闪避", "detail": "与狂舞叠乘，付出身法换取锋芒。", "color": Color("d99574")}
	,{"id": "blood", "name": "血焰契约", "tag": "契约", "desc": "伤害 +60% · 每次挥剑消耗 1 HP", "detail": "可致死，免伤无法抵消献血。", "color": Color("d6767c")}
]

var rng := RandomNumberGenerator.new()
var world: Node2D
var room: DungeonRoom
var player: DungeonPlayer
var effects: DungeonEffects
var hud: Control
var rooms: Array[Dictionary] = []
var enemies: Array[DungeonEnemy] = []
var player_waves: Array[PlayerWave] = []
var actives: ActiveSkills
var shop_page := 0
var shop_slot := 0
var mode := "title":
	set(value):
		if mode == value: return
		mode = value
		if actives != null and value in ["dead", "victory"]:
			actives.tonic_ready = false
			actives.reset_transients()
			_clear_projectiles()
			_clear_zones()
		hud_changed.emit()
var floor_number := 1:
	set(value):
		if floor_number == value: return
		floor_number = value
		hud_changed.emit()
var room_index := 0:
	set(value):
		if room_index == value: return
		room_index = value
		hud_changed.emit()
var kills := 0:
	set(value):
		if kills == value: return
		kills = value
		hud_changed.emit()
var elapsed := 0.0
var shake := 0.0
var transition := 0.0
var clear_timer := 0.0
var travel_cooldown := 0.0
var choices: Array[Dictionary] = []
var collected: Array[Dictionary] = []
var muted := false:
	set(value):
		if muted == value: return
		muted = value
		hud_changed.emit()
var audio_voices: Array[AudioStreamPlayer] = []
var audio_index := 0
var floor_theme := "moss"
var projectiles: Array[EnemyProjectile] = []
var hurt_flash := 0.0
var heartbeat_timer := 0.0
var wave_cooldown := 0.0
var floor_rewards := 0
var damage_stacks := 0
var pending_rewards := 0
var reward_source := "combat"
var currency := 0:
	set(value):
		if currency == value: return
		currency = value
		hud_changed.emit()
var zones: Array[BossZone] = []
var sound_bank := SoundBank.new()
var permanent_shards := 0:
	set(value):
		if permanent_shards == value: return
		permanent_shards = value
		hud_changed.emit()
var permanent_damage := 0
var trails: Array[Dictionary] = []

func _ready() -> void:
	if OS.has_feature("web"):
		ThemeDB.fallback_font = preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
	rng.randomize()
	_setup_input()
	world = Node2D.new()
	world.position = WORLD_ORIGIN
	add_child(world)
	effects = EffectsScript.new()
	world.add_child(effects)
	player = PlayerScript.new()
	player.game = self
	world.add_child(player)
	actives = ActiveSkills.new(self)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HudScript.new()
	hud.game = self
	canvas.add_child(hud)
	for i in 8:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		audio_voices.append(voice)
	if DisplayServer.get_name() != "headless":
		for event in SoundBank.PRESETS: sound_bank.stream_for(event)
	_generate_floor()
	mode = "title"

func _setup_input() -> void:
	var bindings := {"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "dash": KEY_SPACE, "interact": KEY_E, "active_one": KEY_Q, "active_two": KEY_R}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)

func new_run() -> void:
	actives.reset_run()
	floor_number = 1
	kills = 0
	elapsed = 0
	hurt_flash = 0
	heartbeat_timer = 0
	collected.clear()
	floor_rewards = 0
	damage_stacks = 0
	pending_rewards = 0
	currency = 0
	reward_source = "combat"
	trails.clear()
	wave_cooldown = 0
	player.max_hp = 100
	player.hp = 100
	player.rebuild_damage(floor_number, damage_stacks, permanent_damage)
	player.speed = 180
	player.attack_range = 92
	player.attack_cooldown = 0.46
	player.knockback = 80
	player.dash_cooldown = 0
	player.dash_timer = 0
	player.invulnerability = 0
	player.attack_timer = 0.25
	player.sword_wave = 0
	player.dash_trail = 0
	player.lifesteal = 0.0
	player.berserk = 0
	player.hazardproof = 0
	player.ward = 0
	player.ward_available = false
	player.damage_multiplier = 1.0
	player.no_dash = false
	player.oath = false
	player.blood = false
	player.slow_timer = 0
	mode = "playing"
	_generate_floor()

func _generate_floor() -> void:
	player.rebuild_damage(floor_number, damage_stacks, permanent_damage)
	var theme_keys: Array = RoomCatalog.THEMES.keys()
	floor_theme = theme_keys[rng.randi_range(0, theme_keys.size() - 1)]
	if floor_number % 5 == 0:
		# The three guardians are guaranteed to differ in a complete campaign.
		floor_theme = ["moss", "lava", "frost"][mini(2, floori(float(floor_number) / 5) - 1)]
		if floor_number == FINAL_FLOOR: floor_theme = "lava"
	rooms = RoomGenerator.generate(rng, mini(4 + floor_number, 8), floor_number, floor_theme)
	floor_rewards = 0
	player.ward_available = player.ward > 0
	pending_rewards = 0
	reward_source = "combat"
	_enter_room(0, Vector2i.ZERO)
	transition = 0.6

func _enter_room(index: int, from: Vector2i) -> void:
	if actives != null: actives.reset_transients()
	_clear_projectiles()
	_clear_zones()
	trails.clear()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.cancel_mechanics()
			world.remove_child(enemy)
			enemy.queue_free()
	enemies.clear()
	if is_instance_valid(room):
		world.remove_child(room)
		room.queue_free()
	effects.particles.clear()
	effects.numbers.clear()
	room_index = index
	rooms[index].visited = true
	room = RoomScript.new()
	room.presentation_changed.connect(func() -> void: hud_changed.emit())
	room.configure(rooms[index])
	world.add_child(room)
	world.move_child(room, 0)
	player.position = DungeonRoom.CENTER if from == Vector2i.ZERO else DungeonRoom.DOOR_POINTS[from] - Vector2(from) * 68
	player.invulnerability = 0.6
	player.dash_timer = 0
	player.velocity = Vector2.ZERO
	travel_cooldown = 0.45
	transition = 0.35
	var room_kind: String = rooms[index].get("kind", "combat")
	if room_kind in ["treasure", "shop"]:
		rooms[index].cleared = true
		room.set_locked(false)
		if room_kind == "shop" and rooms[index].stock.is_empty():
			rooms[index].stock = _roll_choices()
	elif not rooms[index].cleared:
		room.set_locked(true)
		var count := mini(3 + floor_number + floori(float(rooms[index].depth) / 2.0), 13)
		var types := EnemyCatalog.pool(floor_number)
		var is_boss_room: bool = rooms[index].exit and floor_number % 5 == 0
		if is_boss_room:
			var boss_kind: int = types[rng.randi_range(0, types.size() - 1)]
			spawn_enemy(boss_kind, room.spawn_point(player.position), false, true)
			for i in mini(count, 3):
				var kind: int = types[rng.randi_range(0, types.size() - 1)]
				spawn_enemy(kind, room.spawn_point(player.position))
		else:
			for i in count:
				var kind: int = types[rng.randi_range(0, types.size() - 1)]
				spawn_enemy(kind, room.spawn_point(player.position))
	room.show_exit = rooms[index].exit and rooms[index].rewarded
	hud_changed.emit()

func spawn_enemy(kind: int, at: Vector2, minion: bool = false, boss: bool = false) -> DungeonEnemy:
	if enemies.size() >= MAX_ENEMIES: return null
	var stats: Dictionary = EnemyCatalog.TYPES[kind]
	var enemy := EnemyScript.new()
	enemy.game = self
	enemy.kind = kind
	enemy.is_minion = minion
	enemy.is_boss = boss
	enemy.boss_theme = floor_theme
	enemy.final_boss = boss and floor_number == FINAL_FLOOR
	var growth := enemy_hp_growth(floor_number)
	enemy.max_hp = 16 + floor_number * 3 if minion else int(float(stats.hp) * growth * (9.0 if enemy.final_boss else (5.5 if boss else 1.0)))
	if boss: enemy.max_hp = maxi(enemy.max_hp, BossModule.minimum_hp(floor_number))
	enemy.hp = enemy.max_hp
	enemy.speed = minf(float(stats.speed) + floor_number * 3, 135) * (1.12 if minion else 1.0)
	enemy.damage = (6 if minion else int(stats.damage)) + floor_number * 2 + (8 if boss else 0)
	if rooms[room_index].get("kind", "combat") == "cursed":
		enemy.max_hp = roundi(enemy.max_hp * 1.4)
		enemy.hp = enemy.max_hp
		enemy.damage = roundi(enemy.damage * 1.25)
	if boss:
		enemy.summon_budget = 9 if enemy.final_boss else 6
		play_sound("boss")
	enemy.position = room.nearest_safe_position(at)
	world.add_child(enemy)
	enemies.append(enemy)
	return enemy

func enemy_hp_growth(floor_value: int) -> float:
	var early_layers := mini(maxi(floor_value - 1, 0), 23)
	var late_layers := maxi(floor_value - 24, 0)
	return pow(1.18, float(early_layers)) * pow(1.12, float(late_layers))

func spawn_projectile(at: Vector2, direction: Vector2, damage: int) -> EnemyProjectile:
	# Bound simultaneous hazards without an unbounded projectile field.
	if projectiles.size() >= 160: projectiles[0].destroy()
	var shot := ProjectileScript.new()
	shot.game = self
	shot.position = at
	shot.velocity = direction.normalized() * 205
	shot.damage = damage
	world.add_child(shot)
	projectiles.append(shot)
	return shot

func spawn_player_wave(at: Vector2, direction: Vector2, damage: int) -> PlayerWave:
	var wave := WaveScript.new()
	wave.game = self
	wave.position = at
	wave.velocity = direction.normalized() * 290
	wave.damage = damage
	world.add_child(wave)
	player_waves.append(wave)
	return wave

func _clear_projectiles() -> void:
	for wave in player_waves.duplicate():
		if is_instance_valid(wave): wave.destroy()
	for shot in projectiles:
		if is_instance_valid(shot):
			shot.removed = true
			shot.visible = false
			shot.set_physics_process(false)
			shot.queue_free()
	projectiles.clear()

func spawn_zone(at: Vector2, kind: String, amount: int, options: Dictionary = {}) -> BossZone:
	if zones.size() >= 36: zones[0].retire()
	var zone := BossZone.new()
	zone.game = self
	zone.position = room.nearest_safe_position(at)
	zone.kind = kind
	zone.damage = amount
	for key in options: zone.set(key, options[key])
	world.add_child(zone)
	zones.append(zone)
	return zone

func _clear_zones() -> void:
	for zone in zones:
		if is_instance_valid(zone):
			zone.deactivate()
			zone.queue_free()
	zones.clear()
	if is_instance_valid(player): player.slow_timer = 0

func check_door() -> void:
	if mode != "playing" or travel_cooldown > 0 or room.locked:
		return
	for direction in rooms[room_index].doors:
		if player.position.distance_to(DungeonRoom.DOOR_POINTS[direction]) < 35:
			_enter_room(rooms[room_index].doors[direction], -direction)
			return

func enemy_died(enemy: DungeonEnemy) -> void:
	enemies.erase(enemy)
	kills += 1
	currency += 1 if enemy.is_minion else (8 if enemy.is_boss else 3)
	if player.lifesteal > 0:
		var recovered := maxi(1, roundi(player.max_hp * player.lifesteal))
		player.hp = mini(player.max_hp, player.hp + recovered)
		effects.text(player.position + Vector2(-18, -35), "+%d" % recovered, Color("d78980"))
	if enemy.is_boss:
		permanent_shards += 1
		permanent_damage += 2
		effects.text(enemy.position + Vector2(-28, -45), "余烬碎片 +1", Color("f5d69a"))
	if enemies.is_empty() and mode == "playing":
		_clear_projectiles()
		_clear_zones()
		rooms[room_index].cleared = true
		if rooms[room_index].exit and floor_number == FINAL_FLOOR:
			mode = "victory"
			room.set_locked(false)
			play_sound("victory")
			return
		reward_source = "cursed" if rooms[room_index].get("kind", "combat") == "cursed" else "combat"
		if reward_source == "combat":
			if floor_rewards >= REWARDS_PER_FLOOR:
				pending_rewards = 0
				rooms[room_index].rewarded = true
				room.set_locked(false)
				room.show_exit = rooms[room_index].exit
				hud_changed.emit()
				play_sound("clear")
				return
			# Reserve quota at clear time, independently of opening/rolling cards.
			floor_rewards += 1
		pending_rewards = 2 if reward_source == "cursed" else 1
		mode = "clearing"
		clear_timer = 0.65
		play_sound("clear")

func _offer_reward() -> void:
	hud_changed.emit()
	if pending_rewards <= 0: pending_rewards = 1
	choices = _roll_choices()
	mode = "reward"

func _roll_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pool := available_upgrades()
	for i in 3:
		var index := rng.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result

func available_upgrades() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for upgrade in UPGRADES:
		if upgrade.id == "damage":
			if damage_stacks >= MAX_DAMAGE_STACKS or player.damage >= DungeonPlayer.MAX_BASE_DAMAGE or player.effective_damage() >= DungeonPlayer.MAX_HIT_DAMAGE: continue
			var damage_option: Dictionary = upgrade.duplicate()
			damage_option.desc = "基础伤害 ×1.08 · %d / %d" % [damage_stacks, MAX_DAMAGE_STACKS]
			result.append(damage_option)
			continue
		if upgrade.id in SINGLE_UPGRADES and collected.any(func(item: Dictionary) -> bool: return item.id == upgrade.id):
			continue
		if upgrade.id == "haste":
			if player.attack_cooldown <= MIN_ATTACK_COOLDOWN + 0.00001: continue
			var option: Dictionary = upgrade.duplicate()
			var next := maxf(MIN_ATTACK_COOLDOWN, player.attack_cooldown * 0.93)
			var percent := (1 - next / player.attack_cooldown) * 100
			option.desc = "攻击冷却缩短 %.1f%%" % percent
			if next <= MIN_ATTACK_COOLDOWN + 0.00001:
				option.desc += " · 达到上限"
			result.append(option)
		else: result.append(upgrade)
	return result

func choose_reward(index: int) -> void:
	if mode != "reward" or index < 0 or index >= choices.size():
		return
	var upgrade := choices[index]
	# Reject stale shop cards or an already claimed/capped blessing before payment.
	if not available_upgrades().any(func(option: Dictionary) -> bool: return option.id == upgrade.id): return
	if reward_source == "shop":
		if rooms[room_index].rewarded or currency < shop_price(SHOP_COST): return
		currency -= shop_price(SHOP_COST)
	match upgrade.id:
		"damage":
			damage_stacks += 1
			player.rebuild_damage(floor_number, damage_stacks, permanent_damage)
		"haste": player.attack_cooldown = maxf(MIN_ATTACK_COOLDOWN, player.attack_cooldown * 0.93)
		"speed": player.speed += 8
		"health":
			player.max_hp += 12
			player.hp = mini(player.max_hp, player.hp + 12)
		"reach": player.attack_range += 8
		"force": player.knockback += 8
		"sword_wave": player.sword_wave += 1
		"dash_trail": player.dash_trail += 1
		"lifesteal": player.lifesteal += 0.01
		"berserk": player.berserk += 1
		"hazardproof": player.hazardproof += 1
		"ward": player.ward += 1
		"glass":
			player.damage_multiplier *= 1.4
			player.max_hp = maxi(1, floori(player.max_hp * 0.75))
			player.hp = mini(player.hp, player.max_hp)
		"oath":
			player.oath = true
			player.no_dash = true
		"blood":
			player.damage_multiplier *= 1.6
			player.blood = true
	collected.append(upgrade)
	hud_changed.emit()
	play_sound("reward")
	effects.burst(player.position, upgrade.color, 26)
	pending_rewards -= 1
	if pending_rewards > 0:
		_offer_reward()
		return
	rooms[room_index].rewarded = true
	room.set_locked(false)
	room.show_exit = rooms[room_index].exit
	mode = "playing"
	player.attack_timer = 0.3
	player.invulnerability = 0.5
	reward_source = "combat"

func interact() -> void:
	if mode != "playing" or room.locked or player.position.distance_to(DungeonRoom.CENTER) > 76: return
	var kind: String = rooms[room_index].get("kind", "combat")
	if kind == "shop" or (not rooms[room_index].rewarded and kind == "treasure"):
		reward_source = kind
		pending_rewards = 1
		if kind == "shop":
			shop_page = 0
			# Preserve stock on revisits, replacing only blessings no longer eligible.
			var available := available_upgrades()
			var stock: Array[Dictionary] = []
			for item in rooms[room_index].stock:
				for option in available:
					if option.id == item.id: stock.append(option)
			for item in stock:
				available = available.filter(func(option: Dictionary) -> bool: return option.id != item.id)
			while stock.size() < 3 and not available.is_empty():
				var index := rng.randi_range(0, available.size() - 1)
				stock.append(available[index])
				available.remove_at(index)
			rooms[room_index].stock = stock
			choices.assign(rooms[room_index].stock)
			mode = "reward"
		else: _offer_reward()
		return
	descend()

func leave_shop() -> void:
	if mode != "reward" or reward_source != "shop": return
	pending_rewards = 0
	reward_source = "combat"
	mode = "playing"
	choices = []

func shop_price(base: int) -> int:
	return ceili(base * (1.0 + 0.25 * floori(float(floor_number - 1) / 5.0)))

func in_shop() -> bool:
	return mode == "reward" and reward_source == "shop" and rooms[room_index].kind == "shop"

func shop_buy(index: int) -> void:
	if not in_shop(): return
	if shop_page == 0: choose_reward(index)
	elif shop_page == 1: actives.buy(index, shop_slot)
	elif shop_page == 2: actives.buy_consumable(index)

func set_shop_page(page: int) -> void:
	if not in_shop(): return
	shop_page = clampi(page, 0, 2)
	hud_changed.emit()

func add_dash_trail(at: Vector2) -> void:
	if player.dash_trail <= 0: return
	trails.append({"p": at, "life": 1.25, "max": 1.25, "hit": {}})
	effects.burst(at, Color("e39267"), 10)

func _process_trails(delta: float) -> void:
	for trail in trails:
		trail.life -= delta
		for enemy in enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.dead and enemy.position.distance_to(trail.p) < 30 and not trail.hit.has(enemy):
				trail.hit[enemy] = true
				enemy.take_damage(8, Vector2.ZERO)
	trails = trails.filter(func(trail: Dictionary) -> bool: return trail.life > 0)

func descend() -> void:
	if floor_number >= FINAL_FLOOR or mode != "playing" or not room.show_exit or player.position.distance_to(DungeonRoom.CENTER) > 68:
		return
	floor_number += 1
	player.hp = mini(player.max_hp, player.hp + 20)
	_generate_floor()
	play_sound("descend")

func die() -> void:
	mode = "dead"
	play_sound("death")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if mode == "reward": leave_shop()
			elif mode == "playing": mode = "paused"
			elif mode == "paused": mode = "playing"
		elif event.keycode == KEY_M:
			muted = not muted
		elif event.keycode == KEY_E:
			interact()
		elif event.keycode == KEY_ENTER:
			if mode in ["title", "dead", "victory"]: new_run()
			elif mode == "paused": mode = "playing"
		elif event.keycode in [KEY_Q, KEY_R]:
			var slot := 0 if event.keycode == KEY_Q else 1
			if in_shop():
				shop_slot = slot
				hud_changed.emit()
			else: actives.cast(slot)
		elif event.keycode == KEY_TAB and in_shop(): set_shop_page((shop_page + 1) % 3)
		elif mode == "reward" and event.keycode in [KEY_1, KEY_2, KEY_3]:
			if in_shop(): shop_buy(event.keycode - KEY_1)
			else: choose_reward(event.keycode - KEY_1)
		elif event.keycode == KEY_4 and in_shop() and shop_page == 1: shop_buy(3)

func _process(delta: float) -> void:
	room.active = mode == "playing"
	if mode == "playing":
		actives.update(delta)
		elapsed += delta
		wave_cooldown = maxf(0, wave_cooldown - delta)
		hurt_flash = maxf(0, hurt_flash - delta)
		if player.hp > 0 and float(player.hp) / player.max_hp <= 0.3:
			heartbeat_timer -= delta
			if heartbeat_timer <= 0:
				play_sound("heartbeat")
				heartbeat_timer = 0.85
		else: heartbeat_timer = 0
	if mode == "playing": _process_trails(delta)
	travel_cooldown = maxf(0, travel_cooldown - delta)
	transition = maxf(0, transition - delta)
	shake = maxf(0, shake - delta * 23)
	world.position = WORLD_ORIGIN + Vector2(rng.randf_range(-shake, shake), rng.randf_range(-shake, shake))
	if mode == "clearing":
		clear_timer -= delta
		if clear_timer <= 0:
			_offer_reward()


func play_sound(event: String) -> void:
	if muted or audio_voices.is_empty() or DisplayServer.get_name() == "headless": return
	var voice := audio_voices[audio_index % audio_voices.size()]
	audio_index += 1
	voice.stream = sound_bank.stream_for(event)
	voice.play()
