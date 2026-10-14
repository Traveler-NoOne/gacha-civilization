class_name River
extends RefCounted
## ===========================================================================
## **水路图层**（2026-10-14 解耦工程，按用户定的架构）
##
## 用户的架构（原话要点）：
##   ① 先从地形图（原型图）里把水路**拆出来**，成为一张**线路图**；
##   ② 再把这张线路图**折成基于六边形网格的线路图**；
##   ③ **节点映射到地块的"边点"**（六边形的边/顶点）上；
##   ★ 而且**水路与地图相互独立、不存储在地块数据上** ——
##     需要水路时**直接查"对应坐标的水路图"，而不是去问地图**。
##
## 所以本模块的设计约束（**请守住**）：
##   · **不往地块里写任何东西** —— 没有 `t["river"]` 这类字段（这正是解耦的意义）；
##   · 地形那一层（WorldGen）只负责算出"水往哪流"（汇流 + 流向），
##     本层把它变成**河道路线**；谁要水路，就来找本层查询。
##   · 全程**确定**：并列一律按坐标键兜底 → 同一配方每次生成逐位一致。
##
## ⚠️ 边键格式沿用 W1 定死的规范：`"q,r,d"`
##   · owner = 两端坐标**字典序较小者**（保证一条边只有一个主人）；
##   · `d` = 从 owner 指向另一端的六方向序号；反向 = `(i+3)%6`（已数值验证）。
## ===========================================================================

