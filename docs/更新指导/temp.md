
## 【待做·队首】提交这一轮（2026-10-15 ✓ 调试已通过 ✓）

**当前状态（查过 ✓）**：改动 **15 个文件（+404 / −814）** ✓ 新文件 **2 个**（`threats.gd` ✓ `tile_manager.gd` ✓ 各含 `.uid` ✓）✓
未跟踪里有一个 **`.mnemon/`** ✗（工具目录 ✓ 不该提交 ✓）

- [ ] ① `.gitignore` 末尾加一行 `.mnemon/` ✓
- [ ] ② `git status --short` 看一眼（确认没意外文件 ✓）
- [ ] ③ `git add scripts docs` ✓ 然后 **`git status --short` 再看一眼**（养成"提交前看一眼"的习惯 ✓）
- [ ] ④ **第一笔：代码**（解耦 + enum）✓
- [ ] ⑤ **第二笔：文档**（`temp.md` / `ui结构.md` / `README.md`）✓
- [ ] ⑥ `git log --oneline -3` 确认 ✓
- [ ] ⑦ （可选）`git push origin main` ✓ —— 需**完全权限 + 代理（TUN）** ✓ 失败重试一次 ✓

> 两笔的 `-m` 文案我已经写好，见聊天里的那两段 ✓（直接复制 ✓）

---

### ✅ 进度勾选（2026-10-15 ✓ **代码 11 步全做完** ✓ 只差你手测）

- [x] ① `constants.gd` 插入 `enum Owner`（文件头之后 ✓）
- [x] ② `WorldGen.OWNER_*` → `Consts.Owner.*`（**36 处** ✓ 2 个文件 ✓）
- [x] ③ `.get("owner", "")` → `.get("owner", Consts.Owner.NONE)`（**45 处** ✓ 7 个文件 ✓）
- [x] ④ `"player"` → `Consts.Owner.PLAYER`（**17 处** ✓）
- [x] ⑤ `"enemy"` → `Consts.Owner.ENEMY`（**9 处** ✓）
- [x] ⑥ 类型声明 `: String` → `: int`（**8 处** ✓）
- [x] ⑦ 去掉 `str(…)` 包裹（**6 处** ✓）
- [x] ⑧ `t["owner"] = ""` → `Consts.Owner.NONE`（`game_state:1126` ✓）
- [x] ⑨ `== ""` ／ `!= ""` 形态的 owner 判定（**7 处** ✓ 含 `o != ""` 那 3 处 ✓）
- [x] ⑩ 删掉 `world_gen.gd` 的三行定义 ✓ + `"owner": Consts.Owner.NONE` ✓
- [x] ⑪ 自检 + `--import` ✓ **通过**（中途报过 2 个 `int/String` 解析错 ✗ 已修 ✓）
- [ ] ⑫ **你手测**（开新局看"无主格子" ✓）

> **两个顺手结论** ✓：① Godot **接受** `match` 用类常量当分支（`Consts.Owner.PLAYER:` ✓）→ 不用改 `if/elif` ✓
> ② 改成 enum 之后，**写错比较会被解析器当场抓住** ✓（这次就是 `--import` 抓到 `o != ""` 的 ✗ → 以前用字符串时这种错会**静默通过** ✗✓）

---

## 【计划·队首】`owner` 改成 **enum**（2026-10-15 重建 ✓ 依据："1.0 不考虑旧存档" → 选最干净的表达 ✓）

**决定**：**不用字符串** ✗ → 在 `Consts` 里定义 enum ✓

```gdscript
enum Owner {
	NONE = 0,     # 无主
	PLAYER = 1,   # 我方
	ENEMY = 2,    # 敌方
}
```

访问写法：`Consts.Owner.PLAYER` ✓

> **为什么放 `Consts` 而不是 `TileManager`** ✗：`WorldGen._make_tile()` 里也在用 `NONE` ✓
> 放 `TileManager` 就变成 `WorldGen ⇄ TileManager` **互相引用** ✗（Godot 可能报 Cyclic ✓）

> ⚠️ **这是一次性批次** ✗ —— 60 处要**同批改完**才可测 ✓（中途是"字符串 vs 整数"混合 ✗ 行为会错 ✓）
> 所以：**改完立刻** `--import` + 开新局瞄一眼 ✓

### 影响面（已逐条查全 ✓）

