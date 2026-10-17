class_name TileDef
extends RefCounted
## 地块的定义：**"一个地块长什么样"只有这里说了算** ✓
## 2026-10-15 从 world_gen.gd 搬出来 ✓（生成层只负责"按坐标算出来"，不再自己定义地块的形状）
##
## ⚠️ 地块是**纯 Dictionary**（不是 Resource、不是对象）✓
##   理由：一局有 1387+ 格 ✓ 每格一个对象既费内存又难存档 ✓
##   （对照：`BuildingDef` 用 `Resource` 是对的 ✓ 因为建筑只有几十个 ✓）
##
## ⚠️ 依赖方向：本文件 → `WorldGen`（只用它的高程 / 湿度 / "这格是不是河"）✓ **单向** ✓
##    别在这里反向依赖 `TileManager` ✗

## 高程分档阈值（v1.8.21 第 2 段）。**低于 `WATER_LEVEL` 就是水** ✓
## 原先这四个数是散在 `biome_of()` 里的裸数字 ✗（想调"海多海少"得翻代码 ✓ 现在在这里 ✓）
const WATER_LEVEL := 0.36
const PLAIN_LEVEL := 0.50
const HILL_LEVEL := 0.62
const MOUNTAIN_LEVEL := 0.72

## 二维查表：每行 `[高度上限, 湿度下限, 地形, 地物]`，**从上往下取第一条**
## 「`e < 高度上限` 且 `m > 湿度下限`」的行 ✓；每档最后一行是兜底（湿度下限写 `-1.00` ✓，
## 湿度恒在 0~1 ✓ 所以它必然命中 ✓）。
## ⚠️ **行序就是优先级** ✗ —— 改表时别打乱顺序 ✓（阈值大的湿度行要放在前面 ✓）
const BIOME_TABLE := [
	# 0.36 ~ 0.50：平原带
	[PLAIN_LEVEL,    0.70, "plain",     "swamp"],
	[PLAIN_LEVEL,    0.45, "plain",     "grass"],
	[PLAIN_LEVEL,    0.22, "plain",     "forest"],
	[PLAIN_LEVEL,   -1.00, "dune",      ""],
	# 0.50 ~ 0.62：丘陵带
	[HILL_LEVEL,     0.45, "hill",      "forest"],
	[HILL_LEVEL,     0.22, "hill",      "grass"],
	[HILL_LEVEL,    -1.00, "hill",      ""],
	# 0.62 ~ 0.72：高地带
	[MOUNTAIN_LEVEL, 0.60, "hill",      "forest"],
	[MOUNTAIN_LEVEL, 0.30, "hill",      "grass"],
	[MOUNTAIN_LEVEL, -1.00, "wasteland", ""],
]

## 高程 + 湿度 → 一层地形 + 一层地物（Red Blob 那篇的二维查表，阈值按本作的种类改过）。
## 仍是 f(坐标, 种子) 的纯函数。
## 2026-10-15：原来的 if 串改成查上面的 `BIOME_TABLE` ✓（**等价改写** ✓ 同种子必须一格不差 ✓）
static func biome_of(e: float, m: float) -> Dictionary:
	if e < WATER_LEVEL:
		return {"terrain": "water", "cover": ""}
	for row in BIOME_TABLE:
		if e < float(row[0]) and m > float(row[1]):
			return {"terrain": str(row[2]), "cover": str(row[3])}
	# e ≥ MOUNTAIN_LEVEL：这一档不分湿度，一律山地
	return {"terrain": "mountain", "cover": ""}


## 这一格是不是水 ✓（"水"是**地形**之一 ✓ 与"河"无关 ✗ —— 河是 `t["river"]` ✓）
## 各处判断都走这里 ✗ 别自己写 `== "water"` ✗（以前散在 5 处 ✓）
static func is_water(t: Dictionary) -> bool:
	return str(t.get("terrain", "")) == "water"


## 造一格（地形 + 基础资源）。
## v1.8.20.9：地形/资源 = f(坐标, 世界种子) 的纯函数 —— 同种子同地图，
## 且 expand_map() 后加的那一格与"一开始就生成这么大"时必然一致。
## 别改成用 rng 按顺序摇地形：那样同一格会随生成顺序变样，这条一致性就没了。
static func make(c: Vector2i, world_seed: int) -> Dictionary:
	var t := {
		"c": [c.x, c.y],
		"terrain": "plain",
		"cover": "",
		"resource": "",

		"owner": Consts.Owner.NONE,
		"discovered": false,
		"is_capital": false,
		"name": "",
		"buildings": [],
		"force": 0.0,
		"threat": false,
		"danger": false,   # 高危据点
		"stronghold": "",  # v1.3.1：所属据点（我方地块才有）
		"land_cap": Consts.LAND_CAP_DEFAULT,   # v1.3.1：可用土地上限
	}
	# v1.8.21 第 2 段：地形（地貌）与地物（覆盖物）分两层，由高程 + 湿度查表得出
	var b := biome_of(WorldGen.eroded_elevation_of(c, world_seed), WorldGen.moisture_of(c, world_seed))

	t["terrain"] = b["terrain"]
	t["cover"] = b["cover"]
	# v1.8.21：河流格（上面那次侵蚀已经顺便挑好了，这里只是问一句"这格是不是河"）
	if WorldGen.is_river(c):
		t["river"] = true

	# 基础资源点
	var rr := Hex.hash01(c, 31 + world_seed)
	if t["cover"] == "forest" and rr < 0.55:
		t["resource"] = "wood"
		t["amount"] = 4.0 + rr * 8.0
	elif t["terrain"] == "hill" and rr < 0.45:
		t["resource"] = "coal" if rr < 0.22 else "copper"
		t["amount"] = 3.0 + rr * 8.0
	return t
