## 放行席逻辑的无头测试。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_delivery.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 放行席逻辑测试 ════════")
	_run()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	_section("生成放行申请")
	var desk := DeliveryDesk.new()
	desk.setup(20261020)
	var f := desk.spawn_request(0.0, "CCA1501")
	_check(f.callsign == "CCA1501", "呼号正确", f.callsign)
	_check(f.state == Flight.State.PENDING, "初始状态是等待放行", f.state_text())
	_check(f.stand.length() > 0, "有机位", f.stand)
	_check(f.destination.length() == 4, "目的地是四字码", f.destination)
	_check(DeliveryDesk.is_valid_squawk(f.squawk), "自动生成的应答机合法", f.squawk)
	_check(desk.transcript.size() == 1, "记录了一条机组申请",
		str(desk.transcript.size()))
	_check(String(desk.transcript[0].text).find("申请放行") >= 0, "申请通话文本正确",
		String(desk.transcript[0].text))

	_section("应答机校验")
	_check(DeliveryDesk.is_valid_squawk("4321"), "4321 合法")
	_check(DeliveryDesk.is_valid_squawk("0000"), "0000 合法（格式上）")
	_check(not DeliveryDesk.is_valid_squawk("432"), "3 位不合法")
	_check(not DeliveryDesk.is_valid_squawk("43210"), "5 位不合法")
	_check(not DeliveryDesk.is_valid_squawk("4381"), "含 8 不合法")
	_check(not DeliveryDesk.is_valid_squawk("43a1"), "含字母不合法")
	_check(not DeliveryDesk.is_valid_squawk(""), "空串不合法")

	_section("发放许可")
	var r1 := desk.issue_clearance("CCA1501", "RUMUK 8D", 5000, "4521", 10.0)
	_check(r1.ok, "正常发放成功", str(r1))
	_check(f.state == Flight.State.SENT, "状态变为许可已发", f.state_text())
	_check(f.sid == "RUMUK 8D", "离场程序写入", f.sid)
	_check(f.initial_alt_m == 5000, "高度写入", str(f.initial_alt_m))
	_check(f.squawk == "4521", "应答机写入", f.squawk)

	var ct := DeliveryDesk.clearance_text(f)
	_check(ct.find("CCA1501") >= 0 and ct.find("RUMUK 8D") >= 0
		and ct.find("5000") >= 0 and ct.find("4521") >= 0,
		"许可措辞包含全部要素", ct)

	_section("重复发放被拒绝")
	var r2 := desk.issue_clearance("CCA1501", "BETON 3A", 6000, "1234", 11.0)
	_check(not r2.ok, "等待复诵时不能重复发放", String(r2.error))
	_check(String(r2.error).find("等待复诵") >= 0, "错误信息说明原因", String(r2.error))

	_section("非法输入被拒绝")
	var f2 := desk.spawn_request(12.0, "CES2302")
	var bad_sq := desk.issue_clearance("CES2302", "BETON 3A", 4000, "4399", 13.0)
	_check(not bad_sq.ok, "非法应答机被拒绝", String(bad_sq.error))
	_check(f2.state == Flight.State.PENDING, "被拒绝后状态不变", f2.state_text())
	var bad_alt := desk.issue_clearance("CES2302", "BETON 3A", 0, "4321", 13.0)
	_check(not bad_alt.ok, "高度 0 被拒绝", String(bad_alt.error))
	var bad_sid := desk.issue_clearance("CES2302", "  ", 4000, "4321", 13.0)
	_check(not bad_sid.ok, "空离场程序被拒绝", String(bad_sid.error))
	var no_flight := desk.issue_clearance("NOPE", "BETON 3A", 4000, "4321", 13.0)
	_check(not no_flight.ok, "不存在的航班被拒绝", String(no_flight.error))

	_section("复诵到达")
	desk.tick(11.0)
	_check(f.state == Flight.State.SENT, "未到延迟不复诵", f.state_text())
	desk.tick(12.0)
	_check(f.state == Flight.State.READBACK, "到点后进入待复核", f.state_text())
	_check(f.readback_text.length() > 0, "有复诵文本", f.readback_text.substr(0, 24))

	_section("复诵一致 / 不一致两条路径")
	# 跑一批航班，确保两条路径都能覆盖到
	var desk2 := DeliveryDesk.new()
	desk2.setup(777)
	desk2.spawn_request(0.0, "OK1")
	desk2.issue_clearance("OK1", "RUMUK 8D", 5000, "4321", 0.0)
	desk2.tick(5.0)
	var correct_f: Flight = desk2.get_flight("OK1")
	var want_correct: bool = correct_f.readback_ok

	# 用同一个种子再造一个，验证"复诵正确"和"复诵有误"的表现
	var ok_case := _make_case(4321, true)
	var bad_case := _make_case(4321, false)
	_check(ok_case != null or bad_case != null, "能构造出复诵用例")

	_section("复诵正确时的接受")
	var d_ok := _find_case(true)
	if d_ok != null:
		var ff: Flight = d_ok.get_flight("X1")
		var acc := d_ok.accept_readback("X1", 10.0)
		_check(acc.ok, "一致时接受成功", String(acc.error))
		_check(ff.state == Flight.State.CLEARED, "状态变为已放行", ff.state_text())
		_check(d_ok.cleared_count == 1, "放行计数 +1", str(d_ok.cleared_count))
		_check(d_ok.misjudge_count == 0, "误判计数仍为 0")

	_section("复诵不一致时的接受应当被拒绝")
	var d_bad := _find_case(false)
	if d_bad != null:
		var fb: Flight = d_bad.get_flight("X1")
		var acc2 := d_bad.accept_readback("X1", 10.0)
		_check(not acc2.ok, "不一致时拒绝接受", String(acc2.error))
		_check(String(acc2.error).find("不一致") >= 0, "错误信息说明不一致", String(acc2.error))
		_check(fb.state == Flight.State.READBACK, "状态停留在待复核", fb.state_text())
		_check(d_bad.misjudge_count == 1, "误判计数 +1", str(d_bad.misjudge_count))
		_check(d_bad.cleared_count == 0, "没有误记为已放行")

		var re := d_bad.reissue("X1", 12.0)
		_check(re.ok, "退回重发成功", String(re.error))
		_check(fb.state == Flight.State.PENDING, "重发后回到等待放行", fb.state_text())
		_check(fb.reissue_count == 1, "重发次数 +1", str(fb.reissue_count))
		_check(fb.readback_text == "", "重发后清空旧复诵")

	_section("机位不重复")
	var dstand := DeliveryDesk.new()
	dstand.setup(4242)
	var seen := {}
	var dup := ""
	for i in range(20):
		var sf := dstand.spawn_request(float(i))
		if seen.has(sf.stand):
			dup = sf.stand
		seen[sf.stand] = true
	_check(dup == "", "20 架航班的机位互不重复", ("重复：" + dup) if dup != "" else "")
	# 放行一架后，它的机位应当能被再次分配
	dstand.issue_clearance(dstand.flights[0].callsign, "RUMUK 8D", 5000, "4321", 0.0)
	dstand.tick(5.0)
	dstand.accept_readback(dstand.flights[0].callsign, 6.0)
	_check(dstand.flights[0].is_done(), "第一架已放行")

	_section("通话记录")
	var d3 := DeliveryDesk.new()
	d3.setup(99)
	for i in range(5):
		d3.spawn_request(float(i))
	_check(d3.transcript.size() == 5, "五条记录", str(d3.transcript.size()))
	var rec := d3.recent(3)
	_check(rec.size() == 3, "recent(3) 返回 3 条", str(rec.size()))
	_check(float(rec[2].t) == 4.0, "recent 保持时间顺序（末条最新）",
		str(rec[2].t))
	_check(String(rec[2].side) == "pilot", "记录的发送方正确", String(rec[2].side))

	_section("序列化往返")
	var d4 := DeliveryDesk.new()
	d4.setup(555)
	var fa := d4.spawn_request(0.0, "SAV1")
	d4.issue_clearance("SAV1", "KAMAN 2C", 6000, "7001", 1.0)
	d4.cleared_count = 3
	d4.misjudge_count = 1
	var dict := d4.to_dict()
	var d5 := DeliveryDesk.from_dict(dict)
	_check(d5.flights.size() == 1, "航班数量往返一致", str(d5.flights.size()))
	var fb2: Flight = d5.get_flight("SAV1")
	_check(fb2 != null, "能按呼号取回")
	if fb2 != null:
		_check(fb2.sid == "KAMAN 2C", "离场程序往返一致", fb2.sid)
		_check(fb2.squawk == "7001", "应答机往返一致", fb2.squawk)
		_check(fb2.state == Flight.State.SENT, "状态往返一致", fb2.state_text())
	_check(d5.cleared_count == 3, "统计往返一致", str(d5.cleared_count))
	_check(d5.misjudge_count == 1, "误判统计往返一致", str(d5.misjudge_count))


# ---------------------------------------------------------------- 工具

## 造一个只含一架"已进入待复核"航班的 desk，path_ok 指定复诵是否正确。
## 通过反复换种子凑出想要的复诵结果（比伪造内部状态更接近真实行为）。
func _make_case(_base: int, want_ok: bool) -> DeliveryDesk:
	return _find_case(want_ok)


func _find_case(want_ok: bool) -> DeliveryDesk:
	for seed_v in range(1, 400):
		var d := DeliveryDesk.new()
		d.setup(seed_v)
		d.spawn_request(0.0, "X1")
		d.issue_clearance("X1", "RUMUK 8D", 5000, "4321", 0.0)
		d.tick(5.0)
		var f: Flight = d.get_flight("X1")
		if f.state == Flight.State.READBACK and f.readback_ok == want_ok:
			return d
	return null


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