| 类别 | 处数 | 在哪 |
| --- | --- | --- |
| **定义** | 3 | `world_gen.gd:12–14` → **删** ✓ 换成 `Consts` 的 enum ✓ |
| **读** `.get("owner", …)` | **45** | `threats` 14 ✓ `game_state` 12 ✓ `tile_manager` 9 ✓ `hex_map_view` 5 ✓ `view_world_page` 4 ✓ `cheat` 2 ✓ `build_panel` 1 ✓ |
| **写** `t["owner"] = …` | **15** | `threats` 11 ✓ `tile_manager` 2 ✓ `game_state:1126`（写的是 `""` ✗）✓ `world_gen:277` ✓ |
| **类型声明 `String` → `int`** ✗ | **8** | `cheat:42/56` ✓ `hex_map_view:208/315` ✓ `game_state:318/1034` ✓ `tile_manager:81/179` ✓ |
| **`str(…)` 包裹要去掉** ✗ | **6** | `hex_map_view:228/251` ✓ `build_panel:78` ✓ `game_state:929` ✓ `view_world_page:175/410` ✓ |

### 做法

**① `constants.gd` 第 5 行之后**（`RARITY_NAMES` **之前** ✓）插入上面的 `enum Owner` ✓

**② 批量替换（能吃掉约 55 处 ✓）**

- `WorldGen.OWNER_NONE` → `Consts.Owner.NONE` ✓ ／ `...OWNER_PLAYER` → `Consts.Owner.PLAYER` ✓ ／ `...OWNER_ENEMY` → `Consts.Owner.ENEMY` ✓
- ⭐ **`.get("owner", "")` → `.get("owner", Consts.Owner.NONE)`** ✓ ← **一条吃掉全部 45 处默认值** ✓✓
  （**这条绝不能漏** ✗ 漏了就是"字符串默认值 vs 枚举"→ 一开局满地图判定错 ✗）
- owner 语境里的 `"player"` → `Consts.Owner.PLAYER` ✓、`"enemy"` → `Consts.Owner.ENEMY` ✓

**③ 手动清"变形处"（约 14 处 ✗ 必须逐个改 ✓）**

- `var xxx: String = …get("owner", …)` → **改成 `int`** ✗→✓
- `str(t.get("owner", …))` → **去掉 `str(...)`** ✗（不然是"整数转字符串再比" ✗）
- `game_state:1126` 的 `t["owner"] = ""` → `= Consts.Owner.NONE` ✓
- `view_world_page:410` 的 `match str(t.get("owner", "")):` → `match t.get("owner", Consts.Owner.NONE):` ✓
  两个分支 `"player":` ／ `"enemy":` → `Consts.Owner.PLAYER:` ／ `Consts.Owner.ENEMY:` ✓
  （⚠️ 若编辑器**不接受** `match` 用类常量当分支 ✗ → 那两行改写成 `if/elif` ✓）
- `world_gen._make_tile()` 里 `"owner": OWNER_NONE,` → `"owner": Consts.Owner.NONE,` ✓

**④ 删掉 `world_gen.gd:12–14` 那三行定义** ✓

### 自检（人工 ✓）

- 搜 `WorldGen.OWNER_` → **0** ✓
- 搜 `const OWNER_` → **0** ✓（定义全没了 ✓ 只剩 `Consts` 里的 `enum Owner` ✓）
- 搜 `.get("owner", "")` → **0** ✓✓（**最能说明问题的一条** ✓）
- 搜 `"player"` ／ `"enemy"` → **0** ✓
- 搜同行含 `owner` 的 `: String = ` → **0** ✓

### 手测（6 项）

- ⭐ **开新局 → 未占领的格子必须都是"无主"** ✓✓
  若一开局满地图都像"被占" ✗ → 就是**默认值那条批量替换漏了** ✗（`""` vs `0` ✓）
- **地图颜色**：我方 / 敌方格子颜色正常 ✓（`hex_map_view` ✓）
- **占一块地** ✓（归属变我方 ✓ 迷雾散开 ✓）
- **清剿**一处敌人 ✓
- **据点面板** ✓ ／ **建造面板**（`build_panel` 那处 ✓）／ **统计面板** ✓
- **存一次 + 读一次新档** ✓（不用管旧档 ✓）

**风险**：中 ✓（60 处 ✓ 且没有"中间可测"状态 ✗）→ 同一批改完立刻 `--import` ✓ 然后你开新局瞄"无主格子" ✓✓

---

## ❌ 作废（2026-10-15 ✗ 下面这版把 `owner` 保持字符串 ✗ 与"1.0 不考虑旧存档"矛盾 ✓）

