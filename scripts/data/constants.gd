class_name Consts
extends RefCounted
## 全局常量与公式参数。
## 数值来源于设计文档《抽卡文明》，凡是文档未写明的部分都用「演示用」占位值。


const RARITY_NAMES := {
	1: "普通",
	2: "优良",
	3: "稀有",
	4: "史诗",
	5: "传说",
}

## 稀有度 -> 颜色（没有美术资源，用几何色块区分）
const RARITY_COLORS := {
	1: Color(0.62, 0.62, 0.66),
	2: Color(0.38, 0.75, 0.45),
	3: Color(0.35, 0.58, 0.92),
	4: Color(0.72, 0.45, 0.90),
	5: Color(0.95, 0.76, 0.30),
}

# ---------------------------------------------------------------------------
# 资源标识
# ---------------------------------------------------------------------------
const RES_KEYS: Array[String] = [
	"food", "production", "currency", "research",
	"order_crystal", "cohesion", "admin",
	"wood", "coal", "copper", "iron", "oil", "crystal_shard",
]

const RES_NAMES := {
	"food": "食物",
	"production": "生产力",
	"currency": "货币",
	"research": "科研点",
	"order_crystal": "秩序结晶",
	"cohesion": "凝聚力",
	"admin": "行政点数",
	"wood": "木材",
	"coal": "煤",
	"copper": "铜矿",
	"iron": "铁矿",
	"oil": "原油",
	"crystal_shard": "水晶碎屑",
}

## 只能通过发展系统在大世界生成资源点的高级资源
const ADVANCED_RESOURCES: Array[String] = ["iron", "oil"]

# ---------------------------------------------------------------------------
# 人力
# ---------------------------------------------------------------------------
const POP_START := 3
const POP_HARD_CAP := 40
## 保底人口：稳定度再低也不会把人打到这个数以下（避免 Demo 死亡螺旋）
const POP_FLOOR := 2
## 不建民居时的基础住房上限（营地本身能容纳的人数）
const BASE_HOUSING := 6
## 每块领地提供的住房上限
const HOUSING_PER_TILE := 1
## 经典民居每级提供的住房上限
const HOUSING_PER_HOUSE_LEVEL := 4
## 每个未指派人力每周期消耗的食物
const FOOD_UPKEEP_PER_POP := 0.5

# ---------------------------------------------------------------------------
# 稳定度（文档公式）
#   稳定度 = ((玩家总战斗力 / 敌人总战斗力) * (空白格子数 / (空白格子数 + 1)))
#            * (1 - (敌人数量 / 地图总格子数) * 0.5)
# ---------------------------------------------------------------------------
const STABILITY_MIN_BLOCK := 0.10   ## 低于 10% 无法进行世界泡操作
const FREE_TILE_MIN_BLOCK := 10     ## 无主地块低于 10 个无法进行世界泡操作

# ---------------------------------------------------------------------------
# 地块 / 扩张
# ---------------------------------------------------------------------------
const MAP_START_RADIUS := 21         ## 半径 21 的六边形地图，直径 43 格（约 1387 格）
const MAP_MAX_RADIUS := 30           ## 上限必须大于初始半径，否则「扩建地图」永远扩不动

const CAMP_START_RADIUS := 3         ## 初始点亮范围（保证有足够的无主地块可供扩张与操作限制判定）
## v1.3.1：扩张改用「行政点数」，并受行政影响力折扣
const CLAIM_BASE_COST := 10.0        ## 占领一块无主地块的行政点数基础消耗

## 资源表（**唯一来源**）：顶部资源栏与「统计」面板都从这里取，避免两处口径对不上。
## 每项 = [资源键, 显示名, 颜色]。想加资源：加进对应组，资源栏与统计面板会一起生效。
## 注意："pop"（人力）不是产出资源 —— 它受住房上限约束，两边都要特殊处理。
const RES_ABSTRACT := [
	["production", "生产力", Color(0.90, 0.72, 0.35)],
	["research", "科研点", Color(0.55, 0.75, 0.98)],
	["admin", "行政点数", Color(0.80, 0.85, 0.55)],
	["order_crystal", "秩序结晶", Color(0.75, 0.60, 0.98)],
	["cohesion", "凝聚力", Color(0.98, 0.60, 0.75)],
	["pop", "人力", Color(0.85, 0.90, 1.0)],
]
const RES_CONCRETE := [
	["food", "食物", Color(0.55, 0.85, 0.45)],
	["currency", "货币", Color(0.95, 0.85, 0.45)],
	["wood", "木材", Color(0.7, 0.72, 0.78)],
	["coal", "煤", Color(0.7, 0.72, 0.78)],
	["copper", "铜矿", Color(0.7, 0.72, 0.78)],
	["iron", "铁矿", Color(0.7, 0.72, 0.78)],
	["oil", "原油", Color(0.7, 0.72, 0.78)],
	["crystal_shard", "水晶碎屑", Color(0.7, 0.72, 0.78)],
]
const CLAIM_COST_PER_TILE := 2.0
## 每块领地每个周期提供的基础生产力（让扩张本身有正收益）
const PRODUCTION_PER_TILE := 0.6

