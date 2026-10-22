class_name Peaks
extends RefCounted
## **山脉瘦身**（2026-10-22 用户提）✓
##
## 问题：噪声叠出来的山有时是一**团** ✗ —— 团状的山既不好看，也当不了"地理长城"（山脉要能**封住一侧** ✓）
##
## 做法（只看 `mountain` 格 ✓ 生成完之后跑一遍 ✓）：
##   ① **量厚度**：沿三条六边形轴各量一次连续长度 ✓
##      三个方向**都** > `FAT_WIDTH` 才算胖 ✓
##      ⚠️ 细长的山脊沿**脊线**方向当然很长 ✗ —— 但横截面只有 1~2 格 ✓ 不能算胖 ✗
##         （所以判据是"最窄的那个方向也不止 2 格" ✓ 不是"任意方向长过 2 格"）
##   ② 胖格降级：周围 `NEAR_RADIUS` 格内有**高原** → 变高原 ✓（山团边缘融进高原 ✓）
##      没有 → 变**山地**（`upland`，能走 ✓）✓
##
## ⚠️ 判定一律用**生成结果的原样快照**（`mt` / `plateau`）✓ 改写不回头影响判定 ✓
##    → 与遍历顺序无关 ✓ 同种子同结果 ✓
## ⚠️ 只做**一遍** ✗（不迭代）—— 要更狠就调 `FAT_WIDTH` / `NEAR_RADIUS` ✓

## 厚度上限：> 这个数（即 3 格及以上）算"胖" ✓
const FAT_WIDTH := 2
## "附近有高原"的判定半径（格）✓ 1 = 只看 6 个邻格 ✓
const NEAR_RADIUS := 1

const AXES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1)]


## 把太胖的山降级；返回改了几格 ✓
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

	# 先全部判定（用原样快照），再统一改写 ✓
	var to_plateau: Array[String] = []
	var to_upland: Array[String] = []
	for k in mt.keys():
		var c := WorldGen.coord_of(str(k))
		if not _fat(c, mt):
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


## 三个方向都 > FAT_WIDTH 才算胖 ✓（有一个方向 ≤ FAT_WIDTH = 是脊，保留 ✓）
static func _fat(c: Vector2i, mt: Dictionary) -> bool:
	for axis: Vector2i in AXES:
		if _run(c, axis, mt) <= FAT_WIDTH:
			return false
	return true


## 沿 `axis` 量过 `c` 的连续山脉长度（含自己）✓
static func _run(c: Vector2i, axis: Vector2i, mt: Dictionary) -> int:
	var n := 1
	for s in [1, -1]:
		var p: Vector2i = c + axis * int(s)
		while mt.has(TileManager.key_of(p)):
			n += 1
			p += axis * int(s)
	return n
