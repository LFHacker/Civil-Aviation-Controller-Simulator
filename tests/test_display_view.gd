## 场面图的视图变换（缩放/平移）无头测试。
##
## 这些逻辑纯数学，不依赖鼠标，可以脱离窗口验证。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_display_view.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 场面图视图变换测试 ════════")
	_run()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	var d := AirportDisplay.new()
	d.size = Vector2(800, 500)

	_section("初始视图")
	var fit := d._fit()
	_check(absf(float(d._zoom) - 1.0) < 0.0001, "初始缩放为 1", str(d._zoom))
	_check(d._pan == Vector2.ZERO, "初始无平移", str(d._pan))
	var s0: float = float(fit.s)
	_check(s0 > 0.5 and s0 < 1.0, "基础缩放落在合理区间", str(s0))
	# 地图中心应落在控件中心
	var mid := d._p(AirportDisplay.MAP_W * 0.5, AirportDisplay.MAP_H * 0.5, fit)
	_check(mid.distance_to(Vector2(400, 250)) < 0.5, "地图中心对齐控件中心", str(mid))

	_section("缩放")
	var pivot := Vector2(600, 300)
	var before: Vector2 = (pivot - fit.o) / fit.s
	d._zoom_at(2.0, pivot)
	var fit2 := d._fit()
	_check(absf(float(d._zoom) - 2.0) < 0.0001, "缩放到 2 倍", str(d._zoom))
	_check(absf(float(fit2.s) - s0 * 2.0) < 0.001, "缩放倍率作用到比例尺",
		"%f vs %f" % [float(fit2.s), s0 * 2.0])
	# 鼠标下的地图点应保持不动
	var after: Vector2 = (pivot - fit2.o) / fit2.s
	_check(before.distance_to(after) < 0.5, "缩放锚点保持不动（以鼠标为中心）",
		"%s -> %s" % [str(before), str(after)])

	_section("缩放上限")
	for i in range(20):
		d._zoom_at(1.5, Vector2(400, 250))
	_check(absf(float(d._zoom) - AirportDisplay.MAX_ZOOM) < 0.0001,
		"放大到上限就停住", str(d._zoom))

	_section("缩放下限")
	for i in range(40):
		d._zoom_at(0.8, Vector2(400, 250))
	_check(absf(float(d._zoom) - AirportDisplay.MIN_ZOOM) < 0.0001,
		"缩小到上限就停住", str(d._zoom))

	_section("复位")
	d._pan = Vector2(300, -200)
	d.reset_view()
	_check(absf(float(d._zoom) - 1.0) < 0.0001, "复位后缩放回到 1", str(d._zoom))
	_check(d._pan == Vector2.ZERO, "复位后平移归零", str(d._pan))

	_section("平移限位")
	d._pan = Vector2(99999, 99999)
	d._clamp_pan()
	var lim := Vector2(800, 500) * 1.2 * float(d._zoom)
	_check(float(d._pan.x) <= lim.x + 0.01, "平移被夹在横向范围内", str(d._pan))
	_check(float(d._pan.y) <= lim.y + 0.01, "平移被夹在纵向范围内", str(d._pan))

	_section("机位换算")
	_check(d._stand_index("A01") == 0, "A01 -> 0", str(d._stand_index("A01")))
	_check(d._stand_index("A24") == 23, "A24 -> 23", str(d._stand_index("A24")))
	_check(d._stand_index("") == 0, "空串回落到 0")
	_check(d._stand_index("A99") == 23, "越界编号被夹到 23", str(d._stand_index("A99")))

	d.free()


func _section(title: String) -> void:
	print("")
	print("· " + title)


func _check(cond: bool, name: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("    PASS  " + name)
	else:
		_fails += 1
		if detail == "":
			print("    FAIL  " + name)
		else:
			print("    FAIL  %s  -> %s" % [name, detail])
