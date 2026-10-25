class_name ExitDialog
extends RefCounted
## 休眠 / 退出确认弹窗（2026-10-25 从 game_screen 拆出）✓
##
## 用法：
##     open_dialog(ExitDialog.build(close_dialog, func() -> void: exit_to_menu.emit()))
## 两个回调由 game_screen 提供 —— 这里不碰它的成员 ✓

static func build(on_close: Callable, on_exit_to_menu: Callable) -> DialogLayer:
	var d := UIKit.dialog("休眠 / 退出", 420.0)
	var v := UIKit.vbox(8)
	v.add_child(UIKit.text_label("请选择退出方式", 15, Palette.GOLD))
	var cur := int(GameState.state.get("current_slot", -1))
	if cur < 0:
		v.add_child(UIKit.dim("当前进度还没有保存过，退出前建议先保存（会存到槽位 1）。"))
	else:
		v.add_child(UIKit.dim("当前存档槽位：%d（周期 %d）。" % [cur + 1, int(GameState.state["cycle"])]))

	var to_menu := UIKit.normal("退出到主菜单（先保存）", 14)
	to_menu.pressed.connect(func() -> void:
		on_close.call()
		var slot := int(GameState.state.get("current_slot", -1))
		if slot < 0:
			slot = 1
		Save.write(slot, GameState.state)
		on_exit_to_menu.call())
	v.add_child(to_menu)

	var to_desktop := UIKit.normal("退出到桌面（先保存）", 14)
	UIKit.style_button(to_desktop, false, true)
	to_desktop.pressed.connect(func() -> void:
		on_close.call()
		var slot := int(GameState.state.get("current_slot", -1))
		if slot < 0:
			slot = 1
		Save.write(slot, GameState.state)
		Save.write(Consts.AUTOSAVE_SLOT, GameState.state)
		(Engine.get_main_loop() as SceneTree).quit())
	v.add_child(to_desktop)

	var cancel := UIKit.small("取消", 13)
	cancel.pressed.connect(func() -> void: on_close.call())
	v.add_child(cancel)

	d.set_content(v)
	return d
