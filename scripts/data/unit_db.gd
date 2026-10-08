class_name UnitDB
extends RefCounted
## 单位系统数据（v1.1 更新指导）。
##
## 新增两套属性：
##   · 职业：决定克制关系 —— 近身战士 / 远身战士 / 投射者 / 防御者 / 支援者
##   · 位阶：决定战斗时的属性倍率 —— 募集军 / 正规军 / 角色
## 以及经验值：位阶内倍率由经验进度决定，周期循环最多贡献 100 点经验。

# ---------------------------------------------------------------------------
# v1.5：单位状态（客人 / 公民）
# ---------------------------------------------------------------------------
const STATUS_GUEST := "guest"
const STATUS_CITIZEN := "citizen"

static func status_name(s: String) -> String:
	return "客人" if s == STATUS_GUEST else "公民"


# ---------------------------------------------------------------------------
# v1.7：单位立绘
# ---------------------------------------------------------------------------
## key = 卡 id（每个单位的 `u["id"]`，由 from_card 从卡池带过来，所以不需要额外字段）。
## 只有做了美术的单位才在这里登记；没登记的由调用方回退到 GeoIcon 几何占位，
## 所以删掉某个单位的图也不会崩，只是回到占位。
const ART := {
	"char_grieso": {
		"portrait": "res://art/units/grieso/portrait.png",  # 角色页大立绘 190x170
		"icon": "res://art/units/grieso/icon.png",          # 单位操作窗 60x60
		"chip": "res://art/units/grieso/chip.png",          # 底部单位条 28x28
	},
}

static var _art_cache: Dictionary = {}


