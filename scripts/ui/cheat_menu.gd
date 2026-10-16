class_name CheatMenu
extends RefCounted
## 作弊菜单（独立文件）—— 数据与动作在 core/cheat.gd ✓ 这里只负责"长什么样"。
## 自洽：按钮里用传进来的 DialogLayer 自己关窗（`d.close()`），不需要宿主 game_screen ✓。

## 可作弊资源项
const CHEAT_RESOURCES := [
	["food", "食物"],
	["production", "生产力"],
	["currency", "货币"],
	["research", "科研点"],
	["order_crystal", "秩序结晶"],
	["cohesion", "凝聚力"],
	["admin", "行政点数"],
	["wood", "木材"],
	["pop_total", "人力"],
]

## 创建作弊菜单
static func build() -> DialogLayer:
	var d := UIKit.dialog("作弊菜单", 560.0)
	var v := UIKit.vbox(8)
	v.add_child(UIKit.text_label("适度作弊不伤体验，过度作弊容易空虚。", 12, UIKit.WARN))

	var pages := {} # 用于容纳三个页签：资源 / 世界 / 杂项
	var tabs: Array = [] # [ [页签名, 按钮], ... ]
	var show_page := func(which: String) -> void:
		for pair2 in tabs:
			var p2: Array = pair2
			var w2: String = str(p2[0])
			(pages[w2] as Control).visible = (w2 == which)
			UIKit.style_button(p2[1] as Button, w2 == which, false)   # accent = 当前页高亮
		d.fit_now.call_deferred()

	var bar := UIKit.hbox(6)
	for pair in [["resources", "资源"], ["world", "世界"], ["misc", "杂项"]]:
		var tb := UIKit.small(str(pair[1]), 13)
		bar.add_child(tb)
		var which0: String = str(pair[0])
		tabs.append([which0, tb])
		tb.pressed.connect(func() -> void: show_page.call(which0))
	v.add_child(bar)

	pages["resources"] = _page_resources(d)
	pages["world"] = _page_world(d)
	pages["misc"] = _page_misc(d)
	var page_box := UIKit.vbox(8)
	for pair3 in tabs:
		var w3: String = str((pair3 as Array)[0])
		var pg3: Control = pages[w3]
		pg3.visible = false
		page_box.add_child(pg3)
	v.add_child(page_box)

	show_page.call("resources")     # 默认停在资源页（不记忆上次）

	v.add_child(UIKit.dim("关闭作弊：回到主页面 → 反馈 → 取消勾选「作弊功能」。", 11))

	var sc := UIKit.scroll(v)
	sc.custom_minimum_size = Vector2(0, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.set_content(sc)
	return d
	
## 作弊菜单 · 资源页
static func _page_resources(d: DialogLayer) -> Control:
	var pg := UIKit.vbox(8) # 创建一个页面
	pg.add_child(UIKit.title("添加资源", 15)) # 添加标题
	pg.add_child(UIKit.dim("填写每个资源想增加的数量（可填空或 0），然后点最下面的「一次性添加」。")) # 添加简介
	var grid := UIKit.grid(4, 10, 6) 
	pg.add_child(grid)
	var spins: Dictionary = {}
	for pair in CHEAT_RESOURCES:
		var key: String = pair[0]
		var nm: String = pair[1]
		grid.add_child(UIKit.text_label(nm, 12, UIKit.TEXT_DIM))
		var sb := SpinBox.new()
		sb.min_value = -999999
		sb.max_value = 999999
		sb.step = 1
		sb.value = 0
		sb.custom_minimum_size = Vector2(UI.px(110), UI.px(0))
		grid.add_child(sb)
		spins[key] = sb

	var quick := UIKit.hbox(6)
	var b1 := UIKit.small("快捷：全部 +100", 11)
	b1.pressed.connect(func() -> void:
		for k in spins.keys():
			(spins[k] as SpinBox).value = 100)
	quick.add_child(b1)
	var b2 := UIKit.small("快捷：全部 +1000", 11)
	b2.pressed.connect(func() -> void:
		for k in spins.keys():
			(spins[k] as SpinBox).value = 1000)
	quick.add_child(b2)
	var b0 := UIKit.small("清零", 11)
	b0.pressed.connect(func() -> void:
		for k in spins.keys():
			(spins[k] as SpinBox).value = 0)
	quick.add_child(b0)
	pg.add_child(quick)

	var apply := UIKit.primary("一次性添加", 15)
	apply.pressed.connect(func() -> void:
		var amounts := {}
		for k in spins.keys():
			var v2 := int((spins[k] as SpinBox).value)
			if v2 != 0:
				amounts[k] = v2
		var r := Cheat.add_resources(amounts)
		if not bool(r["ok"]):
			GameState.toast.emit(str(r["why"]))
		else:
			GameState.toast.emit("作弊生效：" + str(r["summary"]))
		d.close())
	pg.add_child(apply)
	return pg

## 作弊菜单 · 世界页
static func _page_world(d: DialogLayer) -> Control:
	var pg := UIKit.vbox(8)
	pg.add_child(UIKit.title("世界", 15))
	pg.add_child(UIKit.dim("把当前大世界的迷雾一次性全部揭开（所有地块的「已点亮」标记置真）。"))
	var reveal := UIKit.normal("揭开全部迷雾", 14)
	reveal.pressed.connect(func() -> void:
		var n := Cheat.reveal_all()
		GameState.toast.emit("已揭开全部迷雾：新揭开 %d 格" % n)
		d.close())
	pg.add_child(reveal)
	pg.add_child(UIKit.dim("（一次性操作，不消耗资源；想恢复只能读旧档。）", 11))
	return pg

## 作弊菜单 · 杂项页
static func _page_misc(d: DialogLayer) -> Control:
	var pg := UIKit.vbox(8)
	pg.add_child(UIKit.title("摧毁敌对单位", 15))
	pg.add_child(UIKit.dim("可以选中大世界中的任何敌对单位直接摧毁。"))
	var enemies := GameState.enemy_tiles()
	pg.add_child(UIKit.dim("当前大世界敌对单位：%d 个" % enemies.size()))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UI.fs(3))
	for t in enemies:
		var key := WorldGen.tile_key(t)
		var label := UnitDB.enemy_label(t)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UI.fs(6))
		list.add_child(row)
		var l := UIKit.text_label("%s　[%s]　战力 %.0f" % [label, key, float(t.get("force", 0.0))],
			12, UIKit.BAD)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var rb := UIKit.tiny("摧毁", 11, true)
		rb.pressed.connect(func() -> void:
			var r := Cheat.destroy_tile_enemies(key)
			if not r["ok"]:
				GameState.toast.emit(str(r["why"]))
			else:
				GameState.toast.emit("已摧毁 %s 的%s" % [key, str(r["label"])])
			d.close())
		row.add_child(rb)
	if enemies.is_empty():
		list.add_child(UIKit.dim("（当前没有敌对单位）"))

	var all_btn := UIKit.normal("摧毁全部敌对单位", 13)
	UIKit.style_button(all_btn, false, true)
	all_btn.pressed.connect(func() -> void:
		var n := Cheat.destroy_all_enemies()
		GameState.toast.emit("已摧毁 %d 个敌对单位" % n)
		d.close())
	pg.add_child(all_btn)
	return pg
