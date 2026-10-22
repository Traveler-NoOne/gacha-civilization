class_name TileLib
extends RefCounted
## **地块库（新世界生成器专用）** ✓
##
## 为什么不复用旧 `TileDef` ✗（用户定的 ✓）：
##   旧库是给"旧高度分布"调的 ✓ 还背着一堆"旧系统要能跑"的包袱 ✗
##   两边各管各的 ✓ 以后旧系统删掉 ✓ 新库不受牵连 ✓（这就是"新旧界限明显" ✓）
##
## ⚠️ **字段要和游戏系统对得上** ✗ —— `owner` / `buildings` / `discovered` / `land_cap` …
##    那些是 `GameState` / `TileManager` / UI 要读的 ✓ 少了新世界就玩不了 ✓✓
##
## ⚠️ 依赖：只用 `Consts`（owner 枚举 / 资源名）＋ `Hex`（坐标哈希）✓
##    **不**依赖 `WorldGen` / `TileDef` / `TileManager` ✓✓（新库是独立的一套）
##
## 2026-10-18 清理 ✓：删掉了"板块构造"时期加的 `crust` / `edge` / `landform` ✗
##   （那条路已放弃 ✓ 现在只剩"高度 ＋ 湿度 查表" ✓）

# ---------------------------------------------------------------------------
# 地形取值（必须与 `Consts.TERRAIN_NAMES` 里的键一致 ✓ 否则画不出来）
# ---------------------------------------------------------------------------
const T_DEEP := "deep_water"
const T_SEA := "water"
const T_PLAIN := "plain"
const T_HILL := "hill"
const T_PLATEAU := "plateau"
## ★ 2026-10-22：山地（`upland`）—— 山脉里**能走**的那一层 ✓
##   ⚠️ **本表不产出它** ✗ —— 它不是"高度"能表达的东西 ✓
##   由 `Peaks.thin_mountains()` 事后把太胖的山团降级打标 ✓（见 `scripts/worldgen/peaks.gd` ✓）
const T_UPLAND := "upland"
const T_VALLEY := "valley"
const T_MOUNTAIN := "mountain"
const T_DUNE := "dune"
const T_WASTELAND := "wasteland"

# ---------------------------------------------------------------------------
# 高度分档 —— 标尺：**0 = 海沟底 ✓ 1 = 海平面 ✓ 5 = 珠峰 ✓ 10 = 大气层顶**
#   三个整数锚点：**0 = −11 km 海沟 ✓ 1.0 = 海平面 ✓ 5.0 = +8,848 m 珠峰 ✓**
#   ⚠️ 极限值只当标尺 ✓ 生成器**不该**真的产出 0 或 ≥5 的高度 ✓（见 `WorldgenBuilder` ✓）
# ---------------------------------------------------------------------------
const H_DEEP := 0.45      ## **深海 / 浅海的分界** ✓
                          ##（2026-10-18：0.64 → 0.45 ✓ 用户要求"海洋要有浅海区域"✓
                          ##   浅海带 = 0.45 ~ 1.00 ✓ 宽得肉眼看得出来 ✓
                          ##   ⚠️ 这个数是为了**视觉分层** ✓ 不追求物理精确 ✗）
const H_SEA := 1.00       ## ★ **海平面**：H_DEEP ~ 1.00 是浅海 ✓
const H_PLAIN := 1.23     ## 平原：1.00 ~ 1.23（0 ~ +500 m ✓）
const H_HILL := 1.90      ## 丘陵：1.23 ~ 1.90（+500 ~ +2,000 m ✓）
const H_PLATEAU := 3.40   ## 高原：1.90 ~ 3.40（+2,000 ~ +6,000 m ✓）
                          ## 2026-10-18：2.81 → 3.40 ✓ 用户要求"**大团的山改成高原**，别一大片山"✓
                          ##   → 抬高山地线 ✓ 于是**大片原来算山的高地，现在算高原** ✓✓
                          ## 山地：≥ 3.40（只有高原里最高的那些脊线才够得着 ✓ 面积小得多 ✓）


