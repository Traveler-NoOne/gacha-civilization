extends Node
## 全局应用设置（Autoload 名：AppSettings）
##
## 为什么要有这个：作弊开关、自动存档周期这类东西**不属于某一份存档**，
## 而是玩家的全局偏好。之前把它们塞在 GameState.state 里，结果
## new_game() / 读档 会重建整个 state 字典，开关就被重置回默认值了 ——
## 表现就是「勾选了作弊，一开始新游戏又变回没勾选」。
##
## 所以这里单独存一份，落到 user://settings.cfg，和存档解耦。

const SETTINGS_PATH := "user://settings.cfg"

var _cheat_enabled := false
## v1.7：默认值与上下限统一走 Consts，不再各写一份死数（原来这里写 2，常量和 fallback 写 1，自相矛盾）
var _autosave_interval: int = Consts.AUTOSAVE_INTERVAL_DEFAULT


func _ready() -> void:
	load_settings()


# ---------------------------------------------------------------------------
# 作弊功能
# ---------------------------------------------------------------------------
func cheat_enabled() -> bool:
	return _cheat_enabled


func set_cheat_enabled(on: bool) -> void:
	if _cheat_enabled == on:
		return
	_cheat_enabled = on
	save_settings()
	changed.emit()


# ---------------------------------------------------------------------------
# 自动存档周期数（默认每 1 个周期）
# ---------------------------------------------------------------------------
func autosave_interval() -> int:
	return clampi(_autosave_interval, Consts.AUTOSAVE_INTERVAL_MIN, Consts.AUTOSAVE_INTERVAL_MAX)


func set_autosave_interval(n: int) -> void:
	var v := clampi(n, Consts.AUTOSAVE_INTERVAL_MIN, Consts.AUTOSAVE_INTERVAL_MAX)
	if _autosave_interval == v:
		return
	_autosave_interval = v
	save_settings()
	changed.emit()


signal changed


# ---------------------------------------------------------------------------
# 读写
# ---------------------------------------------------------------------------
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cheat", "enabled", _cheat_enabled)
	cfg.set_value("save", "autosave_interval", _autosave_interval)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("全局设置保存失败（错误 %d）：%s" % [err, SETTINGS_PATH])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_cheat_enabled = bool(cfg.get_value("cheat", "enabled", false))
	_autosave_interval = int(cfg.get_value("save", "autosave_interval", Consts.AUTOSAVE_INTERVAL_DEFAULT))
