class_name TestUtil
extends RefCounted
## 自检公用工具（**tests/ 专用**，不要给游戏代码用）。
##
## 为什么有这个文件：
## 这些辅助函数原先在每个 diag 文件里**各抄一份** —— `_fail` 抄了 6 份、`_collect_text` 3 份、
## `_host` 3 份、`_find_button` / `_find_toggle` 各 2 份，而"打印结果 + `quit(0/1)`"那条尾巴几乎每份都有。
## 一路改下来就成了"改一个忘一个"：想统一修一处，得记得去 N 个文件里改。
##
## 用法：
##     const U := preload("res://tests/test_util.gd")   # 或者直接用类名 TestUtil
##     var suite := U.reporter("v1.2 自检")
##     ...
##     suite.ok(cond, "说明")        # 打印 ✔/✘ 并计数
##     suite.fail("说明")            # 记一次失败
##     await suite.frames(4)         # 等几帧
##     suite.finish(get_tree())      # 打印结果 + quit(0/1)
##
## 纯函数直接当静态用：`U.collect_text(n)` / `U.find_button(n, "确认")`。

## 失败项数（`finish()` 用它决定退出码）
var failed := 0
## 报告标题（打印用）
var title := ""


func _init(p_title: String = "") -> void:
	title = p_title


## 造一个报告器（`var suite := U.reporter("v1.5 自检")`）
static func reporter(p_title: String) -> TestUtil:
	return TestUtil.new(p_title)


func begin(sub: String = "") -> void:
	print("\n== %s ==" % (title if sub == "" else "%s：%s" % [title, sub]))


func section(sub: String) -> void:
	print("\n== %s ==" % sub)


## 断言：打印 ✔/✘ 并计数
func ok(cond: bool, what: String) -> void:
	print("  %s %s" % ["✔" if cond else "✘", what])
	if not cond:
		failed += 1


func fail(msg: String) -> void:
	print("  [FAIL] " + msg)
	failed += 1


## 缩进的补充说明（不影响成败）
func note(text: String) -> void:
	print("    " + text)


func label(text: String) -> void:
	print("  " + text)


## 等 n 帧
func frames(n: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in n:
		await tree.process_frame


## 收尾：打印结果行 + 按失败数退出
func finish(tree: SceneTree, what: String = "") -> void:
	var head := title if what == "" else what
	print("\n== %s，失败 %d 项 ==" % [head, failed])
	tree.quit(0 if failed == 0 else 1)


# ---------------------------------------------------------------------------
# 纯工具（静态直接用）
# ---------------------------------------------------------------------------

## 全屏空宿主（放被测控件用；v1.5/v1.6/screenshot 原来各有一份）
static func host(parent: Node) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.custom_minimum_size = Vector2(1280, 720)
	parent.add_child(c)
	return c


## 收集一棵子树里的所有文字（Label + Button），用来断言"界面上出现了某段文案"
static func collect_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + " | "
	if n is Button:
		s += "[" + (n as Button).text + "] "
	for c in n.get_children():
		s += collect_text(c)
	return s


## 按**精确文字**找 Button（排除 CheckBox）
static func find_button(n: Node, text: String) -> Button:
	if n is Button and not (n is CheckBox) and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var r := find_button(c, text)
		if r != null:
			return r
	return null


## 按**包含文字**找 Button（排除 CheckBox）
static func find_toggle(n: Node, text: String) -> Button:
	if n is Button and not (n is CheckBox) and (n as Button).text.contains(text):
		return n as Button
	for c in n.get_children():
		var r := find_toggle(c, text)
		if r != null:
			return r
	return null


## 收集某类节点（例如 "SpinBox"）
static func collect(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(collect(c, cls))
	return out
