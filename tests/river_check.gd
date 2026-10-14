extends Node
## **水路图层**（`River`）专项自检 —— 2026-10-14 解耦工程。
##
## 验四件事：
##   ① **解耦**：地块数据里**没有** `river` 字段（水路不存进地图；需要时按坐标查 `River`）；
##   ② **没有河在海里**（用户 2026-10-13 报过的 bug）；
##   ③ **边路径折好了**：每相邻两条边**共顶点**（= 用户"头尾编号"那句话的代码版）；
##   ④ **确定**：同一配方重复生成，路线**逐位一致**；换种子则跟着变。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/river_check.tscn

const SEED := 20240607

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _ready() -> void:
	print("== 水路图层（解耦）专项自检 ==")
	GameState.new_game(SEED)
	var tiles: Dictionary = GameState.state["tiles"]

	# ---- ① 解耦：地块里不该有 river 字段 ----
	var polluted := 0
	for k in tiles.keys():
		if (tiles[k] as Dictionary).has("river"):
			polluted += 1
	print("  地块里带 river 字段的：%d 个（应当 0 —— 水路不存进地图）" % polluted)
	_check(polluted == 0, "**地块里没有 river 字段**（水路与地图解耦）")

	# ---- ② 河格：有、不在海里、能按坐标查询 ----
	var keys := River.river_keys()
	var in_water := 0
	for k2 in keys.keys():
		if not tiles.has(str(k2)):
			continue
		if str((tiles[str(k2)] as Dictionary).get("terrain", "")) == "water":
			in_water += 1
	print("  河格：%d 个（按坐标查 River.river_keys()）；在海里的 %d 个" % [keys.size(), in_water])
	_check(keys.size() > 0, "水路图层里有河（%d 格）" % keys.size())
	_check(in_water == 0, "**没有一格河在海里**（实际 %d）" % in_water)
	var any_key := ""
	for k3 in keys.keys():
		any_key = str(k3)
		break
	_check(any_key != "" and River.has_river_at(any_key),
		"**能按坐标查询**：has_river_at(%s) 为真" % any_key)

	# ---- ③ 边路径：相邻两条边必须共顶点 ----
	var paths := River.paths()
	var path_edges := 0
	var bad := 0
	var longest := 0
	for chain in paths:
		var ch: Array = chain
		path_edges += ch.size()
		longest = maxi(longest, ch.size())
		for i in range(1, ch.size()):
			if not River.edges_adjacent(str(ch[i - 1]), str(ch[i])):
				bad += 1
	print("  边路径：%d 条链、共 %d 条边、最长一条 %d 条边；**相邻边不共顶点 %d 处**"
		% [paths.size(), path_edges, longest, bad])
	_check(paths.size() > 0, "存在边路径（%d 条链）" % paths.size())
	_check(bad == 0, "**每相邻两条边都共顶点**（违例 %d）→ 折好了，画出来不会断" % bad)
	_check(River.edges().size() > 0, "河道边非空（%d 条边）" % River.edges().size())

	# ---- ④ 确定：同配方重复生成逐位一致；换种子跟着变 ----
	var snap_a := str(River.paths())
	GameState.new_game(SEED)
	var snap_b := str(River.paths())
	_check(snap_a == snap_b, "同一配方重复生成 → 边路径**逐位一致**（确定）")
	GameState.new_game(SEED + 1)
	_check(str(River.paths()) != snap_a, "换种子 → 河道路线跟着变")

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
