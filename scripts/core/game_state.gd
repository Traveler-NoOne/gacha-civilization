extends Node
## 全局游戏状态（Autoload 单例名：GameState）
##
## 保存一份可序列化的存档状态，并实现文档中的核心循环：
##   周期结算 -> 建筑产出 -> 人口/幸福度/文化率 -> 稳定度 -> 敌人演化 -> 自动存档

## 检测状态是否改变
signal state_changed

## 全局轻提示广播
signal toast(text: String)

## 存档魔数
const SAVE_MAGIC := "gacha_civilization_demo"
## 存档时代
## 按既有决策：1.0 期不做旧档兼容 —— 版本不符直接拒绝（见 load_from_slot）。
## v5（2026-10-22）：世界生成器换代（旧 WorldGen 已删），地块数据全变 → 旧档一律作废 ✓
const SAVE_VERSION := 5


## 游戏状态
var state: Dictionary = {}
## 建筑表
var building_defs: Array[BuildingDef] = []
## 卡池表
var cards: Array[Dictionary] = []

## 非序列化的运行时缓存
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(Consts.SAVE_DIR) # 读取存档目录
	building_defs = BuildingDB.all() # 读取建筑
	cards = CardDB.all() # 读取卡池
	# v1.8.20.8：不再无条件 randomize —— 种子由 new_game() / load_from_slot() 按状态播，否则同种子复现不了。

	if state.is_empty(): # 如果存档槽为空，初始化新游戏
		new_game()

# ===========================================================================
# 新游戏
# ===========================================================================
func new_game(seed_value: int = 0) -> void:
	var s := int(seed_value)
	if s == 0:
		s = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	# v1.8.20.8：_rng 也按本局种子播（上面 s 为 0 时已取时钟种子，所以新开一局依旧是新的）。

	_rng.seed = s
	state = {

		"seed": s,
		"cycle": 1,
		"current_slot": -1,
		"res": {
			"food": 60.0, "production": 20.0, "currency": 300.0, "research": 0.0,
			"order_crystal": 0.0, "cohesion": 450.0,
			"wood": 10.0, "coal": 0.0, "copper": 0.0,
			"iron": 0.0, "oil": 0.0, "crystal_shard": 0.0,
		},
		"pop_total": Consts.POP_START,
		"tiles": {},          # "q,r" -> tile dict
		"capital": "0,0",
		"strongholds": [],    # v1.3.1 据点（据点可包含多个地块；本作仅首都）
		"admin_effects": [],  # v1.3.1 行政点数的限时 buff / debuff
		"units": [],          # v1.1 单位仓库（角色 / 训练军 / 募集军）
		"teams": [            # v1.1 队伍（每队最多 4 个单位）
			{"name": "第一队", "members": []},
			{"name": "第二队", "members": []},
			{"name": "第三队", "members": []},
		],
		"equipment": [],      # 抽到的武装 / 战备
		"items": {},          # 道具 / 材料统计
		"affinity": {"提瓦特": 0, "崩坏本征": 0, "绝区零": 0, "通用": 0},
		"active_group": "提瓦特",
		"group_rotate_day": 0,
		"techs": [],          # 已解锁科技 id
		"techs_owned_flags": [],  # 例如 genesis_crystal
		"log": [],
		"manual_log": [],
		"pity": {
			"rotation": {"since5": 0, "since4": 0, "total": 0},
			"resource": {"since4": 0, "total": 0},
			"development": {"total": 0},
		},
		"hazard": {"chance": Consts.HAZARD_BASE_CHANCE, "count": 0, "pity": 0},
		"wander": {"count": 0, "pity": 0},
		"threats": [],
		"training_queue": [],   # 训练槽位
		"task_groups": [],      # 任务组（文档「任务页」）
		"tasks": [],            # 进行中的任务
		"tasks_done": [],       # 档案：已完成的任务
		"_group_open": {},      # 任务组折叠状态（UI 用）
		"enemy_killed": 0,      # 击杀计数（任务目标用）
		"tutorial_skipped": true,
		"playtime": 0.0,
		# 注意：自动存档周期数与作弊开关是**全局设置**，
		# 存在 AppSettings（user://settings.cfg），不属于存档。
	}
	WorldgenBuilder.generate(state)
	TileManager.setup_new_world(state)
	Strongholds.setup_capital(state)
	_recompute_derived()
	Units.grant_starting(state)
	_add_log("建立部落，营地落在 %s。" % str(state["capital"]), "info")
	_add_log("初始点亮营地周围 %d 格，其余被迷雾覆盖。" % (1 + 6 * Consts.CAMP_START_RADIUS), "info")
	_setup_default_tasks()
	state_changed.emit()


