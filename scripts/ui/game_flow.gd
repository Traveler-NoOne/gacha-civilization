class_name GameFlow
extends Node
## 周期结算 + 对话框 + 快速保存（2026-10-26 从 game_screen 拆出）✓
##
## 只做"流程"这一层：推一个周期、开/关弹窗、存盘、退出确认。
## 不碰地图、不碰面板布局 —— 需要的地方通过 setup() 传进来的引用调用 ✓

signal exit_to_menu
## 周期结算完了（调用方据此刷新界面）
signal cycle_finished

var _host: Control
var _manager: ManagerCenter
var _panels: PanelsHost
var _dialog: DialogLayer


func setup(host: Control, manager: ManagerCenter, panels: PanelsHost) -> void:
	_host = host
	_manager = manager
	_panels = panels


# ---------------------------------------------------------------------------
# 周期
# ---------------------------------------------------------------------------
func end_cycle() -> void:
	var rep: Dictionary = Cycle.end_cycle(GameState.state, GameState.rng())
	# 世界层 / 当前开着的浮窗页各自接收
	if _panels == null or _panels.current_view == PanelsHost.DEFAULT_VIEW:
		if _manager != null:
			_manager.on_cycle_finished(rep)
	else:
		var v: Variant = _panels.views.get(_panels.current_view, null)
		if v != null and v.has_method("on_cycle_finished"):
			v.on_cycle_finished(rep)
	# v1.2：按设置的周期数触发自动存档时给出提示
	if bool(rep.get("autosaved", false)):
		GameState.toast.emit("已自动存档（每 %d 个周期一次）" % int(rep.get("autosave_interval", 1)))
	cycle_finished.emit()


# ---------------------------------------------------------------------------
# 存档 / 退出 / 作弊
# ---------------------------------------------------------------------------
## 快速保存到当前槽位（没槽位就存 1 号）✓
func quick_save() -> void:
	var slot := int(GameState.state.get("current_slot", -1))
	if slot < 0:
		slot = 1
	Save.write(slot, GameState.state)


func confirm_exit() -> void:
	# 休眠页删除后，这里承接「退出到主菜单 / 退出到桌面」；内容在 scripts/ui/exit_dialog.gd ✓
	open_dialog(ExitDialog.build(close_dialog, func() -> void: exit_to_menu.emit()))


func open_cheat() -> void:
	open_dialog(CheatMenu.build())


# ---------------------------------------------------------------------------
# 对话框（同一时刻只留一个）
# ---------------------------------------------------------------------------
func open_dialog(d: DialogLayer) -> void:
	close_dialog()
	_dialog = d
	if _host != null and is_instance_valid(_host):
		_host.add_child(d)


func close_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func has_dialog() -> bool:
	return is_instance_valid(_dialog)
