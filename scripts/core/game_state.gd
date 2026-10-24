extends Node
## 全局游戏状态（Autoload 单例名：GameState）
##
## 2026-10-22 解耦后，这里**只剩四件事**：
##   ① 持有 `state` 与两个信号（state_changed / toast）
##   ② 开新档 `new_game()` —— 存档结构 + 世界生成的接缝
##   ③ 装读档 `load_from_slot()` —— 文件由 `Save` 读，这里负责装进来 + 播种随机数
##   ④ 两件跨系统的小事：`clear_enemy_tile()` 与开局任务
## 规则都在 `core/` 下的各模块里（Cycle / Res / Units / Combat / Buildings / …）

## 检测状态是否改变
signal state_changed

## 全局轻提示广播
signal toast(text: String)

## 游戏状态
var state: Dictionary = {}

## 非序列化的运行时缓存
var _rng := RandomNumberGenerator.new()


## 本局随机数流（外面要摇随机就借它，别自己 new —— 否则同种子复现不了 ✓）
func rng() -> RandomNumberGenerator:
	return _rng


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(Consts.SAVE_DIR) # 读取存档目录
	# v1.8.20.8：不再无条件 randomize —— 种子由 new_game() / load_from_slot() 按状态播，否则同种子复现不了。

	if state.is_empty(): # 如果存档槽为空，初始化新游戏
		new_game()

# ===========================================================================
# 新游戏
# ===========================================================================
func new_game(seed_value: int = 0) -> void:
	var s := _resolve_seed(seed_value)
	_rng.seed = s
	state = _blank_state(s)
	WorldgenBuilder.generate(state)
	_finish_new_game()


## 分帧版新游戏：世界生成期间每帧让出一次，`on_progress(0~100)` 报告真实进度 ✓
## 加载界面用这个，避免长时间阻塞导致"看着像卡死"。
func new_game_async(seed_value: int = 0, on_progress: Callable = Callable()) -> void:
	var s := _resolve_seed(seed_value)
	_rng.seed = s
	state = _blank_state(s)
	await WorldgenBuilder.generate_async(state, on_progress)
	_finish_new_game()


## 种子 0 = 取时钟随机；同一个数字能复现同一张图 ✓
func _resolve_seed(seed_value: int) -> int:
	var s := int(seed_value)
	if s == 0:
		s = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	# v1.8.20.8：_rng 也按本局种子播（取过时钟种子后，新开一局依旧是新的）
	return s


func _blank_state(s: int) -> Dictionary:
	return {

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


## 世界已经生成好之后的收尾（同步 / 分帧两条路共用）✓
func _finish_new_game() -> void:
	TileManager.setup_new_world(state)
	Strongholds.setup_capital(state)
	Derived.recompute(state)
	Units.grant_starting(state)
	Journal.add(state, "建立部落，营地落在 %s。" % str(state["capital"]), "info")
	Journal.add(state, "初始点亮营地周围 %d 格，其余被迷雾覆盖。" % (1 + 6 * Consts.CAMP_START_RADIUS), "info")
	_setup_default_tasks()
	state_changed.emit()


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
# 读档：把存档装进本局（`Save` 只管文件；装进来 + 给随机数播种在这里）
# ===========================================================================
func load_from_slot(slot: int) -> bool:
	var loaded := Save.read(slot)
	if loaded.is_empty():
		return false
	state = loaded
	state["current_slot"] = slot
	# 读档要把种子放回 _rng，否则读回来的局与存的时候不是同一条随机流 ✓
	_rng.seed = int(state.get("seed", 0))
	toast.emit("已读取槽位 %d" % (slot + 1))
	state_changed.emit()
	return true


func continue_game() -> bool:
	return load_from_slot(Consts.AUTOSAVE_SLOT)