### 原计划：把 `OWNER_*` 三个常量搬到 `Consts`（2026-10-15 用户定 ✓ "现在不搬，以后更难办"）

**为什么放 `Consts`**（**不能**放 `TileManager` ✗）：
- `WorldGen._make_tile()` 里也在用 `OWNER_NONE` ✓ → 放 `TileManager` 就变成 `WorldGen ⇄ TileManager` **互相引用** ✗（Godot 可能报 Cyclic ✓）
- `Consts` 是**谁都能用、自己谁都不依赖**的常量层 ✓ → 放它最稳 ✓✓

**⚠️ 值必须还是这三个字符串，不许改成 enum** ✗ —— `""` / `"player"` / `"enemy"` **就存在存档里** ✓
改成枚举 = **所有旧存档读不了** ✗✓

### 现状（已查全 ✓）

| 用法 | 处数 | 在哪 |
| --- | --- | --- |
| **定义** | 3 | `world_gen.gd:12–14` ✓ |
| `WorldGen.OWNER_*` | **39** | `threats.gd` 25 ✓ ／ `tile_manager.gd` 11 ✓ ／ 其它 ✓ |
| **裸 `OWNER_NONE`**（只有 world_gen 自己 ✓） | 1 | `world_gen.gd:277`（`"owner": OWNER_NONE,` ✓） |
| **裸字符串 owner 比较** ✗（这次顺手收掉 ✓） | **~24** | `game_state.gd` 11 ✓ ／ `hex_map_view.gd` 6 ✓ ／ `view_world_page.gd` 3 ✓（含 `match` 两行 ✓）／ `cheat.gd` 2 ✓ ／ `build_panel.gd` 1 ✓ |

### 做法（四步 ✓ 每步都能跑 ✓）

**① `constants.gd` 第 5 行之后**（`RARITY_NAMES` **之前** ✓）插入：

```gdscript
# ---------------------------------------------------------------------------
# 地块归属（**这三个字符串就存在存档里** ✓ 别改成 enum ✗ 否则旧档读不了）
# ---------------------------------------------------------------------------
const OWNER_NONE := ""
const OWNER_PLAYER := "player"
const OWNER_ENEMY := "enemy"
```

**② 全项目把 `WorldGen.OWNER_` → `Consts.OWNER_`**（39 处 ✓ 纯机械 ✓）

**③ 把裸字符串的 owner 比较换成常量**（~24 处 ✗ **逐条看** ✓ 因为 `"player"` 这种字符串别处也可能有 ✓）

- `== "player"` → `== Consts.OWNER_PLAYER` ✓ ／ `!= "player"` → `!= Consts.OWNER_PLAYER` ✓
- `== "enemy"` → `== Consts.OWNER_ENEMY` ✓ ／ 同理 ✓
- `view_world_page.gd:411/414` 那两行 `match` 分支 → `Consts.OWNER_PLAYER:` ／ `Consts.OWNER_ENEMY:` ✓
  （⚠️ 若编辑器**不接受** `match` 用类常量当分支 ✗ → 那两行改回字符串 ✓ 或改写成 `if/elif` ✓）
- **别动**：`.get("owner", "")` 里的 `""` 默认值 ✓（`OWNER_NONE` 就是 `""` ✓ 等价 ✓ 改了只是噪音 ✗）

**④ 删掉 `world_gen.gd:12–14` 那三行定义** ✓ 并把 `world_gen.gd:277` 的 `OWNER_NONE` → `Consts.OWNER_NONE` ✓

> ⚠️ **顺序**：先做 ① ② ③、**最后才删定义** ✓（不然中间态会"常量不存在" ✗）

### 自检（人工 ✓）

- `scripts/` 里搜 `WorldGen.OWNER_` → **0** ✓
- 搜 `const OWNER_` → **只有 `constants.gd` 那 3 行** ✓
- 搜 `"player"` ／ `"enemy"` → **只剩 `constants.gd` 里的定义** ✓（还有 ✗ = 漏了 ✓）

### 手测（5 项）

- ⭐ **读一个旧存档** ✓✓（**这条最重要** ✗ —— 值没变，旧档必须照常读 ✓）
- 大世界：**占一块地** ✓（归属变我方 ✓）
- **清剿**一处敌人 ✓
- **地图颜色**正常 ✓（我方/敌方格子色 ✓ `hex_map_view` 用的就是 `"player"/"enemy"` ✓）
- **据点面板** ✓ ／ **建造面板**（`build_panel` 那处 owner 判断 ✓）

