## 通播编辑与特情（放行机制规范 §3.2 / §3.4），以及两处小项（07 §4.7、07 §5.1）。
##
## 重点：**玩家选错通播要素 → 放行出去的许可带着错 → 机组出特情**，
## 这条链断了，"通播可编辑"就只是个摆设。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_emergency.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 通播编辑 / 特情测试 ════════")
	_test_options()
	_test_edit_form()
	_test_emergency()
	_test_readback_timeout()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _airport() -> Dictionary:
	return {
		"icao": "ZDEM", "clock_start": "0800",
		"runways": [{"id": "18", "heading_deg": 180, "length_m": 3200},
			{"id": "36", "heading_deg": 360, "length_m": 3200}],
		"frequencies": {"delivery": "121.950", "ground": "121.750",
			"tower": "118.100", "approach": "119.000", "center": "125.600",
			"apron": "121.800"},
		"weather": {"wind": "18005MPS", "visibility": "CAVOK",
			"qnh_hpa": 1013, "temperature_c": 18},
		"atis": "INFO A", "atis_alpha": "A",
	}


func _desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(5150)
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.apply_field(_airport())
	d.enable_atis_lifecycle = true
	d.set_plan([{"callsign": "EMG001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	d.get_flight("EMG001").checked = true
	return d


func _test_options() -> void:
	_section("通播编辑的可选值（§3.2）")
	var d := _desk()
	var o := d.atis_edit_options()
	_check(String(o.alpha) == "B", "下一个代号是 B", String(o.alpha))
	_check((o.qnh as Array).size() >= 2, "QNH 给多个可选值")
	_check((o.qnh as Array).has(1013), "可选值里包含当前实况")
	_check((o.wind as Array).size() == 3, "风给三档")
	_check((o.runway as Array).size() == 2, "跑道给两条")
	_check((o.runway as Array).has("36"), "另一条跑道是 36",
		str(o.runway))
	_check((o.hazards as Array).has("风切变"), "重要天气可选风切变")


func _test_edit_form() -> void:
	_section("按表单发布（可选错值）")
	var d := _desk()
	var o := d.atis_edit_options()

	# 选对：与实况一致 → 不算有误
	var r := d.update_atis({
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK",
		"qnh": 1013, "transition_level": "3600"}, 0.0)
	_check(bool(r.ok), "发布成功", String(r.error))
	_check(not d.atis.has_error, "与实况一致不算有误")
	_check(d.atis.transition_level == "3600", "过渡高度层写进去了")

	# 选错：QNH 挑成 +5 → 记 has_error
	var d2 := _desk()
	var o2 := d2.atis_edit_options()
	var r2 := d2.update_atis({"qnh": (o2.qnh as Array)[3]}, 0.0)
	_check(bool(r2.ok), "选错值也能发布（这就是来源）", String(r2.error))
	_check(d2.atis.has_error, "被标记为与实况不符")
	_check(d2.atis_err_count == 1, "记一次通播有误", str(d2.atis_err_count))

	# 跑道选错也能发布
	var d3 := _desk()
	d3.update_atis({"runway": "36"}, 0.0)
	_check(d3.atis.has_error, "跑道选错同样算有误")
	_check(d3.atis.runway == "36", "写进去的是 36")


func _test_emergency() -> void:
	_section("通播有误 → 特情（§3.4）")
	var d := _desk()
	# 先把通播的 QNH 写错，再放行
	var o := d.atis_edit_options()
	d.update_atis({"qnh": (o.qnh as Array)[3]}, 0.0)
	var f := d.get_flight("EMG001")
	var r := d.issue_clearance("EMG001", "RUMUK 8D", 6000, "1234", 1.0)
	_check(bool(r.ok), "许可发出去了", String(r.error))
	_check(f.atis_suspect, "标记为引用了有误的通播")
	_check(f.emergency == "", "还没到暴露的时候")

	# 到点前不触发
	d.tick(10.0)
	_check(f.emergency == "", "10 秒还不够")
	# 到点后触发特情
	d.tick(60.0)
	_check(f.emergency != "", "45 秒后暴露特情", f.emergency)
	_check(String(f.emergency).contains("高度"), "QNH 错导致高度类特情",
		f.emergency)
	_check(d.emergency_count == 1, "特情计数 +1", str(d.emergency_count))
	var found := false
	for e in d.recent(10):
		if String(e.text).contains("特情"):
			found = true
	_check(found, "通话记录里出现特情提示")

	var rep := d.score_report()
	var has_line := false
	for l in rep.lines:
		if String((l as Dictionary).label).contains("特情"):
			has_line = true
	_check(has_line, "评分明细里写出特情")
	_check(int(rep.total) <= -5, "特情大幅扣分", str(rep.total))

	# 通播正确时不出特情
	var d2 := _desk()
	var f2 := d2.get_flight("EMG001")
	d2.issue_clearance("EMG001", "RUMUK 8D", 6000, "1234", 1.0)
	d2.tick(200.0)
	_check(f2.emergency == "", "通播正确时不出特情", f2.emergency)


func _test_readback_timeout() -> void:
	_section("复诵迟迟不判（07 §4.7）")
	var d := _desk()
	var f := d.get_flight("EMG001")
	d.issue_clearance("EMG001", "RUMUK 8D", 6000, "1234", 0.0)
	d.force_ok_next = true
	d.tick(f.readback_at + 0.1)
	_check(f.state == Flight.State.READBACK, "复诵到了")
	_check(not f.pilot_waiting, "刚到这里还没转等待")
	d.tick(f.t_readback + 179.0)
	_check(not f.pilot_waiting, "180 秒内不催")
	d.tick(f.t_readback + 181.0)
	_check(f.pilot_waiting, "超过 180 秒转机组等待中")


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
