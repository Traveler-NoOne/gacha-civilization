class_name Peaks
extends RefCounted
## **山脉瘦身**（2026-10-22 用户提 / 同日晚改版）✓
##
## 问题：噪声叠出来的山有时是一**团** ✗ —— 团状的山既不好看，也当不了"地理长城"（山脉要能**封住一侧** ✓）
##
## ⚠️ **第一版为什么把山全削没了** ✗（教训，别再写回去）：
##   第一版按"横向连续长度"判胖 ✓ —— 可一条 3 格宽的山脊，**每一格**量出来的横截面都是 3
##   （最边上那格也把整条宽度算进自己）✗ → 每一格都判成胖 → **整片一起降级** ✗✗
##   判"胖"不能问"你这条线上总宽多少" ✗ 只能问"**离边界有多深**" ✓
##
## 现在的做法 = **只留脊线**（给山块描一条中轴 ✓）：
##   ① 算**深度**：从山块边界往里的层数 ✓ 边界格 = 1 ✓（多源 BFS ✓）
##   ② 只留**深度是局部最大**的格子 ✓（6 邻里没有更深的 ✓）—— 这条线就是脊线 ✓
##      · 1~2 格宽的山脊：所有格深度都是 1 ✓ → 全是局部最大 ✓ → **原样保留** ✓✓
##      · 3 格宽：1 2 1 ✓ → 留中间 ✓
##      · 4 格宽：1 2 2 1 ✓ → 留中间两格 ✓（**最宽就 2 格** ✓ 正好符合"不包括两格"✓）
##      · 一大团：中间只剩一条线 ✓ 团越胖削得越多 ✓ 但**绝不会整片消失** ✓✓（每个连通块至少留一格）
##   ③ 降级的格子：`NEAR_RADIUS` 格内有**高原** → 变高原 ✓；没有 → 变**山地**（`upland`，能走 ✓）
##
## ⚠️ 判定一律用**生成结果的原样快照**（`mt` / `plateau` / `depth`）✓ 改写不回头影响判定 ✓
##    → 与遍历顺序无关 ✓ 同种子同结果 ✓
## ⚠️ 只做**一遍** ✗（不迭代）✓

## "附近有高原"的判定半径（格）✓ 1 = 只看 6 个邻格 ✓
const NEAR_RADIUS := 1


## 把山块削成脊线；返回改了几格 ✓
static func thin_mountains(tiles: Dictionary) -> int:
	var mt := {}
	var plateau := {}
	for k in tiles.keys():
		var tr := str((tiles[k] as Dictionary).get("terrain", ""))
		if tr == TileLib.T_MOUNTAIN:
			mt[k] = true
		elif tr == TileLib.T_PLATEAU:
			plateau[k] = true
	if mt.is_empty():
		return 0

	var depth := _depths(mt)

	# 先全部判定（原样快照），再统一改写 ✓
	var to_plateau: Array[String] = []
	var to_upland: Array[String] = []
	for k in mt.keys():
		var c := WorldGen.coord_of(str(k))
		if _on_spine(c, int(depth[k]), depth, mt):
			continue
		var near_plateau := false
		for n: Vector2i in Hex.spiral(NEAR_RADIUS):
			if plateau.has(TileManager.key_of(c + n)):
				near_plateau = true
				break
		if near_plateau:
			to_plateau.append(str(k))
		else:
			to_upland.append(str(k))

	for k in to_plateau:
		var t: Dictionary = tiles[k]
		t["terrain"] = TileLib.T_PLATEAU
	for k in to_upland:
		var t: Dictionary = tiles[k]
		t["terrain"] = TileLib.T_UPLAND
	return to_plateau.size() + to_upland.size()


## 每格的深度：边界格 = 1 ✓ 往里每层 +1 ✓（多源 BFS ✓ 与遍历顺序无关 ✓）
static func _depths(mt: Dictionary) -> Dictionary:
	var depth := {}
	var frontier: Array[String] = []
	for k in mt.keys():
		var c := WorldGen.coord_of(str(k))
		for n: Vector2i in Hex.neighbors(c):
			if not mt.has(TileManager.key_of(n)):
				depth[k] = 1
				frontier.append(str(k))
				break
	var layer := 1
	while not frontier.is_empty():
		var next: Array[String] = []
		for k in frontier:
			var c := WorldGen.coord_of(k)
			for n: Vector2i in Hex.neighbors(c):
				var nk := TileManager.key_of(n)
				if mt.has(nk) and not depth.has(nk):
					depth[nk] = layer + 1
					next.append(nk)
		frontier = next
		layer += 1
	return depth


## 深度是局部最大 = 脊线 ✓（6 邻里有更深的就不是 ✓ 于是只剩最里面那条线 ✓）
static func _on_spine(c: Vector2i, d: int, depth: Dictionary, mt: Dictionary) -> bool:
	for n: Vector2i in Hex.neighbors(c):
		var nk := TileManager.key_of(n)
		if mt.has(nk) and int(depth[nk]) > d:
			return false
	return true
