class_name BuildingDB
extends RefCounted
## 建筑数据。v1.6.2：做了一波数值平衡（对照表见 docs/版本记录/v1.6.2.md）。
##
## 平衡口径：
##   · 每级建筑维护 0.25 生产力（BUILDING_UPKEEP_PRODUCTION），所以**每级加成必须 > 0.25**，
##     否则升级反而变亏 —— 这是旧数值最大的问题（满级净收益几乎被维护费吃光）。
##   · 经济建筑（生产/食物/货币）的**回本周期目标 4~8 个周期**（建造消耗 ÷ 满员每周期净产出）。
##   · 科研建筑回本慢是刻意的（科研是科技门槛货币），但产能要比上一档明显高一档。
##   · 「炼金所 / 黑土学院」是科技解锁的高阶建筑、消耗货币，产能约为初级的 3~4 倍。

static func all() -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []

	# ======================= 工业建筑 =======================
	# 经典田地：2 人力/级，每人 1.3 食物，每级 +0.35 食物，−2 幸福。
	out.append(_mk({
		"id": "classic_field", "name": "经典田地", "category": "工业建筑", "subcategory": "食物", "land": 0.4,
		"desc": "每级最多指派两个人力，每个人力每周期产出 1.3 份食物，每级额外增加 0.35 份食物，同时将 -2 幸福度。",
		"workers": 2,
		"per_worker": {"food": 1.3},
		"per_level": {"food": 0.35},
		"cost": {"production": 10.0}, "cost_inc": {"production": 10.0},
		"happy": -2.0, "happy_per_level": 0.0,
		"tech": "",
	}))

	# 经典面包坊：1 人力/级，不产食物，+6 幸福（每级 +0.6）。
	out.append(_mk({
		"id": "classic_bakery", "name": "经典面包坊", "category": "工业建筑", "subcategory": "食物", "land": 0.3,
		"desc": "每级最多指派一个人力，不产出食物，但是将 +6 幸福度，每级额外增加 0.6 幸福度。",
		"workers": 1,
		"per_worker": {},
		"per_level": {},
		"cost": {"production": 20.0}, "cost_inc": {"production": 15.0},
		"happy": 6.0, "happy_per_level": 0.6,
		"tech": "",
	}))

	# 经典磨坊：1 人力/级，每人消耗 1 食物、产出 2.6 食物（净 +1.6，高于田地的每人 1.3），每级 +0.35。
	out.append(_mk({
		"id": "classic_mill", "name": "经典磨坊", "category": "工业建筑", "subcategory": "食物", "land": 0.4,
		"desc": "每级最多指派一个人力，每个人力每周期消耗 1 份食物，产出 2.6 份食物（净 +1.6），每级额外增加 0.35 份食物。",
		"workers": 1,
		"per_worker": {"food": 2.6},
		"per_level": {"food": 0.35},
		"upkeep_per_worker": {"food": 1.0},
		"cost": {"production": 25.0}, "cost_inc": {"production": 20.0},
		"happy": 0.0, "happy_per_level": 0.0,
		"tech": "",
	}))

	# 经典工坊：2 人力/级，每人 1.5 生产力 + 0.4 科研点，每级 +0.35 生产力。
	out.append(_mk({
		"id": "classic_workshop", "name": "经典工坊", "category": "工业建筑", "subcategory": "生产", "land": 0.4,
		"desc": "每级最多指派两个人力，每个人力每周期产出 1.5 生产力、0.4 科研点，每级额外增加 0.35 生产力。",
		"workers": 2,
		"per_worker": {"production": 1.5, "research": 0.4},
		"per_level": {"production": 0.35},
		"cost": {"production": 20.0}, "cost_inc": {"production": 15.0},
		"tech": "",
	}))

	# 经典市场（v1.6.2 新增）：2 人力/级，每人 1.6 货币，每级 +0.35 货币。
	out.append(_mk({
		"id": "classic_market", "name": "经典市场", "category": "工业建筑", "subcategory": "商业", "land": 0.4,
		"desc": "每级最多指派两个人力，每个人力每周期产出 1.6 货币，每级额外增加 0.35 货币。",
		"workers": 2,
		"per_worker": {"currency": 1.6},
		"per_level": {"currency": 0.35},
		"cost": {"production": 25.0}, "cost_inc": {"production": 20.0},
		"tech": "",
	}))

	# 经典矿场：2 人力/级，每人 1.1 生产力，每级 +0.35；有矿物资源点则额外 +1（每级 +0.35）。
	out.append(_mk({
		"id": "classic_mine", "name": "经典矿场", "category": "工业建筑", "subcategory": "生产", "land": 0.5,
		"desc": "每级最多指派两个人力，每个人力每周期产出 1.1 生产力，每级额外增加 0.35 生产力，同时如果所在格子存在矿物资源点，可产出对应矿产 +1，每级额外增加 0.35 份矿产。",
		"workers": 2,
		"per_worker": {"production": 1.1},
		"per_level": {"production": 0.35},
		"node_bonus": 1.0, "node_bonus_per_level": 0.35,
		"uses_node": true,
		"cost": {"production": 8.0}, "cost_inc": {"production": 12.0},
		"tech": "mining",
	}))

	# 炼金所：1 人力/级，每人 5.5 生产力，每级 +1.5；允许转换基础材料。科技解锁、消耗货币。
	out.append(_mk({
		"id": "alchemy_lab", "name": "炼金所", "category": "工业建筑", "subcategory": "生产", "land": 0.6,
		"desc": "每级最多指派一个人力，每个人力每周期产出 5.5 生产力，每级额外增加 1.5 生产力，同时允许转换基础材料。",
		"workers": 1,
		"per_worker": {"production": 5.5},
		"per_level": {"production": 1.5},
		"cost": {"production": 180.0, "currency": 400.0}, "cost_inc": {"production": 50.0, "currency": 100.0},
		"max_level": 3,
		"tech": "alchemy_black_soil",
	}))

	# ======================= 军事建筑 =======================
	# 经典训练场地：每级多一个训练槽位，每次训练消耗 1 人力，五个周期后转变为训练军。
	out.append(_mk({
		"id": "classic_training_ground", "name": "经典训练场地", "category": "军事建筑", "subcategory": "陆军", "land": 0.5,
		"desc": "每级可多一个训练槽位，每次训练需要消耗 1 个人力，将在五个周期后转变为军事单位-训练军。",
		"workers": 0,
		"per_worker": {}, "per_level": {},
		"cost": {"production": 20.0}, "cost_inc": {"production": 15.0},
		"tech": "",
	}))

	# ======================= 民用建筑 =======================
	# 经典民居：按「人力/住房比」插值：房屋少人力多 → 至多 +10 货币/级、幸福 −10；反之 +1 货币、幸福 +10。
	out.append(_mk({
		"id": "classic_house", "name": "经典民居", "category": "民用建筑", "subcategory": "居住", "land": 0.5,
		"desc": "如果房屋越少、人力越多，民居将提供至多 +10 个货币每级，但是幸福度 -10，人力停止增长。如果房屋越多、人力越少，民居只能提供 +1 货币，幸福度 +10。",
		"workers": 0,
		"per_worker": {}, "per_level": {},
		"housing_ratio_gold": {"min": 1.0, "max": 10.0},
		"housing_ratio_happy": {"min": 10.0, "max": -10.0},
		"cost": {"production": 20.0}, "cost_inc": {"production": 20.0},
		"tech": "",
	}))

	# 经典学院：2 人力/级，每人 0.9 科研点，每级 +0.35。
	out.append(_mk({
		"id": "classic_academy", "name": "经典学院", "category": "民用建筑", "subcategory": "教育", "land": 0.6,
		"desc": "每级最多指派两个人力，每个人力每周期产出 0.9 科研点。每级额外增加 0.35 科研点。",
		"workers": 2,
		"per_worker": {"research": 0.9},
		"per_level": {"research": 0.35},
		"culture": 0.05,
		"cost": {"production": 40.0}, "cost_inc": {"production": 45.0},
		"tech": "",
	}))

	# 黑土学院：2 人力/级，每人 3.2 科研点，每级 +1.2。科技解锁、消耗货币。
	out.append(_mk({
		"id": "black_soil_academy", "name": "黑土学院", "category": "民用建筑", "subcategory": "教育", "land": 0.6,
		"desc": "每级最多指派两个人力，每个人力每周期产出 3.2 科研点，每级额外增加 1.2 科研点。",
		"workers": 2,
		"per_worker": {"research": 3.2},
		"per_level": {"research": 1.2},
		"culture": 0.15,
		"cost": {"production": 300.0, "currency": 2400.0}, "cost_inc": {"production": 100.0, "currency": 800.0},
		"max_level": 3,
		"tech": "alchemy_black_soil",
	}))

	# 经典仓储：每级提高所有具体资源（货币除外）的存储上限 50。
	out.append(_mk({
		"id": "classic_warehouse", "name": "经典仓储", "category": "民用建筑", "subcategory": "存储", "land": 0.4,
		"desc": "每级提高所有具体资源（货币除外）的存储上限 50。",
		"workers": 0,
		"per_worker": {}, "per_level": {},
		"cost": {"production": 30.0}, "cost_inc": {"production": 25.0},
		"tech": "",
	}))

	return out


