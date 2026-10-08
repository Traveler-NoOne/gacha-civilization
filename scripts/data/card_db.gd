class_name CardDB
extends RefCounted
## 抽卡卡池数据。
## 文档原意是抽取米哈游作品中的角色 / 武器 / 生物等，这里用「几何图形 + 文字」的
## 占位内容代替美术资源，只保留稀有度、卡组、类型这些会影响玩法的字段。
##
## pool: character 角色 / weapon 武装 / relic 战备 / item 道具 / material 材料 / advanced 高级材料
## group: 卡组。v1.1 更新把卡组名改成了文明组：

const GROUPS := ["提瓦特", "崩坏本征", "绝区零", "通用"]

## 每个卡池条目：id, name, rarity, group, pool, kind(几何形状), attr(演示属性)
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_build(out)
	# v1.1：为角色补齐「职业 / 位阶 / 文明组」字段
	for c in out:
		if str(c["pool"]) == "character":
			c["profession"] = profession_of(c)
			c["rank"] = UnitDB.HERO
			c["unit_type"] = "character"
	return out


## 角色 id -> 职业（v1.1 职业系统）
## 这里用字符串字面量而不是 UnitDB.XXX，因为跨脚本常量不能出现在常量表达式里
const PROFESSION_BY_ID := {
	# 提瓦特
	"char_geo": "defender",
	"char_anemo": "melee",
	"char_dendro": "support",
	"char_hydro": "support",
	"char_pyro": "ranged",
	"char_cryo": "projectile",
	"char_electro": "melee",
	# 崩坏本征
	"char_herrscher": "projectile",
	"char_valkyrie": "melee",
	"char_honkai_mech": "defender",
	"char_stigmata": "ranged",
	"char_bronya": "projectile",
	"char_grieso": "projectile",   # v1.6：开局赠送
	# 绝区零
	"char_void_hunter": "melee",
	"char_agent": "ranged",
	"char_bangboo": "support",
	"char_ethereal": "projectile",
}


## 取某个角色的职业 id
static func profession_of(card: Dictionary) -> String:
	return str(PROFESSION_BY_ID.get(str(card.get("id", "")), "melee"))


## 文明组映射：卡池卡组名 -> v1.1 的三个文明组
const CIV_GROUPS: Array[String] = ["提瓦特", "崩坏本征", "绝区零"]

const GROUP_TO_CIV := {
	"提瓦特": "提瓦特",
	"绝区零": "绝区零",
	"崩坏本征": "崩坏本征",
	# 旧名（v1.1 更新前）
}


## 取某张卡所属的文明组（通用类返回空字符串）
static func civ_group_of(card: Dictionary) -> String:
	var g := str(card.get("group", ""))
	if g == "通用" or g == "":
		return ""
	return str(GROUP_TO_CIV.get(g, g))


