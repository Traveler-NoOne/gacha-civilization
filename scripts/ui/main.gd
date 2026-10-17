extends Control
## 入口：负责在「主页面」和「游戏主页」之间切换，并承载全局提示。

const MENU_SCENE := "res://scripts/ui/menu_screen.gd"
const GAME_SCENE := "res://scripts/ui/game_screen.gd"
const LOADING_SCENE := "res://scripts/ui/loading_screen.gd"

var _toast_layer: Control
var _toast_box: VBoxContainer
var _current: Control

@onready var _root: Control = self


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# v1.8.20：先把分辨率应用好（UI 尺寸词典 + 窗口尺寸），再搭界面
	_apply_resolution()
	_build_toast_layer()
	GameState.toast.connect(_on_toast)
	show_menu()


## v1.6：全 UI 统一黑体 —— 由**项目级主题** `scripts/ui/ui_theme.tres` 提供
## （挂在 project.godot 的 `gui/theme/custom`，所以游戏和测试都会吃到）。
## 用 SystemFont 指定黑体族，不打包字体文件。


## v1.8.20：启动时应用玩家保存的分辨率。
## 未知的值回落到基准档（`UI.set_resolution_key` 里兜底），避免手改 settings.cfg 弄出奇怪尺寸。
## v1.8.20：应用分辨率。
##
## 拆成两半，因为两件事的时机不一样：
##
## ① **档位立刻设**（`UI.set_resolution_key`）——
##    UI 是构建时按 `UI.px()/fs()` 算尺寸的，晚一帧就会按错倍率搭界面。
##
## ② **窗口尺寸必须延后**——
##    Godot 在启动时按 `project.godot` 的 `viewport_width/height` 定窗口尺寸；
##    在 `_ready()` 里立刻改会被它覆盖掉。用户实测到的现象正是这个：
##    **项目设置里改大小永远有效，游戏里怎么改、怎么重启都没用。**
##    所以等窗口真正建好（两帧）再改，最后才锁成不可缩放
##   （锁要放在尺寸之后 —— 反过来在 Windows 上尺寸会被忽略）。
func _apply_resolution() -> void:
	UI.set_resolution_key(AppSettings.resolution())


	_apply_window_size.call_deferred()


func _apply_window_size() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if AppSettings.fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_size(UI.current_size())
		await get_tree().process_frame
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	var got := DisplayServer.window_get_size()
	print("分辨率档 %s：窗口 %s（期望 %s）" % [UI.current_key(), str(got), str(UI.current_size())])
	# 编辑器「内嵌游戏窗口」模式下，Godot 会拒绝改窗口尺寸（控制台会提示 Embedded window can't be resized）
	# —— 那不是代码问题。关掉编辑器设置里的 Game Embed，或直接跑导出版即可。
	if got != UI.current_size():
		print("  （若你是在编辑器里跑：请关掉「编辑器设置 → 运行 → 游戏内嵌」，否则窗口尺寸改不了）")





func _build_toast_layer() -> void:
	_toast_layer = Control.new()
	_toast_layer.name = "ToastLayer"
	_toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_layer)
	var anchor := VBoxContainer.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	anchor.position = Vector2(UI.px(0), UI.px(16))
	anchor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.alignment = BoxContainer.ALIGNMENT_CENTER
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(anchor)
	_toast_box = VBoxContainer.new()
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_toast_box)


func _on_toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UI.fs(18))
	lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	var sb := UIKit.panel_style(Color(0.08, 0.07, 0.11, 0.92), Color(0.85, 0.7, 0.3, 0.9), 6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	_toast_box.add_child(panel)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


func _clear_current() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null


func show_menu() -> void:
	_clear_current()
	var scr: Control = load(MENU_SCENE).new()
	scr.name = "MenuScreen"
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scr)
	move_child(scr, 0)
	_current = scr
	scr.start_game_requested.connect(_on_start_game)


## v1.8.9：加载界面的**顺序**是刻意的 —— 先出界面，再干活。
## 现在加载近乎瞬间所以看不出区别；等地图内容多了，慢的部分就会花在这张界面上（而不是卡在菜单上）。
func _on_start_game(mode: String, opts: Dictionary = {}) -> void:
	show_loading(func() -> bool:
		match mode:
			"continue":
				return GameState.continue_game()
			"load":
				return true   # 由菜单自己处理读档，读成功后直接过来
			_:
				# 2026-10-15：新游戏设置面板给的种子（0 = 随机 —— new_game 里会取时钟 ✓）
				GameState.new_game(int(opts.get("seed", 0)))
				return true
	)


## v1.8.9：过场加载界面。ok=false 表示"这次进不去"（例如没有存档可继续）→ 回主菜单。
func show_loading(work: Callable) -> void:
	_clear_current()
	var scr: Control = load(LOADING_SCENE).new()
	scr.name = "LoadingScreen"
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scr)
	move_child(scr, 0)
	_current = scr
	scr.finished.connect(func(ok: bool) -> void:
		if ok:
			show_game()
		else:
			show_menu())
	scr.begin(work)


func show_game() -> void:
	_clear_current()
	var scr: Control = load(GAME_SCENE).new()
	scr.name = "GameScreen"
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scr)
	move_child(scr, 0)
	_current = scr
	scr.exit_to_menu.connect(show_menu)
