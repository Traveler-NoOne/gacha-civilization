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
const SAVE_VERSION := 5   # W1：新增 state["worlds"] / state["edges"]（老档直接删，见 load_from_slot）


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
		"worlds": [          # W1：每块世界一份"配方"（现在只有第一块；W5/W6/W7 才真正用上）
			{
				"dir": null, "origin": [0, 0], "seed": s,
				"map_radius": Consts.MAP_START_RADIUS,
				"sim_size": 512, "climate_size": 128,
				"crop_center": null, "crop_radius": 107, "world_age": 0.35,
			},
		],
		"edges": {},         # W1：边集合（键 "q,r,d"；两类边 river_edge / water_edge）；W4 才写入
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
	WorldGen.generate(state)
	_setup_capital_stronghold()
	_recompute_derived()
	_grant_starting_units()
	_add_log("建立部落，营地落在世界中央。", "info")
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
	for t in owned_tiles():
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


func tile_at(key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if tiles.has(key):
		return tiles[key]
	return {}


# ===========================================================================
# v1.3.1 据点（本作仅首都；v1.7 删死代码时误删过这一行声明，已补回）
# ===========================================================================
const CAPITAL_STRONGHOLD := "sh_capital"


func _setup_capital_stronghold() -> void:
	state["strongholds"] = [{
		"id": CAPITAL_STRONGHOLD,
		"name": "首都",
		"core": str(state.get("capital", "0,0")),
		"control": 1.0,          # 掌控力（预留，本作恒 1.0）
		"queue": [],             # 规划队列（吃生产力）
		"decrees": [],           # v1.8.3 政事队列（吃行政点数）
	}]
	var cap := tile_at(str(state.get("capital", "0,0")))
	if not cap.is_empty():
		cap["stronghold"] = CAPITAL_STRONGHOLD
		if not cap.has("land_cap"):
			cap["land_cap"] = Consts.LAND_CAP_DEFAULT


func strongholds() -> Array:
	return state.get("strongholds", [])


## v1.6：开局赠送 5★ 公民「格蕾修」。
## 她是前文明「方舟计划」的乘员——方舟带着前文明的全部科技成果离开、寻找新的世界。
## 所以她是"从毁灭的世界漂来的遗民"，正是本作核心设定（这枚世界泡靠收留末日来客立起来）
## 的具象化，也是召唤 / 招募系统的预告：她本身就是第一位"客人"（开局已是公民）。
## 数值与 card_db 的 char_grieso 保持一致（攻中等 / 防低 / 血低 / 速中等 / 敏高）。
func _grant_starting_units() -> void:
	var card := CardDB.find("char_grieso")
	if card.is_empty():
		return
	# 数值与职业都从卡池数据取（PROFESSION_BY_ID 里 char_grieso -> projectile），
	# 这样格蕾修的数值只有 card_db 一份来源，改平衡不会漏改这里。
	card = card.duplicate()
	card["profession"] = CardDB.profession_of(card)
	var u := UnitDB.from_card(card)
	u["status"] = UnitDB.STATUS_CITIZEN
	u["tile"] = str(state.get("capital", ""))
	u["acquired_cycle"] = int(state["cycle"])
	u["move_left"] = max_move(u)
	(state["units"] as Array).append(u)
	add_log("格蕾修随方舟的残骸漂流至此，成为你的第一位公民。", "unit")


func stronghold_by_id(sid: String) -> Dictionary:
	for s in strongholds():
		if str(s.get("id", "")) == sid:
			return s
	return {}


## 当前默认管理的据点（本作仅首都）
func current_stronghold() -> Dictionary:
	var all := strongholds()
	if all.is_empty():
		return {}
	return all[0]


func stronghold_of(tile: Dictionary) -> String:
	return str(tile.get("stronghold", ""))


## 某据点包含的地块（仅我方领地）
func stronghold_tiles(sid: String) -> Array:
	var out := []
	for t in owned_tiles():
		if str(t.get("stronghold", "")) == sid:
			out.append(t)
	return out


func land_cap(tile: Dictionary) -> float:
	return float(tile.get("land_cap", Consts.LAND_CAP_DEFAULT))


func land_used(tile: Dictionary) -> float:
	var used := 0.0
	for b in tile.get("buildings", []):
		var def := find_building(str(b.get("id", "")))
		if def != null:
			used += def.land
	return used


func land_free(tile: Dictionary) -> float:
	return maxf(0.0, land_cap(tile) - land_used(tile))


func _new_bid() -> String:
	return "b_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]


# ===========================================================================
# v1.3.1 掌控力（预留接口：只保留数据结构与骨架，本版不接行为）
# ===========================================================================
func control_of(stronghold: Dictionary) -> float:
	return float(stronghold.get("control", 1.0))


func owned_tiles() -> Array:
	var out := []
	for k in state["tiles"].keys():
		var t: Dictionary = state["tiles"][k]
		if t.get("owner", "") == "player":
			out.append(t)
	return out


func discovered_tiles() -> Array:
	var out := []
	for k in state["tiles"].keys():
		var t: Dictionary = state["tiles"][k]
		if t.get("discovered", false):
			out.append(t)
	return out


func free_tiles() -> Array:
	var out := []
	for k in state["tiles"].keys():
		var t: Dictionary = state["tiles"][k]
		if t.get("discovered", false) and t.get("owner", "") == "":
			out.append(t)
	return out


func enemy_tiles() -> Array:
	var out := []
	for k in state["tiles"].keys():
		var t: Dictionary = state["tiles"][k]
		var o: String = t.get("owner", "")
		if o != "" and o != "player":
			out.append(t)
	return out


# ===========================================================================
# 派生数值
# ===========================================================================
func assigned_pop() -> int:
	var n := 0
	for t in owned_tiles():
		for b in t.get("buildings", []):
			n += int(b.get("workers", 0))
	return n


func free_pop() -> int:
	return maxi(0, int(state["pop_total"]) - assigned_pop())


func housing_capacity() -> int:
	# 基础住房 + 每块领地若干 + 民居等级
	var cap := Consts.BASE_HOUSING + Consts.HOUSING_PER_TILE * owned_tiles().size()
	for t in owned_tiles():
		for b in t.get("buildings", []):
			if b.get("id", "") == "classic_house":
				cap += Consts.HOUSING_PER_HOUSE_LEVEL * int(b.get("level", 1))
	return mini(cap, Consts.POP_HARD_CAP)


func culture_rate() -> float:
	var c := 0.0
	for t in owned_tiles():
		for b in t.get("buildings", []):
			var def := find_building(b.get("id", ""))
			if def == null:
				continue
			c += float(BuildingDB.meta_of(def, "culture", 0.0)) * float(b.get("level", 1))
	return c


## 幸福度是「基础 + 建筑 + 制度 - 民怨」
func happiness() -> float:
	var h := 50.0
	for t in owned_tiles():
		for b in t.get("buildings", []):
			var def := find_building(b.get("id", ""))
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
	f += float(owned_tiles().size()) * Consts.FORCE_PER_TILE
	# v1.1：单位战力按「位阶倍率修正后的属性」换算，越精锐贡献越大
	for u in state["units"]:
		f += UnitDB.power_of(u)
	for t in owned_tiles():
		for b in t.get("buildings", []):
			var id: String = b.get("id", "")
			if id == "classic_training_ground":
				f += 4.0 * float(b.get("level", 1))
	return f


func enemy_force() -> float:
	var f := 0.0
	for t in enemy_tiles():
		f += float(t.get("force", Consts.WANDER_FORCE))
	for _t in state["threats"]:
		f += Consts.THREAT_FORCE
	return f


## 文档公式：稳定度
##   ((玩家总战斗力 / 敌人总战斗力) * (空白格子数 / (空白格子数 + 1)))
##   * (1 - (敌人数量 / 地图总格子数) * 0.5)
## ⚠️ W1：这里**故意是全局口径** —— 下面的 player_force / enemy_force / free_tiles
## 以及"地图总格子数"（`state["tiles"].size()`）全都遍历**整张 tiles 字典**。
## 将来的"多块世界"是**并进同一个 tiles 字典**的（见 世界生成-W7.md），
## 所以它们自动就是"所有世界加总"。**别改成按"当前显示的世界"统计** ——
## 那样每拼一块新世界，稳定度就会突跳一次。
func stability() -> float:
	var pf := player_force()
	var ef := enemy_force()
	var ratio := 1.0
	if ef > 0.0:
		ratio = pf / ef
	else:
		ratio = 2.0   # 没有敌人时视为非常稳定
	ratio = clampf(ratio, 0.0, 2.0)

	var blank := float(free_tiles().size())
	var blank_factor := blank / (blank + 1.0)

	var total_tiles := maxi(1, state["tiles"].size())
	var enemy_count := float(enemy_tiles().size() + state["threats"].size())
	var pressure := 1.0 - (enemy_count / float(total_tiles)) * 0.5

	var s := (ratio * blank_factor) * pressure
	return clampf(s, 0.0, 1.0)


func find_building(id: String) -> BuildingDef:
	for b in building_defs:
		if b.id == id:
			return b
	return null


func tech_unlocked(id: String) -> bool:
	return state["techs"].has(id)


func has_flag(f: String) -> bool:
	return state["techs_owned_flags"].has(f)


# ===========================================================================
# v1.1 单位系统：单位仓库 / 派驻 / 编队 / 经验
# ===========================================================================
func unit_by_uid(uid: String) -> Dictionary:
	for u in state["units"]:
		if str(u["uid"]) == uid:
			return u
	return {}


func units_on_tile(key: String) -> Array:
	var out := []
	for u in state["units"]:
		if str(u.get("tile", "")) == key:
			out.append(u)
	return out


## 未派驻到任何地块的单位
func idle_units() -> Array:
	var out := []
	for u in state["units"]:
		if str(u.get("tile", "")) == "":
			out.append(u)
	return out


## 派驻单位到地块（一个格子最多 4 个单位，v1.1 第 9 条）
func deploy_unit(uid: String, key: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var tile := tile_at(key)
	if tile.is_empty():
		return {"ok": false, "why": "地块不存在"}
	if tile.get("owner", "") != "player":
		return {"ok": false, "why": "只能派驻到我方地块"}
	if not control_ok(key):
		return {"ok": false, "why": "该领地掌控力不足 %.0f%%" % (Consts.CONTROL_SELF_OPERATE * 100.0)}
	var cur := units_on_tile(key)
	if str(u.get("tile", "")) == key:
		return {"ok": false, "why": "该单位已经在此地块"}
	if cur.size() >= UnitDB.UNITS_PER_TILE:
		return {"ok": false, "why": "该地块已驻满 %d 个单位" % UnitDB.UNITS_PER_TILE}
	u["tile"] = key
	add_log("%s 进驻 %s（该地块 %d/%d）。" % [
		str(u["name"]), key, units_on_tile(key).size(), UnitDB.UNITS_PER_TILE], "unit")
	state_changed.emit()
	return {"ok": true, "why": ""}


func withdraw_unit(uid: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var was := str(u.get("tile", ""))
	if was == "":
		return {"ok": false, "why": "该单位未派驻"}
	u["tile"] = ""
	add_log("%s 从 %s 撤回。" % [str(u["name"]), was], "unit")
	state_changed.emit()
	return {"ok": true, "why": ""}


# ---------------------------------------------------------------------------
# v1.5：客人 / 公民、部署（掌控力门槛）、移动与攻击
# ---------------------------------------------------------------------------
static func tile_key(t: Dictionary) -> String:
	var c: Array = t.get("c", [])
	if c.size() < 2:
		return ""
	return WorldGen.key_of(Vector2i(int(c[0]), int(c[1])))


func units_by_status(s: String) -> Array:
	var out := []
	for u in state["units"]:
		if str(u.get("status", UnitDB.STATUS_CITIZEN)) == s:
			out.append(u)
	return out


func guest_units() -> Array:
	return units_by_status(UnitDB.STATUS_GUEST)


## v1.7：单单位的客人 / 公民判断（视图里此前各自内联同一串 get + 比较）
static func is_citizen(u: Dictionary) -> bool:
	return str(u.get("status", UnitDB.STATUS_CITIZEN)) == UnitDB.STATUS_CITIZEN


static func is_guest(u: Dictionary) -> bool:
	return str(u.get("status", UnitDB.STATUS_CITIZEN)) == UnitDB.STATUS_GUEST


func citizen_units() -> Array:
	return units_by_status(UnitDB.STATUS_CITIZEN)


## 地块掌控力 = 该地块所属据点的 control_of()。
## v1.5：据点 control 仍恒 1.0（衰减留待后续），所以门槛先挂着、暂不拦人。
func tile_control(key: String) -> float:
	var t := tile_at(key)
	if t.is_empty():
		return 0.0
	var sid := str(t.get("stronghold", ""))
	if sid == "":
		return 0.0
	return control_of(stronghold_by_id(sid))


func control_ok(key: String) -> bool:
	return tile_control(key) >= Consts.CONTROL_SELF_OPERATE


## 合法部署地块：我方领地 + 掌控力达标 + 未驻满
func deployable_keys() -> Array[String]:
	var out: Array[String] = []
	for t in owned_tiles():
		var k := tile_key(t)
		if k == "" or not control_ok(k):
			continue
		if units_on_tile(k).size() >= UnitDB.UNITS_PER_TILE:
			continue
		out.append(k)
	return out


## 最大移动力：2 移动速度 = 1 移动力（用基础速度，不吃位阶/等级倍率）
func max_move(unit: Dictionary) -> int:
	var spd := float((unit.get("attr", {}) as Dictionary).get("spd", 2))
	return maxi(1, int(floor(spd / float(Consts.MOVE_PER_SPEED))))


## 招募第一步：只校验，不改状态（真正的转换在 confirm_recruit）
func begin_recruit(uid: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("status", "")) != UnitDB.STATUS_GUEST:
		return {"ok": false, "why": "只有客人可以招募"}
	var keys := deployable_keys()
	if keys.is_empty():
		return {"ok": false, "why": "没有可部署的领地（需掌控力 ≥ 80% 且未驻满）"}
	state["pending_recruit"] = uid
	state_changed.emit()
	return {"ok": true, "why": "", "tiles": keys}


## 取消招募：客人保持客人，不做任何转换
func cancel_recruit() -> void:
	if state.has("pending_recruit"):
		state.erase("pending_recruit")
		state_changed.emit()


func pending_recruit_uid() -> String:
	return str(state.get("pending_recruit", ""))


## 招募的唯一转换点：客人 → 公民 + 落地
func confirm_recruit(uid: String, key: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("status", "")) != UnitDB.STATUS_GUEST:
		return {"ok": false, "why": "只有客人可以招募"}
	var t := tile_at(key)
	if t.is_empty() or t.get("owner", "") != "player":
		return {"ok": false, "why": "只能部署到我方领地"}
	if not control_ok(key):
		return {"ok": false, "why": "该领地掌控力不足 %.0f%%" % (Consts.CONTROL_SELF_OPERATE * 100.0)}
	if units_on_tile(key).size() >= UnitDB.UNITS_PER_TILE:
		return {"ok": false, "why": "该地块已驻满 %d 个单位，请另选" % UnitDB.UNITS_PER_TILE}
	u["status"] = UnitDB.STATUS_CITIZEN
	u["tile"] = key
	u["acquired_cycle"] = int(state["cycle"])
	u["move_left"] = max_move(u)
	state.erase("pending_recruit")
	add_log("%s 接受了招募，成为公民并进驻 %s。" % [str(u["name"]), key], "unit")
	state_changed.emit()
	return {"ok": true, "why": ""}


## 遣返：把客人送回他自己的世界（直接从库存移除）
func dismiss_guest(uid: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("status", "")) != UnitDB.STATUS_GUEST:
		return {"ok": false, "why": "只有客人可以遣返"}
	state["units"].erase(u)
	add_log("%s 被遣返回了自己的世界。" % str(u["name"]), "unit")
	state_changed.emit()
	return {"ok": true, "why": ""}


## 从库存移除一个单位（阵亡 / 遣返共用）
func remove_unit(uid: String) -> bool:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return false
	state["units"].erase(u)
	return true


## v1.6.1：驻军 —— 驻守在当前地块。
## 驻军时维护费打折（领地内 −60% / 领地外 −10%），代价是**不能移动或攻击**。
func toggle_garrison(uid: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("tile", "")) == "":
		return {"ok": false, "why": "该单位不在大世界上"}
	var g := not bool(u.get("garrisoned", false))
	u["garrisoned"] = g
	add_log("%s %s。" % [str(u["name"]), "开始驻军" if g else "解除驻军"], "unit")
	state_changed.emit()
	return {"ok": true, "why": "", "garrisoned": g}


func tile_passable(key: String) -> bool:
	var t := tile_at(key)
	if t.is_empty():
		return false
	if t.get("owner", "") == "enemy":
		return false
	return bool(t.get("discovered", false))



## 距离 2 时的中间格（轴向坐标下取两点之差的一半）
static func _middle_key(a: Vector2i, b: Vector2i) -> String:
	var diff := b - a
	if diff.x % 2 != 0 or diff.y % 2 != 0:
		return ""
	return WorldGen.key_of(a + Vector2i(diff.x / 2, diff.y / 2))


## 移动：相邻格耗 1、间隔一格耗 2（中间格须可通行）
## 移动合法性校验：move_unit 与 UI 高亮**共用同一份规则**，
## 避免出现"界面高亮可走、实际点下去被拒绝"的不一致（v1.7 修）。
func can_move_to(uid: String, key: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var from := str(u.get("tile", ""))
	if from == "":
		return {"ok": false, "why": "该单位不在大世界上"}
	if key == from:
		return {"ok": false, "why": "已经在这里了"}
	if bool(u.get("garrisoned", false)):
		return {"ok": false, "why": "该单位正在驻军，先「解除驻军」才能移动"}
	if not (state["tiles"] as Dictionary).has(key):
		return {"ok": false, "why": "地块不存在"}
	var a := WorldGen.coord_of(from)
	var b := WorldGen.coord_of(key)
	var d := Hex.distance(a, b)
	if d < 1 or d > 2:
		return {"ok": false, "why": "只能移动到 1~2 格内的地块"}
	var cost := Consts.MOVE_COST_NEAR if d == 1 else Consts.MOVE_COST_FAR
	if not tile_passable(key):
		return {"ok": false, "why": "目标地块无法通行（敌方或未点亮）"}
	if d == 2:
		var mid := _middle_key(a, b)
		if mid != "" and not tile_passable(mid):
			return {"ok": false, "why": "中间的地块无法通行"}
	if units_on_tile(key).size() >= UnitDB.UNITS_PER_TILE:
		return {"ok": false, "why": "目标地块已驻满"}
	if int(u.get("move_left", 0)) < cost:
		return {"ok": false, "why": "移动力不足（需 %d，剩 %d）" % [cost, int(u.get("move_left", 0))]}
	return {"ok": true, "why": "", "cost": cost}


## 某单位当前**真正**能走到的地块（UI 高亮用；与 move_unit 同一份规则）
func move_candidates(uid: String) -> Array[String]:
	var out: Array[String] = []
	var u := unit_by_uid(uid)
	if u.is_empty():
		return out
	var from := str(u.get("tile", ""))
	if from == "":
		return out
	var a := WorldGen.coord_of(from)
	for d in Hex.DIRECTIONS:
		var k1 := WorldGen.key_of(a + d)
		if bool(can_move_to(uid, k1)["ok"]) and not out.has(k1):
			out.append(k1)
		for d2 in Hex.DIRECTIONS:
			var k2 := WorldGen.key_of(a + d + d2)
			if k2 == from or out.has(k2):
				continue
			if bool(can_move_to(uid, k2)["ok"]):
				out.append(k2)
	return out


## 移动：相邻格耗 1、间隔一格耗 2（中间格须可通行）
func move_unit(uid: String, key: String) -> Dictionary:
	var chk := can_move_to(uid, key)
	if not bool(chk["ok"]):
		return {"ok": false, "why": str(chk["why"])}
	var u := unit_by_uid(uid)
	var cost := int(chk["cost"])
	u["move_left"] = int(u.get("move_left", 0)) - cost
	u["tile"] = key
	# v1.6.2：单位移动会点亮周围一格的迷雾
	WorldGen.discover_radius(state, WorldGen.coord_of(key), 1)
	add_log("%s 移动到 %s（消耗 %d 移动力）。" % [str(u["name"]), key, cost], "unit")
	state_changed.emit()
	return {"ok": true, "why": "", "cost": cost}

func unit_attack(uid: String, key: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var from := str(u.get("tile", ""))
	if from == "":
		return {"ok": false, "why": "该单位不在大世界上"}
	if Hex.distance(WorldGen.coord_of(from), WorldGen.coord_of(key)) != 1:
		return {"ok": false, "why": "只能攻击相邻地块"}
	var t := tile_at(key)
	if t.is_empty() or t.get("owner", "") != "enemy":
		return {"ok": false, "why": "目标不是敌方地块"}
	if bool(u.get("garrisoned", false)):
		return {"ok": false, "why": "该单位正在驻军，先「解除驻军」才能攻击"}
	if int(u.get("move_left", 0)) <= 0:
		return {"ok": false, "why": "该单位本周期已行动"}
	var lines: Array[String] = []
	var force := float(t.get("force", Consts.WANDER_FORCE))
	var enemy_prof := _enemy_profession(t)
	var enemy := {"profession": enemy_prof, "attr": {"atk": force * Consts.ENEMY_ATK_MUL, "def": force * Consts.ENEMY_DEF_MUL}}
	var r := UnitDB.resolve_damage(u, enemy)
	var dmg := float(r["damage"])
	var adv := int(r["advantage"])
	var tag := "（克制！）" if adv > 0 else ("（被克制）" if adv < 0 else "")
	force -= dmg
	lines.append("%s 对 %s 造成 %.1f 伤害%s" % [str(u["name"]), enemy_label(t), dmg, tag])
	gain_exp(uid, 12, "combat")

	var won := force <= 0.0
	if won:
		on_enemy_killed(t)
		clear_enemy_tile(key)
		lines.append("战斗胜利：%s 的敌人被清剿。" % key)
		add_log("战斗胜利：%s 被 %s 清剿。" % [key, str(u["name"])], "combat")
	else:
		t["force"] = force
		var cr := UnitDB.resolve_damage(enemy, u)
		var back := float(cr["damage"])
		u["hp"] = int(u.get("hp", 1)) - int(round(back))
		lines.append("%s 反击 %s，造成 %.1f 伤害" % [enemy_label(t), str(u["name"]), back])
		if int(u.get("hp", 1)) <= 0:
			lines.append("%s 阵亡。" % str(u["name"]))
			add_log("%s 在进攻 %s 时阵亡。" % [str(u["name"]), key], "combat")
			on_unit_died(str(u.get("rank", UnitDB.RECRUIT)))
			state["units"].erase(u)
		else:
			add_log("战斗未决：%s 的敌人仍在顽抗。" % key, "combat")

	u["move_left"] = 0   # 攻击耗尽本周期行动
	state_changed.emit()
	return {"ok": true, "why": "", "won": won, "lines": lines, "damage": dmg,
		"died": int(u.get("hp", 1)) <= 0}


## 编队：把单位加入某队（一队最多 4 个单位，v1.1 第 10 条）
func assign_team(uid: String, team_index: int) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var teams: Array = state["teams"]
	if team_index < 0 or team_index >= teams.size():
		return {"ok": false, "why": "队伍不存在"}
	var team: Dictionary = teams[team_index]
	var members: Array = team["members"]
	if members.has(uid):
		return {"ok": false, "why": "该单位已在此队伍"}
	if members.size() >= UnitDB.UNITS_PER_TEAM:
		return {"ok": false, "why": "该队伍已满 %d 个单位" % UnitDB.UNITS_PER_TEAM}
	# 先从原队伍移除（一个单位只能属于一个队伍）
	for t in teams:
		(t["members"] as Array).erase(uid)
	members.append(uid)
	u["team"] = team_index
	add_log("%s 编入%s。" % [str(u["name"]), str(team["name"])], "unit")
	state_changed.emit()
	return {"ok": true, "why": ""}


func remove_from_team(uid: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	for t in state["teams"]:
		(t["members"] as Array).erase(uid)
	u["team"] = -1
	state_changed.emit()
	return {"ok": true, "why": ""}


func team_units(team_index: int) -> Array:
	var teams: Array = state["teams"]
	if team_index < 0 or team_index >= teams.size():
		return []
	var out := []
	for uid in (teams[team_index]["members"] as Array):
		var u := unit_by_uid(str(uid))
		if not u.is_empty():
			out.append(u)
	return out


## 单位叠加装备后的战斗属性
func unit_combat_attr(u: Dictionary) -> Dictionary:
	var a := UnitDB.effective_attr(u)
	var eq: Dictionary = u.get("equipped", {})
	for slot in ["weapon", "relic"]:
		var item_id := str(eq.get(slot, ""))
		if item_id == "":
			continue
		for e in state["equipment"]:
			if str(e["id"]) == item_id:
				var ea: Dictionary = e.get("attr", {})
				for k in ea.keys():
					a[k] = float(a.get(k, 0.0)) + float(ea[k])
	return a


## 获取经验（来源分「周期循环」与「战斗」两类，周期循环最多贡献 100 点）
func gain_exp(uid: String, amount: int, source: String = "combat") -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var rank := str(u.get("rank", UnitDB.RECRUIT))
	var cap := UnitDB.exp_cap(rank)
	var cur := int(u.get("exp", 0))
	if cur >= cap:
		return {"ok": false, "why": "经验已满，可尝试晋升"}
	var gain := amount
	if source == "cycle":
		var used := int(u.get("exp_from_cycles", 0))
		var room := maxi(0, UnitDB.EXP_FROM_CYCLES_CAP - used)
		gain = mini(amount, room)
		if gain <= 0:
			return {"ok": false, "why": "周期循环经验已达上限（%d）" % UnitDB.EXP_FROM_CYCLES_CAP}
		u["exp_from_cycles"] = used + gain
		u["exp_from_cycle"] = int(u.get("exp_from_cycle", 0)) + gain
	else:
		u["exp_from_combat"] = int(u.get("exp_from_combat", 0)) + gain
	u["exp"] = mini(cap, cur + gain)
	state_changed.emit()
	return {"ok": true, "why": "", "gain": gain, "exp": int(u["exp"]), "cap": cap}


## 晋升到更高位阶（募集军 -> 正规军 -> 角色）
func promote_unit(uid: String) -> Dictionary:
	var u := unit_by_uid(uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var rank := str(u.get("rank", UnitDB.RECRUIT))
	var nxt := UnitDB.next_rank(rank)
	if nxt == "":
		return {"ok": false, "why": "已经是最高位阶"}
	if int(u.get("exp", 0)) < UnitDB.exp_cap(rank):
		return {"ok": false, "why": "经验未满（%d/%d）" % [int(u.get("exp", 0)), UnitDB.exp_cap(rank)]}
	u["rank"] = nxt
	u["exp"] = 0
	u["exp_from_cycles"] = 0
	u["exp_from_combat"] = 0
	add_log("%s 晋升为%s。" % [str(u["name"]), UnitDB.rank_name(nxt)], "unit")
	state_changed.emit()
	return {"ok": true, "why": "", "rank": nxt}


## 每周期给所有单位少量经验（周期循环来源，上限 100 点）
func grow_unit_exp(report: Dictionary) -> void:
	var gained := 0
	for u in state["units"]:
		var r := gain_exp(str(u["uid"]), UnitDB.EXP_PER_CYCLE, "cycle")
		if r["ok"]:
			gained += int(r["gain"])
	if gained > 0:
		report["events"].append("单位在周期循环中累计获得 %d 点经验。" % gained)


# ---------------------------------------------------------------------------
# v1.5：单位维护费 / 客人离去 / 移动力重置
# ---------------------------------------------------------------------------
## 单个单位的周期维护费（客人只吃食物；公民吃食物 + 货币，驻守我方领地 −60%、领地外 −10%）
func unit_upkeep_of(u: Dictionary) -> Dictionary:
	if is_guest(u):
		return {"food": Consts.GUEST_FOOD_PER_CYCLE, "currency": 0.0}
	var t := tile_at(str(u.get("tile", "")))
	var own: bool = (not t.is_empty()) and str(t.get("owner", "")) == "player"
	# v1.6.1：只有「驻军」状态才享受维护费折扣（领地内 −60% / 领地外 −10%）；行军时全额
	var mul := 1.0
	if bool(u.get("garrisoned", false)):
		mul = Consts.UPKEEP_MUL_IN_TERRITORY if own else Consts.UPKEEP_MUL_OUTSIDE
	return {"food": Consts.UNIT_UPKEEP_FOOD * mul, "currency": Consts.UNIT_UPKEEP_CURRENCY * mul}


## v1.7：全体单位的维护费合计（原来在 3 个地方各遍历一遍、口径容易漂）
func units_upkeep_total() -> Dictionary:
	var out := {"food": 0.0, "currency": 0.0}
	for u in state["units"]:
		var uk := unit_upkeep_of(u)
		out["food"] = float(out["food"]) + float(uk.get("food", 0.0))
		out["currency"] = float(out["currency"]) + float(uk.get("currency", 0.0))
	return out


## 把单位维护费并进本期收支（end_cycle 段 3.5 调用，之后段 4 会统一结算）
func _units_upkeep_into(_income: Dictionary, upkeep: Dictionary) -> void:
	var tot := units_upkeep_total()
	upkeep["food"] = float(upkeep.get("food", 0.0)) + float(tot["food"])
	upkeep["currency"] = float(upkeep.get("currency", 0.0)) + float(tot["currency"])


## 客人：超过 15 个周期后，每周期按累计概率离去
func guest_leave_tick(report: Dictionary) -> void:
	var cyc := int(state["cycle"])
	var leaving: Array = []
	for u in guest_units():
		var age := cyc - int(u.get("acquired_cycle", cyc))
		if age < Consts.GUEST_LEAVE_FROM_CYCLE:
			continue
		var p := float(u.get("leave_chance", 0.0)) \
			+ _rng.randf_range(Consts.GUEST_LEAVE_STEP_MIN, Consts.GUEST_LEAVE_STEP_MAX)
		u["leave_chance"] = p
		if _rng.randf() < p:
			leaving.append(u)
	for u in leaving:
		add_log("%s 等得太久，离开了（未招募的客人会自行离去）。" % str(u["name"]), "unit")
		(state["units"] as Array).erase(u)
	if not leaving.is_empty():
		report["events"].append("%d 位客人等不到招募，离开了。" % leaving.size())


## 每周期重置移动力
func reset_unit_moves() -> void:
	for u in state["units"]:
		u["move_left"] = max_move(u)


## 征兵：把空闲人力转成募集军（对应文档「军事建筑 - 经典训练场地」的思路，
## 但募集军是「刚招募、经验为负修正」的那一类，见 v1.1 第 25 条）
## 征兵的花费（唯一来源：检查与支付都用它）
const RECRUIT_COST := {"food": 20.0, "currency": 60.0}


## 征兵是否可行 —— **只检查，不花钱、不落单位**。
## v1.8.3：把这套检查抽出来，好让"直接征兵"与"政事：征兵"两条路**共用同一份判定**
## （两处各写一遍的话，迟早一边改了另一边没改）。返回 "" 表示可以。
func recruit_blocked_reason(profession: String) -> String:
	if free_pop() <= 0:
		return "没有空闲人力"
	if not UnitDB.PROFESSIONS.has(profession):
		return "未知职业"
	# 需要一座训练场地
	var has_ground := false
	for t in owned_tiles():
		for b in t.get("buildings", []):
			if str(b.get("id", "")) == "classic_training_ground":
				has_ground = true
	if not has_ground:
		return "需要先建造「经典训练场地」"
	if not can_afford(RECRUIT_COST):
		return "资源不足（%s）" % cost_to_text(RECRUIT_COST)
	# v1.5：公民必须存在于大世界 —— 直接派驻首都；首都满员则拒绝
	if units_on_tile(str(state.get("capital", ""))).size() >= UnitDB.UNITS_PER_TILE:
		return "首都已驻满 %d 个单位，先空出位置再征兵" % UnitDB.UNITS_PER_TILE
	return ""


func recruit_soldier(profession: String) -> Dictionary:
	var why := recruit_blocked_reason(profession)
	if why != "":
		return {"ok": false, "why": why}
	pay(RECRUIT_COST)
	# v1.5：公民必须存在于大世界 —— 直接派驻首都
	var cap_key := str(state.get("capital", ""))
	var nm := "%s·募集兵" % UnitDB.profession_name(profession)
	var u := UnitDB.make_soldier("recruit", profession, UnitDB.RECRUIT, nm, 1)
	u["tile"] = cap_key
	u["acquired_cycle"] = int(state["cycle"])
	u["move_left"] = max_move(u)
	(state["units"] as Array).append(u)
	add_log("招募了 %s（进驻首都）。" % nm, "unit")
	state_changed.emit()
	return {"ok": true, "why": "", "unit": u}


## 战斗模拟：让某单位的队伍去打一块敌方地块（抽象结算，替代战棋）
## 返回详细的战斗日志，供 UI 展示
func simulate_battle(key: String) -> Dictionary:
	var tile := tile_at(key)
	if tile.is_empty():
		return {"ok": false, "why": "地块不存在"}
	var owner: String = tile.get("owner", "")
	if owner == "" or owner == "player":
		return {"ok": false, "why": "该地块不是敌方地块"}
	var attackers := units_on_tile_neighbors(key)
	if attackers.is_empty():
		return {"ok": false, "why": "相邻我方地块没有驻军，请先派驻单位"}
	var enemy_force := float(tile.get("force", Consts.WANDER_FORCE))
	var log_lines: Array[String] = []
	var total_damage := 0.0
	var enemy_hp := enemy_force * Consts.ENEMY_HP_MUL
	var advantage_hits := 0

	# 敌方也要选目标：高危以上才会考虑克制，否则随机（v1.1 第 30 条）
	var is_high_risk: bool = tile.get("danger", false) or tile.get("threat", false)
	var enemy_profession := _enemy_profession(tile)

	for u in attackers:
		if enemy_hp <= 0.0:
			break
		var my_prof := str(u.get("profession", UnitDB.MELEE))
		# 敌方 AI：高危敌人会挑被自己克制的目标，否则随机
		var enemy_attacker := {"profession": enemy_profession, "attr": {"atk": enemy_force * Consts.ENEMY_ATK_MUL}}
		var adv := UnitDB.advantage(my_prof, enemy_profession)
		var r := UnitDB.resolve_damage(u, enemy_attacker)
		enemy_hp -= float(r["damage"])
		total_damage += float(r["damage"])
		var tag := ""
		if adv > 0:
			tag = "（克制！）"
			advantage_hits += 1
		elif adv < 0:
			tag = "（被克制）"
		log_lines.append("%s[%s] 对 %s 造成 %.1f 伤害%s" % [
			str(u["name"]), UnitDB.profession_name(my_prof),
			enemy_label(tile), float(r["damage"]), tag])
		gain_exp(str(u["uid"]), 12, "combat")

	# 敌人反击：随机挑一个攻击单位（高危才会优先针对克制目标）
	var counter_target: Dictionary = {}
	if not attackers.is_empty():
		if is_high_risk:
			for u2 in attackers:
				if UnitDB.advantage(enemy_profession, str(u2.get("profession", ""))) > 0:
					counter_target = u2
					break
		if counter_target.is_empty():
			counter_target = attackers[randi() % attackers.size()]
	if not counter_target.is_empty():
		var cr := UnitDB.resolve_damage(
			{"profession": enemy_profession, "attr": {"atk": enemy_force * Consts.ENEMY_ATK_MUL_LOW}},
			counter_target)
		log_lines.append("%s 反击 %s，造成 %.1f 伤害" % [
			enemy_label(tile), str(counter_target["name"]), float(cr["damage"])])

	var won := enemy_hp <= 0.0
	if won:
		on_enemy_killed(tile)   # 依据击杀时的敌人类型给行政产出 buff（须在清空标记前）
		clear_enemy_tile(key)
		log_lines.append("战斗胜利：%s 被清剿。" % key)
		add_log("战斗胜利：%s 的%s被消灭。" % [key, enemy_label(tile)], "combat")
	else:
		log_lines.append("战斗未决：敌方剩余战力 %.0f。" % (enemy_hp * 0.5))
		add_log("战斗未决：%s 的敌人仍在顽抗。" % key, "combat")

	state_changed.emit()
	return {
		"ok": true, "why": "", "won": won, "lines": log_lines,
		"damage": total_damage, "advantage_hits": advantage_hits,
		"attackers": attackers.size(), "high_risk": is_high_risk,
	}


## 参与进攻的单位：与目标相邻的我方地块上的驻军
func units_on_tile_neighbors(key: String) -> Array:
	var out := []
	for n in Hex.neighbors(WorldGen.coord_of(key)):
		var nk := WorldGen.key_of(n)
		var t := tile_at(nk)
		if t.is_empty() or t.get("owner", "") != "player":
			continue
		out.append_array(units_on_tile(nk))
	return out


## v1.7：清空一块敌方地块（击杀 / 清剿 / 作弊摧毁共用同一份 teardown）。
## 以前这段在 4 个地方各写了一遍，口径已经漂移。返回"清空之前是否为终极威胁"，
## 便于调用方决定文案与威胁列表的处理。
func clear_enemy_tile(key: String) -> bool:
	var t := tile_at(key)
	if t.is_empty():
		return false
	var was_threat: bool = t.get("threat", false)
	t["owner"] = ""
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


## v1.7：地块 -> 敌人显示名（唯一出口；词表在 Consts.ENEMY_LABELS）
static func enemy_label(tile: Dictionary) -> String:
	if tile.get("threat", false):
		return str(Consts.ENEMY_LABELS["threat"])
	if tile.get("danger", false):
		return str(Consts.ENEMY_LABELS["danger"])
	return str(Consts.ENEMY_LABELS["wander"])


## 敌人也有职业：高危据点/威胁是防御型，游荡敌人随机
static func _enemy_profession(tile: Dictionary) -> String:
	if tile.get("threat", false):
		return UnitDB.PROJECTILE
	if tile.get("danger", false):
		return UnitDB.DEFENDER
	var h := int(absf(float(tile.get("force", 5.0)) * 7.0)) % UnitDB.PROFESSION_ORDER.size()
	return UnitDB.PROFESSION_ORDER[h]


# ===========================================================================
# 建筑操作（v1.3.1：按可用土地计容；同种可重复；修建走「即时或规划队列」）
# ===========================================================================
func tile_building(tile: Dictionary, id: String) -> Dictionary:
	## 返回该地块上首个同 id 建筑（兼容旧调用）
	for b in tile.get("buildings", []):
		if b.get("id", "") == id:
			return b
	return {}


func tile_buildings_of(tile: Dictionary, id: String) -> Array:
	var out := []
	for b in tile.get("buildings", []):
		if b.get("id", "") == id:
			out.append(b)
	return out


func tile_building_by_bid(tile: Dictionary, bid: String) -> Dictionary:
	for b in tile.get("buildings", []):
		if str(b.get("bid", "")) == bid:
			return b
	return {}


## 校验能否在此地块建造该建筑（只看归属 / 科技 / 可用土地；付不付得起交给队列）
func can_build(tile: Dictionary, def: BuildingDef) -> Dictionary:
	if tile.is_empty():
		return {"ok": false, "why": "地块不存在"}
	if tile.get("owner", "") != "player":
		return {"ok": false, "why": "该地块尚未被占领"}
	if def.required_tech != "" and not tech_unlocked(def.required_tech):
		return {"ok": false, "why": "需要科技：%s" % tech_name(def.required_tech)}
	if land_used(tile) + def.land > land_cap(tile) + 0.0001:
		return {"ok": false, "why": "可用土地不足（需 %.1f，剩余 %.1f）" % [def.land, land_free(tile)]}
	return {"ok": true, "why": ""}


## 建造入口：生产力够则立即建成，不够则进规划队列
func build(tile_key: String, id: String) -> Dictionary:
	return request_build(tile_key, id)


func request_build(tile_key: String, id: String) -> Dictionary:
	var def := find_building(id)
	if def == null:
		return {"ok": false, "why": "未知建筑"}
	var tile := tile_at(tile_key)
	var chk := can_build(tile, def)
	if not chk["ok"]:
		return chk
	var cost := def.upgrade_cost(1)
	var non_prod := _non_production_cost(cost)
	if not can_afford(non_prod):
		return {"ok": false, "why": "资源不足（%s）" % cost_to_text(non_prod)}
	pay(non_prod)
	var item := {
		"kind": "build", "tile": tile_key, "id": id, "level": 1, "bid": "",
		"need_prod": float(cost.get("production", 0.0)), "paid_prod": 0.0,
	}
	var queued := _enqueue(item, tile_key)
	_add_log("%s：%s" % ["已加入规划队列" if queued else "建造", def.display_name], "build")
	_recompute_derived()
	state_changed.emit()
	return {"ok": true, "why": "", "queued": queued}


## 入队：先把现有储量生产力灌进该项，够则立刻完成，否则 append 到据点队列
func _enqueue(item: Dictionary, tile_key: String) -> bool:
	var tile := tile_at(tile_key)
	var sh := stronghold_by_id(stronghold_of(tile))
	if sh.is_empty():
		sh = current_stronghold()
	var need: float = float(item["need_prod"]) - float(item["paid_prod"])
	var give := minf(res("production"), maxf(0.0, need))
	if give > 0.0:
		add_res("production", -give)
		item["paid_prod"] = float(item["paid_prod"]) + give
	if float(item["paid_prod"]) + 0.0001 >= float(item["need_prod"]):
		_execute_queue_item(item)
		return false
	if sh.is_empty():
		return false
	(sh["queue"] as Array).append(item)
	return true


## 完成一个队列项（真正落地建筑 / 升级）
func _execute_queue_item(item: Dictionary) -> void:
	var tile := tile_at(str(item.get("tile", "")))
	if tile.is_empty():
		return
	var def := find_building(str(item.get("id", "")))
	if str(item.get("kind", "")) == "build":
		if not tile.has("buildings"):
			tile["buildings"] = []
		(tile["buildings"] as Array).append({
			"bid": _new_bid(), "id": str(item["id"]), "level": 1, "workers": 0,
		})
	else:
		var b := tile_building_by_bid(tile, str(item.get("bid", "")))
		if b.is_empty():
			return   # 目标建筑已被摧毁，项目作废
		b["level"] = int(item.get("level", 1))
	if def != null:
		_add_log("%s完成：%s" % [
			"建造" if str(item.get("kind", "")) == "build" else "升级", def.display_name], "build")


## 每周期用可用生产力推进队列；返回未被队列消耗的生产力
func _process_build_queue(avail: float) -> float:
	for sh in strongholds():
		var q: Array = sh.get("queue", [])
		var i := 0
		while i < q.size():
			if avail <= 0.0:
				break
			var item: Dictionary = q[i]
			var need := float(item.get("need_prod", 0.0)) - float(item.get("paid_prod", 0.0))
			var put := minf(avail, maxf(0.0, need))
			item["paid_prod"] = float(item.get("paid_prod", 0.0)) + put
			avail -= put
			if float(item["paid_prod"]) + 0.0001 >= float(item.get("need_prod", 0.0)):
				q.remove_at(i)
				_execute_queue_item(item)   # 完成后下一项顶上，不 i++
			else:
				break   # 队首未完成，后面的不推进
	return maxf(0.0, avail)


# ===========================================================================
# v1.8.3：政事队列（吃行政点数）
# ===========================================================================
## 政事能不能排？"" 表示可以。同样**只检查，不改状态**。
func decree_blocked_reason(id: String) -> String:
	if not DecreeDB.exists(id):
		return "没有这条政事"
	if id == DecreeDB.RECRUIT:
		return recruit_blocked_reason(UnitDB.MELEE)
	return ""


## 把一条政事排进据点队列
func enqueue_decree(id: String, profession: String = UnitDB.MELEE) -> Dictionary:
	if not DecreeDB.exists(id):
		return {"ok": false, "why": "没有这条政事"}
	var why := decree_blocked_reason(id)
	if why != "":
		return {"ok": false, "why": why}
	var sh := current_stronghold()
	if sh.is_empty():
		return {"ok": false, "why": "没有据点"}
	if not sh.has("decrees"):
		sh["decrees"] = []
	(sh["decrees"] as Array).append({
		"id": id,
		"profession": profession,
		"cost": DecreeDB.cost_of(id),
		"paid": 0.0,
	})
	add_log("政事「%s」已排入队列。" % DecreeDB.display_name(id), "admin")
	state_changed.emit()
	return {"ok": true, "why": ""}


## 每周期用**当期入账的行政点数**推进政事队列。
## 结构与 _process_build_queue 一致：**队首没办完，后面的不推进**（避免摊薄）。
func _process_decree_queue(avail: float) -> void:
	for sh in strongholds():
		var q: Array = sh.get("decrees", [])
		var i := 0
		while i < q.size():
			if avail <= 0.0:
				break
			var item: Dictionary = q[i]
			var need := float(item.get("cost", 0.0)) - float(item.get("paid", 0.0))
			var put := minf(avail, maxf(0.0, need))
			item["paid"] = float(item.get("paid", 0.0)) + put
			avail -= put
			if float(item["paid"]) + 0.0001 >= float(item.get("cost", 0.0)):
				q.remove_at(i)
				_execute_decree(item)
			else:
				break


## 政事完成时执行效果。
## 若效果**执行不了**（前置在这期间变了，比如首都已驻满），
## **把已投入的行政点数退还**并记日志 —— 不白吞玩家的点数。
func _execute_decree(item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	var paid := float(item.get("paid", 0.0))
	if id == DecreeDB.RECRUIT:
		var r := recruit_soldier(str(item.get("profession", UnitDB.MELEE)))
		if bool(r["ok"]):
			add_log("政事「征兵」完成：%s 进驻首都。" % str((r["unit"] as Dictionary).get("name", "")), "admin")
		else:
			add_res("admin", paid)
			add_log("政事「征兵」未能执行（%s），已退还行政点数 %.1f。" % [str(r["why"]), paid], "admin")
	else:
		add_res("admin", paid)
		add_log("未知政事「%s」，已退还行政点数 %.1f。" % [id, paid], "admin")


## 队列编辑（UI 用）
func queue_move(sid: String, index: int, delta: int) -> void:
	var sh := stronghold_by_id(sid)
	if sh.is_empty():
		return
	var q: Array = sh.get("queue", [])
	var j := index + delta
	if index < 0 or index >= q.size() or j < 0 or j >= q.size():
		return
	var tmp: Variant = q[index]
	q[index] = q[j]
	q[j] = tmp
	state_changed.emit()


func queue_remove(sid: String, index: int) -> void:
	var sh := stronghold_by_id(sid)
	if sh.is_empty():
		return
	var q: Array = sh.get("queue", [])
	if index < 0 or index >= q.size():
		return
	q.remove_at(index)
	state_changed.emit()


## 移除所有指向某建筑实例的队列项（该建筑被摧毁 / 降级时用）
func drop_queue_items_for_bid(bid: String) -> void:
	if bid == "":
		return
	for sh in strongholds():
		var q: Array = sh.get("queue", [])
		var kept: Array = []
		for item in q:
			if str(item.get("bid", "")) != bid:
				kept.append(item)
		sh["queue"] = kept


func _non_production_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost.keys():
		if str(k) != "production":
			out[k] = cost[k]
	return out


func request_upgrade_by_bid(tile_key: String, bid: String) -> Dictionary:
	var tile := tile_at(tile_key)
	var b := tile_building_by_bid(tile, bid)
	if b.is_empty():
		return {"ok": false, "why": "该地块没有此建筑"}
	return _request_upgrade_instance(tile_key, b)


func _request_upgrade_instance(tile_key: String, b: Dictionary) -> Dictionary:
	var def := find_building(str(b.get("id", "")))
	if def == null:
		return {"ok": false, "why": "未知建筑"}
	var lv := int(b.get("level", 1))
	if lv >= def.level_cap():
		return {"ok": false, "why": "已达等级上限"}
	var target := lv + 1
	var cost := def.upgrade_cost(target)
	var non_prod := _non_production_cost(cost)
	if not can_afford(non_prod):
		return {"ok": false, "why": "资源不足（%s）" % cost_to_text(non_prod)}
	pay(non_prod)
	var item := {
		"kind": "upgrade", "tile": tile_key, "id": str(b.get("id", "")),
		"level": target, "bid": str(b.get("bid", "")),
		"need_prod": float(cost.get("production", 0.0)), "paid_prod": 0.0,
	}
	var queued := _enqueue(item, tile_key)
	_add_log("%s → Lv.%d：%s" % [def.display_name, target,
		"已加入规划队列" if queued else "升级完成"], "build")
	_recompute_derived()
	state_changed.emit()
	return {"ok": true, "why": "", "queued": queued}


## 指派 / 撤回人力（delta 可正可负）；按 id 命中首个同种建筑
func assign_worker(tile_key: String, id: String, delta: int) -> Dictionary:
	var tile := tile_at(tile_key)
	var b := tile_building(tile, id)
	if b.is_empty():
		return {"ok": false, "why": "该地块没有此建筑"}
	return _assign_worker_instance(b, delta)


func assign_worker_by_bid(tile_key: String, bid: String, delta: int) -> Dictionary:
	var tile := tile_at(tile_key)
	var b := tile_building_by_bid(tile, bid)
	if b.is_empty():
		return {"ok": false, "why": "该地块没有此建筑"}
	return _assign_worker_instance(b, delta)


func _assign_worker_instance(b: Dictionary, delta: int) -> Dictionary:
	var def := find_building(str(b.get("id", "")))
	if def == null:
		return {"ok": false, "why": "未知建筑"}
	var cur := int(b.get("workers", 0))
	var cap := def.max_workers(int(b["level"]))
	if delta > 0:
		if cur >= cap:
			return {"ok": false, "why": "已达该等级人力上限（%d）" % cap}
		if free_pop() <= 0:
			return {"ok": false, "why": "没有空闲人力"}
	b["workers"] = clampi(cur + delta, 0, cap)
	_recompute_derived()
	state_changed.emit()
	return {"ok": true, "why": ""}


## 该地块当前建筑的产出预览
func tile_yield(tile: Dictionary) -> Dictionary:
	var out := {}
	for b in tile.get("buildings", []):
		var def := find_building(b.get("id", ""))
		if def == null:
			continue
		var lv := int(b.get("level", 1))
		var w := int(b.get("workers", 0))
		var y := def.yield_now(lv, w)
		# 矿场：依赖地块资源点
		var uses_node := bool(BuildingDB.meta_of(def, "uses_node", false))
		if uses_node and tile.get("resource", "") != "":
			var bonus := float(BuildingDB.meta_of(def, "node_bonus", 1.0)) \
				+ float(BuildingDB.meta_of(def, "node_bonus_per_level", 0.25)) * float(lv)
			var rk: String = tile["resource"]
			y[rk] = float(y.get(rk, 0.0)) + bonus
		# 磨坊等：人力维护
		var upk: Dictionary = BuildingDB.meta_of(def, "upkeep_per_worker", {})
		for k in upk.keys():
			y[k] = float(y.get(k, 0.0)) - float(upk[k]) * float(w)
		for k in y.keys():
			out[k] = float(out.get(k, 0.0)) + float(y[k])
	return out


## 首都民居按照「房屋比例」给金币
func _housing_gold(level: int) -> float:
	var def := find_building("classic_house")
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
	for t in owned_tiles():
		var y := tile_yield(t)
		for k in y.keys():
			income[k] = float(income.get(k, 0.0)) + float(y[k])
	# 民居金币
	for t in owned_tiles():
		for b in t.get("buildings", []):
			if b.get("id", "") == "classic_house":
				income["currency"] = float(income.get("currency", 0.0)) + _housing_gold(int(b.get("level", 1)))

	# 2. 领地基础产出与建筑维护
	var owned_list := owned_tiles()
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
	_units_upkeep_into(income, upkeep)

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
	var leftover := _process_build_queue(prod_avail)
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
	WorldGen.evolve(state, _rng, report)

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
	settle_admin(report)

	# 9.6 v1.8.3：政事队列推进。
	# 必须排在 9.5 之后 —— 它吃的是"本期刚入账的行政点数"
	#（与规划队列吃当期生产力同一套手感）。
	_process_decree_queue(float((report.get("income", {}) as Dictionary).get("admin", 0.0)))

	# 10. 单位经验：通过周期循环缓缓增长（每个单位最多因此获得 100 点）
	grow_unit_exp(report)

	# 10.5 v1.5：客人离去判定 + 单位移动力重置
	guest_leave_tick(report)
	reset_unit_moves()

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
	return 1 + int(state["techs"].size()) + int(float(owned_tiles().size()) / 4.0) \
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
	var guest_coh := Consts.GUEST_COHESION_PER_CYCLE * float(guest_units().size())
	cohesion += guest_coh
	add_res("cohesion", cohesion)
	report["income"]["order_crystal"] = float(report["income"].get("order_crystal", 0.0)) + crystal
	report["income"]["cohesion"] = float(report["income"].get("cohesion", 0.0)) + cohesion


# ===========================================================================
# v1.3.1 行政点数
#   基底每周期 +1（永久）；其余来源都是限时 buff / debuff（state["admin_effects"]）。
#   另有「当期收支项」：每条为正 +0.1、每条为 0/负 -0.1（每周期按当期经济重算）。
# ===========================================================================
## 当期经济各资源净收支（用于行政点数的收支项判定）
func _balance_lines() -> Array[float]:
	var inc := {}
	for t in owned_tiles():
		var y := tile_yield(t)
		for k in y.keys():
			inc[k] = float(inc.get(k, 0.0)) + float(y[k])
	var owned := owned_tiles()
	if not owned.is_empty():
		inc["production"] = float(inc.get("production", 0.0)) \
			+ Consts.PRODUCTION_PER_TILE * float(owned.size())
	for t in owned:
		for b in t.get("buildings", []):
			inc["production"] = float(inc.get("production", 0.0)) \
				- Consts.BUILDING_UPKEEP_PRODUCTION * float(b.get("level", 1))
	inc["food"] = float(inc.get("food", 0.0)) \
		- Consts.FOOD_UPKEEP_PER_POP * float(state["pop_total"])
	# v1.5：单位维护费也算进当期收支（否则行政点数的收支项判定会与真实收支不符）
	var tot2 := units_upkeep_total()
	inc["food"] = float(inc.get("food", 0.0)) - float(tot2["food"])
	inc["currency"] = float(inc.get("currency", 0.0)) - float(tot2["currency"])
	var lines: Array[float] = []
	for k in inc.keys():
		lines.append(float(inc[k]))
	return lines


func settle_admin(report: Dictionary) -> void:
	var base := Consts.ADMIN_BASE_PER_CYCLE
	var buffs := 0.0
	for e in state.get("admin_effects", []):
		buffs += float(e.get("delta", 0.0))
	var pos := 0
	var neg := 0
	for v in _balance_lines():
		if v > 0.0:
			pos += 1
		else:
			neg += 1
	var lines_delta := Consts.ADMIN_PER_POSITIVE_LINE * float(pos) \
		- Consts.ADMIN_PER_NEGATIVE_LINE * float(neg)
	var income := maxf(0.0, base + buffs + lines_delta)
	add_res("admin", income)
	# 计时递减 + 清理过期项
	var kept: Array = []
	for e in state.get("admin_effects", []):
		e["remaining"] = int(e.get("remaining", 0)) - 1
		if int(e["remaining"]) > 0:
			kept.append(e)
	state["admin_effects"] = kept
	if not report.has("income"):
		report["income"] = {}
	report["income"]["admin"] = float(report["income"].get("admin", 0.0)) + income
	if pos > 0 or neg > 0:
		report["events"].append("行政点数 +%.1f（基底 %.1f｜buff %+.1f｜收支 %d正/%d负）" % [
			income, base, buffs, pos, neg])


## 击杀敌对单位后的行政产出 buff（作弊摧毁不调用）
func on_enemy_killed(tile: Dictionary) -> void:
	if tile.is_empty():
		return
	var kind := _enemy_admin_kind(tile)
	if kind == "" or not Consts.ADMIN_KILL_BUFFS.has(kind):
		return
	var b: Dictionary = Consts.ADMIN_KILL_BUFFS[kind]
	_add_admin_effect(float(b["delta"]), int(b["duration"]), "击杀%s" % _enemy_admin_label(kind))


## 友军阵亡后的行政产出 debuff（预留：当前 Demo 无单位阵亡机制）
func on_unit_died(rank: String) -> void:
	if not Consts.ADMIN_DEATH_DEBUFFS.has(rank):
		return
	var b: Dictionary = Consts.ADMIN_DEATH_DEBUFFS[rank]
	_add_admin_effect(-float(b["delta"]), int(b["duration"]), "%s阵亡" % UnitDB.rank_name(rank))


func _add_admin_effect(delta: float, duration: int, label: String) -> void:
	if not state.has("admin_effects"):
		state["admin_effects"] = []
	(state["admin_effects"] as Array).append({
		"delta": delta, "remaining": duration,
		"source": "kill" if delta > 0.0 else "death", "label": label,
	})
	_add_log("行政影响：%s，每周期 %+.1f（持续 %d 周期）。" % [label, delta, duration], "world")


static func _enemy_admin_kind(tile: Dictionary) -> String:
	if tile.get("threat", false):
		return "threat"
	if tile.get("danger", false):
		return "fortress" if float(tile.get("force", 0.0)) >= Consts.EXTREME_HAZARD_FORCE else "danger"
	if tile.get("wander", false):
		return "high" if float(tile.get("force", 0.0)) >= Consts.HIGH_WANDER_FORCE else "danger"
	return ""


static func _enemy_admin_label(kind: String) -> String:
	return str(Consts.ENEMY_LABELS.get(kind, Consts.ENEMY_LABELS["unknown"]))


## 某项资源的「每周期收支明细」（供顶部资源栏点击悬浮窗使用，v1.4.1）
## 返回 { "income": [{label, amount}...], "upkeep": [{label, amount}...] }，amount 正为收入、负为支出
func resource_breakdown(key: String) -> Dictionary:
	var inc: Array = []
	var upk: Array = []
	var building_out := 0.0
	for t in owned_tiles():
		var y := tile_yield(t)
		building_out += float(y.get(key, 0.0))
		if key == "currency":
			for b in t.get("buildings", []):
				if str(b.get("id", "")) == "classic_house":
					building_out += _housing_gold(int(b.get("level", 1)))
	if absf(building_out) > 0.0001:
		inc.append({"label": "建筑产出", "amount": building_out})
	if key == "production":
		var territory := Consts.PRODUCTION_PER_TILE * float(owned_tiles().size())
		if territory > 0.0001:
			inc.append({"label": "领地", "amount": territory})
	# 周期结算类（抽卡货币 / 行政）
	if key == "order_crystal":
		inc.append({"label": "周期结算", "amount":
			Consts.CRYSTAL_PER_CYCLE + Consts.CRYSTAL_PER_LEVEL * float(player_level())})
	elif key == "cohesion":
		var hp := happiness()
		inc.append({"label": "周期结算", "amount":
			(Consts.COHESION_PER_CYCLE + Consts.COHESION_PER_HAPPINESS * hp)
			* (1.0 + culture_rate() * Consts.COHESION_CULTURE_BONUS)})
	elif key == "admin":
		inc.append({"label": "行政基底", "amount": Consts.ADMIN_BASE_PER_CYCLE})
		var buffs := 0.0
		for e in state.get("admin_effects", []):
			buffs += float(e.get("delta", 0.0))
		if absf(buffs) > 0.0001:
			inc.append({"label": "击杀/阵亡 buff", "amount": buffs})
		var pos := 0
		var neg := 0
		for v in _balance_lines():
			if v > 0.0:
				pos += 1
			else:
				neg += 1
		var ld := Consts.ADMIN_PER_POSITIVE_LINE * float(pos) - Consts.ADMIN_PER_NEGATIVE_LINE * float(neg)
		if absf(ld) > 0.0001:
			inc.append({"label": "收支项（%d正/%d负）" % [pos, neg], "amount": ld})
	# 维护 / 消耗
	if key == "production":
		var bup := 0.0
		for t in owned_tiles():
			for b in t.get("buildings", []):
				bup += Consts.BUILDING_UPKEEP_PRODUCTION * float(int(b.get("level", 1)))
		if bup > 0.0001:
			upk.append({"label": "建筑维护", "amount": -bup})
	elif key == "food":
		var fup := Consts.FOOD_UPKEEP_PER_POP * float(state["pop_total"])
		if fup > 0.0001:
			upk.append({"label": "人口维护", "amount": -fup})
		var uf := float(units_upkeep_total()["food"])
		if uf > 0.0001:
			upk.append({"label": "单位维护", "amount": -uf})
	elif key == "currency":
		var um := float(units_upkeep_total()["currency"])
		if um > 0.0001:
			upk.append({"label": "单位维护", "amount": -um})
	return {"income": inc, "upkeep": upk}


## v1.7：统一的「每周期收支估算」出口。
## 直接复用 resource_breakdown()（顶部资源栏悬浮窗用的同一份口径），
## 这样管理页、悬浮窗、真实结算三者不会再各算一套、数字打架。
func income_estimate() -> Dictionary:
	var out := {}
	for k in Consts.RES_KEYS:
		var bd := resource_breakdown(k)
		var sum := 0.0
		for e in bd["income"]:
			sum += float(e["amount"])
		for e in bd["upkeep"]:
			sum += float(e["amount"])
		if absf(sum) > 0.0001:
			out[k] = sum
	return out


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
# 科技
# ===========================================================================
func tech_name(id: String) -> String:
	for t in Consts.TECHS:
		if t["id"] == id:
			return t["name"]
	if id == "genesis_crystal":
		return "创世结晶"
	return id


func can_research(id: String) -> Dictionary:
	var def: Dictionary = {}
	for t in Consts.TECHS:
		if t["id"] == id:
			def = t
			break
	if def.is_empty():
		return {"ok": false, "why": "未知科技"}
	if tech_unlocked(id):
		return {"ok": false, "why": "已研究"}
	for p in def["prereq"]:
		# 前置可能是科技，也可能是「发展抽卡得到的标记」
		if tech_unlocked(p) or has_flag(p):
			continue
		return {"ok": false, "why": "缺少前置：%s" % tech_name(p)}
	if res("research") < float(def["cost"]):
		return {"ok": false, "why": "科研点不足（需要 %d）" % int(def["cost"])}
	return {"ok": true, "why": ""}


func research(id: String) -> Dictionary:
	var chk := can_research(id)
	if not chk["ok"]:
		return chk
	for t in Consts.TECHS:
		if t["id"] == id:
			add_res("research", -float(t["cost"]))
			state["techs"].append(id)
			var names: Array[String] = []
			for bid in t["unlocks"]:
				var bd := find_building(bid)
				if bd != null:
					names.append(bd.display_name)
			_add_log("研究完成：%s（解锁 %s）" % [t["name"], "、".join(names)], "tech")
			break
	state_changed.emit()
	return {"ok": true, "why": ""}


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
	_migrate()
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
# 自动存档周期数 + 作弊功能
#
# 注意：这两项是**全局设置**，存在 AppSettings 里（user://settings.cfg），
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


func cheat_enabled() -> bool:
	return AppSettings.cheat_enabled()


func set_cheat_enabled(on: bool) -> void:
	AppSettings.set_cheat_enabled(on)
	if on:
		_add_log("作弊功能已开启。", "cheat")
		toast.emit("作弊功能已开启")
	else:
		_add_log("作弊功能已关闭。", "cheat")
		toast.emit("作弊功能已关闭")
	state_changed.emit()


## 作弊：批量增加资源
func cheat_add_resources(amounts: Dictionary) -> void:
	var parts: Array[String] = []
	for k in amounts.keys():
		var v := float(amounts[k])
		if v == 0.0:
			continue
		if k == "pop_total":
			state["pop_total"] = clampi(int(state["pop_total"]) + int(v), 1, Consts.POP_HARD_CAP)
			parts.append("人力 %+d" % int(v))
		else:
			add_res(str(k), v)
			parts.append("%s %+d" % [Consts.res_name(str(k)), int(v)])
	if parts.is_empty():
		toast.emit("没有填写任何数量")
		return
	_add_log("【作弊】获得 %s。" % "、".join(parts), "cheat")
	toast.emit("作弊生效：" + "、".join(parts))
	state_changed.emit()


## 作弊：直接摧毁地块上的敌对单位
func cheat_destroy_tile(key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return {"ok": false, "why": "地块不存在"}
	var t: Dictionary = tiles[key]
	var owner: String = t.get("owner", "")
	if owner == "" or owner == "player":
		return {"ok": false, "why": "该地块没有敌对单位"}
	var label := enemy_label(t)
	clear_enemy_tile(key)
	_add_log("【作弊】直接摧毁了 %s 的%s。" % [key, label], "cheat")
	state_changed.emit()
	return {"ok": true, "why": "", "label": label}


## 作弊：一键清空大世界里所有敌对单位
func cheat_destroy_all_enemies() -> int:
	var keys: Array[String] = []
	for k in (state["tiles"] as Dictionary).keys():
		var t: Dictionary = state["tiles"][k]
		var o: String = t.get("owner", "")
		if o != "" and o != "player":
			keys.append(str(k))
	for k in keys:
		cheat_destroy_tile(k)
	toast.emit("已摧毁 %d 个敌对单位" % keys.size())
	return keys.size()


## 作弊：**点亮全部迷雾**（把所有地块标为已发现）—— 一次性动作，不能盖回去
func cheat_reveal_all() -> int:
	var n := 0
	for k in (state["tiles"] as Dictionary).keys():
		var t: Dictionary = state["tiles"][k]
		if not bool(t.get("discovered", false)):
			t["discovered"] = true
			n += 1
	_add_log("【作弊】点亮了全部迷雾（%d 格）。" % n, "cheat")
	toast.emit("已点亮全部迷雾（%d 格）" % n)
	state_changed.emit()
	return n

func has_continue() -> bool:
	return slot_exists(Consts.AUTOSAVE_SLOT)


func continue_game() -> bool:
	return load_from_slot(Consts.AUTOSAVE_SLOT)


func any_save() -> bool:
	for i in Consts.SAVE_SLOTS:
		if slot_exists(i):
			return true
	return false


## 兼容旧存档缺失字段
func _migrate() -> void:
	var defaults: Dictionary = {
		"cycle": 1, "current_slot": -1, "pop_total": Consts.POP_START,
		"tiles": {}, "capital": "0,0", "units": [], "equipment": [],
		"items": {}, "affinity": {}, "active_group": "提瓦特",
		"techs": [], "techs_owned_flags": [], "log": [], "manual_log": [],
		"threats": [], "training_queue": [], "playtime": 0.0,
		"task_groups": [], "tasks": [], "tasks_done": [], "_group_open": {},
		"enemy_killed": 0,
		"strongholds": [], "admin_effects": [],
	}
	for k in defaults.keys():
		if not state.has(k):
			state[k] = defaults[k]

	# v1.3.1：据点 + 地块土地 + 建筑实例 id
	if (state.get("strongholds", []) as Array).is_empty():
		_setup_capital_stronghold()
	var land_fixed := false
	for tk in (state.get("tiles", {}) as Dictionary).keys():
		var t: Dictionary = state["tiles"][tk]
		if t.get("owner", "") != "player":
			continue
		if str(t.get("stronghold", "")) == "":
			t["stronghold"] = CAPITAL_STRONGHOLD
		if not t.has("land_cap"):
			t["land_cap"] = Consts.LAND_CAP_DEFAULT
		if not t.has("buildings"):
			t["buildings"] = []
		var used := 0.0
		for b in t["buildings"]:
			if str(b.get("bid", "")) == "":
				b["bid"] = _new_bid()
			var bd := find_building(str(b.get("id", "")))
			if bd != null:
				used += bd.land
		# 旧存档可能一地满是建筑：把土地上限抬到恰好容纳现有建筑，避免读档即丢建筑
		if used > float(t.get("land_cap", Consts.LAND_CAP_DEFAULT)) + 0.0001:
			t["land_cap"] = used
			land_fixed = true
	if land_fixed:
		_add_log("旧存档已按现有建筑放宽地块的可用土地上限。", "info")

	if not state.has("teams") or (state["teams"] as Array).is_empty():
		state["teams"] = [
			{"name": "第一队", "members": []},
			{"name": "第二队", "members": []},
			{"name": "第三队", "members": []},
		]
	# 补齐单位缺失字段
	for u in state["units"]:
		if not u.has("uid"):
			u["uid"] = "u_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
		if not u.has("profession"):
			u["profession"] = CardDB.profession_of(u)
		if not u.has("rank"):
			u["rank"] = UnitDB.HERO
		if not u.has("exp"):
			u["exp"] = 0
			u["exp_from_cycles"] = 0
			u["exp_from_combat"] = 0
		if not u.has("unit_type"):
			u["unit_type"] = "character"
		if not u.has("team"):
			u["team"] = -1
		if not u.has("tile"):
			u["tile"] = ""
		if not u.has("unique"):
			u["unique"] = []
		# v1.5：客人 / 公民 + 血量 / 移动力
		if not u.has("status"):
			u["status"] = UnitDB.STATUS_GUEST \
				if str(u.get("unit_type", "")) == "character" else UnitDB.STATUS_CITIZEN
		if not u.has("acquired_cycle"):
			u["acquired_cycle"] = int(state.get("cycle", 1))
		if not u.has("leave_chance"):
			u["leave_chance"] = 0.0
		if not u.has("move_left"):
			u["move_left"] = 0
		if not u.has("garrisoned"):
			u["garrisoned"] = false
		if not u.has("hp") or int(u.get("hp", 0)) <= 0:
			u["hp"] = UnitDB.max_hp(u)

	if not state.has("res"):
		state["res"] = {}
	for k in Consts.RES_KEYS:
		if not (state["res"] as Dictionary).has(k):
			state["res"][k] = 0.0
	# v1.4：按存储上限夹一次（旧存档可能超过上限）
	for k in Consts.RES_KEYS:
		var cap := storage_cap(k)
		if cap >= 0.0 and float(state["res"].get(k, 0.0)) > cap:
			state["res"][k] = cap
	if not state.has("pity"):
		state["pity"] = {
			"rotation": {"since5": 0, "since4": 0, "total": 0},
			"resource": {"since4": 0, "total": 0},
			"development": {"total": 0},
		}
	if not state.has("hazard"):
		state["hazard"] = {"chance": Consts.HAZARD_BASE_CHANCE, "count": 0, "pity": 0}
	if not state.has("wander"):
		state["wander"] = {"count": 0, "pity": 0}
	for g in CardDB.GROUPS:
		if not (state["affinity"] as Dictionary).has(g):
			state["affinity"][g] = 0
