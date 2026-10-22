class_name WorldPreview
extends RefCounted
## 世界生成**预览工具** —— **不开始游戏** ✓ 只生成一次世界 ✓ 出一张 PNG ✓
##
## 复用游戏里的 `HexMapView` 画 ✓ 所以图里看到的就是进游戏后会看到的样子 ✓
##
## ⭐ 用途：**同一张图出两次 → 逐字节一致** ✓
##   （没有自检套件的现在，这是唯一的"确定性验收" ✓）
##
## ⚠️ 必须**带窗口**跑 ✗（`--headless` 下 `SubViewport` 拿不到纹理 ✓）
## ⚠️ 会**临时替换** `GameState.state` ✓ 画完立刻还原 ✓（换的是**句柄** ✓ 不是深拷贝 ✓）
##
## 2026-10-16：画布尺寸改成**按地图半径算** ✓（以前写死 3000 ✗ 半径改到 50 之后就切边 ✗）

## 出图目录：放项目里 ✓ 你能直接双击看 ✓（导出版 `res://` 只读 ✗ 但这是开发工具 ✓）
const OUT_DIR := "res://preview"
const HEX_SIZE := 32.0


## 画布尺寸 ＋ 原点：**按当前半径算** ✓（跟着 `Hex` 的像素换算走 ✓ 不自己推公式 ✗）
## 返回 `{ size: Vector2i, origin: Vector2 }`；`origin` 是"世界原点在画布里的位置" ✓
static func _canvas(radius: int, hex_size: float) -> Dictionary:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c: Vector2i in Hex.spiral(radius):
		var p := Hex.axial_to_pixel(c.x, c.y, hex_size)
		min_v = Vector2(minf(min_v.x, p.x), minf(min_v.y, p.y))
		max_v = Vector2(maxf(max_v.x, p.x), maxf(max_v.y, p.y))
	var pad := hex_size * 1.5
	var w := int(ceil(max_v.x - min_v.x + pad * 2.0))
	var h := int(ceil(max_v.y - min_v.y + pad * 2.0))
	return {"size": Vector2i(maxi(w, 64), maxi(h, 64)), "origin": Vector2(w * 0.5, h * 0.5)}


## 生成一张预览图 ✓ 返回 `{ok, path, seed}`（path 是**绝对路径** ✓ 失败为空 ✓）
static func save_preview(host: Node, seed_value: int) -> Dictionary:
	var old_state: Dictionary = GameState.state
	GameState.new_game(seed_value)          # 生成一张完整、合法的世界 ✓
	# `HexMapView` 有 7 处 `if not t["discovered"]: return` ✓ → 不揭开就只画首都周围几圈 ✗
	TileManager.discover_all(GameState.state)
	var real_seed := int(GameState.state.get("seed", seed_value))

	var radius := Consts.MAP_START_RADIUS
	var canvas := _canvas(radius, HEX_SIZE)

	# --- 离屏视口（尺寸跟着地图走 ✓）---
	var vp := SubViewport.new()
	vp.size = canvas["size"]
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)

	var view := HexMapView.new()
	view.hex_size = HEX_SIZE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(view)
	view.center_on_axial(Vector2i.ZERO)    # 全图居中 ✓ 不跟首都（跟了会裁掉半边 ✗）
	await host.get_tree().process_frame
	await host.get_tree().process_frame    # 再等一帧：让 `_draw` 跑完 ✓

	var img: Image = vp.get_texture().get_image()
	var path := ""
	if img != null and img.get_width() > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		var abs_path := ProjectSettings.globalize_path(
			"%s/worldgen_%d_%s.png" % [OUT_DIR, real_seed, stamp])
		var err := img.save_png(abs_path)
		if err == OK:
			path = abs_path
		else:
			push_warning("预览图保存失败（错误 %d）：%s" % [err, abs_path])
	else:
		push_warning("预览图渲染失败：视口没拿到纹理（是不是在 --headless 下跑的？）")

	vp.queue_free()
	GameState.state = old_state            # 还原 ✓
	return {"ok": path != "", "path": path, "seed": real_seed}