## v1.8.21：地形 = 地表形态（地貌）。森林/草地这类"地表覆盖物"归**地物**，见下面的 COVER_*。
const TERRAIN_NAMES := {
	"water": "水域",
	"plain": "平原",
	"hill": "丘陵",
	"mountain": "山脉",
	"dune": "沙丘",
	"wasteland": "荒地",
	"forest": "树林",   # 旧档遗留：森林已改归「地物」，这条只为老档不至于显示成洋红
}

const TERRAIN_COLORS := {
	"water": Color(0.16, 0.28, 0.46),
	"plain": Color(0.30, 0.42, 0.26),
	"hill": Color(0.40, 0.36, 0.28),
	"mountain": Color(0.48, 0.46, 0.44),
	"dune": Color(0.58, 0.50, 0.32),
	"wasteland": Color(0.34, 0.28, 0.26),
	"forest": Color(0.16, 0.32, 0.20),   # 旧档遗留，同上
}

## v1.8.21：地物 = 地表覆盖物（叠在地形之上的一层）。空串 = 裸地。
const COVER_NAMES := {
	"": "裸地",
	"grass": "草地",
	"forest": "森林",
	"swamp": "沼泽",
}

const COVER_COLORS := {
	"grass": Color(0.44, 0.60, 0.30),
	"forest": Color(0.14, 0.34, 0.20),
	"swamp": Color(0.26, 0.36, 0.28),
}


# ---------------------------------------------------------------------------
# 战斗（演示用简化数值）
# ---------------------------------------------------------------------------
const FORCE_PER_POP := 1.0
const FORCE_PER_TILE := 2.0
## 敌人地块上限：随我方领地数量增长，避免「稳定度死亡螺旋」把 Demo 卡死
const ENEMY_CAP_BASE := 4
const ENEMY_CAP_PER_OWNED := 0.5
const ENEMY_CAP_PER_CYCLE := 0.1
## 清剿敌人：需要多少战斗力才能打下一块敌方地块
const CLEAR_FORCE_PER_ENEMY := 1.25

## 每级每周期的基础维护消耗（演示用，避免无限滚雪球）
const BUILDING_UPKEEP_PRODUCTION := 0.25

# ---------------------------------------------------------------------------
# v1.3.1 土地（地块计容）
# ---------------------------------------------------------------------------
## 每个地块的可用土地上限（默认 1.0，未来由科技树提升）
const LAND_CAP_DEFAULT := 1.0

# ---------------------------------------------------------------------------
# v1.3.1 建造队列 / 生产力盈余
# ---------------------------------------------------------------------------
## 生产力「盈余存储」上限：无队列需求时多出来的生产力最多存这么多，超出作废
const PRODUCTION_STORE_CAP := 20.0

# ---------------------------------------------------------------------------
# v1.4 存储上限与资源分类
# ---------------------------------------------------------------------------
## 科研点上限（须 >= 120，保证「炼金-黑土」可研）
const RESEARCH_STORE_CAP := 200.0
## 具体资源默认存储上限（货币除外）
const STORAGE_CAP_CONCRETE := 100.0
## 经典仓储每级提升的具体资源上限
const WAREHOUSE_CAP_PER_LEVEL := 50.0

## 具体资源里「有存储上限」的（= 具体资源去掉货币）
const CAPPED_CONCRETE: Array[String] = [
	"food", "wood", "coal", "copper", "iron", "oil", "crystal_shard",
]

