## 教学引导（08 §10）、各席位通话类型清单（08 §7）、
## 以及「地面准备好了」（07 §5.1）的测试，无头可跑。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_guide.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 教学 / 通话清单 / 地面准备好了 ════════")
	_test_call_types()
	_test_teaching()
	_test_ground_ready()
	_test_visible_state()
	_test_taxi_skip()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _test_call_types() -> void:
	_section("各席位通话类型（08 §7）")
	var del := Radio.call_types("delivery")
	_check(del.size() == 5, "放行席 5 类通话", str(del.size()))
	_check(String((del[0] as Dictionary).type) == "申请放行", "第一类是申请放行")
	_check(String((del[0] as Dictionary).dir) == "pilot", "申请由机组发起")

	var ground := Radio.call_types("ground")
	_check(ground.size() == 5, "地面席 5 类", str(ground.size()))
	var types := PackedStringArray()
	for t in ground:
		types.append(String((t as Dictionary).type))
	_check(types.has("发布滑行许可"), "地面席有滑行许可", ",".join(types))
	_check(types.has("移交塔台"), "地面席有移交塔台")

	var tower := Radio.call_types("tower")
	_check(tower.size() == 3, "塔台席 3 类", str(tower.size()))
	_check(String((tower[1] as Dictionary).type) == "发布起飞许可",
		"塔台第二类是起飞许可")

	_check(Radio.call_types("approach").is_empty(), "进近席待扩展（空表）")
	_check(Radio.call_types("不存在").is_empty(), "未知席位返回空")


func _test_teaching() -> void:
	_section("教学引导（08 §10）")
	var p := Radio.teaching_hint("preset")
	_check(p.contains("候选"), "简易模式提示点候选", p)
	var f := Radio.teaching_hint("form")
	_check(f.contains("发放行许可"), "填空式提示逐项填", f)
	var t := Radio.teaching_hint("text")
	_check(t.contains("语音档未接入"), "文本模式明确标注语音未接入", t)
	_check(Radio.teaching_hint("随便").contains("发放行许可"), "未知模式退回默认")


func _desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(606)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.set_plan([{"callsign": "GRD001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	d.get_flight("GRD001").checked = true
	d.issue_clearance("GRD001", "RUMUK 8D", 6000, "1234", 0.0)
	return d


func _test_ground_ready() -> void:
	_section("地面准备好了（07 §5.1）")
	var d := _desk()
	var f := d.get_flight("GRD001")
	d.force_ok_next = true
	d.tick(f.readback_at + 0.1)
	_check(f.state == Flight.State.READBACK, "复诵到了")
	d.accept_readback("GRD001", 5.0)
	_check(f.ground_ready_at > 5.0, "排了一个 2–5 秒后的回报",
		str(f.ground_ready_at))
	_check(f.ground_ready_at <= 10.5, "延迟不超过 5 秒", str(f.ground_ready_at))

	d.tick(f.ground_ready_at - 0.5)
	_check(not f.ground_ready_said, "没到点不说")
	d.tick(f.ground_ready_at + 0.5)
	_check(f.ground_ready_said, "到点机组报地面准备好了")
	var found := false
	for e in d.recent(10):
		if String(e.text).contains("地面准备好了"):
			found = true
	_check(found, "通话记录里有这句话")

	# 只说一次
	var before := d.transcript.size()
	d.tick(f.ground_ready_at + 100.0)
	_check(d.transcript.size() == before, "不会重复说")

	# 已经移交的就不说了
	var d2 := _desk()
	var g := d2.get_flight("GRD001")
	d2.force_ok_next = true
	d2.tick(g.readback_at + 0.1)
	d2.accept_readback("GRD001", 5.0)
	d2.handoff_ground("GRD001", 6.0)
	d2.tick(g.ground_ready_at + 1.0)
	_check(not g.ground_ready_said, "移交后不再播这句")


func _test_visible_state() -> void:
	_section("九个可见状态（07 §6.1）")
	_check(Flight.VIS_STATES.size() == 9, "状态表 9 项",
		str(Flight.VIS_STATES.size()))
	var f := Flight.new()
	_check(f.visible_state() == 1, "未放行 = 1", str(f.visible_state()))
	_check(f.visible_state_text() == "未放行", "文案", f.visible_state_text())
	f.state = Flight.State.SENT
	_check(f.visible_state() == 1, "发了许可但没确认，仍算未放行")
	f.state = Flight.State.CLEARED
	_check(f.visible_state() == 2, "已放行 = 2", str(f.visible_state()))
	_check(f.visible_state_text() == "已放行", "文案", f.visible_state_text())

	# 后续席位写 ops_state 就能接管（④–⑨）
	f.ops_state = 4
	_check(f.visible_state() == 4, "地面席写入正在滑行")
	_check(f.visible_state_text() == "正在滑行", f.visible_state_text())
	f.ops_state = 8
	_check(f.visible_state_text() == "已离地", f.visible_state_text())
	f.ops_state = 99
	_check(f.visible_state() == 8, "越界被夹住", str(f.visible_state()))

	var back := Flight.from_dict(f.to_dict())
	_check(back.ops_state == 99, "ops_state 往返")


func _test_taxi_skip() -> void:
	_section("滑行路线「通报 / 不通报」（08 §5.2）")
	var d := _desk()
	var f := d.get_flight("GRD001")
	f.atis_ok = false
	# 什么都没通报时：滑行路线算漏
	var before := d.dep_info_missing(f)
	var r := d.set_dep_taxi_skip("GRD001", true)
	_check(bool(r.ok), "可以选不通报", String(r.error))
	_check(f.dep_taxi_skip, "标记上了")
	_check(d.dep_info_missing(f) == before - 1, "不通报之后不再算漏",
		"%d -> %d" % [before, d.dep_info_missing(f)])

	var rep := d.score_report()
	var has := false
	for l in rep.lines:
		if String((l as Dictionary).label).contains("滑行路线未通报"):
			has = true
	_check(has, "评分里单独记一笔")

	# 再切回来
	d.set_dep_taxi_skip("GRD001", false)
	_check(not f.dep_taxi_skip, "可以切回通报")
	_check(d.dep_info_missing(f) == before, "又算回漏报", str(d.dep_info_missing(f)))


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
