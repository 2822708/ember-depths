class_name EnemyCatalog
extends RefCounted
## Kind order also indexes the sprite palette. Damage is independent of HP/speed.
const TYPES: Array[Dictionary] = [
	{"name": "掷火者", "min_floor": 1, "hp": 42, "speed": 58, "damage": 12, "color": Color("c49c67"), "windup": 0.65},
	{"name": "裂角冲锋者", "min_floor": 1, "hp": 58, "speed": 62, "damage": 20, "color": Color("bb806d"), "windup": 0.7},
	{"name": "唤灵祭司", "min_floor": 2, "hp": 48, "speed": 50, "damage": 10, "color": Color("ad8bc8"), "windup": 1.0},
	{"name": "爆焰虫", "min_floor": 2, "hp": 35, "speed": 80, "damage": 28, "color": Color("dd9a57"), "windup": 0.9},
	{"name": "裂生黏灵", "min_floor": 3, "hp": 66, "speed": 56, "damage": 14, "color": Color("82b795"), "windup": 0.48},
	{"name": "盾卫", "min_floor": 4, "hp": 52, "speed": 34, "damage": 8, "color": Color("90a9ad"), "windup": 0.72, "mechanic": "shield_guard"},
	{"name": "相位者", "min_floor": 6, "hp": 46, "speed": 68, "damage": 9, "color": Color("91c9dc"), "windup": 0.55, "mechanic": "phase_walker"},
	{"name": "治疗祭司", "min_floor": 5, "hp": 85, "speed": 58, "damage": 6, "color": Color("a6c89b"), "windup": 0.9, "mechanic": "warden"}
]

const MECHANICS := {
	"shield_guard": {"front_arc_degrees": 120.0, "front_damage_multiplier": 0.10, "back_damage_multiplier": 1.0, "turn_speed": 0.55, "interval": 4.0, "warning": 0.7, "duration": 1.1, "push_speed": 100.0, "push_radius": 38.0, "trigger_distance": 240.0, "push_front_multiplier": 0.0},
	"phase_walker": {"period": 2.5, "duration": 1.2, "warning": 0.5, "move_multiplier": 0.60, "ring_count": 8, "ring_speed": 130.0},
	"warden": {"interval": 6.0, "windup": 1.2, "channel": 1.5, "tick_interval": 1.0, "radius": 420.0, "heal_fraction": 0.04, "follow_distance": 140.0, "setback": 0.5, "beam_duration": 0.3}
}

# All ordinary-enemy skill tuning is here; every hit is at most base damage.
const SKILLS := {
	"throw": {"count": 3, "arc_degrees": 25.0},
	"charge": {"duration": 0.65, "shock_radius": 70.0, "shock_warning": 0.3, "shock_duration": 0.25},
	"summon": {"count": 3, "slow_radius": 95.0, "slow_duration": 2.0, "warning": 0.3, "zone_duration": 0.15, "cooldown": 4.5},
	"explode": {"radius": 130.0, "fire_duration": 2.0, "fire_warning": 0.2},
	"split": {"count": 2, "invulnerability": 0.5}
}

const COMBAT := {
	"melee_cooldown": 0.75, "throw_cooldown": 1.25, "charge_cooldown": 1.9,
	"melee_windup": 0.36, "pursuit_distance": 200.0, "pursuit_multiplier": 1.15,
	"pressure_health_fraction": 0.30, "pressure_cooldown_multiplier": 0.90
}

static func mechanic(kind: int) -> Dictionary:
	return MECHANICS.get(TYPES[kind].get("mechanic", ""), {})

static func pool(floor_number: int) -> Array[int]:
	var result: Array[int] = []
	for i in TYPES.size():
		if floor_number >= TYPES[i].min_floor: result.append(i)
	return result