static func _build(out: Array[Dictionary]) -> void:
	# ---------------- 角色 ----------------
	out.append(_c("char_geo", "岩构骑士", 4, "提瓦特", "character", "square", {"atk": 42, "def": 30, "hp": 260, "spd": 3, "agi": 12}))
	out.append(_c("char_anemo", "风羽游侠", 4, "提瓦特", "character", "triangle", {"atk": 46, "def": 20, "hp": 210, "spd": 4, "agi": 18}))
	out.append(_c("char_dendro", "草生术士", 3, "提瓦特", "character", "hexagon", {"atk": 30, "def": 18, "hp": 190, "spd": 3, "agi": 14}))
	out.append(_c("char_hydro", "水镜使", 3, "提瓦特", "character", "circle", {"atk": 28, "def": 22, "hp": 220, "spd": 3, "agi": 15}))
	out.append(_c("char_pyro", "炽炎枪兵", 3, "提瓦特", "character", "triangle", {"atk": 36, "def": 22, "hp": 200, "spd": 4, "agi": 13}))
	out.append(_c("char_cryo", "霜原猎手", 2, "提瓦特", "character", "diamond", {"atk": 24, "def": 14, "hp": 160, "spd": 4, "agi": 16}))
	out.append(_c("char_electro", "雷纹先锋", 2, "提瓦特", "character", "diamond", {"atk": 26, "def": 15, "hp": 165, "spd": 3, "agi": 14}))

	out.append(_c("char_herrscher", "空律·崩坏", 5, "崩坏本征", "character", "star", {"atk": 72, "def": 40, "hp": 340, "spd": 4, "agi": 20}))
	out.append(_c("char_valkyrie", "女武神·白夜", 4, "崩坏本征", "character", "triangle", {"atk": 50, "def": 26, "hp": 240, "spd": 5, "agi": 22}))
	out.append(_c("char_honkai_mech", "崩坏机兵", 3, "崩坏本征", "character", "square", {"atk": 32, "def": 34, "hp": 280, "spd": 2, "agi": 8}))
	out.append(_c("char_stigmata", "圣痕持有者", 3, "崩坏本征", "character", "hexagon", {"atk": 34, "def": 24, "hp": 230, "spd": 3, "agi": 15}))
	out.append(_c("char_bronya", "重装射手", 2, "崩坏本征", "character", "square", {"atk": 28, "def": 20, "hp": 180, "spd": 3, "agi": 11}))
	# v1.6：格蕾修（前文明「方舟计划」的乘员）——5★ 投射者：攻中等 / 防低 / 血低 / 速中等 / 敏高
	out.append(_c("char_grieso", "格蕾修", 5, "崩坏本征", "character", "line", {"atk": 62, "def": 22, "hp": 230, "spd": 4, "agi": 26}))

	out.append(_c("char_void_hunter", "虚狩·空洞", 5, "绝区零", "character", "star", {"atk": 68, "def": 34, "hp": 300, "spd": 5, "agi": 24}))
	out.append(_c("char_agent", "代理人·刃", 4, "绝区零", "character", "star", {"atk": 54, "def": 24, "hp": 220, "spd": 5, "agi": 21}))
	out.append(_c("char_bangboo", "邦布·工蜂", 2, "绝区零", "character", "circle", {"atk": 18, "def": 16, "hp": 150, "spd": 3, "agi": 10}))
	out.append(_c("char_ethereal", "以太体", 3, "绝区零", "character", "hexagon", {"atk": 33, "def": 18, "hp": 200, "spd": 4, "agi": 17}))

	# ---------------- 武装 / 战备 ----------------
	out.append(_c("wpn_skyward", "天空之刃", 5, "提瓦特", "weapon", "line", {"atk": 48}))
	out.append(_c("wpn_iron_sting", "铁蜂刺", 3, "提瓦特", "weapon", "line", {"atk": 22}))
	out.append(_c("wpn_training", "训练长枪", 1, "通用", "weapon", "line", {"atk": 8}))
	out.append(_c("wpn_key_of_cast", "识之钥", 5, "崩坏本征", "weapon", "line", {"atk": 46}))
	out.append(_c("wpn_judgment", "裁决之槌", 4, "崩坏本征", "weapon", "line", {"atk": 34}))
	out.append(_c("wpn_w_engine", "音擎·轰鸣", 4, "绝区零", "weapon", "line", {"atk": 36}))
	out.append(_c("wpn_stun_baton", "眩晕警棍", 2, "绝区零", "weapon", "line", {"atk": 15}))

	out.append(_c("rel_gladiator", "角斗士的终幕", 5, "提瓦特", "relic", "diamond", {"def": 30}))
	out.append(_c("rel_wanderer", "流浪大地的乐团", 4, "提瓦特", "relic", "diamond", {"def": 22}))
	out.append(_c("rel_hp_flower", "生命之花", 2, "通用", "relic", "diamond", {"def": 10}))
	out.append(_c("rel_planar", "次元球", 4, "崩坏本征", "relic", "diamond", {"def": 24}))
	out.append(_c("rel_drive_disc", "驱动盘·极地", 4, "绝区零", "relic", "diamond", {"def": 23}))
	out.append(_c("rel_old_gear", "旧齿轮", 1, "通用", "relic", "diamond", {"def": 5}))

	# ---------------- 道具（资源页） ----------------
	out.append(_c("item_currency_pack", "货币袋", 2, "通用", "item", "circle", {"give": {"currency": 800.0}}))
	out.append(_c("item_food_pack", "干粮箱", 2, "通用", "item", "circle", {"give": {"food": 40.0}}))
	out.append(_c("item_prod_pack", "工具包", 2, "通用", "item", "circle", {"give": {"production": 30.0}}))
	out.append(_c("item_blueprint", "建筑图纸", 3, "通用", "item", "circle", {"give": {"production": 80.0}}))
	out.append(_c("item_research_note", "研究手稿", 3, "通用", "item", "circle", {"give": {"research": 25.0}}))
	out.append(_c("item_crystal", "秩序结晶碎块", 4, "通用", "item", "circle", {"give": {"order_crystal": 2.0}}))

	# ---------------- 材料（资源页） ----------------
	out.append(_c("mat_base_ore", "基础矿料", 2, "通用", "material", "hexagon", {"give": {"copper": 6.0}}))
	out.append(_c("mat_wood", "成材木", 2, "通用", "material", "hexagon", {"give": {"wood": 8.0}}))
	out.append(_c("mat_coal", "精煤", 2, "通用", "material", "hexagon", {"give": {"coal": 6.0}}))
	out.append(_c("mat_iron", "铁锭", 3, "通用", "material", "hexagon", {"give": {"iron": 4.0}}))
	out.append(_c("mat_oil", "原油桶", 3, "通用", "material", "hexagon", {"give": {"oil": 3.0}}))

	# 高级材料：只在对应卡组轮换期间可抽出
	out.append(_c("adv_geo_gem", "岩元素宝石", 4, "提瓦特", "advanced", "star", {"give": {"crystal_shard": 2.0}}))
	out.append(_c("adv_honkai_core", "崩坏核心", 4, "崩坏本征", "advanced", "star", {"give": {"crystal_shard": 2.0}}))
	out.append(_c("adv_ether_gel", "以太凝胶", 4, "绝区零", "advanced", "star", {"give": {"crystal_shard": 2.0}}))
	out.append(_c("adv_weekly", "周本材料", 5, "通用", "advanced", "star", {"give": {"crystal_shard": 5.0, "research": 60.0}}))

	# ---------------- 功能（发展页） ----------------
	out.append(_c("fn_resource_node", "资源地脉", 4, "通用", "function", "hexagon", {"spawn_resource": 1}))
	out.append(_c("fn_high_node", "高级资源地脉", 5, "通用", "function", "star", {"spawn_resource": 2}))
	out.append(_c("fn_genesis_crystal", "创世结晶", 5, "提瓦特", "function", "star", {"tech": "genesis_crystal"}))
	out.append(_c("fn_elem_leyline", "元素地脉", 3, "提瓦特", "function", "circle", {"regen": "crystal_shard"}))
	out.append(_c("fn_tech_scroll", "古代技术卷轴", 3, "通用", "function", "square", {"research": 120.0}))
	out.append(_c("fn_camp_upgrade", "营地扩建许可", 4, "通用", "function", "square", {"expand_map": 1}))

	# ---------------- 终局威胁（发展页必定产出） ----------------