**风险**：低-中 ✓（都是机械替换 ✓ 唯一真风险是第 ③ 步**误改非 owner 的 `"player"`** ✗ → 所以逐条看 ✓）

---

## ✅ 代码已完成（2026-10-15 ✓ **待你手检**）：纯度优化 —— `generate()` 末尾 10 行搬进 `TileManager.setup_new_world()`

> **改动** ✓：`tile_manager.gd` 新增 `setup_new_world()` ✓ ／ `game_state.new_game()` **第 100 行**加调用 ✓
> ／ `world_gen.generate()` 末尾那 10 行（标记首都 + 初始点亮）已删 ✓ → `world_gen` **344 → 333 行** ✓
> **手检**：开一次**新游戏** → 首都那一格：归属我方 ✓ 已点亮 ✓ 名字「首都·初始营地」✓ 不能被当扩张目标 ✓
> 初始点亮一圈 ✓；然后**占一块地** ✓ ／ **清剿** ✓ 仍正常 ✓

## 【小修】`game_state.new_game()` 第 103 行有一句**过时的日志文案** ✗

```gdscript
	_add_log("建立部落，营地落在世界中央。", "info")   # ✗ 现在不在中央了
```

v1.8.21 起首都是由 `choose_capital()` 挑出来的（**资源较好、不贴边境**的一格 ✓）
→ 改成类似：`_add_log("建立部落，营地落在 %s。" % str(state["capital"]), "info")` ✓
（第 104 行的"初始点亮营地周围 %d 格"**是准确的** ✓ 不用动 ✓）

---

## 【计划】纯度优化：把 `generate()` 末尾那 10 行搬进 `TileManager.setup_new_world()`

**为什么**：`generate()` 现在同时管两件事 ✗ —— 前半段"**造**格子"（生成 ✓）后半段"标记首都 + 初始点亮"（**改**格子 ✗）
→ 搬完之后 `WorldGen` 就**真的只造不改** ✓；`TileManager` 也补上了"新世界初始化"这一环 ✓

### 现状（已读 ✓ 行号准 ✓）

- `scripts/core/world_gen.gd` · `generate()`（253–274 行）
  - **253–263 行**：造格子 + `state["capital"] = choose_capital(tiles)` ✓ → **留下** ✓
  - **265–274 行**：标记首都 + 初始点亮 ✓ → **要搬** ✗
    - 起点 `265: var cap := coord_of(str(state["capital"]))`
    - 终点 `274: TileManager.discover_radius(state, cap, Consts.CAMP_START_RADIUS)`
- **调用者只有 1 处** ✓：`game_state.gd:99`（`new_game()` 里的 `WorldGen.generate(state)` ✓）

### 做法（顺序别颠倒 ✗：**先加函数 → 再加调用 → 最后删旧码** ✓）

**① `tile_manager.gd` 末尾加：**

```gdscript
## 新世界落成后的地块初始化：标记首都 + 初始点亮
## （从 WorldGen.generate() 搬出来的 ✓ 生成层只管"造" ✗ "改格子"归这里 ✓）
static func setup_new_world(state: Dictionary) -> void:
	var tiles: Dictionary = state["tiles"]
	var cap := WorldGen.coord_of(str(state["capital"]))
	var cap_tile: Dictionary = tiles[key_of(cap)]
	cap_tile["owner"] = WorldGen.OWNER_PLAYER
	cap_tile["discovered"] = true
	cap_tile["is_capital"] = true
	cap_tile["name"] = "首都·初始营地"
	cap_tile["claimable"] = false
	cap_tile["buildings"] = []
	discover_radius(state, cap, Consts.CAMP_START_RADIUS)
```

> ⚠️ 注意：`key_of` 和 `discover_radius` 现在**都是 `tile_manager` 自己的** ✓ → **不要加前缀** ✓
> 只有 `WorldGen.coord_of` / `WorldGen.OWNER_PLAYER` 要前缀 ✓（方向仍是 `TileManager → WorldGen` 单向 ✓）
> 而且 `state["capital"]` 在 `generate()` 里**已经设好了** ✓ → 所以这个函数只要传 `state` 就够 ✓

**② `game_state.gd:99` 之后补一行：**

```gdscript
	TileManager.setup_new_world(state)
```

**③ 删掉 `world_gen.gd` 的 265–274 行**（`var cap := …` 到 `TileManager.discover_radius(…)` ✓）
→ 删完 `generate()` 应当**以** `state["capital"] = choose_capital(tiles)` **结束** ✓

