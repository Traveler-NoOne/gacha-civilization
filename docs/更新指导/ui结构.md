# `scripts/ui/` 结构说明

> 2026-10-15 立 ✓ **这份写的是"现在的样子"**，不是历史记录 ✓
> 规模：`scripts/ui/` 共 **33 个 `.gd`**（含 `views/parts/treasure_character/` 子目录里的 5 个 ✓）

---

## 一、四类文件（别混 ✓）

| 类别 | 在哪 | 里面是什么 | 怎么被加载 |
| --- | --- | --- | --- |
| **顶层「屏」** | `ui/*.gd` | 整屏逻辑：`main`（场景根）/ `menu_screen`（主菜单）/ `game_screen`（游戏界面）/ `loading_screen` | 编辑器与 `scenes/main.tscn` 直接挂 ✓ |
| **导航页** | `ui/views/*.gd` | 导航切换的一级页：`view_world_page`（大世界）/ `gacha_view`（世界泡）/ `treasure_view`（至宝）/ `log_view`（日志） | **按路径表** `load(...).new()` ✓（表在 `view_world_page` 之外的父级/各 view 自己里 ✓） |
| **浮窗 / 页面板** | `ui/panels/*.gd` | 跟随式浮窗：`stronghold_panel` / `stats_panel` / `build_panel` / `tech_panel` / `log_panel`，以及基类 `page_panel` | **有 `class_name`**，按类 `new()` ✓ |
| **控件与工具** | `ui/*.gd`（其余） | `ui_kit`（静态工厂）/ `hex_map_view`（地图控件）/ `dialog_layer`（通用弹窗）/ `geo_icon` / `cheat_menu` / `view_host` / `ui_scale` | 按需 ✓ |

---

## 二、两条**有意**的差异（别去"统一" ✗）

1. **`views/` 与 `views/parts/` 不加 `class_name`** ✓ —— 它们靠**路径表**加载
   （形如 `{"id": "...", "name": "...", "script": "res://..."}` ✓）
   → 好处：加页 / 换页 / 改名**只动表里一行** ✓
2. **`panels/` 有 `class_name`** ✓ —— 因为它们是"按类实例化"的浮窗 ✓

---

## 三、`views/parts/` 是什么

**某个父视图的私有子页**（不是公共控件 ✓）：

| 父视图 | 它的子页 |
| --- | --- |
| `views/log_view.gd` | `parts/log_task.gd` / `log_record.gd` / `log_codex.gd` / `log_manual.gd` |
| `views/treasure_view.gd` | `parts/treasure_character.gd` / `treasure_gear.gd` / `treasure_item.gd` |
| `parts/treasure_character.gd` | `parts/treasure_character/` 下的 `main` / `skill` / `profession` / `rank` / `team` ✓ |

> 命名规则 = **家族名 + 用途** ✓（`log_*` ✓ `treasure_*` ✓ `treasure_character/*` ✓）

---

## 四、子页的**两种形态**（看它有没有 `class_name` 就能分辨 ✓）

| 形态 | 长相 | 怎么调 |
| --- | --- | --- |
| **页**（`extends Control` ✓ **无 `class_name`**） | 自带 `_ready()` / `refresh()` / `on_cycle_finished()` | `load(路径).new()` → 加进容器 → `add_child` 触发它的 `_ready` ✓ |
| **构建器**（`extends RefCounted` ✓ **有 `class_name`**） | `static func build(detail_host, u, on_changed)` ✓ **无状态** ✓ | **按类名直接调** ✓（`CharacterMain.build(...)` ✓） |

> ⚠️ **这是踩过的坑** ✗：`load("x.gd").build(...)` 和 `dict["k"].build(...)` 都是**动态调用** ✗，
> 而**静态函数只能按"类名"直接调** ✓ —— 想让它能跑，就给文件一个 `class_name` ✓
> （`UnitDB.rank_name()` / `TileManager.key_of()` / `Cheat.set_enabled()` 全是这个道理 ✓）

---

## 五、明确**不做**的（免得将来手痒 ✓）

- **不拆** `ui_kit.gd`（474 行，纯静态工厂 ✓ 内聚 ✓）、**不拆** `hex_map_view.gd`（475 行，一个控件的整套绘制 ✓）
- **不给** `views/*.gd` / `views/parts/*.gd` 加 `class_name` ✗（它们靠路径表 ✓）
- **不把**顶层 4 个「屏」再分 `screens/` ✗（路径引在 `main.tscn` / `main.gd` / `project.godot` ✓ 收益只是整齐 ✗）
- **不动** `view_host.gd`（15 行但它是**真工具**：「只显示一个子视图的容器（懒加载 + 切换）」✓）

### 为什么根部这 11 个**不分**子文件夹（2026-10-15 定 ✓ 附阈值）

**现状**：根部 11 个 = 4 屏 + 6 控件/工具 + 1 尺寸 ✓ 四类**一句话就能说清** ✓

1. **代价是真的**：这 11 个里有 6 个的路径被硬编码在别处（`main.gd` 里 3 条屏路径 ✓、`main.tscn` 挂 `main.gd` ✓、
   `project.godot` 挂 `ui_scale.gd` ✓、`game_screen` 里 `preload(view_host.gd)` ✓、`UIKit` 里 `dialog_layer` ✓）
   → 搬一次要改 **6~8 处字符串** ✗，而且 **`tests/` 已删** ✓ → 只能靠手动跑游戏才发现错 ✗
2. **根部这几个恰好是"最该先看到"的** ✓（屏在哪 / 工具箱在哪 / 地图控件在哪 ✓）→ 多一层反而多一跳 ✗
3. **Godot 路径文化** ✗ 目录越深 `res://` 路径越长越易错 ✓

**该分的阈值（三条，任一触发再动 ✓）**
- 根部**超过 ~15 个文件** ✗
- **某一类超过 ~6 个且还在长** ✗（现在 4 / 6 / 1 ✓ 都在舒适区 ✓）
- 出现"**3 个以上只有彼此在用**"的小圈子 ✗ → 那时它才该成为 `screens/` / `widgets/` ✓

**真要分的话：只在编辑器的文件系统面板里拖** ✗→✓
> 别用手搬（资源管理器 / `git mv`）✗ —— 每个 `.gd` 还配一个 `.uid` ✓
> 手搬要".uid 一起搬 + 手动改所有引用" ✓；编辑器拖会自动改 ✓✓
> （`ui_scale.gd` 那次能零改动，是因为 **autoload 名字没变** ✓ 不是因为"搬文件不要紧" ✗）

---

## 六、想查当前结构（一条命令）

```powershell
$ui = Resolve-Path scripts\ui
Get-ChildItem $ui -Recurse -File -Filter *.gd | ForEach-Object {
  "{0,5}  {1}" -f (Get-Content $_.FullName).Count, $_.FullName.Substring($ui.Path.Length + 1)
} | Sort-Object
```