# ---------------------------------------------------------------------------
# v1.3.1 行政点数（扩张货币 + 未来多据点）
#   基底每周期 +1，永久；其余来源都是限时 buff（state["admin_effects"]）。
# ---------------------------------------------------------------------------
const ADMIN_BASE_PER_CYCLE := 1.0        ## 每周期固定基底产出
const ADMIN_PER_POSITIVE_LINE := 0.1     ## 每条「正收支」额外 +0.1
const ADMIN_PER_NEGATIVE_LINE := 0.1     ## 每条「0/负收支」额外 -0.1
## 击杀奖励：敌人类型 -> {delta, duration}
const ADMIN_KILL_BUFFS := {
	"danger": {"delta": 0.1, "duration": 15},    # 危险敌人
	"high": {"delta": 0.2, "duration": 30},      # 高危敌人（高危游荡敌人）
	"fortress": {"delta": 0.5, "duration": 50},  # 高危据点（极度高危据点）
	"threat": {"delta": 1.0, "duration": 100},   # 终极威胁
}
## 友军阵亡惩罚：位阶 -> {delta, duration}
const ADMIN_DEATH_DEBUFFS := {
	"recruit": {"delta": 0.1, "duration": 15},   # 募集军
	"regular": {"delta": 0.2, "duration": 30},   # 正规军
	"hero": {"delta": 0.5, "duration": 50},      # 角色
}
## 行政影响力：行政点数越多，扩张等行政消耗越低（折扣 = 点数 × 系数，封顶）
const ADMIN_INFLUENCE_PER_POINT := 0.01
const ADMIN_INFLUENCE_MAX := 0.5

# ---------------------------------------------------------------------------
# v1.3.1 掌控力（预留接口，本版不接行为；单据点下恒 100%）
# ---------------------------------------------------------------------------
const CONTROL_SELF_OPERATE := 0.80    ## 低于此线：小操作据点自行处理

# ---------------------------------------------------------------------------
# v1.5 单位：客人 / 公民、维护费、移动力、点击权重
# ---------------------------------------------------------------------------
## 客人（召唤来的个体，暂时以客人身份存在）
const GUEST_COHESION_PER_CYCLE := 0.1  ## 每个客人每周期提供的凝聚力
const GUEST_FOOD_PER_CYCLE := 0.1      ## 每个客人每周期消耗的食物
const GUEST_LEAVE_FROM_CYCLE := 15     ## 超过 15 个周期未招募的客人开始有概率离去
const GUEST_LEAVE_STEP_MIN := 0.001    ## 每周期离去概率自增下限（0.1%）
const GUEST_LEAVE_STEP_MAX := 0.010    ## 每周期离去概率自增上限（1.0%）

## 公民单位的周期维护费
const UNIT_UPKEEP_FOOD := 0.5
const UNIT_UPKEEP_CURRENCY := 3.0
const UPKEEP_MUL_IN_TERRITORY := 0.4   ## 驻守我方领地：维护费 −60%
const UPKEEP_MUL_OUTSIDE := 0.9        ## 在领地之外：维护费 −10%

## 移动：2 移动速度 = 1 移动力
const MOVE_PER_SPEED := 2
const MOVE_COST_NEAR := 1              ## 移动到相邻格
const MOVE_COST_FAR := 2               ## 间隔一格的跳跃


# ---------------------------------------------------------------------------
# 世界泡货币的周期结算
#   秩序结晶：根据玩家等级每周期结算给予
#   凝聚力：幸福程度给予数值，文化率给予倍率
# ---------------------------------------------------------------------------
const CRYSTAL_PER_CYCLE := 1.2          ## 每个周期的基础秩序结晶
const CRYSTAL_PER_LEVEL := 0.4          ## 每级追加
const COHESION_PER_CYCLE := 26.0        ## 每周期基础凝聚力
const COHESION_PER_HAPPINESS := 0.9     ## 幸福度（数值）换算
const COHESION_CULTURE_BONUS := 1.0     ## 文化率作为倍率的上限加成（倍率 = 1 + 文化率 * 该系数）

# ---------------------------------------------------------------------------
# 世界泡（v1.5：三个子系统 = 召唤 / 打捞 / 发展）
# ---------------------------------------------------------------------------
const DRAW_COST_COHESION := 160.0     ## 召唤系统：消耗凝聚力
const DRAW_COST_CRYSTAL := 1.0        ## 打捞系统：消耗秩序结晶

## 各稀有度基础权重
const RARITY_WEIGHTS := {1: 68.0, 2: 26.0, 3: 5.0, 4: 0.9, 5: 0.1}

## 软保底：标准池 60 抽后 5★ 权重开始爬升；90 抽硬保底
const PITY_SOFT := 60
const PITY_HARD := 90
## 打捞池保底（材料池，只需要 4★ 保底）
const PITY_SOFT_RES := 30
const PITY_HARD_RES := 50

