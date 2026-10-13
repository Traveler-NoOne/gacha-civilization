extends Node
## 死引用 / 死文案 专项自检（1.8.21.2）
##
## 为什么要有它：这批清掉的东西有个共同点 —— **它们不会让脚本报错、自检也不会红**，
## 只有玩家照着那句话走过去才会撞墙（"到「世界 → 地块规划页」"、"在「管理」里招募募集兵"，
## 而地块规划页 v1.8.5 就删了、管理入口 v1.8.7 就删了）。
## 所以把它钉成断言：以后再有人搬走入口，这几条会**当场红**。
##
## ⚠️ 为什么**不**用"grep 源码"当验收标准：
## 注释里**故意保留**了"原来指向哪、为什么改"（总规则第 7 条），源码里当然还搜得到那些旧词。
## 真正该断的是**运行期出现在界面上的文字** —— 所以这里直接把控件建出来、把文字收上来查。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/dead_ref_check.tscn
##
## ⚠️ 必须用**场景**跑，不能用 --script（后者不注册 autoload，引用 GameState 的生产脚本编译不过）。

const MP := preload("res://scripts/ui/views/parts/manual_page.gd")
const CP := preload("res://scripts/ui/views/parts/character_page.gd")

## 不该出现在**玩家可见文字**里的词（都指向已删除的入口）
const FORBIDDEN: Array[String] = ["管理页", "地块规划页", "「管理」", "管理 →"]

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


## 收集一棵子树里的所有文字（Label + Button）—— 就是玩家真正看得见的那部分
static func _text_of(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	if n is Button:
		s += "[" + (n as Button).text + "]\n"
	for c in n.get_children():
		s += _text_of(c)
	return s


func _check_clean(txt: String, where: String) -> void:
	var hit: Array[String] = []
	for w in FORBIDDEN:
		if txt.contains(w):
			hit.append(w)
	_check(hit.is_empty(), "%s 里没有指向已删入口的词（命中：%s）" % [where, str(hit)])


func _ready() -> void:
	print("== 死引用 / 死文案 专项自检 ==")
	GameState.new_game(20240607)     # 干净一局：首都 + 空队列 + 空单位列表

	# ① 手册「相关位置」：四条原来都指向管理页
	var groups: Array[String] = TermDB.groups()
	_check(groups.size() >= 7, "手册分组取到 %d 组（应 >= 7）" % groups.size())
	var hints := ""
	var non_empty := 0
	for g in groups:
		var h := str(MP._related_hint(g))
		hints += h + "\n"
		if h.strip_edges() != "":
			non_empty += 1
	_check_clean(hints, "手册「相关位置」全部 %d 组" % groups.size())
	# 反向护栏：防止"全删成空串"这种假通过
	_check(non_empty >= 5, "手册里给出「相关位置」的组 >= 5（实际 %d）" % non_empty)

	# ② 据点管理窗口：空规划队列的提示（原「世界 → 地块规划页」，且被右边缘截断）
	var sp := StrongholdPanel.new()
	add_child(sp)
	sp.key = str(GameState.state["capital"])
	sp.tab = "info"
	sp.refresh()
	await get_tree().process_frame
	var tip_txt := _text_of(sp.build_box)
	_check_clean(tip_txt, "据点窗口·规划队列（空）")
	_check(tip_txt.contains("右键地块"), "空队列提示指向「右键地块 → 🔨」（实际：%s）" % tip_txt.strip_edges())
	var wrapped := false
	var found_tip := false
	for c in sp.build_box.get_children():
		if c is Label and (c as Label).text.contains("队列为空"):
			found_tip = true
			wrapped = (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	_check(found_tip, "找到了那行「队列为空」提示")
	_check(wrapped, "空队列提示开了自动换行（不会再被右边缘截断，bug#11）")

	# ③ 角色页：无单位时的空状态提示（原「在「管理」里招募募集兵」）
	GameState.state["units"] = []
	var cp: Control = CP.new()
	add_child(cp)
	for i in 4:
		await get_tree().process_frame
	if cp.has_method("refresh"):
		cp.call("refresh")
		for i in 2:
			await get_tree().process_frame
	var cp_txt := _text_of(cp)
	_check_clean(cp_txt, "角色页（无单位时的空状态）")
	_check(cp_txt.contains("政事"), "角色页空状态指向「政事」征兵（实际：%s）" % cp_txt.strip_edges())

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
