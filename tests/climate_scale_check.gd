extends Node
## 降水**尺度不变性**专项测试 —— 故意从默认自检里**拆出来的"慢测试"**。
##
## 为什么要拆：默认 `climate_check` 会在一趟里重建多次场（多分辨率 × 真实/平坦）。
## 字段涨到 384² 之后它变成**分钟级**，把"每步都验证"的工作方式拖死
## （2026-10-13 实测：默认自检 >10 分钟跑不完，而且输出是缓冲的、连进度都看不到）。
## → 默认自检只留秒级的快检查；这条单独跑。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/climate_scale_check.tscn
##
## 它验的是什么：**同一个物理点**，在不同**栅格分辨率**下，降水应当基本一致。
##   ① 平坦地形：只留"每格下多少 vs 每距离下多少"这一个变量（快、干净）→ **断言**
##   ② 真实地形：混叠与含水量上限都会在这里体现 → **只打印、不断言**（属已知残差）

const SEED := 20240607
const FLAT_SEED := 987654321

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _ratio(a: float, b: float) -> float:
	return maxf(a, b) / maxf(minf(a, b), 0.0000001)


func _ready() -> void:
	print("== 降水尺度不变性（独立慢测试）==")
	var d_point := Vector2(6.0, 6.0)

	# ---- ① 平坦地形 ----
	var flat := func(_cc: Vector2i) -> float:
		return 0.5
	var flat_vals: Array = []
	for g in [128, 384]:
		var t0 := Time.get_ticks_msec()
		Climate.set_field_grid(g)
		var ff := Climate.build(FLAT_SEED, flat)
		var v := Climate.precip_at_pixel(d_point, 3, ff)
		print("  平坦 栅格 %3d：月降水 %.6f（建场 %d ms）" % [g, v, Time.get_ticks_msec() - t0])
		flat_vals.append(v)
	var r_flat := _ratio(float(flat_vals[0]), float(flat_vals[1]))
	print("  → 平坦地形跨分辨率比值 = **%.3f**（这才是「每格 vs 每距离」的干净结果）" % r_flat)
	_check(r_flat < 1.05,
		"**平坦地形下尺度无关**（%.3f < 1.05）→ 每步系数已按物理距离折算" % r_flat)

	# ---- ② 真实地形（诊断）----
	Climate.set_crop(Vector2.ZERO)
	var real_vals: Array = []
	for g2 in [128, 384]:
		Climate.set_field_grid(g2)
		var f2 := WorldGen.climate_for(SEED)
		real_vals.append(Climate.precip_at_pixel(d_point, 3, f2))
	Climate.set_field_grid(Climate.FIELD_GRID)
	var r_real := _ratio(float(real_vals[0]), float(real_vals[1]))
	print("  真实地形跨分辨率：栅格 128 = %.6f ／ 384 = %.6f → 比值 **%.3f**"
		% [float(real_vals[0]), float(real_vals[1]), r_real])
	print("  （真实地形上的残差来自①**地形混叠**：粗网格跨山脊时一步的爬升远大于细网格的 3 倍；")
	print("    ②**含水量上限**：粗网格每步补水多、更早饱和。属已知，故意不断言。）")

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
