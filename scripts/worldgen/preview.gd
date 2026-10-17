class_name WorldPreview
extends RefCounted
## 世界生成**预览工具**（2026-10-15）—— **不开始游戏** ✓ 只生成一次世界 ✓ 出一张 PNG ✓
##
## 两个用途（都是迭代生成器时最需要的 ✓）：
##   1. 看"这张图长什么样" ✓ —— **复用游戏里的 `HexMapView`** ✓ 所以和游戏里看到的**完全一致** ✓
##   2. ⭐ **同一个种子出两次 → 两张图应当逐格一致** ✓✓
##      （在没有自检套件的现在，这是**唯一可用的"确定性验收"** ✓）
##
## ⚠️ 必须**带窗口**跑 ✗ —— `--headless` 下 `SubViewport` 拿不到纹理 ✓
## ⚠️ 它会**临时替换** `GameState.state`（好让 `HexMapView` 有东西可画）✓ 画完立刻还原 ✓
##    原理：换的是**句柄** ✓ 不是深拷贝 ✓（Dictionary 在 GDScript 里是引用 ✓）

## 出图目录：放在项目里 ✓ 你能直接双击看 ✓（跑导出版时 `res://` 只读 ✗ 但这是开发工具 ✓）
const OUT_DIR := "res://preview"
## 画布边长：够装下半径 21 的全图 ✓（hex_size 32 → 约 2400px ✓ 留余量 ✓）
const PIXELS := 3000
const HEX_SIZE := 32.0


## 生成一张预览图 ✓ 返回 `{ok, path, seed}`（path 是**绝对路径** ✓ 失败时为空 ✓）
static func save_preview(host: Node, seed_value: int) -> Dictionary:
	var old_state: Dictionary = GameState.state
	GameState.new_game(seed_value)          # 生成一张完整、合法的世界（含首都/据点/初始单位 ✓）
	# ⚠️ 预览要的是"**生成出来的世界**" ✓ 不是"玩家此刻看到的世界" ✗
	#    `HexMapView` 有 7 处 `if not t["discovered"]: return` ✓ → 不揭开就只画首都周围三圈 ✗
	#    这里复用 `TileManager.discover_all()`（作弊菜单"揭开全部迷雾"用的也是它 ✓）
	#    画完会连同 state 一起还原 ✓ 零副作用 ✓
	TileManager.discover_all(GameState.state)
	var real_seed := int(GameState.state.get("seed", seed_value))

	# --- 离屏视口 + 复用游戏里的地图控件 ---
	var vp := SubViewport.new()
	vp.size = Vector2i(PIXELS, PIXELS)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)

	var view := HexMapView.new()
	view.hex_size = HEX_SIZE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(view)
	view.center_on_axial(Vector2i.ZERO)      # 全图居中 ✓ 不跟首都（跟了会裁掉半边 ✗）

	# 等两帧：让布局 + _draw 都跑完 ✓
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var img: Image = vp.get_texture().get_image()
	var path := ""
	if img != null and img.get_width() > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		var abs_path := ProjectSettings.globalize_path("%s/worldgen_%d_%s.png" % [OUT_DIR, real_seed, stamp])
		var err := img.save_png(abs_path)
		if err == OK:
			path = abs_path
		else:
			push_warning("预览图保存失败（错误 %d）：%s" % [err, abs_path])
	else:
		push_warning("预览图渲染失败：视口没拿到纹理（是不是在 --headless 下跑的？）")

	vp.queue_free()
	GameState.state = old_state              # 还原 ✓ 不让预览搅乱当前状态
	return {"ok": path != "", "path": path, "seed": real_seed}
