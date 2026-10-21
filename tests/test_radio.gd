## 陆空对话机制（08 文档）测试，无头可跑。
##
## ① 标准读法（洞幺两三四五六拐八勾）；
## ② 通话骨架与槽位校验（进阶模式的基础）；
## ③ 简易模式候选通话：按状态过滤、含错误候选可开关、点了要真的生效。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_radio.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 陆空对话测试 ════════")
	_test_readout()
	_test_slots()
	_test_candidates()
	_test_mistake_candidate()
	_test_send()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _test_readout() -> void:
	_section("标准读法（MH/T 4014）")
	_check(Radio.read_digits("1200") == "幺两洞洞", "1200 → 幺两洞洞",
		Radio.read_digits("1200"))
	_check(Radio.read_digits("7309") == "拐三洞勾", "7/9 读拐/勾",
		Radio.read_digits("7309"))
	_check(Radio.read_number(5000, " 米") == "五洞洞洞 米",
		"5000 米", Radio.read_number(5000, " 米"))
	_check(Radio.read_freq("121.950") == "幺两幺点勾五洞", "频率读法",
		Radio.read_freq("121.950"))
	_check(Radio.read_callsign("CCA1501") == "CCA幺五洞幺", "呼号读法",
		Radio.read_callsign("CCA1501"))
	_check(Radio.read_digits("ABC") == "ABC", "非数字原样返回")


func _test_slots() -> void:
	_section("通话骨架与槽位")
	var slots := Radio.clearance_slots()
	var has_sid := false
	for it in slots:
		if String((it as Dictionary).get("slot", "")) == "sid":
			has_sid = true
	_check(has_sid, "许可骨架里有离场程序槽位")

	var filled := {"atc": "白云放行", "callsign": "CCA1501", "limit": "ZBAA",
		"sid": "RUMUK 8D", "route": "W105 LADIX", "alt": "6000",
		"squawk": "1234", "qnh": "1013"}
	_check(Radio.missing_slots(slots, filled).is_empty(), "填满后不缺槽位")
	var text := Radio.assemble(slots, filled)
	_check(text.contains("白云放行") and text.contains("RUMUK 8D"),
		"拼出来含关键要素", text)

	var partial := {"atc": "白云放行"}
	var miss := Radio.missing_slots(slots, partial)
	_check(miss.size() > 0, "缺槽位能被数出来", str(miss.size()))
	var chk := Radio.check_slots(slots, partial)
	_check(not bool(chk.ok), "缺槽位不允许发送")
	_check(String(chk.error).contains("没填"), "提示说还差几项", String(chk.error))
	var shown := Radio.assemble(slots, partial)
	_check(shown.contains("[己方呼号]"), "空槽位显示成占位符", shown)


func _desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(1234)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.set_plan([{"callsign": "RAD001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	d.get_flight("RAD001").checked = true
	return d


func _test_candidates() -> void:
	_section("简易模式候选（08 §2.3）")
	var d := _desk()
	var list := d.radio_candidates("RAD001")
	_check(list.size() >= 2 and list.size() <= 4, "2–4 条候选", str(list.size()))
	var kinds := {}
	for c in list:
		kinds[String((c as Dictionary).kind)] = true
	_check(kinds.has("clearance"), "有待申请时的完整许可")
	_check(kinds.has("wait"), "有「请稍等」")
	_check(kinds.has("repeat"), "有「重复一遍」")
	var clr := _find(list, "clr")
	_check(String(clr.text).contains("RAD001"), "许可里带呼号")
	_check(String(clr.text).contains("1013"), "许可里带修正海压")
	_check(bool(clr.correct), "默认都是正确候选")

	# 复诵到达后的候选不一样
	var f := d.get_flight("RAD001")
	d.issue_clearance("RAD001", "RUMUK 8D", 6000, "1234", 0.0)
	d.force_ok_next = true
	d.tick(f.readback_at + 0.1)
	var list2 := d.radio_candidates("RAD001")
	var k2 := {}
	for c in list2:
		k2[String((c as Dictionary).kind)] = true
	_check(k2.has("accept"), "复诵阶段有「复诵正确」")
	_check(k2.has("reissue"), "复诵阶段有「重发」")
	_check(not k2.has("clearance"), "复诵阶段不再给许可候选")

	# 放行完成的候选是移交
	d.accept_readback("RAD001", 5.0)
	var list3 := d.radio_candidates("RAD001")
	_check(String((list3[0] as Dictionary).kind) == "handoff",
		"完成放行后给移交指令", String((list3[0] as Dictionary).kind))
	_check(String((list3[0] as Dictionary).text).contains("121.750"),
		"移交里带地面频率")


func _test_mistake_candidate() -> void:
	_section("含错误候选（08 §2.4）")
	var d := _desk()
	var before := d.radio_candidates("RAD001").size()
	d.candidate_error = true
	var list := d.radio_candidates("RAD001")
	_check(list.size() == before + 1, "多出一条错误候选", str(list.size()))
	var bad := _find(list, "clr_bad")
	_check(not bool(bad.correct), "错误候选被标成不正确")
	_check(String(bad.text).contains("1018"), "错误候选的 QNH 被改过",
		String(bad.text))
	_check(not String(bad.text).contains("1013"), "正确值不在了")


func _test_send() -> void:
	_section("候选点了要真的生效")
	var d := _desk()
	var r := d.send_candidate("RAD001", "wait", 1.0)
	_check(bool(r.ok), "请稍等可以发", String(r.error))
	_check(d.get_flight("RAD001").state == Flight.State.PENDING,
		"请稍等不改状态")

	var r2 := d.send_candidate("RAD001", "clr", 2.0)
	_check(bool(r2.ok), "许可候选能发出去", String(r2.error))
	_check(d.get_flight("RAD001").state == Flight.State.SENT, "状态推进")

	var r3 := d.send_candidate("RAD001", "clr", 3.0)
	_check(not bool(r3.ok), "重复发同一条会被拒", String(r3.error))

	var f := d.get_flight("RAD001")
	d.force_ok_next = true
	d.tick(f.readback_at + 0.1)
	var r4 := d.send_candidate("RAD001", "rb_ok", 10.0)
	_check(bool(r4.ok), "复诵正确能确认", String(r4.error))
	_check(d.get_flight("RAD001").state == Flight.State.CLEARED, "状态到已放行")

	var r5 := d.send_candidate("RAD001", "handoff", 20.0)
	_check(bool(r5.ok), "移交能发", String(r5.error))
	_check(d.get_flight("RAD001").handed_off, "移交生效")

	var r6 := d.send_candidate("RAD001", "不存在的候选", 21.0)
	_check(not bool(r6.ok), "不存在的候选被拒")


func _find(list: Array, id: String) -> Dictionary:
	for c in list:
		if String((c as Dictionary).id) == id:
			return c
	return {}


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