**④ 自检**：`world_gen.gd` 里应当**再也搜不到** `OWNER_PLAYER` ／ `is_capital` ／ `首都·初始营地` ／ `CAMP_START_RADIUS` ✗
（`OWNER_NONE` 还在 ✓ 那是 `_make_tile` 用的 ✓）

### 验收（手检 ✓）

开一次**新游戏** → 看首都那一格：
- 归属我方 ✓ ＋ 已点亮 ✓ ＋ 名字是「首都·初始营地」✓ ＋ 是首都（不能被当扩张目标 ✓）
- **初始点亮是一圈**（`Consts.CAMP_START_RADIUS` ✓）
- 然后**占一块地** ✓ ／ **清剿一处敌人** ✓ 仍正常（`is_capital` / `claimable` 会影响占地判断 ✓）

**行数**：`world_gen` **344 → ≈334** ✓

---

## 【计划】`world_gen.gd` 解耦：**一分为三**（2026-10-15 立 ✓）

> ✅ **2026-10-15 状态：拆完了 ✓ 验收通过 ✓**
> `world_gen.gd` **933 → 344 行** ✓ ／ `tile_manager.gd` **265 行** ✓ ／ `threats.gd` **355 行** ✓
> 旧引用残留 **0** ✓ ／ 新旧两边的"被调名"都对得上定义 ✓ ／ `--import` 无解析错 ✓
> **剩下两件可选**（都在文件末尾 ▸「第 3 步」与「暂留」两条）：① `setup_new_world()` 纯度优化 ✓
> ② `OWNER_*` 三个常量还在 `WorldGen` ✓（全项目都用 `WorldGen.OWNER_*` ✓ 搬它影响面大 ✗ 以后再说 ✓）

**目标**：`world_gen` **只负责"造格子"** ✓；"改格子"归 `tile_manager` ✓；敌人/威胁另立 `threats` ✓

**判据（一句话）**：**造**格子 → `WorldGen` ✓ ／ **改**格子（归属·迷雾·资源·敌人）→ `TileManager` ✓ ／ **只跟敌人有关**（刷怪·演化·破坏）→ `Threats` ✓

### 现状清点（933 行 / 51 个条目 ✓ 已逐个归类）

| 归谁 | 装什么 | 原行号 |
| --- | --- | --- |
| **`WorldGen`（留下）** | 噪声 / 大陆形状 / 高程 / 侵蚀 / 河格 / 湿度 / 地形地物表 / 挑首都 / `generate` / `_make_tile` / `expand_map` / `map_radius` / `coord_of` / `OWNER_*`（**注**：`key_of` 后来也搬进了 `TileManager` ✓ 全项目 31 处已改 ✓） | 40–56, 63–74, 90–175, 180–185, 192–207, 212–235, 242–273, 285–354, 908–932 |
| **`TileManager`（新）** | 地块键工具（`tile_key` / `middle_key`）/ 迷雾（`discover_radius` / `discover_all`）/ 领地（`claim_base_cost` `claim_cost` `claimable_keys` `claim` `_stronghold_for_claim`）/ 清剿（`clear_requirement` `can_clear` `clear_tile` `_adjacent_to_player`）/ 资源点（`spawn_resource_node`）/ 计数（`owned_tile_count` `enemy_tile_count` `_enemy_tile_count`）/ `amount_cap` | 17–28, 275, 364–488, 618–680, 681–700, 853–857 |
| **`Threats`（新）** | 危险据点 / 游荡敌人 / 终极威胁 / 候选格 / 敌人上限 / **`evolve`（151 行）** / `_damage_tile` | 490–628, 702–851 |
| **暂留** | `OWNER_NONE/PLAYER/ENEMY`（全项目都用 `WorldGen.OWNER_*` ✓ 搬它影响面太大 ✗ 以后再说 ✓） | 12–14 |

### 依赖方向（已确认**不会成环** ✓）

```
TileManager → WorldGen.make_tile()     ← 扩张/新世界要"造一格" ✓
Threats     → 谁都不依赖 ✓
WorldGen    → 谁都不依赖 ✓✓           ← 因为 expand_map 留在 WorldGen ✓
```

> `_make_tile` 要**转公开 → `make_tile`** ✓（跨模块用 ✓）
> `expand_map` **留在 `WorldGen`** ✓ —— 它本质是 `generate` 的增量版 ✓ 也是唯一需要 `make_tile` 的外部入口 ✓

### 可选但建议：把"造完之后那 5 行"也挪走

