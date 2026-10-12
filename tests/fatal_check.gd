extends Node
## 覆盖 1.8.20.10：致命错误码机制 + 地图缺地块时该报 E-MAP-001。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/fatal_check.tscn
##
## ⚠️ 自检必须用场景跑，不能用 --script（后者不注册 autoload）。

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _ready() -> void:
	print("== 致命错误码 专项自检 ==")
	Fatal.suppress_quit = true      # 先别让它把测试进程杀掉
	Fatal.last_code = ""
	Fatal.count = 0

	var m := HexMapView.new()
	add_child(m)
	m.size = Vector2(1280, 720)
	for i in 3:
		await get_tree().process_frame

	# ① 有数据：不该报，且算得出可见地块
	var n_ok: int = m.call("_visible_tiles").size()
	_check(n_ok > 0, "有地块数据时算得出 %d 格（应 > 0）" % n_ok)
	_check(Fatal.count == 0, "正常情况不该报致命错误（count=%d）" % Fatal.count)

	# ② state 整个为空（= 世界生成没跑成的最极端形态）
	var saved: Dictionary = GameState.state
	GameState.state = {}
	var n_a: int = m.call("_visible_tiles").size()
	_check(n_a == 0, "state 为空时返回空（实际 %d）" % n_a)
	_check(Fatal.last_code == "E-MAP-001", "报了 E-MAP-001（实际 [%s]）" % Fatal.last_code)
	_check(Fatal.count == 1, "count 记到 1（实际 %d）" % Fatal.count)

	# ③ 键在但为空（最容易漏的那种：new_game 的 state 自带 tiles: {}）
	GameState.state = {"tiles": {}}
	var n_b: int = m.call("_visible_tiles").size()
	_check(n_b == 0, "只有空 tiles 键时返回空（实际 %d）" % n_b)
	_check(Fatal.count == 2, "「键在但为空」也要报（count 实际 %d）" % Fatal.count)

	# ④ 恢复现场 → 又能正常算，且不再报
	GameState.state = saved
	var n_c: int = m.call("_visible_tiles").size()
	_check(n_c > 0, "恢复 state 后又算得出 %d 格" % n_c)
	_check(Fatal.count == 2, "恢复之后不再新增报错（count 实际 %d）" % Fatal.count)

	# ⑤ 码表同步：CODES ↔ docs/错误代码.md 双向都要对得上（长期护栏）
	var doc_txt := ""
	var f := FileAccess.open("res://docs/错误代码.md", FileAccess.READ)
	if f != null:
		doc_txt = f.get_as_text()
		f.close()
	_check(doc_txt != "", "读到了 docs/错误代码.md（%d 字）" % doc_txt.length())
	var missing_in_doc: Array = []
	for code in Fatal.CODES.keys():
		if not doc_txt.contains(str(code)):
			missing_in_doc.append(str(code))
	_check(missing_in_doc.is_empty(), "CODES 里每个码都在文档里有（缺：%s）" % str(missing_in_doc))
	# 反向：文档里出现的 E-XXX-NNN 形式的码，都必须在 CODES 里登记
	var re := RegEx.new()
	re.compile("E-[A-Z]+-[0-9]{3}")
	var in_doc: Array = []
	for mm in re.search_all(doc_txt):
		in_doc.append(mm.get_string())
	var unregistered: Array = []
	for code2 in in_doc:
		if not Fatal.CODES.has(code2):
			unregistered.append(code2)
	_check(unregistered.is_empty(), "文档里的码都在 CODES 里有（未登记：%s）" % str(unregistered))
	print("  （文档里共出现 %d 个码，CODES 里登记 %d 个）" % [in_doc.size(), Fatal.CODES.size()])

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
