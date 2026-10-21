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
## 2026-10-16：加了 `DEEP_LEVEL`（深海 ✓）与 `HIGHLAND_LEVEL`（高原带 ✓）——
## 因为用户说"地块种类太少" ✓：原来 0.62~0.72 全算丘陵 ✗ 高原被吞了 ✓
const DEEP_LEVEL := 0.20
const WATER_LEVEL := 0.36
const PLAIN_LEVEL := 0.50
const HILL_LEVEL := 0.62
const HIGHLAND_LEVEL := 0.66
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
	# 0.62 ~ 0.66：高地丘陵
	[HIGHLAND_LEVEL, 0.45, "hill",      "forest"],
	[HIGHLAND_LEVEL, 0.22, "hill",      "grass"],
	[HIGHLAND_LEVEL, -1.00, "hill",     ""],
	# 0.66 ~ 0.72：**高原带**（新 ✓ 高而平 ✓ 湿度只决定植被 ✓）
	[MOUNTAIN_LEVEL, 0.40, "plateau",   "forest"],
	[MOUNTAIN_LEVEL, 0.20, "plateau",   "grass"],
	[MOUNTAIN_LEVEL, -1.00, "wasteland", ""],
]

## 高程 + 湿度 → 一层地形 + 一层地物（Red Blob 那篇的二维查表，阈值按本作的种类改过）。
## 仍是 f(坐标, 种子) 的纯函数。
## 2026-10-15：原来的 if 串改成查上面的 `BIOME_TABLE` ✓（**等价改写** ✓ 同种子必须一格不差 ✓）
## 2026-10-16：水拆成**深海 / 浅海** ✓（登陆、洪水、洋流都要这个区分 ✓）
static func biome_of(e: float, m: float) -> Dictionary:
	if e < DEEP_LEVEL:
		return {"terrain": "deep_water", "cover": ""}
	if e < WATER_LEVEL:
		return {"terrain": "water", "cover": ""}
	for row in BIOME_TABLE:
		if e < float(row[0]) and m > float(row[1]):
			return {"terrain": str(row[2]), "cover": str(row[3])}
	# e ≥ MOUNTAIN_LEVEL：这一档不分湿度，一律山地
	return {"terrain": "mountain", "cover": ""}


## 这一格是不是水 ✓（"水"是**地形**之一 ✓ 与"河"无关 ✗ —— 河是 `t["river"]` ✓）
## 各处判断都走这里 ✗ 别自己写 `== "water"` ✗（以前散在 5 处 ✓）
## ⚠️ 2026-10-16：水拆成"深海 / 浅海"两种 ✓ → **两个都算水** ✓✓
##    （挑首都 / 刷怪候选 / 占地 / 清剿 全靠这个函数排除水 ✓ 漏一个就会往海里放东西 ✗）
static func is_water(t: Dictionary) -> bool:
	var tr := str(t.get("terrain", ""))
	return tr == "water" or tr == "deep_water"


## 造一格（**旧系统的入口** ✓）。
## v1.8.20.9：地形/资源 = f(坐标, 世界种子) 的纯函数 —— 同种子同地图，
## 且 expand_map() 后加的那一格与"一开始就生成这么大"时必然一致。
## 别改成用 rng 按顺序摇地形：那样同一格会随生成顺序变样，这条一致性就没了。
##
## 2026-10-16：拆出 `make_from()` 当**接缝** ✓ —— 新世界生成器（`scripts/worldgen/`）
## 把自己算出来的高度传进来 ✓ 就能填出**同一套旧字段**的 tiles ✓✓
##（⚠️ **不是**"新库不许加字段" ✗ —— 加新字段的活儿在新库那边做 ✓ 这里只负责"旧字段怎么填" ✓
##  旧代码读地块一律 `.get(key, 默认值)` ✓ 所以新字段它看不见 ✓ 互不打扰 ✓）
## 本函数**行为一个字节都没变** ✓（只是把三个输入从"内部算"变成"参数" ✓）
static func make(c: Vector2i, world_seed: int) -> Dictionary:
	return make_from(c, world_seed,
		WorldGen.eroded_elevation_of(c, world_seed),   # 旧：侵蚀后的高度
		WorldGen.moisture_of(c, world_seed),           # 旧：噪声湿度（M4 才换 ✓）
		WorldGen.is_river(c))


## 造一格（**高度 / 湿度 / 是否河 / 地貌打标**，都由调用方给 ✓ 2026-10-16 新增的接缝 ✓）
## 除这些输入，其余（字段、资源规则）与 `make()` 完全一致 ✓
## `landform` 用来放"**高度本身表达不出来**"的东西 ✓（现在只有 "valley" 谷地 ✓ —— 它低不低要看四周 ✓）
static func make_from(c: Vector2i, world_seed: int, height: float, moisture: float,
		is_river: bool, landform: String = "") -> Dictionary:
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
	var b := biome_of(height, moisture)

	t["terrain"] = b["terrain"]
	t["cover"] = b["cover"]
	# 地貌打标（生成器才知道的东西 ✓）：谷地 = 比四周低 ✓ 高度自己看不出来 ✓
	if landform != "":
		t["terrain"] = landform
	# 河流格：由调用方决定 ✓（旧系统来自侵蚀挑出的 `_river_keys` ✓ 新系统将来来自 M6 的水网 ✓）
	if is_river:
		t["river"] = true

	# 基础资源点（规则没变 ✓ 仍是"地物 = 森林 / 地形 = 丘陵"✓）
	var rr := Hex.hash01(c, 31 + world_seed)
	if t["cover"] == "forest" and rr < 0.55:
		t["resource"] = "wood"
		t["amount"] = 4.0 + rr * 8.0
	elif t["terrain"] == "hill" and rr < 0.45:
		t["resource"] = "coal" if rr < 0.22 else "copper"
		t["amount"] = 3.0 + rr * 8.0
	return t
