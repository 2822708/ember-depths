class_name RoomCatalog
extends RefCounted
## All geometry is authored in tile coordinates. The central cross stays clear,
## connecting every entrance and leaving a safe landing around the exit portal.

const LAYOUTS: Array[Dictionary] = [
	{"name": "双柱小屋", "min_floor": 1, "max_floor": 3, "pillars": [Vector2i(6, 5), Vector2i(20, 11)], "walls": [Rect2i(2, 2, 3, 4), Rect2i(23, 12, 3, 4)], "hazards": []},
	{"name": "四柱回廊", "min_floor": 1, "max_floor": 3, "pillars": [Vector2i(6, 4), Vector2i(20, 4), Vector2i(6, 12), Vector2i(20, 12)], "walls": [], "hazards": []},
	{"name": "苔痕偏厅", "min_floor": 1, "max_floor": 3, "pillars": [Vector2i(7, 12), Vector2i(19, 4), Vector2i(5, 4)], "walls": [Rect2i(2, 12, 3, 4), Rect2i(23, 2, 3, 4)], "hazards": []},
	{"name": "折影长廊", "min_floor": 2, "max_floor": 6, "pillars": [Vector2i(18, 12)], "walls": [Rect2i(5, 4, 6, 1), Rect2i(5, 4, 1, 3), Rect2i(17, 12, 6, 1), Rect2i(22, 11, 1, 2)], "hazards": []},
	{"name": "双庭石室", "min_floor": 2, "max_floor": 6, "pillars": [Vector2i(5, 5), Vector2i(21, 11)], "walls": [Rect2i(9, 2, 1, 4), Rect2i(18, 12, 1, 4)], "hazards": []},
	{"name": "尖刺试炼", "min_floor": 3, "max_floor": 6, "pillars": [Vector2i(5, 4), Vector2i(21, 12)], "walls": [], "hazards": [{"kind": "spikes", "rect": Rect2i(8, 5, 3, 2)}, {"kind": "spikes", "rect": Rect2i(17, 11, 3, 2)}]},
	{"name": "裂隙石桥", "min_floor": 4, "max_floor": -1, "pillars": [Vector2i(4, 12), Vector2i(22, 4)], "walls": [], "hazards": [{"kind": "pit", "rect": Rect2i(8, 2, 3, 5)}, {"kind": "pit", "rect": Rect2i(17, 11, 3, 5)}]},
	{"name": "熔池工坊", "min_floor": 4, "max_floor": -1, "pillars": [Vector2i(5, 4), Vector2i(21, 12)], "walls": [Rect2i(8, 12, 3, 1)], "hazards": [{"kind": "lava", "rect": Rect2i(17, 3, 6, 3)}, {"kind": "lava", "rect": Rect2i(4, 11, 4, 3)}]},
	{"name": "断桥祭坛", "min_floor": 5, "max_floor": -1, "pillars": [Vector2i(4, 5), Vector2i(22, 11)], "walls": [], "hazards": [{"kind": "pit", "rect": Rect2i(7, 3, 4, 3)}, {"kind": "pit", "rect": Rect2i(17, 12, 4, 3)}, {"kind": "spikes", "rect": Rect2i(18, 4, 3, 2)}, {"kind": "spikes", "rect": Rect2i(7, 12, 3, 2)}]},
	{"name": "深渊熔核", "min_floor": 6, "max_floor": -1, "pillars": [Vector2i(5, 12), Vector2i(21, 4)], "walls": [], "hazards": [{"kind": "pit", "rect": Rect2i(4, 3, 4, 3)}, {"kind": "pit", "rect": Rect2i(20, 12, 4, 3)}, {"kind": "lava", "rect": Rect2i(9, 11, 2, 4)}, {"kind": "lava", "rect": Rect2i(17, 3, 2, 4)}, {"kind": "spikes", "rect": Rect2i(8, 5, 3, 2)}]}
]

const THEMES := {
	"moss": {"name": "苔藓遗迹", "floor": Color("172b2b"), "wall": Color("42574d"), "detail": Color("688665"), "light": Color("e8b76d"), "dust": Color("b3c58a"), "crest": Color("42675b")},
	"lava": {"name": "熔火遗迹", "floor": Color("302326"), "wall": Color("64504a"), "detail": Color("976547"), "light": Color("ff9250"), "dust": Color("f5ab5e"), "crest": Color("785042")},
	"frost": {"name": "霜封遗迹", "floor": Color("202e3e"), "wall": Color("526879"), "detail": Color("83a8bb"), "light": Color("8fdae9"), "dust": Color("c4e7f3"), "crest": Color("4e748c")}
}

static func pool(floor_number: int) -> Array[int]:
	var result: Array[int] = []
	for i in LAYOUTS.size():
		if floor_number >= LAYOUTS[i].min_floor and (LAYOUTS[i].max_floor < 0 or floor_number <= LAYOUTS[i].max_floor):
			result.append(i)
	return result
