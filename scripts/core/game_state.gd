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

## 本局随机数流（外面要摇随机就借它，别自己 new —— 否则同种子复现不了 ✓）
func rng() -> RandomNumberGenerator:
	return _rng
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
	Derived.recompute(state)
	Units.grant_starting(state)
	Journal._add(state, "建立部落，营地落在 %s。" % str(state["capital"]), "info")
	Journal._add(state, "初始点亮营地周围 %d 格，其余被迷雾覆盖。" % (1 + 6 * Consts.CAMP_START_RADIUS), "info")
	_setup_default_tasks()
	state_changed.emit()


# ===========================================================================
# 便捷访问
# ===========================================================================


# ===========================================================================
# 地块收尾：清空一块敌方地块（击杀 / 清剿 / 作弊摧毁共用）
# ===========================================================================
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


# ===========================================================================
# 开局任务（系统自带的任务组，玩家不能删）
# ===========================================================================
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