## 取单位立绘。没有对应美术时返回 null（调用方回退）。
static func art_of(u: Dictionary, slot: String = "portrait") -> Texture2D:
	var key := str(u.get("id", ""))
	var ck := "%s/%s" % [key, slot]
	if _art_cache.has(ck):
		return _art_cache[ck]
	var rec: Dictionary = ART.get(key, {})
	var path := str(rec.get(slot, ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_art_cache[ck] = tex
	return tex


# ---------------------------------------------------------------------------
# 职业
# ---------------------------------------------------------------------------
const MELEE := "melee"
const RANGED := "ranged"
const PROJECTILE := "projectile"
const DEFENDER := "defender"
const SUPPORT := "support"

const PROFESSION_ORDER: Array[String] = [MELEE, RANGED, PROJECTILE, DEFENDER, SUPPORT]

const PROFESSIONS := {
	MELEE: {
		"name": "近身战士",
		"icon": "triangle",
		"color": Color(0.92, 0.45, 0.38),
		"counters": [DEFENDER, SUPPORT],
		"range": 1,
		"desc": "利用格斗术或匕首刀剑的战士，在复杂环境下具备灵活性。克制防御者和支援者。",
	},
	RANGED: {
		"name": "远身战士",
		"icon": "square",
		"color": Color(0.95, 0.75, 0.35),
		"counters": [MELEE, DEFENDER],
		"range": 1,
		"desc": "使用长枪或大剑的战士，能通过武器控制距离、阻止近身。克制近身战士和防御者。",
	},
	PROJECTILE: {
		"name": "投射者",
		"icon": "line",
		"color": Color(0.55, 0.80, 0.95),
		"counters": [MELEE, RANGED],
		"range": 2,
		"desc": "使用枪械或弓弩的战士，能够在间隔一个格子的情况下伤害到其他单位。克制近身战士和远身战士。",
	},
	DEFENDER: {
		"name": "防御者",
		"icon": "hexagon",
		"color": Color(0.45, 0.85, 0.55),
		"counters": [],
		"range": 1,
		"desc": "以抵抗或帮助友军阻止敌人远程投送武力，小幅度减免所在格子及队伍中单位所受伤害，大幅度减免投射者造成的伤害。",
	},
	SUPPORT: {
		"name": "支援者",
		"icon": "star",
		"color": Color(0.80, 0.60, 0.95),
		"counters": [],
		"range": 1,
		"desc": "不直接造成伤害，而是根据条件增幅特定单位的伤害或提供减免。",
	},
}

## 为召唤角色预留的独特机制接口（v1.1 文档第 19 条）
const UNIQUE_HOOKS := {
	"charge": "蓄力：下一回合伤害翻倍",
	"pierce": "贯穿：伤害无视目标 50% 防御",
	"guard_aura": "守护领域：相邻友军受到的伤害 -20%",
	"volley": "齐射：同时攻击目标及其相邻的一个敌人",
	"revive_once": "不灭：首次阵亡时以 30% 生命复活",
}

# ---------------------------------------------------------------------------
# 位阶
# ---------------------------------------------------------------------------
const RECRUIT := "recruit"
const REGULAR := "regular"
const HERO := "hero"

const RANK_ORDER: Array[String] = [RECRUIT, REGULAR, HERO]

const RANKS := {
	RECRUIT: {
		"name": "募集军",
		"icon": "diamond",
		"color": Color(0.70, 0.72, 0.78),
		"exp_cap": 100,
		"mul_min": 0.6,
		"mul_max": 0.8,
		"desc": "刚招募的军队单位，对战斗并不熟练，甚至常常犯错，因此倍率可能为负修正。经验值上限 100 点。",
	},
	REGULAR: {
		"name": "正规军",
		"icon": "hexagon",
		"color": Color(0.55, 0.80, 0.95),
		"exp_cap": 200,
		"mul_min": 0.8,
		"mul_max": 1.1,
		"desc": "招募已久、训练已久，或短时间经历过惨烈战斗的单位，有丰富的战斗经验，不会再犯低级错误。经验值上限 200 点。",
	},
	HERO: {
		"name": "角色",
		"icon": "star",
		"color": Color(0.95, 0.78, 0.35),
		"exp_cap": 500,
		"mul_min": 1.0,
		"mul_max": 2.0,
		"desc": "通过特殊事件转换或召唤获得的单位，具备独特性；在世界的眷顾下不会产生负修正。经验值上限 500 点。",
	},
}

## 单位占用地块/队伍的容量上限
const UNITS_PER_TILE := 4
const UNITS_PER_TEAM := 4
## 周期循环最多能贡献的经验
const EXP_FROM_CYCLES_CAP := 100
## 每个周期自然增长的经验
const EXP_PER_CYCLE := 2


static func profession_name(p: String) -> String:
	return str((PROFESSIONS.get(p, {}) as Dictionary).get("name", p))


static func profession_color(p: String) -> Color:
	return (PROFESSIONS.get(p, {}) as Dictionary).get("color", Color.WHITE)


static func profession_icon(p: String) -> String:
	return str((PROFESSIONS.get(p, {}) as Dictionary).get("icon", "circle"))


static func profession_desc(p: String) -> String:
	return str((PROFESSIONS.get(p, {}) as Dictionary).get("desc", ""))


static func rank_name(r: String) -> String:
	return str((RANKS.get(r, {}) as Dictionary).get("name", r))


static func rank_color(r: String) -> Color:
	return (RANKS.get(r, {}) as Dictionary).get("color", Color.WHITE)


static func rank_icon(r: String) -> String:
	return str((RANKS.get(r, {}) as Dictionary).get("icon", "circle"))


static func rank_desc(r: String) -> String:
	return str((RANKS.get(r, {}) as Dictionary).get("desc", ""))


static func exp_cap(r: String) -> int:
	return int((RANKS.get(r, {}) as Dictionary).get("exp_cap", 100))


# ---------------------------------------------------------------------------
# 位阶倍率：由位阶区间 + 经验进度插值得到
# ---------------------------------------------------------------------------
## exp_progress: 0.0 ~ 1.0（经验 / 该位阶经验上限）
static func rank_multiplier(rank: String, exp_progress: float) -> float:
	var def: Dictionary = RANKS.get(rank, RANKS[RECRUIT])
	var lo := float(def["mul_min"])
	var hi := float(def["mul_max"])
	return lerpf(lo, hi, clampf(exp_progress, 0.0, 1.0))


## 单个单位的经验进度
static func progress_of(unit: Dictionary) -> float:
	var rank := str(unit.get("rank", RECRUIT))
	var cap := maxi(1, exp_cap(rank))
	return clampf(float(unit.get("exp", 0)) / float(cap), 0.0, 1.0)


## 位阶晋升链
static func next_rank(rank: String) -> String:
	match rank:
		RECRUIT: return REGULAR
		REGULAR: return HERO
		_: return ""


## 是否可以晋升（经验满且还有更高位阶）
static func can_promote(unit: Dictionary) -> bool:
	var rank := str(unit.get("rank", RECRUIT))
	if next_rank(rank) == "":
		return false
	return int(unit.get("exp", 0)) >= exp_cap(rank)


# ---------------------------------------------------------------------------
# 克制关系
# ---------------------------------------------------------------------------
## a 是否克制 b
static func counters(a: String, b: String) -> bool:
	var def: Dictionary = PROFESSIONS.get(a, {})
	return (def.get("counters", []) as Array).has(b)


## 攻方对守方的克制结果：+1 克制 / -1 被克制 / 0 无关系
static func advantage(attacker: String, defender: String) -> int:
	if counters(attacker, defender):
		return 1
	if counters(defender, attacker):
		return -1
	return 0


# ---------------------------------------------------------------------------
# 单位工厂
# ---------------------------------------------------------------------------
## 从卡池的「角色」条目创建单位
static func from_card(card: Dictionary) -> Dictionary:
	var uid := "u_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	var u := {
		"uid": uid,
		"id": str(card["id"]),
		"name": str(card["name"]),
		"rarity": int(card["rarity"]),
		"group": str(card.get("group", "通用")),
		"kind": str(card.get("kind", "circle")),
		"unit_type": str(card.get("unit_type", "character")),  # character / trained / recruit
		"profession": str(card.get("profession", MELEE)),
		"rank": str(card.get("rank", HERO)),
		"exp": 0,
		"exp_from_cycles": 0,
		"exp_from_combat": 0,
		"level": 1,
		"star": int(card["rarity"]),
		"attr": _attr_of(card),
		"equipped": {"weapon": "", "relic": ""},
		"skills": [],
		"unique": [],           # 预留的独特机制接口
		"team": -1,             # 所属队伍（-1 = 未编队）
		"tile": "",             # 驻守地块（空 = 未派驻）
		# v1.5：客人 / 公民 + 战斗与移动状态
		"status": STATUS_GUEST,
		"acquired_cycle": 0,    # 召唤所在周期（由 GameState 落库时填）
		"leave_chance": 0.0,    # 客人累计离去概率
		"hp": 0,                # 当前血量（下方按满血初始化）
		"move_left": 0,
		"garrisoned": false,    # v1.6.1：是否驻军（驻军打折维护费，但不能行动）
	}
	u["hp"] = max_hp(u)
	return u


## 创建募集军 / 正规军这类非召唤单位
static func make_soldier(unit_type: String, profession: String, rank: String,
		name_text: String, rarity: int = 1) -> Dictionary:
	var u := {
		"uid": "s_%d_%d" % [Time.get_ticks_usec(), randi() % 100000],
		"id": unit_type,
		"name": name_text,
		"rarity": rarity,
		"group": "通用",
		"kind": PROFESSIONS[profession]["icon"] if PROFESSIONS.has(profession) else "circle",
		"unit_type": unit_type,
		"profession": profession,
		"rank": rank,
		"exp": 0,
		"exp_from_cycles": 0,
		"exp_from_combat": 0,
		"level": 1,
		"star": rarity,
		"attr": _base_attr_for(profession, rank),
		"equipped": {"weapon": "", "relic": ""},
		"skills": [],
		"unique": [],
		"team": -1,
		"tile": "",
		# v1.5：本土征兵即公民
		"status": STATUS_CITIZEN,
		"acquired_cycle": 0,
		"leave_chance": 0.0,
		"hp": 0,
		"move_left": 0,
		"garrisoned": false,
	}
	u["hp"] = max_hp(u)
	return u


static func _attr_of(card: Dictionary) -> Dictionary:
	var out := {}
	for k in ["atk", "def", "hp", "spd", "agi"]:
		if card.has(k):
			out[k] = int(card[k])
	return out


## 非召唤单位的基准属性（位阶越低基础越弱，再叠加位阶倍率）
static func _base_attr_for(profession: String, rank: String) -> Dictionary:
	var base := {"atk": 18, "def": 12, "hp": 140, "spd": 3, "agi": 10}
	match profession:
		MELEE:
			base = {"atk": 24, "def": 12, "hp": 150, "spd": 4, "agi": 14}
		RANGED:
			base = {"atk": 26, "def": 10, "hp": 140, "spd": 3, "agi": 12}
		PROJECTILE:
			base = {"atk": 22, "def": 8, "hp": 120, "spd": 3, "agi": 16}
		DEFENDER:
			base = {"atk": 14, "def": 24, "hp": 200, "spd": 2, "agi": 8}
		SUPPORT:
			base = {"atk": 8, "def": 14, "hp": 150, "spd": 3, "agi": 12}
	var scale := 1.0
	if rank == REGULAR:
		scale = 1.25
	elif rank == HERO:
		scale = 1.6
	var out := {}
	for k in base.keys():
		out[k] = int(round(float(base[k]) * scale))
	return out


# ---------------------------------------------------------------------------
# 战斗属性计算（含位阶倍率）
# ---------------------------------------------------------------------------
## 返回经过位阶倍率修正后的属性
static func effective_attr(unit: Dictionary) -> Dictionary:
	var mul := rank_multiplier(str(unit.get("rank", RECRUIT)), progress_of(unit))
	var lv := maxi(1, int(unit.get("level", 1)))
	var lv_mul := 1.0 + float(lv - 1) * 0.04
	var out := {}
	var attr: Dictionary = unit.get("attr", {})
	for k in attr.keys():
		out[k] = float(attr[k]) * mul * lv_mul
	return out


## 血量上限（含位阶与等级倍率）
static func max_hp(unit: Dictionary) -> int:
	return maxi(1, int(round(float(effective_attr(unit).get("hp", 1.0)))))


## 战斗力（用于稳定度公式里的角色战力贡献）
static func power_of(unit: Dictionary) -> float:
	var a := effective_attr(unit)
	return (float(a.get("atk", 0.0)) + float(a.get("def", 0.0)) * 0.6
		+ float(a.get("hp", 0.0)) * 0.12) * 0.5


## 伤害结算（含克制与防御者减免）
## 返回 { damage, advantage, mitigated }
static func resolve_damage(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var aa := effective_attr(attacker)
	var da := effective_attr(defender)
	var atk := float(aa.get("atk", 1.0))
	var dfn := float(da.get("def", 0.0))
	var adv := advantage(str(attacker.get("profession", MELEE)),
		str(defender.get("profession", MELEE)))
	# 克制：+30% / -20%
	var adv_mul := 1.0
	if adv > 0:
		adv_mul = 1.3
	elif adv < 0:
		adv_mul = 0.8
	# 防御者的大幅度投射者减免
	var prof_d := str(defender.get("profession", MELEE))
	var prof_a := str(attacker.get("profession", MELEE))
	var mit := 0.0
	if prof_d == DEFENDER:
		mit = 0.2
		if prof_a == PROJECTILE:
			mit = 0.6      # 大幅度减免投射者伤害
	var raw := atk * adv_mul * (1.0 - mit)
	var dmg := maxf(1.0, raw - dfn * 0.5)
	return {"damage": dmg, "advantage": adv, "mitigated": mit, "attack": atk, "defense": dfn}


# ---------------------------------------------------------------------------
# 单位分类
# ---------------------------------------------------------------------------
static func unit_type_name(t: String) -> String:
	match t:
		"character": return "角色"
		"trained": return "训练军"
		"recruit": return "募集军"
		_: return t