static func _mk(d: Dictionary) -> BuildingDef:
	var b := BuildingDef.new()
	b.id = d.get("id", "")
	b.display_name = d.get("name", "")
	b.category = d.get("category", "工业建筑")
	b.subcategory = d.get("subcategory", "")
	b.desc = d.get("desc", "")
	b.max_workers_per_level = int(d.get("workers", 0))
	b.yield_per_worker = d.get("per_worker", {})
	b.yield_per_level = d.get("per_level", {})
	b.cost_base = d.get("cost", {})
	b.cost_per_level = d.get("cost_inc", {})
	b.happiness_base = float(d.get("happy", 0.0))
	b.happiness_per_level = float(d.get("happy_per_level", 0.0))
	b.max_level = int(d.get("max_level", 5))
	b.required_tech = d.get("tech", "")
	b.land = float(d.get("land", 0.4))
	# 下面这些是「特殊效果」标记，用字符串形式挂在资源上，供 GameState 读取
	var extras: Array[String] = []
	for key in ["upkeep_per_worker", "node_bonus", "node_bonus_per_level", "uses_node",
			"housing_ratio_gold", "housing_ratio_happy",
			"culture"]:
		if d.has(key):
			b.set_meta(key, d[key])
			extras.append(key)
	b.special = ",".join(extras)
	return b


## 便捷读取 meta（不存在时给默认值）
static func meta_of(b: BuildingDef, key: String, def_value: Variant) -> Variant:
	if b.has_meta(key):
		return b.get_meta(key)
	return def_value


static func find(id: String) -> BuildingDef:
	for b in all():
		if b.id == id:
			return b
	return null