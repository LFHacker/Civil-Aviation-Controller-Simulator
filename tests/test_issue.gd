## 许可发布三模式 + 离场情报通报（放行机制规范 §5）测试，无头可跑。
##
## ① 预设一键：按计划 + 运行要素生成完整许可；
## ② 自由文本：关键词 + 数值解析七项要素，缺哪项说哪项；
## ③ 离场情报：机组抄了 ATIS 就可省略（QNH 除外），没抄就要逐项通报。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_issue.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 许可模式 / 离场情报测试 ════════")
	_test_preset()
	_test_free_text()
	_test_squawk_scan()
	_test_dep_info()
	_test_incomplete_query()
	_test_serialize()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _desk(atis_ok: bool = true) -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(2718)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.enable_dep_info = true
	d.set_plan([{"callsign": "ISS001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	var f := d.get_flight("ISS001")
	f.checked = true
	f.atis_ok = atis_ok
	f.squawk = "4321"
	f.clearance_limit = "ZBAA"
	f.dep_freq = "119.000"
	return d


func _test_preset() -> void:
	_section("模式 A：预设一键")
	var d := _desk()
	var p := d.preset_clearance("ISS001")
	_check(bool(p.ok), "能生成预设许可", String(p.error))
	_check(String(p.sid) == "RUMUK 8D", "离场程序来自计划", String(p.sid))
	_check(int(p.alt_m) == 6000, "高度来自计划", str(p.alt_m))
	_check(DeliveryDesk.is_valid_squawk(String(p.squawk)), "应答机有效",
		String(p.squawk))
	_check(String(p.text).contains("ISS001"), "文本里有呼号")

	var r := d.issue_preset("ISS001", 0.0)
	_check(bool(r.ok), "一键发送成功", String(r.error))
	_check(d.get_flight("ISS001").state == Flight.State.SENT, "状态为许可已发布")


func _test_free_text() -> void:
	_section("模式 C：自由文本解析")
	var d := _desk()
	var good := "ISS001，许可放行至 ZBAA，按 RUMUK 8D 离场，经 W105 LADIX，" \
		+ "初始高度 6000 米，应答机 4321，修正海压 1013。"
	var r := d.issue_free_text("ISS001", good, 0.0)
	_check(bool(r.ok), "完整通话说得对就能发", String(r.error))

	# 缺呼号
	var d2 := _desk()
	var r2 := d2.issue_free_text("ISS001",
		"许可放行至 ZBAA，按 RUMUK 8D 离场，初始高度 6000 米，应答机 4321，修正海压 1013。",
		0.0)
	_check(not bool(r2.ok), "缺呼号被拒", String(r2.error))
	_check(String(r2.error).contains("呼号"), "明确指出缺呼号", String(r2.error))

	# 缺放行界限
	var d3 := _desk()
	var r3 := d3.issue_free_text("ISS001",
		"ISS001，按 RUMUK 8D 离场，初始高度 6000 米，应答机 4321，修正海压 1013。", 0.0)
	_check(not bool(r3.ok), "缺放行界限被拒", String(r3.error))
	_check(String(r3.error).contains("放行界限"), "指出缺放行界限", String(r3.error))

	# 缺离场程序
	var d4 := _desk()
	var r4 := d4.issue_free_text("ISS001",
		"ISS001，许可放行至 ZBAA，初始高度 6000 米，应答机 4321，修正海压 1013。", 0.0)
	_check(not bool(r4.ok), "缺离场程序被拒", String(r4.error))
	_check(String(r4.error).contains("离场程序"), "指出缺离场程序", String(r4.error))

	# 缺修正海压（QNH 是刚性项）
	var d5 := _desk()
	var r5 := d5.issue_free_text("ISS001",
		"ISS001，许可放行至 ZBAA，按 RUMUK 8D 离场，初始高度 6000 米，应答机 4321。", 0.0)
	_check(not bool(r5.ok), "缺 QNH 被拒", String(r5.error))
	_check(String(r5.error).contains("修正海压"), "指出缺修正海压", String(r5.error))

	# 空通话
	var d6 := _desk()
	_check(not bool(d6.issue_free_text("ISS001", "   ", 0.0).ok), "空内容被拒")


func _test_squawk_scan() -> void:
	_section("应答机扫描")
	_check(DeliveryDesk.find_squawk_in_text("应答机 4321。", 6000) == "4321",
		"识别 4321")
	_check(DeliveryDesk.find_squawk_in_text("初始高度 6000 米，应答机 1234。",
		6000) == "1234", "不会把高度当编码")
	_check(DeliveryDesk.find_squawk_in_text("应答机 7890", 6000) == "",
		"含 8/9 的不算八进制")
	_check(DeliveryDesk.find_squawk_in_text("没有任何数字", 6000) == "",
		"没有数字返回空")


func _test_dep_info() -> void:
	_section("离场情报通报（§5.2）")
	var d := _desk(false)   # 机组没抄 ATIS
	var f := d.get_flight("ISS001")
	var items := d.departure_info_items(f)
	_check(items.size() == 7, "七项离场情报", str(items.size()))
	var qnh_item := _item(items, "qnh")
	_check(bool(qnh_item.required), "QNH 是刚性项")
	_check(not bool(qnh_item.covered), "QNH 不因 ATIS 省略")
	_check(not bool(_item(items, "wind").covered), "没抄 ATIS 时风速不算覆盖")
	_check(d.dep_info_missing(f) == 6, "六项待通报（QNH 单列）",
		str(d.dep_info_missing(f)))

	d.toggle_dep_info("ISS001", "wind")
	_check(bool(_item(d.departure_info_items(f), "wind").notified),
		"通报后可勾上")
	_check(d.dep_info_missing(f) == 5, "待通报减少一项",
		str(d.dep_info_missing(f)))

	d.notify_all_dep_info("ISS001")
	_check(d.dep_info_missing(f) == 0, "一键全通报后为零",
		str(d.dep_info_missing(f)))

	# 抄了 ATIS 的航班：可省略项自动算已覆盖
	var d2 := _desk(true)
	var f2 := d2.get_flight("ISS001")
	_check(d2.dep_info_missing(f2) == 0, "抄了 ATIS 就不用逐项通报",
		str(d2.dep_info_missing(f2)))
	_check(bool(_item(d2.departure_info_items(f2), "vis").covered),
		"能见度被 ATIS 覆盖")

	# 发放行许可时把漏报数记到航班上
	var d3 := _desk(false)
	d3.issue_clearance("ISS001", "RUMUK 8D", 6000, "4321", 0.0)
	_check(d3.get_flight("ISS001").dep_info_skipped == 6,
		"漏报数记在航班上", str(d3.get_flight("ISS001").dep_info_skipped))
	var rep := d3.score_report()
	var has_line := false
	for l in rep.lines:
		if String((l as Dictionary).label).contains("离场情报"):
			has_line = true
	_check(has_line, "评分明细里写出离场情报漏报")


func _item(list: Array, key: String) -> Dictionary:
	for it in list:
		if String((it as Dictionary).key) == key:
			return it
	return {}


func _test_incomplete_query() -> void:
	_section("许可不完整 → 机组质疑（07 §4.4）")
	# 进阶模式：缺离场程序交给机组质疑，而不是管制端直接拒
	var d := _desk()
	d.pilot_check_enabled = true
	d.difficulty = "normal"
	var f := d.get_flight("ISS001")
	var r := d.issue_free_text("ISS001",
		"ISS001，许可放行至 ZBAA，初始高度 6000 米，应答机 4321，修正海压 1013。", 0.0)
	_check(bool(r.get("queried", false)), "机组质疑而不是直接拒", String(r.error))
	_check(String(r.error).contains("许可不完整"), "质疑内容是「许可不完整」",
		String(r.error))
	_check(String(r.error).contains("离场程序"), "点名缺离场程序", String(r.error))
	_check(f.state == Flight.State.PENDING, "状态没有推进", str(f.state))
	_check(f.pilot_queries == 1, "质疑计数 +1", str(f.pilot_queries))

	# 简易模式：不质疑，直接由管制端提示缺项
	var e := _desk()
	e.pilot_check_enabled = true
	e.difficulty = "easy"
	var r2 := e.issue_free_text("ISS001",
		"ISS001，许可放行至 ZBAA，初始高度 6000 米，应答机 4321，修正海压 1013。", 0.0)
	_check(not bool(r2.get("queried", false)), "简易模式不质疑")
	_check(not bool(r2.ok), "简易模式直接提示缺项", String(r2.error))

	# 缺修正海压永远是硬错误，不交给机组
	var d3 := _desk()
	d3.pilot_check_enabled = true
	var r3 := d3.issue_free_text("ISS001",
		"ISS001，许可放行至 ZBAA，按 RUMUK 8D 离场，初始高度 6000 米，应答机 4321。", 0.0)
	_check(not bool(r3.ok), "缺 QNH 直接拒绝", String(r3.error))
	_check(String(r3.error).contains("修正海压"), "提示缺修正海压", String(r3.error))


func _test_serialize() -> void:
	_section("存档往返")
	var d := _desk(false)
	var f := d.get_flight("ISS001")
	d.toggle_dep_info("ISS001", "wind")
	f.dep_info_skipped = 3
	var back := Flight.from_dict(f.to_dict())
	_check(back.dep_info_notified.has("wind"), "通报记录往返")
	_check(back.dep_info_skipped == 3, "漏报计数往返")


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