`generate()` 末尾那几行（首都标记 `owner/discovered/is_capital/name/claimable` + `discover_radius` 初始点亮 ✓）
**其实都是"改格子"** ✗ → 建议挪成 `TileManager.setup_new_world(state)` ✓
→ `game_state.new_game()` 里 `WorldGen.generate(state)` 之后补一句 ✓
（**不是必须** ✓ 不做也不会成环 ✓ 只是让生成层更纯 ✓）

### 调用点：21 处 / 9 个文件（已查全 ✓）

| 文件 | 处 | 用到的 |
| --- | --- | --- |
| `ui/views/view_world_page.gd` | 5 | `claimable_keys` ×2 ✓ `claim_cost` ✓ `claim` ✓ `expand_map` |
| `core/game_state.gd` | 4 | `tile_key` ✓ `middle_key` ✓ `discover_radius` ✓ `evolve` |
| `core/gacha.gd` | 5 | `maybe_spawn_wanderer` ✓ `maybe_spawn_hazard` ✓ `spawn_ultimate_threat` ✓ `spawn_resource_node` ✓ `expand_map` |
| `ui/panels/stats_panel.gd` | 2 | `claim_cost` ✓ `claimable_keys` |
| `ui/panels/stronghold_panel.gd` | 2 | `tile_key` |
| `ui/views/parts/treasure_character/team.gd` | 1 | `tile_key` |
| `ui/cheat_menu.gd` | 1 | `tile_key` |
| `core/cheat.gd` | 1 | `discover_all` |

> 替换时**按函数名搜** ✓ 别按行号 ✗（会漂 ✓）

### 做法（三步 ✓ 每步都能跑 ✓ 每步都要**真的开一局玩一遍** ✗ 因为没有自检了 ✓）

1. **先建 `threats.gd`**（最独立 ✓ 零外部依赖 ✓）
   把 490–628 + 702–851 整段剪过去 ✓ → 改 `game_state.gd` 里 `evolve` 那处 ✓ + `gacha.gd` 里刷怪那三处 ✓
   **手玩**：抽卡触发游荡敌人 / 高危据点 ✓ 周期结算里敌人演化正常 ✓
2. **再建 `tile_manager.gd`**：搬上表那一堆 ✓ + `_make_tile` → **`make_tile`**（public ✓）
   把 7 个文件的 `WorldGen.X` → `TileManager.X` ✓（`view_world_page` / `stats_panel` / `stronghold_panel` / `team` / `cheat_menu` / `cheat` / `game_state` ✓）
   **手玩**：占领 ✓ 迷雾 ✓ 统计面板（扩张消耗/相邻无主格 ✓）据点面板 ✓ 角色页队伍 ✓ 作弊菜单揭迷雾 ✓
3. **（可选）解纯度**：把"首都标记 + 初始点亮"挪成 `TileManager.setup_new_world(state)` ✓
   **手玩**：开新局 ✓ 首都位置/名字/初始点亮范围都对 ✓

**验收（人工 ✓）**：全项目搜 `WorldGen.` ✓ 剩下的应当**只有生成相关**
（噪声/高程/侵蚀/湿度/地物表/`generate`/`make_tile`/`choose_capital`/`expand_map`/`map_radius`/`key_of`/`coord_of`/`OWNER_*` ✓）

---

## 【小修】`DialogLayer.set_content()` 里那条**打不着**的守卫

```gdscript
	var slot := _body.get_node_or_null("ContentSlot")
	if slot == null:
		return
```

- `_body != null` 时，`ContentSlot` **必然已经存在**（同一帧 `_ready` 里刚建 ✓）→ 这条**永远不成立** ✗
- 唯一能"触发"它的方式是**有人改了节点名** ✓ = 开发错误 ✓ 不在负责范围 ✓（按项目口径：不可能路径不写守卫 ✓）
- 而且**删了更好** ✓：留着它 = 把开发错误变成**静默失败**（内容凭空消失、一句报错都没有 ✗）；
  删掉后（或改用 `get_node` ✓）改错名字会**当场报错并指出行号** ✓

> ⚠️ **上面那条 `if _body == null:` 要留着** ✓ —— 那是正当的"**先设内容、后入树**"路径，
> 而且**本项目正在走**：`CheatMenu.build()` 里 `set_content(sc)` 发生在 `add_child(d)` **之前** ✓
> → 那时 `_ready` 还没跑 ✓ → 内容先存进 `_content` ✓ 由 `_ready` 里补挂 ✓

**验收**：删掉那两行 ✓ 开一次游戏 ✓ 弹窗内容照常显示 ✓
