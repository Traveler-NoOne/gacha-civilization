
## 第 5 步：给 `ui/` 写一份结构说明

放 `docs/更新指导/ui结构.md` ✓（**别塞进代码** ✗），内容三句：
1. 四类边界：`*_screen` = 顶层屏 ✓ / `views` = 导航页 ✓ / `panels` = 浮窗与页面板 ✓ / 其余 = 控件与工具 ✓
2. **哪些有 `class_name`、哪些按路径加载**（`panels` 有 ✓ 按类 `new()`；`views` / `parts` 没有 ✓ 按路径表加载 ✓ —— 这是**有意的** ✓ 别"统一" ✗）
3. `views/parts/*` 是**某个父视图的私有子页** ✓（不是公共控件 ✗）

## ⚠️ 明确**不做**的（免得将来手痒 ✓）

- **不拆** `ui_kit.gd`（474 行但纯工厂 ✓ 内聚 ✓）、**不拆** `hex_map_view.gd`（475 行，一个控件的整套绘制 ✓）
- **不给** `views/*.gd` 加 `class_name` ✗（它们靠路径表加载 ✓）
- **不把** `ui/` 顶层 4 个"屏"再分 `screens/` ✗（路径引在 `main.tscn` / `main.gd` / `project.godot` 里 ✓ 收益只是整齐 ✗）
- **不动** `view_host.gd`（15 行但它是**真工具**："只显示一个子视图的容器（懒加载 + 切换）" ✓）

---

## 【必修】`DialogLayer.fit_now()` 的 `chrome` 会**越算越大** ✗（"面板被顶到满屏"的根因）

**现象**：反复切页签（= 反复调 `fit_now()`）之后，弹窗高度**只增不减** ✗，最后顶到视口上限
（你截的图正是：面板 ≈1060、`usable_height()` = 1080 ✓ 正好撞满 ✓）

**根因**（`scripts/ui/dialog_layer.gd` 的 `fit_now()`）：

```gdscript
	var panel_min := _panel.get_combined_minimum_size().y   # ✗ 这里含着"上一次写死的面板高度"
	var slot_min := slot_c.get_combined_minimum_size().y
	var chrome := maxf(0.0, panel_min - slot_min)           # ✗ 于是 chrome 把上一次的整个高度都吃进去
	...
	_panel.custom_minimum_size = Vector2(dialog_width, chrome + body_room)   # ✗ 再写回去 → 越滚越大
```

`custom_minimum_size` **本身就计入** `get_combined_minimum_size()` ✓
→ 所以那行量的是"**面板固有内容 + 上一次写进去的高度**" ✗

**为什么以前没暴露**：旧版单页作弊菜单**只调一次** `fit_now` ✓；三页签每次切换都调 ✓ → 才露出来 ✓

**修法**：在量 `panel_min` **之前**，先把面板写死的高度**归零** ✓（就像它已经对 `slot_c` 做的那样 ✓）

```gdscript
	slot_c.custom_minimum_size = Vector2(UI.px(0), UI.px(0))
	slot_c.size_flags_vertical = Control.SIZE_FILL
	_panel.custom_minimum_size = Vector2(dialog_width, 0)      # ← 就加这一行 ★
	var panel_min := _panel.get_combined_minimum_size().y
```

**验收**：开作弊菜单 → 在三个页签之间**反复切 10 次** ✓
面板高度应当**跟着当前页内容上下变**（资源页高、世界页矮 ✓），**不再单调变大** ✓、也不再每次都顶满屏 ✓

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