## 与 WorldGen 同格式的坐标工具。**故意各留一份**：
## 本层必须能独立于 WorldGen 存在（这正是"解耦"），
## 而它只是"两整数拼/拆字符串"，重复代价远小于引入循环依赖。
static func key_of(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func coord_of(k: String) -> Vector2i:
	var parts := k.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## 河道的取法：**陆地格**汇流量的前百分之几当"河头"，再由河头顺流补到入海。
## ⚠️ 这是"河多河少"的唯一旋钮，纯口味、可逆（0.20 时是全图约 170 格河）。
const RIVER_FLOW_PERCENT := 0.20
## 水位线的**固定值**来自 Consts.SEA_LEVEL（共享常量，见那里说明）。
static var _keys: Dictionary = {}          ## 河格（地块键 → true）
static var _edges: Dictionary = {}         ## 河道边（边键 → 流量）
static var _paths: Array = []              ## 边路径（每条河一串边键，**相邻两条必共顶点**）
static var _seed := -999999


## 由 WorldGen 的侵蚀结果**建出这一局的水路图层**（侵蚀算完汇流后调用一次）。
## `flow`: 每格汇流量；`flow_to`: 每格往哪流；`heights`: 侵蚀后的高度（用来判"到海了"）。
static func build(world_seed: int, flow: Dictionary, flow_to: Dictionary,
		heights: Dictionary) -> void:
	_keys = {}
	_edges = {}
	_paths = []
	_seed = world_seed

	# ---- 1) 挑"河头"：只按**陆地格**统计 ----
	# ⚠️ 海里也有"流量"（海盆会把大片区域的水汇到一起）。把海算进去的话，
	#   "流量前 X%"几乎全是深海格 → 玩家实测"**大多数河流在海里**、陆地上只有一两条"。
	var flows: Array = []
	for k4 in flow.keys():
		if float(heights.get(k4, 1.0)) >= Consts.SEA_LEVEL:
			flows.append(int(flow[k4]))
	if flows.is_empty():
		return
	flows.sort()
	var river_want := maxi(1, int(float(flows.size()) * RIVER_FLOW_PERCENT))
	var river_cut := int(flows[flows.size() - river_want])
	for k5 in flow.keys():
		if float(heights.get(k5, 1.0)) >= Consts.SEA_LEVEL and int(flow[k5]) >= river_cut:
			_keys[k5] = true

	# ---- 2) 顺流补到入海（否则河会在半路断掉）----
	# 判据：「流量 ≥ 阈值 **或** 终点是海/湖」——这里补的就是后半句。
	# 到海就停：**入海口那一格不标成河**（否则河边又跑到海里）。
	for k0 in _keys.keys():
		var cur := str(k0)
		var guard := 0
		while guard < 512:
			guard += 1
			var to := str(flow_to.get(cur, ""))
			if to == "":
				break
			if float(heights.get(to, 1.0)) < Consts.SEA_LEVEL:
				break
			_keys[to] = true
			cur = to

	# ---- 3) 把河道落到"边"上 ----
	for kr in _keys.keys():
		var to2 := str(flow_to.get(kr, ""))
		if to2 == "":
			continue
		var ek := edge_key_of(str(kr), to2)
		if ek != "":
			_edges[ek] = int(flow.get(kr, 1))

	# ---- 4) 折成**边路径**（文明6式）----
	# 每一步：水从"入边"进这一格、从"出边"出这一格；两条边若不相邻（不共顶点），
	# 就**沿着这个六边形的边一条条走过去**把它们接起来 —— 走短的那一边。
	# 于是整条河的边序列**每相邻两条必共顶点**，画出来不可能断。
	# ⚠️ 只认**河格之间**的上下游：用"全部格子"算上游的话，几乎每格都有上游
	#    → 所有河头都被跳过、一条链都建不出来（自检当场抓到 0 条）。
	var has_up := {}
	for ku in _keys.keys():
		var tu := str(flow_to.get(ku, ""))
		if tu != "" and _keys.has(tu):
			has_up[tu] = true
	for kh in _keys.keys():
		var kstart := str(kh)
		if has_up.has(kstart):
			continue                     # 不是源头，从源头开始走就行
		var chain: Array = []
		var cur := kstart
		var d_in := -1
		var guard_a := 0
		while guard_a < 512:
			guard_a += 1
			var nxt := str(flow_to.get(cur, ""))
			if nxt == "":
				break
			var cc := coord_of(cur)
			var d_out := _dir_to(cc, coord_of(nxt))
			if d_out < 0:
				break
			if d_in < 0:
				chain.append(_edge_key(cc, d_out))
			else:
				var step := 1 if _ring_delta(d_in, d_out) <= 3 else -1
				var dcur := d_in
				var guard_b := 0
				while dcur != d_out and guard_b < 8:
					guard_b += 1
					dcur = ((dcur + step) % 6 + 6) % 6
					chain.append(_edge_key(cc, dcur))
			if not _keys.has(nxt):
				break                    # 出了河网（应当就是到海了）
			d_in = (d_out + 3) % 6       # 下一格的"入边"= 本格出边的反向
			cur = nxt
		if chain.size() >= 2:
			_paths.append(chain)


# ===========================================================================
# 查询接口（**谁要水路就来这里查** —— 这正是"与地图解耦"的用法）
# ===========================================================================

## 这一格有河吗？（按坐标查询，不看地块数据）
static func has_river_at(tile_key: String) -> bool:
	return _keys.has(tile_key)


## 全部河格（地块键 → true）
static func river_keys() -> Dictionary:
	return _keys


## 河道边（边键 → 流量，流量用来定线宽）
static func edges() -> Dictionary:
	return _edges


## 边路径（每条河一串边键；**相邻两条边必共顶点**，所以画出来不会断）
static func paths() -> Array:
	return _paths


## 边路径是否已建好
static func ready() -> bool:
	return _seed != -999999


# ===========================================================================
# 边键与顶点工具（W1 的规范）
# ===========================================================================

## 把"两端坐标"规范化成一条边的键 `"q,r,d"`（owner = 字典序较小者）。
## 两端必须相邻；不相邻或重复则返回空串。
static func edge_key_of(a: String, b: String) -> String:
	var ca := coord_of(a)
	var cb := coord_of(b)
	if ca == cb:
		return ""
	var d := _dir_to(ca, cb)
	if d < 0:
		return ""
	if cb.x < ca.x or (cb.x == ca.x and cb.y < ca.y):
		return _edge_key(cb, (d + 3) % 6)
	return _edge_key(ca, d)


## 从 a 到 b 的六方向序号；不相邻返回 -1
static func _dir_to(a: Vector2i, b: Vector2i) -> int:
	for i in Hex.DIRECTIONS.size():
		if a + Hex.DIRECTIONS[i] == b:
			return i
	return -1


static func _edge_key(c: Vector2i, d: int) -> String:
	return "%d,%d,%d" % [c.x, c.y, d]


## 绕六边形从 a 到 b 的**最短步数**（0~3）
static func _ring_delta(a: int, b: int) -> int:
	return mini(((b - a) % 6 + 6) % 6, ((a - b) % 6 + 6) % 6)


## 一条边的两个**顶点**（像素空间坐标，size=1）
static func _edge_vertices(ek: String) -> Array:
	var parts := ek.split(",")
	if parts.size() != 3:
		return []
	var c := Vector2i(int(parts[0]), int(parts[1]))
	var d := int(parts[2])
	var k := ((6 - d) % 6 + 6) % 6          # 边 k ↔ DIRECTIONS[(−k) mod 6]（已验证）
	var center := Hex.axial_to_pixel(c.x, c.y, 1.0)
	var cs := Hex.corners(center, 1.0)
	return [cs[k], cs[(k + 1) % 6]]


## 两条边**是否共顶点**（= 用户说的"尾接头"）。同一条边视为共顶点。
## ⚠️ 判据用**距离**而不是"把坐标格式化成字符串再比" —— 后者会因为 `-0.000` 与 `0.000`
##    这类浮点符号差异产生**假违例**（实测误报了 3 处）。
static func edges_adjacent(e1: String, e2: String) -> bool:
	if e1 == e2:
		return true
	var v1 := _edge_vertices(e1)
	var v2 := _edge_vertices(e2)
	if v1.is_empty() or v2.is_empty():
		return false
	var a0: Vector2 = v1[0]
	var a1: Vector2 = v1[1]
	var b0: Vector2 = v2[0]
	var b1: Vector2 = v2[1]
	return a0.distance_to(b0) < 0.001 or a0.distance_to(b1) < 0.001 \
		or a1.distance_to(b0) < 0.001 or a1.distance_to(b1) < 0.001
