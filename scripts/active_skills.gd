class_name ActiveSkills
extends RefCounted
## Run-owned purchases; room-owned cooldowns and temporary effects.
const TYPES: Array[Dictionary] = [
	{"id": "shock", "name": "余烬冲击", "price": 50, "cooldown": 6.0, "desc": "穿透剑气 · 三段当前伤害", "color": Color("efb578")},
	{"id": "ring", "name": "烈焰护环", "price": 60, "cooldown": 8.0, "desc": "150px 爆发 · 伤害与击退", "color": Color("ed916c")},
	{"id": "stasis", "name": "时之凝滞", "price": 70, "cooldown": 10.0, "desc": "420px 内减速 50% · 2 秒", "color": Color("99cce3")},
	{"id": "rekindle", "name": "余烬复燃", "price": 80, "cooldown": 20.0, "desc": "恢复 30% 最大生命", "color": Color("9bd5a1")}
]
const CONSUMABLES: Array[Dictionary] = [
	{"name": "疗伤余烬", "price": 45, "desc": "立即恢复 30% 最大生命"},
	{"name": "炽焰药剂", "price": 65, "desc": "下一场战斗伤害 +20% · 30 秒"},
	{"name": "守火护符", "price": 100, "desc": "抵挡下一次受伤 · 换房保留"}
]
var game: Node2D
var levels: Dictionary = {}
var slots: Array[String] = ["", ""]
var cooldowns: Array[float] = [0.0, 0.0]
var tonic_timer := 0.0
var tonic_ready := false
var hud_timer := 0.0
var visual_timer := 0.0
var visual_radius := 0.0
var visual_color := Color.WHITE

func _init(owner_game: Node2D) -> void:
	game = owner_game

func reset_run() -> void:
	levels.clear()
	slots = ["", ""]
	tonic_ready = false
	reset_transients()

func reset_transients() -> void:
	cooldowns = [0.0, 0.0]
	tonic_timer = 0
	visual_timer = 0
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.active_slow_timer = 0
	game.hud_changed.emit()

func data_for(id: String) -> Dictionary:
	for item in TYPES:
		if item.id == id: return item
	return {}

func price(index: int) -> int:
	var item := TYPES[index]
	var level := int(levels.get(item.id, 0))
	return game.shop_price(int(item.price) if level == 0 else (90 if level == 1 else 140))

func buy(index: int, slot: int) -> bool:
	if not game.in_shop() or index < 0 or index >= TYPES.size() or slot not in [0, 1]: return false
	var item := TYPES[index]
	var level := int(levels.get(item.id, 0))
	if level >= 3: return false
	var cost := price(index)
	if game.currency < cost: return false
	game.currency -= cost
	levels[item.id] = level + 1
	# Upgrade an equipped skill without moving it. New unlocks use selected slot.
	if not slots.has(item.id): equip(item.id, slot)
	game.hud_changed.emit()
	game.play_sound("reward")
	return true

func equip(id: String, slot: int) -> bool:
	if not game.in_shop() or not levels.has(id) or slot not in [0, 1]: return false
	var old_slot := slots.find(id)
	if old_slot >= 0: slots[old_slot] = ""
	slots[slot] = id
	cooldowns[slot] = 0
	game.hud_changed.emit()
	return true

func buy_consumable(index: int) -> bool:
	if not game.in_shop() or index < 0 or index >= CONSUMABLES.size(): return false
	var cost: int = game.shop_price(CONSUMABLES[index].price)
	if game.currency < cost: return false
	if index == 0 and game.player.hp >= game.player.max_hp: return false
	if index == 1 and (tonic_ready or tonic_timer > 0): return false
	if index == 2 and game.player.ward_available: return false
	game.currency -= cost
	if index == 0: game.player.hp = mini(game.player.max_hp, game.player.hp + roundi(game.player.max_hp * 0.3))
	elif index == 1: tonic_ready = true
	else: game.player.ward_available = true
	game.hud_changed.emit()
	game.play_sound("reward")
	return true

func update(delta: float) -> void:
	visual_timer = maxf(0, visual_timer - delta)
	if tonic_ready and not game.enemies.is_empty():
		tonic_ready = false
		tonic_timer = 30.0
	var changing := tonic_timer > 0 or cooldowns[0] > 0 or cooldowns[1] > 0
	tonic_timer = maxf(0, tonic_timer - delta)
	for i in 2: cooldowns[i] = maxf(0, cooldowns[i] - delta)
	if changing and tonic_timer == 0 and cooldowns[0] == 0 and cooldowns[1] == 0: game.hud_changed.emit()
	hud_timer += delta
	if changing and hud_timer >= 0.1:
		hud_timer = 0
		game.hud_changed.emit()

func cast(slot: int) -> bool:
	if game.mode != "playing" or slot not in [0, 1] or slots[slot].is_empty() or cooldowns[slot] > 0: return false
	var item := data_for(slots[slot])
	var level := int(levels[item.id])
	var effect := pow(1.3, level - 1)
	var player: DungeonPlayer = game.player
	# Set before dealing damage: a killing cast can transition to victory, which resets it.
	cooldowns[slot] = float(item.cooldown)
	match item.id:
		"shock":
			var wave: PlayerWave = game.spawn_player_wave(player.position + player.facing * 18, player.facing, mini(DungeonPlayer.MAX_HIT_DAMAGE, roundi(player.effective_damage() * effect)))
			wave.pulses = 3
			wave.velocity = player.facing * 430 * effect
			wave.life = 1.1
		"ring":
			visual_timer = 0.35
			visual_radius = 150 * sqrt(effect)
			visual_color = item.color
			for enemy in game.enemies.duplicate():
				if is_instance_valid(enemy) and not enemy.dead and player.position.distance_to(enemy.position) <= 150 * sqrt(effect):
					enemy.take_damage(mini(DungeonPlayer.MAX_HIT_DAMAGE, roundi(player.effective_damage() * effect)), (enemy.position - player.position).normalized() * 220 * effect)
			game.effects.burst(player.position, item.color, 36)
		"stasis":
			visual_timer = 0.35
			visual_radius = 420
			visual_color = item.color
			for enemy in game.enemies:
				if player.position.distance_to(enemy.position) <= 420:
					enemy.active_slow_timer = 2.0 * effect
					enemy.active_slow_multiplier = 0.5
			game.effects.burst(player.position, item.color, 30)
		"rekindle":
			player.hp = mini(player.max_hp, player.hp + roundi(player.max_hp * 0.30 * effect))
			game.effects.text(player.position + Vector2(-20, -40), "复燃", item.color)
	game.effects.text(player.position + Vector2(-30, -55), item.name, item.color)
	game.hud_changed.emit()
	game.play_sound("cast")
	return true
