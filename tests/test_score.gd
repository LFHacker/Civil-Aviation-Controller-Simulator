## 移交检查清单 / 整理进程单 / 运行品质评分（放行机制规范 §7、§4、§11）测试。
##
## 重点：
## ① 五项检查任何一项不满足就不许移交（高阶还要逐项确认）；
## ② 整理进程单有 2 秒冷却、且不改任何航班数据；
## ③ 评分只算账、不判负 —— 行为要能一条条对上。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_score.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 移交 / 整理 / 评分 测试 ════════")
	_test_checklist()
	_test_handoff_easy()
	_test_handoff_hard()
	_test_tidy()
	_test_score()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(31415)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.enable_handoff_check = true
	d.enable_qnh_gate = true
	d.set_plan([{"callsign": "HOF001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	return d


## 推到"复诵已确认"（放行完成）
func _cleared() -> DeliveryDesk:
	var d := _desk()
	var f := d.get_flight("HOF001")
	f.checked = true
	d.confirm_qnh("HOF001")
	d.issue_clearance("HOF001", "RUMUK 8D", 6000, "1234", 0.0)
	d.force_ok_next = true
	d.tick(f.readback_at + 0.1)
	d.accept_readback("HOF001", 5.0)
	return d


func _item(list: Array, key: String) -> Dictionary:
	for it in list:
		if String((it as Dictionary).key) == key:
			return it
	return {}


func _test_checklist() -> void:
	_section("五项检查（§7.1）")
	var d := _desk()
	var f := d.get_flight("HOF001")
	var chk := d.handoff_checklist(f)
	_check(chk.size() == 5, "共 5 项", str(chk.size()))
	_check(not bool(_item(chk, "plan").ok), "计划没审查 → 不满足")
	_check(not bool(_item(chk, "qnh").ok), "QNH 没确认 → 不满足")
	_check(not bool(_item(chk, "readback").ok), "没复诵确认 → 不满足")

	f.checked = true
	d.confirm_qnh("HOF001")
	_check(bool(_item(d.handoff_checklist(f), "plan").ok), "审查后该项满足")
	_check(bool(_item(d.handoff_checklist(f), "qnh").ok), "确认后 QNH 满足")

	var d2 := _cleared()
	var chk2 := d2.handoff_checklist(d2.get_flight("HOF001"))
	var all_ok := true
	for it in chk2:
		if not bool((it as Dictionary).ok):
			all_ok = false
	_check(all_ok, "走完全流程后五项全满足")


func _test_handoff_easy() -> void:
	_section("简易移交")
	var d := _desk()
	var bad := d.handoff_ground("HOF001", 10.0)
	_check(not bool(bad.ok), "条件不满足不能移交", String(bad.error))
	_check(String(bad.error).contains("放行"), "提示说明还没放行",
		String(bad.error))

	# 已经放行了，但通播过期没处置 → 清单里的"通播状态已核对"不满足
	var d2 := _cleared()
	d2.enable_atis_lifecycle = true
	d2.atis_expired = true
	var r := d2.handoff_ground("HOF001", 20.0)
	_check(not bool(r.ok), "通播没处置不能移交", String(r.error))
	_check(String(r.error).contains("通播"), "点名缺的是通播状态",
		String(r.error))
	d2.atis_expired = false
	_check(d2.handoff_ready(d2.get_flight("HOF001")), "ready 判断为真")
	var ok := d2.handoff_ground("HOF001", 20.0)
	_check(bool(ok.ok), "可以移交", String(ok.error))
	var f := d2.get_flight("HOF001")
	_check(f.handed_off, "标记已移交")
	_check(not f.handoff_late, "没超时就不打标记")
	_check(f.flow_state() == 7, "状态到「已移交地面」", str(f.flow_state()))
	# 通话记录里有联系地面
	var found := false
	for e in d2.recent(10):
		if String(e.text).contains("联系地面"):
			found = true
	_check(found, "通话记录里出现「联系地面」")


func _test_handoff_hard() -> void:
	_section("高阶：逐项确认 + 90 秒时限")
	var d := _cleared()
	d.handoff_hard = true
	var f := d.get_flight("HOF001")
	_check(not d.handoff_ready(f), "没逐项确认前不能移交")
	var r := d.handoff_ground("HOF001", 20.0)
	_check(not bool(r.ok), "直接点移交被拒", String(r.error))
	_check(String(r.error).contains("逐项确认"), "提示要求逐项确认",
		String(r.error))

	for it in d.handoff_checklist(f):
		var key := String((it as Dictionary).key)
		var c := d.confirm_handoff_item("HOF001", key)
		_check(bool(c.ok), "确认「%s」" % key, String(c.error))
	_check(d.handoff_ready(f), "都确认后可以移交")

	# 90 秒时限：复诵确认在 5 秒，130 秒之后才移交 → 超时
	var ok := d.handoff_ground("HOF001", 130.0)
	_check(bool(ok.ok), "超时也允许移交（不阻断）", String(ok.error))
	_check(f.handoff_late, "打上移交超时标记")

	# 条件不满足的项不能确认
	var d2 := _desk()
	d2.handoff_hard = true
	var r2 := d2.confirm_handoff_item("HOF001", "readback")
	_check(not bool(r2.ok), "不满足的项不能勾", String(r2.error))

	# 简易模式不需要逐项确认
	var d3 := _cleared()
	var r3 := d3.confirm_handoff_item("HOF001", "plan")
	_check(not bool(r3.ok), "简易模式不做逐项确认", String(r3.error))


func _test_tidy() -> void:
	_section("整理进程单（§4）")
	var d := _desk()
	d.set_plan([{"callsign": "TID002", "type": "A320", "dest": "ZSPD",
		"stand": "A06", "sid": "BETON 3A", "alt": 5000}])
	d.spawn_request(0.0)
	var a := d.get_flight("HOF001")
	var b := d.get_flight("TID002")
	# 手动打乱顺序
	d.move_flight("TID002", 0)
	_check(b.order_rank == 0, "先被拖到最前", str(b.order_rank))

	var r := d.tidy_strips(10.0)
	_check(bool(r.ok), "整理成功", String(r.error))
	_check(a.order_rank == -1 and b.order_rank == -1, "整改后按计划时刻排")

	# 2 秒冷却
	var r2 := d.tidy_strips(11.0)
	_check(not bool(r2.ok), "冷却期内不能再整理", String(r2.error))
	var r3 := d.tidy_strips(12.5)
	_check(bool(r3.ok), "过了冷却可以再整理", String(r3.error))

	# 整理不改变任何航班状态
	_check(d.get_flight("HOF001").state == Flight.State.PENDING,
		"整理不改状态")


func _test_score() -> void:
	_section("运行品质评分（§11）")
	var d := _desk()
	var rep0 := d.score_report()
	_check(int(rep0.total) == 0, "什么都没做时 0 分", str(rep0.total))
	_check(String(rep0.grade) == "C", "0 分是 C", String(rep0.grade))

	# 一次干净的放行 + 移交
	var d2 := _cleared()
	d2.handoff_hard = true
	for it in d2.handoff_checklist(d2.get_flight("HOF001")):
		d2.confirm_handoff_item("HOF001", String((it as Dictionary).key))
	d2.handoff_ground("HOF001", 30.0)
	var rep := d2.score_report()
	_check(int(rep.total) >= 3, "干净放行有正分", str(rep.total))
	var labels := PackedStringArray()
	for l in rep.lines:
		labels.append("%s(%+d)" % [String((l as Dictionary).label),
			int((l as Dictionary).delta)])
	_check(labels.size() >= 2, "评分有明细", ",".join(labels))

	# 误判扣分
	var d3 := _cleared()
	d3.get_flight("HOF001").missed_readback = 2
	var rep3 := d3.score_report()
	_check(int(rep3.total) <= 2 - 6 + 1, "复诵漏检扣 6 分", str(rep3.total))
	var has_missed := false
	for l in rep3.lines:
		if String((l as Dictionary).label).contains("复诵漏检"):
			has_missed = true
	_check(has_missed, "明细里写出复诵漏检")

	# 通播有误扣分
	var d4 := _desk()
	d4.enable_atis_lifecycle = true
	d4.update_atis({"qnh": 1018}, 0.0)
	_check(d4.atis_err_count == 1, "记一次通播有误", str(d4.atis_err_count))
	var rep4 := d4.score_report()
	_check(int(rep4.total) == -3, "扣 3 分", str(rep4.total))

	# 超时计入
	var d5 := _desk()
	d5.readback_timeouts = 1
	var rep5 := d5.score_report()
	_check(int(rep5.total) == -2, "复诵超时扣 2 分", str(rep5.total))

	# 存档往返
	var f := _cleared().get_flight("HOF001")
	f.handoff_late = true
	f.handoff_confirmed["plan"] = true
	var back := Flight.from_dict(f.to_dict())
	_check(back.handoff_late, "超时标记往返")
	_check(back.handoff_confirmed.has("plan"), "逐项确认往返")


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
