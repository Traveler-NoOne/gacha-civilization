extends Node
## 覆盖 v1.8.20.11：鼠标离开地块后旧弹窗应当**已被销毁**，于是下次弹的时候
## 尺寸里绝不会混进上一个格子的内容（"弹窗时高时矮"的直接原因）。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/popup_measure_check.tscn
##
## ⚠️ 必须用场景跑（--script 不注册 autoload）。

const PAGE_W := 1280.0
const PAGE_H := 720.0

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _text_of(n: Node) -> String:
	if n is Label:
		return (n as Label).text
	if n is Button:
		return (n as Button).text
	return ""


func _ready() -> void:
	print("== 悬浮弹窗：离开地块即销毁 专项自检 ==")
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var page: Control = load("res://scripts/ui/views/view_world_page.gd").new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(page)
	page.size = Vector2(PAGE_W, PAGE_H)
	for i in 4:
		await get_tree().process_frame

	var keys: Array = []
	for k in GameState.state["tiles"].keys():
		if bool((GameState.state["tiles"][k] as Dictionary).get("discovered", false)):
			keys.append(str(k))
			if keys.size() >= 2:
				break
	_check(keys.size() >= 2, "找到两个已点亮的格子（%s）" % str(keys))
	if keys.size() < 2:
		print("== 结果：无法继续 ==")
		get_tree().quit(1)
		return
	var key_a: String = keys[0]
	var key_b: String = keys[1]

	# ① 悬停 A 满 1 秒 → 弹 A
	page.call("_on_hover_changed", key_a, Vector2(400.0, 300.0))
	await get_tree().create_timer(1.3).timeout
	var pop: Variant = page.get("tile_info_popup")
	_check(pop != null and (pop as Control).visible, "悬停满 1 秒后弹窗出现了")
	var box: Node = page.get("tile_info_box")
	var n_a: int = box.get_child_count()
	print("  弹 A（%s）：子项 %d 个" % [key_a, n_a])
	_check(n_a > 0, "A 的内容装进去了（%d 行）" % n_a)

	# ② 鼠标移到 B（这就是"离开 A"）→ 同一帧内弹窗就该没了
	page.call("_on_hover_changed", key_b, Vector2(400.0, 300.0))
	_check(page.get("tile_info_popup") == null, "离开 A 的同一帧内，弹窗已被销毁（引用已置空）")
	_check(page.get("tile_info_box") == null, "内容盒引用也一起置空了")

	# ③ 悬停 B 满 1 秒 → 弹 B；此时箱子里只该有 B
	await get_tree().create_timer(1.3).timeout
	var pop2: Variant = page.get("tile_info_popup")
	_check(pop2 != null and (pop2 as Control).visible, "悬停 B 满 1 秒后弹窗重新出现")
	var box2: Node = page.get("tile_info_box")
	var leaked: Array = []
	for c in box2.get_children():
		var txt := _text_of(c)
		if txt.contains(key_a):
			leaked.append(txt)
	var n_b: int = box2.get_child_count()
	print("  弹 B（%s）：子项 %d 个（A 单独时是 %d）；A 的残留 %d 行" % [key_b, n_b, n_a, leaked.size()])
	_check(leaked.is_empty(), "B 的弹窗里没有 A 的残留行（残留：%s）" % str(leaked))
	_check(n_b < n_a + 10, "子项数没有变成 A+B 叠加（%d）" % n_b)

	# ④ 鼠标移出地图（emit ""）→ 也应当销毁
	page.call("_on_hover_changed", "")
	_check(page.get("tile_info_popup") == null, "鼠标移出地图后弹窗也被销毁")

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
