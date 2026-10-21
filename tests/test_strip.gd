## 飞行进程单与移交的测试。
##
## 依据《民用航空空中交通管理规则》：
##   第一百三十三条 —— 塔台必须使用飞行进程单，动态、许可、指令都要记入
##   第一百三十四条 —— 按 MH4011 标准填写
##   第二百条（八）  —— 滑行至等待点后转频联系机场管制席（即移交）
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_strip.gd
extends SceneTree

var _checks := 0
var _fails := 0

const AIRPORT := {
	"id": "DEMO",
	"icao": "ZDEM",
	"clock_start": "0755",
	"atis_alpha": "A",
	"runways": [{"id": "18", "heading_deg": 180}],
	"frequencies": {"delivery": "121.950", "ground": "121.750", "approach": "119.000"},
	"weather": {"wind": "18005MPS", "visibility": "CAVOK",
		"qnh_hpa": 1013, "temperature_c": 18},
}


func _initialize() -> void:
	print("")
	print("════════ 飞行进程单与移交测试 ════════")
	_test_check_plan()
	_test_timestamps()
	_test_handoff()
	_test_serialization()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _new_desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(777)
	d.apply_field(AIRPORT)
	return d


func _test_check_plan() -> void:
	_section("核对飞行计划")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CCA1501")
	_check(not f.checked, "新航班默认未核对计划")
	_check(f.t_check < 0.0, "未核对时没有时间戳")

	d.enable_strip_check = true
	var r := d.issue_clearance("CCA1501", "RUMUK 8D", 6000, "4521", 1.0)
	_check(not r.ok, "未核对计划不能发放行许可", String(r.error))
	_check(String(r.error).find("核对") >= 0, "错误信息提示去核对", String(r.error))
	_check(f.state == Flight.State.PENDING, "被拒后状态不变")

	var c := d.check_plan("CCA1501", 2.0)
	_check(c.ok, "核对计划成功", String(c.error))
	_check(f.checked, "进程单标记为已核对")
	_check(absf(f.t_check - 2.0) < 0.001, "核对时间戳写入", str(f.t_check))
	_check(not d.check_plan("CCA1501", 3.0).ok, "重复核对被拒绝")
	_check(not d.check_plan("NOPE", 3.0).ok, "不存在的航班返回失败")

	var r2 := d.issue_clearance("CCA1501", "RUMUK 8D", 6000, "4521", 4.0)
	_check(r2.ok, "核对后可以发许可", String(r2.error))

	# 关掉检查时行为不变（老用例与单元测试走这条路）
	var d2 := _new_desk()
	d2.spawn_request(0.0, "CES2302")
	_check(d2.issue_clearance("CES2302", "BETON 3A", 5000, "1234", 1.0).ok,
		"未开启检查时不核对也能发许可")

	# 已经进入流程的航班不能再"核对"
	var d3 := _new_desk()
	var f3 := d3.spawn_request(0.0, "CSN7788")
	d3.issue_clearance("CSN7788", "SASAN 5B", 4000, "4321", 1.0)
	_check(not d3.check_plan("CSN7788", 2.0).ok, "已发许可后不能再核对计划")
	_check(not f3.checked, "状态未被改成已核对")


func _test_timestamps() -> void:
	_section("进程单时间戳")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CHH1120")
	d.check_plan("CHH1120", 5.0)
	d.issue_clearance("CHH1120", "KAMAN 2C", 5000, "4321", 10.0)
	_check(absf(f.t_sent - 10.0) < 0.001, "发许可时间戳", str(f.t_sent))

	d.tick(11.0)
	_check(f.t_readback < 0.0, "复诵未到时不写时间戳")
	d.tick(12.0)
	_check(absf(f.t_readback - 12.0) < 0.001, "复诵到达时间戳", str(f.t_readback))

	var acc := d.accept_readback("CHH1120", 15.0)
	_check(acc.ok, "复诵正确可以放行", String(acc.error))
	_check(absf(f.t_cleared - 15.0) < 0.001, "放行完成时间戳", str(f.t_cleared))

	# 退回重发要把发许可/复诵时间戳清掉，重新计时
	var d2 := _new_desk()
	var g := d2.spawn_request(0.0, "CQH8890")
	d2.issue_clearance("CQH8890", "RUMUK 8D", 5000, "4321", 1.0)
	d2.tick(10.0)
	d2.reissue("CQH8890", 11.0)
	_check(g.t_sent < 0.0 and g.t_readback < 0.0, "重发后清空旧时间戳",
		"%s / %s" % [str(g.t_sent), str(g.t_readback)])
	_check(g.t_check < 0.0 or g.checked, "重发不撤销计划核对状态")


func _test_handoff() -> void:
	_section("移交地面")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CCA1501")
	_check(not d.handoff_ground("CCA1501", 1.0).ok, "未放行不能移交")
	d.issue_clearance("CCA1501", "RUMUK 8D", 6000, "4521", 2.0)
	_check(not d.handoff_ground("CCA1501", 3.0).ok, "等待复诵时不能移交")

	d.tick(4.0)
	d.accept_readback("CCA1501", 5.0)
	var before := d.transcript.size()
	var r := d.handoff_ground("CCA1501", 6.0)
	_check(r.ok, "放行完成后可以移交", String(r.error))
	_check(f.handed_off, "进程单标记已移交")
	_check(absf(f.t_handoff - 6.0) < 0.001, "移交时间戳", str(f.t_handoff))
	_check(d.transcript.size() == before + 2, "移交产生一问一答",
		"%d -> %d" % [before, d.transcript.size()])
	_check(not d.handoff_ground("CCA1501", 7.0).ok, "重复移交被拒绝")
	_check(not d.handoff_ground("NOPE", 7.0).ok, "不存在的航班返回失败")
	_check(d.handed_off_count() == 1, "移交计数正确", str(d.handed_off_count()))

	# 移交后仍然算"已处理完"，不再出现在待放行列表
	var still_pending := false
	for x in d.pending():
		if (x as Flight).callsign == "CCA1501":
			still_pending = true
	_check(not still_pending, "移交后不出现在待放行列表")


func _test_serialization() -> void:
	_section("进程单随存档往返")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CES2302")
	d.check_plan("CES2302", 1.0)
	d.issue_clearance("CES2302", "BETON 3A", 5000, "1234", 2.0)
	d.tick(4.0)
	d.accept_readback("CES2302", 5.0)
	d.handoff_ground("CES2302", 6.0)

	var back := DeliveryDesk.from_dict(d.to_dict())
	var g: Flight = back.flights[0]
	_check(g.checked, "核对状态往返一致")
	_check(g.handed_off, "移交状态往返一致")
	_check(absf(g.t_check - 1.0) < 0.001, "核对时间戳往返一致", str(g.t_check))
	_check(absf(g.t_sent - 2.0) < 0.001, "发许可时间戳往返一致", str(g.t_sent))
	_check(absf(g.t_cleared - 5.0) < 0.001, "放行时间戳往返一致", str(g.t_cleared))
	_check(absf(g.t_handoff - 6.0) < 0.001, "移交时间戳往返一致", str(g.t_handoff))


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