static func _c(id: String, name: String, rarity: int, group: String, pool: String,
		kind: String, extra: Dictionary) -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"rarity": rarity,
		"group": group,
		"pool": pool,
		"kind": kind,
	}
	d.merge(extra, true)
	return d


## 按卡池类型筛选
## v1.7：按 id 取一张卡（格蕾修的数值统一从这里取，不再在别处抄一份）
static func find(id: String) -> Dictionary:
	for c in all():
		if str(c.get("id", "")) == id:
			return c
	return {}


static func by_pool(cards: Array[Dictionary], pool: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cards:
		if c["pool"] == pool:
			out.append(c)
	return out


## 轮换页可抽：角色 + 武装 + 战备
static func rotation_cards(cards: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cards:
		if c["pool"] in ["character", "weapon", "relic"]:
			out.append(c)
	return out


## 资源页可抽：道具 + 材料 + 高级材料（高级材料受当前卡组限制）
static func resource_cards(cards: Array[Dictionary], active_group: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in cards:
		if c["pool"] in ["item", "material"]:
			out.append(c)
		elif c["pool"] == "advanced":
			if c["group"] == "通用" or c["group"] == active_group:
				out.append(c)
	return out


## 发展页可抽：功能
static func development_cards(cards: Array[Dictionary]) -> Array[Dictionary]:
	return by_pool(cards, "function")


## 几何形状 -> 用于绘制的点（单位正方形内 -1..1）
static func shape_points(kind: String) -> PackedVector2Array:
	match kind:
		"triangle":
			return PackedVector2Array([Vector2(0, -1), Vector2(0.9, 0.75), Vector2(-0.9, 0.75)])
		"square":
			return PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)])
		"diamond":
			return PackedVector2Array([Vector2(0, -1), Vector2(0.85, 0), Vector2(0, 1), Vector2(-0.85, 0)])
		"hexagon":
			var pts := PackedVector2Array()
			for i in 6:
				var a := deg_to_rad(60.0 * float(i) - 90.0)
				pts.append(Vector2(cos(a), sin(a)))
			return pts
		"star":
			var sp := PackedVector2Array()
			for i in 10:
				var a2 := deg_to_rad(36.0 * float(i) - 90.0)
				var rr := 1.0 if i % 2 == 0 else 0.45
				sp.append(Vector2(cos(a2), sin(a2)) * rr)
			return sp
		"line":
			return PackedVector2Array([Vector2(-1.0, -0.22), Vector2(1.0, -0.22), Vector2(1.0, 0.22), Vector2(-1.0, 0.22)])
		_:
			var cp := PackedVector2Array()
			for i in 20:
				var a3 := TAU * float(i) / 20.0
				cp.append(Vector2(cos(a3), sin(a3)))
			return cp