# ===========================================================================
# 便捷访问
# ===========================================================================
func res(key: String) -> float:
	return float(state["res"].get(key, 0.0))


func add_res(key: String, amount: float) -> void:
	var r: Dictionary = state["res"]
	r[key] = float(r.get(key, 0.0)) + amount
	if r[key] < 0.0:
		r[key] = 0.0
	var cap := storage_cap(key)
	if cap >= 0.0 and r[key] > cap:
		r[key] = cap


## 某资源的存储上限；返回 -1 表示无上限（v1.4）
func storage_cap(key: String) -> float:
	match key:
		"production":
			return Consts.PRODUCTION_STORE_CAP
		"research":
			return Consts.RESEARCH_STORE_CAP
		"currency", "admin", "order_crystal", "cohesion":
			return -1.0
	if Consts.CAPPED_CONCRETE.has(key):
		return Consts.STORAGE_CAP_CONCRETE + warehouse_bonus()
	return -1.0


## 经典仓储带来的具体资源上限提升（v1.4）
func warehouse_bonus() -> float:
	var lv := 0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if str(b.get("id", "")) == "classic_warehouse":
				lv += int(b.get("level", 1))
	return float(lv) * Consts.WAREHOUSE_CAP_PER_LEVEL


func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if res(k) < float(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost.keys():
		add_res(k, -float(cost[k]))
	return true


## 文本形式的消耗，用于按钮提示
func cost_to_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost.keys():
		var v := float(cost[k])
		var t := Consts.res_name(k)
		parts.append("%s %.1f" % [t, v] if v != floorf(v) else "%s %d" % [t, int(v)])
	return "、".join(parts)


# ===========================================================================
# 派生数值
# ===========================================================================
func assigned_pop() -> int:
	var n := 0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			n += int(b.get("workers", 0))
	return n


func free_pop() -> int:
	return maxi(0, int(state["pop_total"]) - assigned_pop())


func housing_capacity() -> int:
	# 基础住房 + 每块领地若干 + 民居等级
	var cap := Consts.BASE_HOUSING + Consts.HOUSING_PER_TILE * TileManager.owned_tiles(state).size()
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if b.get("id", "") == "classic_house":
				cap += Consts.HOUSING_PER_HOUSE_LEVEL * int(b.get("level", 1))
	return mini(cap, Consts.POP_HARD_CAP)


func culture_rate() -> float:
	var c := 0.0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var def := BuildingDB.find(b.get("id", ""))
			if def == null:
				continue
			c += float(BuildingDB.meta_of(def, "culture", 0.0)) * float(b.get("level", 1))
	return c


## 幸福度是「基础 + 建筑 + 制度 - 民怨」
func happiness() -> float:
	var h := 50.0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var def := BuildingDB.find(b.get("id", ""))
			if def == null:
				continue
			var lv := int(b.get("level", 1))
			if def.id == "classic_house":
				h += _housing_happiness(def, lv)
			else:
				h += def.happiness_now(lv)
	# 人力过剩会不满（对应民居描述里的「人力停止增长」）
	var over := assigned_pop()
	if over > housing_capacity():
		h -= 3.0 * float(over - housing_capacity())
	# 粮食短缺
	if res("food") <= 0.0:
		h -= 15.0
	return clampf(h, 0.0, 100.0)


func _housing_happiness(def: BuildingDef, level: int) -> float:
	var rng: Dictionary = BuildingDB.meta_of(def, "housing_ratio_happy", {"min": 10.0, "max": -10.0})
	var t := _housing_ratio()
	return lerpf(float(rng["min"]), float(rng["max"]), t) * float(level) / 5.0


## 人力 / 住房比：0 = 房屋极少人力极多，1 = 房屋极多人手不足
func _housing_ratio() -> float:
	var cap := maxi(1, housing_capacity())
	var ratio := float(state["pop_total"]) / float(cap)
	return clampf(ratio, 0.0, 1.0)


func player_force() -> float:
	var f := float(state["pop_total"]) * Consts.FORCE_PER_POP
	f += float(TileManager.owned_tiles(state).size()) * Consts.FORCE_PER_TILE
	# v1.1：单位战力按「位阶倍率修正后的属性」换算，越精锐贡献越大
	for u in state["units"]:
		f += UnitDB.power_of(u)
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var id: String = b.get("id", "")
			if id == "classic_training_ground":
				f += 4.0 * float(b.get("level", 1))
	return f


func enemy_force() -> float:
	var f := 0.0
	for t in TileManager.enemy_tiles(state):
		f += float(t.get("force", Consts.WANDER_FORCE))
	for _t in state["threats"]:
		f += Consts.THREAT_FORCE
	return f


## 文档公式：稳定度
##   ((玩家总战斗力 / 敌人总战斗力) * (空白格子数 / (空白格子数 + 1)))
##   * (1 - (敌人数量 / 地图总格子数) * 0.5)
func stability() -> float:
	var pf := player_force()
	var ef := enemy_force()
	var ratio := 1.0
	if ef > 0.0:
		ratio = pf / ef
	else:
		ratio = 2.0   # 没有敌人时视为非常稳定
	ratio = clampf(ratio, 0.0, 2.0)

	var blank := float(TileManager.free_tiles(state).size())
	var blank_factor := blank / (blank + 1.0)

	var total_tiles := maxi(1, state["tiles"].size())
	var enemy_count := float(TileManager.enemy_tiles(state).size() + state["threats"].size())
	var pressure := 1.0 - (enemy_count / float(total_tiles)) * 0.5

	var s := (ratio * blank_factor) * pressure
	return clampf(s, 0.0, 1.0)


## v1.7：清空一块敌方地块（击杀 / 清剿 / 作弊摧毁共用同一份 teardown）。
## 以前这段在 4 个地方各写了一遍，口径已经漂移。返回"清空之前是否为终极威胁"，
## 便于调用方决定文案与威胁列表的处理。
func clear_enemy_tile(key: String) -> bool:
	var t := TileManager.tile_at(state, key)
	if t.is_empty():
		return false
	var was_threat: bool = t.get("threat", false)
	t["owner"] = Consts.Owner.NONE
	t["force"] = 0.0
	t["wander"] = false
	t["danger"] = false
	t["threat"] = false
	t["name"] = ""
	state["enemy_killed"] = int(state.get("enemy_killed", 0)) + 1
	if was_threat:
		var keep: Array = []
		for th in state["threats"]:
			if str(th.get("key", "")) != key:
				keep.append(th)
		state["threats"] = keep
	return was_threat


## 首都民居按照「房屋比例」给金币
func _housing_gold(level: int) -> float:
	var def := BuildingDB.find("classic_house")
	if def == null:
		return 0.0
	var rng: Dictionary = BuildingDB.meta_of(def, "housing_ratio_gold", {"min": 1.0, "max": 10.0})
	# 人力越多（ratio 越小）-> 金币越多
	var t := 1.0 - _housing_ratio()
	return lerpf(float(rng["min"]), float(rng["max"]), t) * float(level)


# ===========================================================================
# 周期结算
# ===========================================================================
func end_cycle() -> Dictionary:
	var report := {
		"cycle": int(state["cycle"]),
		"income": {},
		"upkeep": {},
		"pop_change": 0,
		"events": [],
		"happiness": happiness(),
		"stability": stability(),
	}

	# 1. 建筑产出
	var income := {}
	for t in TileManager.owned_tiles(state):
		var y := Buildings.tile_yield(t)
		for k in y.keys():
			income[k] = float(income.get(k, 0.0)) + float(y[k])
	# 民居金币
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if b.get("id", "") == "classic_house":
				income["currency"] = float(income.get("currency", 0.0)) + _housing_gold(int(b.get("level", 1)))

	# 2. 领地基础产出与建筑维护
	var owned_list := TileManager.owned_tiles(state)
	if not owned_list.is_empty():
		income["production"] = float(income.get("production", 0.0)) \
			+ Consts.PRODUCTION_PER_TILE * float(owned_list.size())
	var upkeep := {}
	for t in owned_list:
		for b in t.get("buildings", []):
			upkeep["production"] = float(upkeep.get("production", 0.0)) \
				+ Consts.BUILDING_UPKEEP_PRODUCTION * float(b.get("level", 1))

	# 3. 人口食物维护
	var pop := int(state["pop_total"])
	upkeep["food"] = float(upkeep.get("food", 0.0)) + Consts.FOOD_UPKEEP_PER_POP * float(pop)

	# 3.5 v1.5：单位维护费（公民）+ 客人食物开销
	Units._units_upkeep_into(state, income, upkeep)

	# 4. 结算
	#   生产力单独处理（v1.3.1）：先补维护（不够用货币抵），再填建造队列，
	#   最后把剩余存起来（上限 PRODUCTION_STORE_CAP，超出作废）
	var prod_in := float(income.get("production", 0.0))
	var prod_upk := float(upkeep.get("production", 0.0))
	for k in income.keys():
		if str(k) != "production":
			add_res(k, float(income[k]))
	for k in upkeep.keys():
		if str(k) != "production":
			add_res(k, -float(upkeep[k]))
	var prod_avail := prod_in - prod_upk
	if prod_avail < 0.0:
		var short := -prod_avail
		add_res("currency", -short * 2.0)
		report["events"].append("生产力不足，用货币抵付维护 %.0f" % short)
		prod_avail = 0.0
	var leftover := Buildings.process_queue(state, prod_avail)
	var room := maxf(0.0, Consts.PRODUCTION_STORE_CAP - res("production"))
	var added := minf(leftover, room)
	if added > 0.0:
		add_res("production", added)
	# 夹取（含被外部直接赋值超过上限的情况）
	if res("production") > Consts.PRODUCTION_STORE_CAP:
		add_res("production", -(res("production") - Consts.PRODUCTION_STORE_CAP))
	if leftover - added > 0.001:
		report["events"].append("生产力盈余超出存储上限（%d），%.1f 点作废。" % [
			int(Consts.PRODUCTION_STORE_CAP), leftover - added])

	report["income"] = income
	report["upkeep"] = upkeep

	# 5. 人口增长（受幸福度与住房上限影响）
	var happy := happiness()
	var cap := housing_capacity()
	var growth := 0
	if pop < cap:
		var chance := 0.0
		if res("food") > 10.0:
			chance = 0.35 + (happy - 50.0) * 0.004
		if _rng.randf() < clampf(chance, 0.0, 0.95):
			growth = 1
	if res("food") <= 0.0 and pop > 1 and _rng.randf() < 0.5:
		growth = -1
		report["events"].append("食物耗尽，有人离开了部落。")
	state["pop_total"] = clampi(pop + growth, 1, Consts.POP_HARD_CAP)
	report["pop_change"] = growth

	# 6. 敌人与世界演化
	Threats.evolve(state, _rng, report)

	# 7. 周期推进
	state["cycle"] = int(state["cycle"]) + 1
	state["playtime"] = float(state.get("playtime", 0.0)) + 1.0

	# 8. 稳定度过低会流失人力（保留保底人口与最低稳定度，避免死亡螺旋）
	var st := stability()
	if st < 0.30 and int(state["pop_total"]) > Consts.POP_FLOOR and _rng.randf() < 0.5:
		state["pop_total"] = maxi(Consts.POP_FLOOR, int(state["pop_total"]) - 1)
		report["events"].append("稳定度 %.0f%%，人力流失。" % (st * 100.0))

	# 9. 抽卡货币的周期结算（秩序结晶按等级，凝聚力按幸福度 × 文化率）
	settle_gacha_currency(report)

	# 9.5 行政点数的周期结算（基底 + 限时 buff/debuff + 当期收支项；见 v1.3.1）
	Admin.settle(state, report)

	# 9.6 v1.8.3：政事队列推进。
	# 必须排在 9.5 之后 —— 它吃的是"本期刚入账的行政点数"
	#（与规划队列吃当期生产力同一套手感）。
	Decrees.process_queue(state, float((report.get("income", {}) as Dictionary).get("admin", 0.0)))

	# 10. 单位经验：通过周期循环缓缓增长（每个单位最多因此获得 100 点）
	Units.grow_unit_exp(state, report)

	# 10.5 v1.5：客人离去判定 + 单位移动力重置
	Units.guest_leave_tick(state, _rng, report)
	Units.reset_unit_moves(state)

	_recompute_derived()
	report["happiness"] = happiness()
	report["stability"] = stability()
	_add_log("第 %d 周期结束：%s" % [report["cycle"], _report_line(income, upkeep, growth)], "cycle")
	for e in report["events"]:
		_add_log(e, "warn")

	# 11. 自动存档（按全局设置里的「自动存档周期数」，默认每周期）
	var interval := autosave_interval()
	var due := (int(state["cycle"]) - 1) % interval == 0
	if due:
		autosave()
	report["autosaved"] = due
	report["autosave_interval"] = interval
	state_changed.emit()
	return report


func _report_line(income: Dictionary, upkeep: Dictionary, pop_change: int) -> String:
	var inc: Array[String] = []
	for k in income.keys():
		inc.append("+%.1f %s" % [float(income[k]), Consts.res_name(k)])
	var upk: Array[String] = []
	for k in upkeep.keys():
		upk.append("-%.1f %s" % [float(upkeep[k]), Consts.res_name(k)])
	var pop_text := "人力不变"
	if pop_change > 0:
		pop_text = "人力 +%d" % pop_change
	elif pop_change < 0:
		pop_text = "人力 %d" % pop_change
	return "收入[%s] 支出[%s] %s" % ["、".join(inc), "、".join(upk), pop_text]


## 玩家等级：由科技、领地、周期共同决定（用于秩序结晶的周期结算）
func player_level() -> int:
	return 1 + int(state["techs"].size()) + int(float(TileManager.owned_tiles(state).size()) / 4.0) \
		+ int(float(state["cycle"]) / 10.0)


## 每周期结算的抽卡货币
func settle_gacha_currency(report: Dictionary) -> void:
	var lv := player_level()
	var crystal := Consts.CRYSTAL_PER_CYCLE + Consts.CRYSTAL_PER_LEVEL * float(lv)
	add_res("order_crystal", crystal)
	var hp := happiness()
	var culture := culture_rate()
	var cohesion := (Consts.COHESION_PER_CYCLE + Consts.COHESION_PER_HAPPINESS * hp) \
		* (1.0 + culture * Consts.COHESION_CULTURE_BONUS)
	# v1.5：未招募的客人也会提供一点凝聚力
	var guest_coh := Consts.GUEST_COHESION_PER_CYCLE * float(Units.guest_units(state).size())
	cohesion += guest_coh
	add_res("cohesion", cohesion)
	report["income"]["order_crystal"] = float(report["income"].get("order_crystal", 0.0)) + crystal
	report["income"]["cohesion"] = float(report["income"].get("cohesion", 0.0)) + cohesion


func _recompute_derived() -> void:
	# 当前没有需要缓存的重型派生量，占位以便后续扩展
	pass


## 系统自动创建的任务组与任务（文档说这些不能被玩家删除）
func _setup_default_tasks() -> void:
	state["task_groups"] = [
		{"id": "sys_main", "name": "主线进程", "system": true},
		{"id": "sys_world", "name": "世界经营", "system": true},
	]
	state["_group_open"] = {"sys_main": true, "sys_world": true}
	state["tasks"] = [
		{
			"id": "sys_t_tiles", "name": "扩张领地", "desc": "占领 3 块无主地块，让部落站稳脚跟。",
			"group": "sys_world", "system": true, "created_cycle": 1, "reset_cycles": 0,
			"goals": [{"type": "tile", "key": "", "need": 3, "text": "占领地块"}],
		},
		{
			"id": "sys_t_wood", "name": "囤积木材", "desc": "收集 10 份木材用于后续建造。",
			"group": "sys_world", "system": true, "created_cycle": 1, "reset_cycles": 0,
			"goals": [{"type": "resource", "key": "wood", "need": 10, "text": "累计 木材"}],
		},
		{
			"id": "sys_t_gacha", "name": "初次召唤", "desc": "在「世界泡 → 召唤系统」召唤到至少一名角色。",
			"group": "sys_main", "system": true, "created_cycle": 1, "reset_cycles": 0,
			"goals": [{"type": "item", "key": "char_geo", "need": 1, "text": "收集 岩构骑士"}],
		},
		{
			"id": "sys_t_cycle", "name": "生存 20 个周期", "desc": "在崩坏 / 深渊 / 空洞的威胁下活过 20 个周期。",
			"group": "sys_main", "system": true, "created_cycle": 1, "reset_cycles": 0,
			"goals": [{"type": "cycle", "key": "", "need": 20, "text": "存活周期"}],
		},
	]
	state["tasks_done"] = []
	state["enemy_killed"] = 0


# ===========================================================================
# 日志
# ===========================================================================
func add_log(text: String, kind: String = "info") -> void:
	_add_log(text, kind)


func _add_log(text: String, kind: String) -> void:
	var entry := {"cycle": int(state.get("cycle", 1)), "text": text, "kind": kind}
	var l: Array = state["log"]
	l.append(entry)
	while l.size() > 300:
		l.pop_front()


func add_manual_log(text: String) -> void:
	var l: Array = state["manual_log"]
	l.append({"cycle": int(state["cycle"]), "text": text})
	_add_log("记录：%s" % text, "record")
	state_changed.emit()


# ===========================================================================
# 存档
# ===========================================================================
func slot_path(slot: int) -> String:
	return "%s/slot_%02d.json" % [Consts.SAVE_DIR, slot]


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func slot_summary(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var st: Dictionary = d.get("state", {})
	return {
		"slot": slot,
		"cycle": int(st.get("cycle", 0)),
		"tiles": int((st.get("tiles", {}) as Dictionary).size()),
		"chars": (st.get("units", []) as Array).size(),
		"time": str(d.get("saved_at", "")),
	}


func save_to_slot(slot: int) -> bool:
	var payload := {
		"magic": SAVE_MAGIC,
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"state": state,
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		toast.emit("存档失败：无法写入槽位 %d" % slot)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	state["current_slot"] = slot
	toast.emit("已保存到槽位 %d" % (slot + 1))
	state_changed.emit()
	return true


func load_from_slot(slot: int) -> bool:
	if not slot_exists(slot):
		toast.emit("槽位 %d 没有存档" % (slot + 1))
		return false
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		toast.emit("存档损坏")
		return false
	var d: Dictionary = parsed
	if d.get("magic", "") != SAVE_MAGIC:
		toast.emit("存档格式不匹配")
		return false
	# v1.7：1.0 期间不做旧档兼容（留到 2.0）—— 版本不符直接拒绝，不再尝试迁移老档
	# 拍板（1.8.21）：版本不匹配的档**直接删掉**（地形/数据模型都换了，
	# 留着旧档只会在地图上显示成不认识的种类）
	if int(d.get("version", 0)) != SAVE_VERSION:
		var was := int(d.get("version", 0))
		delete_slot(slot)
		toast.emit("存档已过期（该档 v%d，当前 v%d），已删除，请新开一局" % [was, SAVE_VERSION])
		return false

	var loaded: Dictionary = d.get("state", {})
	if loaded.is_empty():
		toast.emit("存档内容为空")
		return false
	state = loaded
	state["current_slot"] = slot
	# v1.8.20.8：读档要把种子放回 _rng，否则读回来的局与存的时候不是同一条流（get 兜底防缺字段）。

	_rng.seed = int(state.get("seed", 0))
	toast.emit("已读取槽位 %d" % (slot + 1))

	state_changed.emit()
	return true


func delete_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
	if err != OK:
		toast.emit("删除失败（错误 %d）" % err)
		return false
	toast.emit("已删除槽位 %d" % (slot + 1))
	state_changed.emit()
	return true


func autosave() -> void:
	save_to_slot(Consts.AUTOSAVE_SLOT)


# ===========================================================================
# 自动存档周期数
#
# 注意：这项是**全局设置**，存在 AppSettings 里（user://settings.cfg），
# 不放进 state。放进来会被 new_game() / 读档 一起重建，开关就丢了 ——
# 之前的 bug 就是这么来的（勾了作弊，一开始新游戏又变回没勾）。
# 下面这些函数保留，只是转发到 AppSettings，方便调用方不用改。
# ===========================================================================
func autosave_interval() -> int:
	return AppSettings.autosave_interval()

func set_autosave_interval(n: int) -> void:
	AppSettings.set_autosave_interval(n)
	toast.emit("自动存档已设为每 %d 个周期一次" % autosave_interval())
	state_changed.emit()

func has_continue() -> bool:
	return slot_exists(Consts.AUTOSAVE_SLOT)


func continue_game() -> bool:
	return load_from_slot(Consts.AUTOSAVE_SLOT)


func any_save() -> bool:
	for i in Consts.SAVE_SLOTS:
		if slot_exists(i):
			return true
	return false


