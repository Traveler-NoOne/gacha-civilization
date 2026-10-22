class_name Peaks
extends RefCounted
## **山脉瘦身**（2026-10-22 用户提 / 第三版做法）✓
##
## 问题：噪声叠出来的山有时是一**团** ✗ —— 团状的山当不了"地理长城" ✓
##
## ⚠️ 前两版为什么不行（教训，别再写回去）：
##   · 第一版按"横向连续长度"判胖 → 一条 3 格宽的山脊，**每一格**量出来都是 3
##     （最边上那格也把整条宽度算进自己）→ 全判胖 → **一次全削没** ✗✗
##   · 第二版改成"只留最里面那条脊线" → **削过头**：3 格宽直接变 1 格、小团变孤点 ✗
##
## 现在（用户口径）：**一次只削一个边，削完重新量，还胖就再来一轮** ✓
##   ① 每轮重新量厚度：三条六边形轴的连续长度，取**最小**那条 = 最窄的截面 ✓
##   ② 所有山格厚度都 ≤ `FAT_WIDTH`（2）→ 收工 ✓ —— **2 格宽是允许的**（"不包括两格"）✓
##   ③ 否则挑**最窄的那条轴**（团就是往这个方向被削），只削该方向**最外层**的胖格 ✓
##      下一轮削**反方向** ✓（左右交替 → 山脊不会越削越偏 ✓）
##   ④ 回到 ① ✓
##
##   效果：3 格宽削一轮 → 2 格 ✓；4 格宽两轮 ✓；一大团会被削成一条 **2 格宽**的带子 ✓
##   ⚠️ **本来就 ≤2 格的山脊永远不在削的名单里** ✓✓ 所以不会整片消失 ✓
##   ⚠️ 只削"胖格"、不削细格 → 顺手接在团边上的细山脊也不会被一起削掉 ✓
##
## 降级去向：附近 `NEAR_RADIUS` 格内有**高原** → 高原 ✓；没有 → **山地**（`upland`，能走 ✓）
## ⚠️ 判定一律用同一份快照 + 固定顺序 ✓ 同种子同结果 ✓

const FAT_WIDTH := 2      ## 厚度上限：> 2（3 格及以上）算胖 ✓
const MAX_WALK := 8       ## 量厚度最多走这么多格 ✓（只要分得出"2 格"和"更宽"就行 ✓）
const MAX_PASSES := 40    ## 最多削这么多轮 ✓（防手滑死循环 ✓）
const NEAR_RADIUS := 1    ## "附近有高原"的判定半径（1 = 只看 6 个邻格）✓

const AXES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1)]


## 把山块一轮一轮削到最宽 2 格；返回共改了几格 ✓
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

	var removed := 0
	var side := 1
	for _pass in MAX_PASSES:
		var runs := _runs(mt)
		var axis := _thin_axis(runs)
		if axis == Vector2i.ZERO:
			break                       # 没有胖格了，收工 ✓
		var dir: Vector2i = axis * side
		side = -side                    # 下一轮削另一边 ✓

		var layer := _edge_layer(mt, runs, dir)
		if layer.is_empty():
			dir = -dir                  # 这一侧没有可削的 → 换另一边试 ✓
			layer = _edge_layer(mt, runs, dir)
		if layer.is_empty():
			break                       # 两边都没有可削的（小团常见）→ 收手，别死循环 ✓

		for k in layer:
			var t: Dictionary = tiles[k]
			if _near_plateau(TileManager.coord_of(k), plateau):
				t["terrain"] = TileLib.T_PLATEAU
			else:
				t["terrain"] = TileLib.T_UPLAND
			mt.erase(k)
			removed += 1
	return removed


## 每格三条轴的连续长度（截断在 MAX_WALK 内）✓
static func _runs(mt: Dictionary) -> Dictionary:
	var out := {}
	for k in mt.keys():
		var c := TileManager.coord_of(str(k))
		out[k] = [_run(c, AXES[0], mt), _run(c, AXES[1], mt), _run(c, AXES[2], mt)]
	return out


## 这个方向最外层的胖格 ✓（细格不算 —— 免得把接在团边上的细山脊一起削掉 ✓）
static func _edge_layer(mt: Dictionary, runs: Dictionary, dir: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for k in mt.keys():
		var c := TileManager.coord_of(str(k))
		if mt.has(TileManager.key_of(c + dir)):
			continue
		if _min_run(runs[k]) <= FAT_WIDTH:
			continue
		out.append(str(k))
	return out


## 最窄的那条轴（胖格们在这条轴上"总长度"最小）；没有胖格就返回 ZERO ✓
static func _thin_axis(runs: Dictionary) -> Vector2i:
	var sums: Array[int] = [0, 0, 0]
	var any_fat := false
	for k in runs.keys():
		var r: Array = runs[k]
		if _min_run(r) <= FAT_WIDTH:
			continue
		any_fat = true
		for i in 3:
			sums[i] += int(r[i])
	if not any_fat:
		return Vector2i.ZERO
	var best := 0
	for i in [1, 2]:
		if sums[i] < sums[best]:
			best = i
	return AXES[best]


## 某个方向上的连续山脉长度（含自己，最多走 MAX_WALK 步）✓
static func _run(c: Vector2i, axis: Vector2i, mt: Dictionary) -> int:
	var n := 1
	for s in [1, -1]:
		var p: Vector2i = c + axis * int(s)
		for _i in MAX_WALK:
			if not mt.has(TileManager.key_of(p)):
				break
			n += 1
			p += axis * int(s)
	return n


static func _min_run(r: Array) -> int:
	return mini(int(r[0]), mini(int(r[1]), int(r[2])))


static func _near_plateau(c: Vector2i, plateau: Dictionary) -> bool:
	for n: Vector2i in Hex.spiral(NEAR_RADIUS):
		if plateau.has(TileManager.key_of(c + n)):
			return true
	return false