# ---------------------------------------------------------------------------
# 高危据点 / 游荡敌人 / 终极威胁
# ---------------------------------------------------------------------------
const HAZARD_BASE_CHANCE := 0.04      ## 每次打捞的初始概率
const HAZARD_CHANCE_PER_DRAW := 0.005 ## 每次未触发则累加
const HAZARD_PITY := 10               ## 生成 10 次高危据点后必定生成极度高危据点
const WANDER_BASE_CHANCE := 0.30      ## 每次召唤生成游荡敌人的概率（大概率、不变化）
const WANDER_PITY := 90               ## 90 次游荡敌人后必定生成高危游荡敌人
## v1.7：敌人分类的显示名 —— **唯一的词表**（地图标签 / 日志 / 作弊列表都从这里取）
const ENEMY_LABELS := {
	"threat": "终极威胁",
	"fortress": "极度高危据点",
	"danger": "高危据点",
	"high": "高危游荡敌人",
	"wander": "游荡敌人",
	"unknown": "敌人",
}

## v1.7：敌人在战斗中的换算系数（集中一处，便于调平衡；以前散落在 5 个地方写魔数）
const ENEMY_ATK_MUL := 0.5        ## 敌人攻击力 = 地块 force × 此系数
const ENEMY_ATK_MUL_LOW := 0.45   ## 敌人反击时的攻击力系数（略低）
const ENEMY_DEF_MUL := 0.3        ## 敌人防御力 = 地块 force × 此系数
const ENEMY_HP_MUL := 2.0         ## 敌人总血量 = 地块 force × 此系数
const HAZARD_FORCE := 12.0
const WANDER_FORCE := 5.0
const EXTREME_HAZARD_FORCE := 30.0
const HIGH_WANDER_FORCE := 18.0

## 终极威胁：生成后 (W) 个周期内在无主地块游荡，之后直扑首都
const THREAT_WANDER_CYCLES := 6
const THREAT_FORCE := 90.0

# ---------------------------------------------------------------------------
# 版本
# ---------------------------------------------------------------------------
const DEMO_VERSION := "v1.8.21"
const DEMO_VERSION_FULL := "抽卡文明 Demo v1.8.21（量子之海 · 黑体 UI · 首套资源图标 · 真实地形）"

## v1.5：免责声明（主菜单左下角 + 反馈弹窗各一处）
const DISCLAIMER_TEXT := "本作为非官方同人作品，与米哈游无关，仅供非商业交流。"

# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------
const SAVE_DIR := "user://saves"
const SAVE_SLOTS := 10
## 自动存档槽 = 0 号。
##    **0 号槽由自动化测试使用** 
##    所以**不要把重要存档放在 0 号**；正常游玩请存 5 / 8 / 9 号之类。
##    这是**刻意的约定，不是 bug**（用户决定：不去改测试，改为明确约定）。
##    详见 docs/更新指导/v1.8.1b-测试无害化.md
const AUTOSAVE_SLOT := 0
## v1.2：自动存档周期数，默认每 1 个周期存档一次，玩家可在设置里自定义
const AUTOSAVE_INTERVAL_DEFAULT := 1
const AUTOSAVE_INTERVAL_MIN := 1
const AUTOSAVE_INTERVAL_MAX := 50

# ---------------------------------------------------------------------------
# 反馈与作弊（v1.2）
# ---------------------------------------------------------------------------
const FEEDBACK_QQ_GROUP := "625366551"
const FEEDBACK_EMAIL := "3462323439@qq.com"

# ---------------------------------------------------------------------------
# 科技树（演示用：只做文档里出现的两条线）
# ---------------------------------------------------------------------------
const TECHS := [
	{
		"id": "mining",
		"name": "开采",
		"era": "远古时代",
		"prereq": [],
		"cost": 5.0,
		"unlocks": ["classic_mine"],
		"desc": "前置：无。解锁建筑：经典矿场。",
	},
	{
		"id": "alchemy_black_soil",
		"name": "炼金-黑土",
		"era": "七神时代",
		"prereq": ["genesis_crystal"],
		"cost": 120.0,
		"unlocks": ["black_soil_academy", "alchemy_lab"],
		"desc": "前置：创世结晶（由发展系统获得）。解锁建筑：黑土学院、炼金所。",
	},
]


static func res_name(key: String) -> String:
	return RES_NAMES.get(key, key)


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS.get(r, Color.WHITE)


static func rarity_name(r: int) -> String:
	return RARITY_NAMES.get(r, "?")


static func terrain_color(t: String) -> Color:
	return TERRAIN_COLORS.get(t, Color.MAGENTA)


static func terrain_name(t: String) -> String:
	return TERRAIN_NAMES.get(t, t)


## v1.8.21：地物取色/取名。空串 = 裸地，取色返回全透明（表示"不叠加"）。
static func cover_color(c: String) -> Color:
	return COVER_COLORS.get(c, Color(0, 0, 0, 0))


static func cover_name(c: String) -> String:
	return COVER_NAMES.get(c, c)
