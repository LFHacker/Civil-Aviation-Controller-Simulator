## 放行顺序与延误通知的测试。
##
## 依据《民用航空空中交通管理规则》：
##   第二百九十二条 —— 放行顺序：按原计划起飞时间次序；考虑优先权/机型/尾流/流量
##   第二百九十三条 —— 可预计延误超过 30 分钟时，应当尽可能通知航空器驾驶员
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_order.gd
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
	print("════════ 放行顺序与延误通知测试 ════════")
	_test_plan_minutes()
	_test_ordering()
	_test_delay()
	_test_notices()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _new_desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(31337)
	d.apply_field(AIRPORT)
	return d


func _test_plan_minutes() -> void:
	_section("计划时刻解析")

	var f := Flight.new()
	f.planned_std = "0800"
	_check(DeliveryDesk.plan_minutes(f) == 480, "0800 → 480 分钟",
		str(DeliveryDesk.plan_minutes(f)))
	f.planned_std = "0015"
	_check(DeliveryDesk.plan_minutes(f) == 15, "0015 → 15 分钟")
	f.planned_std = ""
	_check(DeliveryDesk.plan_minutes(f) == -1, "空串返回 -1")
	f.planned_std = "8O0O"
	_check(DeliveryDesk.plan_minutes(f) == -1, "含字母返回 -1")

	_check(DeliveryDesk.wake_class("B789") == "H", "B789 是重型")
	_check(DeliveryDesk.wake_class("B738") == "M", "B738 是中型")
	_check(DeliveryDesk.wake_class("A321") == "M", "A321 是中型")
	_check(DeliveryDesk.wake_class("A332") == "H", "A332 是重型")


func _test_ordering() -> void:
	_section("放行顺序（第二百九十二条）")

	var d := _new_desk()
	d.set_plan([
		{"std": "0830", "callsign": "LATE1", "type": "B738", "dest": "ZBAA", "stand": "A01"},
		{"std": "0800", "callsign": "EARLY", "type": "B738", "dest": "ZBAA", "stand": "A02"},
		{"std": "0815", "callsign": "MID", "type": "B738", "dest": "ZBAA", "stand": "A03"},
	])
	# 故意乱序进来
	d.spawn_request(0.0)
	d.spawn_request(1.0)
	d.spawn_request(2.0)

	var ordered := d.ordered_pending()
	_check(ordered.size() == 3, "三架都在待放行里", str(ordered.size()))
	_check((ordered[0] as Flight).callsign == "EARLY", "最早计划的排第一",
		(ordered[0] as Flight).callsign)
	_check((ordered[1] as Flight).callsign == "MID", "其次 MID", (ordered[1] as Flight).callsign)
	_check((ordered[2] as Flight).callsign == "LATE1", "最后 LATE1", (ordered[2] as Flight).callsign)

	# 没有计划的航班排在有计划的后面
	var d2 := _new_desk()
	d2.seed_initial(0.0, 1)
	var no_plan: Flight = d2.flights[0]
	no_plan.planned_std = ""
	d2.set_plan([{"std": "0800", "callsign": "PLANNED", "type": "B738",
		"dest": "ZBAA", "stand": "A09"}])
	d2.spawn_request(5.0)
	var o2 := d2.ordered_pending()
	_check((o2[0] as Flight).callsign == "PLANNED", "有计划的排前",
		(o2[0] as Flight).callsign)
	_check((o2[1] as Flight).callsign == no_plan.callsign, "没计划的排后")

	# 同一时刻按呼号排，结果稳定
	var d3 := _new_desk()
	d3.set_plan([
		{"std": "0800", "callsign": "ZZZ9", "type": "B738", "dest": "ZBAA", "stand": "A01"},
		{"std": "0800", "callsign": "AAA1", "type": "B738", "dest": "ZBAA", "stand": "A02"},
	])
	d3.spawn_request(0.0)
	d3.spawn_request(1.0)
	var o3 := d3.ordered_pending()
	_check((o3[0] as Flight).callsign == "AAA1", "同刻按呼号排序",
		(o3[0] as Flight).callsign)


func _test_delay() -> void:
	_section("延误分钟数")

	var d := _new_desk()
	d.set_plan([{"std": "0800", "callsign": "CCA1501", "type": "B738",
		"dest": "ZBAA", "stand": "A01"}])
	var f := d.spawn_request(0.0)

	# 本场时钟 0755 起步：0 秒时还没到计划时刻
	_check(d.delay_minutes(f, 0.0) == -5, "0755 时计划 0800 → −5 分钟",
		str(d.delay_minutes(f, 0.0)))
	# 5 分钟后正好 0800
	_check(d.delay_minutes(f, 300.0) == 0, "0800 时延误 0", str(d.delay_minutes(f, 300.0)))
	# 再过 29 分钟
	_check(d.delay_minutes(f, 300.0 + 29 * 60) == 29, "延误 29 分钟")
	_check(d.delay_minutes(f, 300.0 + 31 * 60) == 31, "延误 31 分钟")

	# 没有计划的航班不算延误
	var d2 := _new_desk()
	d2.seed_initial(0.0, 1)
	var g: Flight = d2.flights[0]
	g.planned_std = ""
	_check(d2.delay_minutes(g, 99999.0) == 0, "无计划航班不参与延误计算")


func _test_notices() -> void:
	_section("延误通知（第二百九十三条）")

	var d := _new_desk()
	d.set_plan([{"std": "0800", "callsign": "CCA1501", "type": "B738",
		"dest": "ZBAA", "stand": "A01"}])
	var f := d.spawn_request(0.0)

	# 延误 30 分钟：不通知
	d.tick(300.0 + 30 * 60)
	_check(not f.delay_notified, "延误恰好 30 分钟还不通知")
	_check(d.check_delay_notices(300.0 + 30 * 60) == 0, "30 分钟不产生通知")

	# 延误 31 分钟：通知一次
	var before := d.transcript.size()
	var n := d.check_delay_notices(300.0 + 31 * 60)
	_check(n == 1, "31 分钟产生一条通知", str(n))
	_check(f.delay_notified, "航班标记为已通知")
	_check(d.transcript.size() == before + 1, "通话记录多一条",
		"%d -> %d" % [before, d.transcript.size()])
	var last: Dictionary = d.transcript[d.transcript.size() - 1]
	_check(String(last.get("text", "")).find("延误") >= 0, "通知内容含延误字样",
		String(last.get("text", "")))
	_check(String(last.get("side", "")) == "atc", "通知由管制发出")

	# 再 tick 不会重复通知
	var n2 := d.check_delay_notices(300.0 + 45 * 60)
	_check(n2 == 0, "不会重复通知", str(n2))

	# 已经放行的航班不再通知
	var d2 := _new_desk()
	d2.set_plan([{"std": "0800", "callsign": "CES2302", "type": "A320",
		"dest": "ZSPD", "stand": "A02"}])
	var g := d2.spawn_request(0.0)
	d2.issue_clearance("CES2302", "BETON 3A", 5000, "4321", 1.0)
	# 复诵到达要等 READBACK_DELAY（1.6 秒）
	d2.tick(3.0)
	d2.accept_readback("CES2302", 3.5)
	_check(g.state == Flight.State.CLEARED, "先放行掉", g.state_text())
	_check(d2.check_delay_notices(300.0 + 60 * 60) == 0, "已放行的不通知延误")

	# 状态随存档往返
	var back := DeliveryDesk.from_dict(d.to_dict())
	_check(bool((back.flights[0] as Flight).delay_notified), "已通知标记随存档保留")


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