## 高程 + 湿度 → 地形 + 地物 ✓（二维查表 ✓）
static func terrain_of(height: float, moisture: float) -> Dictionary:
	# ① 水
	if height < H_DEEP:
		return {"terrain": T_DEEP, "cover": ""}
	if height < H_SEA:
		return {"terrain": T_SEA, "cover": ""}
	# ② 陆：按高度带 + 湿度
	if height < H_PLAIN:
		if moisture > 0.70:
			return {"terrain": T_PLAIN, "cover": "swamp"}
		if moisture > 0.45:
			return {"terrain": T_PLAIN, "cover": "grass"}
		if moisture > 0.22:
			return {"terrain": T_PLAIN, "cover": "forest"}
		return {"terrain": T_DUNE, "cover": ""}
	if height < H_HILL:
		if moisture > 0.45:
			return {"terrain": T_HILL, "cover": "forest"}
		if moisture > 0.22:
			return {"terrain": T_HILL, "cover": "grass"}
		return {"terrain": T_HILL, "cover": ""}
	if height < H_PLATEAU:
		if moisture > 0.40:
			return {"terrain": T_PLATEAU, "cover": "forest"}
		if moisture > 0.20:
			return {"terrain": T_PLATEAU, "cover": "grass"}
		return {"terrain": T_WASTELAND, "cover": ""}
	return {"terrain": T_MOUNTAIN, "cover": ""}


## 是不是水（深海 + 浅海都算 ✓）
static func is_water(t: Dictionary) -> bool:
	var tr := str(t.get("terrain", ""))
	return tr == T_SEA or tr == T_DEEP


## 是不是**深海**（登陆 / 洪水 / 迷失都要判这个 ✓）
static func is_deep_water(t: Dictionary) -> bool:
	return str(t.get("terrain", "")) == T_DEEP


## 造一格 ✓
## `ctx`：`{ height, moisture, is_river }`（后两个都可省 ✓）
##   · `height`：**0~10 标尺** ✓（1.0 = 海平面 ✓）
##   · `moisture`：0~1 ✓
static func make(c: Vector2i, world_seed: int, ctx: Dictionary) -> Dictionary:
	var h := float(ctx.get("height", 1.0))
	var m := float(ctx.get("moisture", 0.5))
	var b := terrain_of(h, m)

	var t := {
		"c": [c.x, c.y],
		# --- 地形 / 地物 ---
		"terrain": b["terrain"],
		"cover": b["cover"],
		# --- 游戏系统要读的（少一个新世界就玩不了 ✗）---
		"resource": "",
		"owner": Consts.Owner.NONE,
		"discovered": false,
		"is_capital": false,
		"name": "",
		"buildings": [],
		"force": 0.0,
		"threat": false,
		"danger": false,
		"stronghold": "",
		"land_cap": Consts.LAND_CAP_DEFAULT,
		# --- 新生成器自己的字段（旧代码 `.get()` 读不到就不受影响 ✓）---
		"height": h,                            # 高度留档 ✓（以后做气候要读 ✓ 调参也要看 ✓）
	}

	# 河流格（现在先不用 ✓ 但接口留着 ✓）
	if bool(ctx.get("is_river", false)):
		t["river"] = true

	# 基础资源点（新库自己的规则 ✓ 先沿用"森林=木材 / 丘陵=煤铜" ✓ 以后可重定 ✓）
	var rr := Hex.hash01(c, 31 + world_seed)
	if t["cover"] == "forest" and rr < 0.55:
		t["resource"] = "wood"
		t["amount"] = 4.0 + rr * 8.0
	elif t["terrain"] == T_HILL and rr < 0.45:
		t["resource"] = "coal" if rr < 0.22 else "copper"
		t["amount"] = 3.0 + rr * 8.0
	return t
