## 申请时机的测试（07 §2.2）：按 TOBT 倒推提前 N 分钟，不再"每 18 秒冒一架"。
##
## 文档原文：「每架航班按 TOBT（目标撤轮挡时间）倒推，在 TOBT 前 N 分钟
## （默认 15 分钟，可配置）进入 READY_TO_REQUEST 状态」，
## 进入后 0–10 秒随机延迟再发起首次申请。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_schedule.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 申请时机（定时器机制）测试 ════════")
	_test_seed_due()
	_test_lead()
	_test_fallback()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _desk(clock: String = "0755", lead: float = 15.0,
		plans: Array = []) -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(4242)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": clock, "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.lead_minutes = lead
	d.set_plan(plans)
	return d


func _plans() -> Array:
	return [
		{"std": "0800", "callsign": "AAA001", "type": "B738", "dest": "ZBAA",
			"stand": "A01", "sid": "RUMUK 8D", "alt": 6000},
		{"std": "0815", "callsign": "BBB002", "type": "A320", "dest": "ZSPD",
			"stand": "A02", "sid": "BETON 3A", "alt": 5000},
		{"std": "0830", "callsign": "CCC003", "type": "A321", "dest": "ZGGG",
			"stand": "A03", "sid": "SASAN 5B", "alt": 6000},
	]


func _test_seed_due() -> void:
	_section("开局只放「已经到点」的航班")
	# 时钟 07:55，提前 15 分钟 → 0800 那架在 07:45 就该申请了，其余没到点
	var d := _desk("0755", 15.0, _plans())
	var n := d.seed_due(0.0)
	_check(n == 1, "开局只放出 1 架（0800 那架）", str(n))
	_check(d.flights.size() == 1, "列表里也只有 1 架", str(d.flights.size()))
	_check(d.get_flight("AAA001") != null, "放出来的是 0800 的航班")

	# 同一时刻再要，不该再冒新的
	_check(d.maybe_spawn(0.0) == null, "没到点就不来新的")
	# 07:59:59 还不该来第二架
	_check(d.maybe_spawn(299.0) == null, "07:59:59 仍不该来第二架")
	# 08:00 过后，0815 那架（提前 15 分钟 = 08:00）到点；留出 10 秒抖动余量
	var f := d.maybe_spawn(330.0)
	_check(f != null, "08:00 之后第二架会来", str(f))
	if f != null:
		_check(String(f.callsign) == "BBB002", "来的是 0815 那架", String(f.callsign))
	_check(d.flights.size() == 2, "现在一共 2 架", str(d.flights.size()))


func _test_lead() -> void:
	_section("提前量可配置")
	# 提前量改成 5 分钟：0755 时 0800 那架刚好到点（07:55）
	var d := _desk("0755", 5.0, _plans())
	_check(d.plan_request_minute(0) >= 475.0 - 0.01 and
		d.plan_request_minute(0) <= 475.0 + 11.0 / 60.0,
		"提前 5 分钟 → 0800 那架的申请时刻 ≈ 07:55",
		str(d.plan_request_minute(0)))
	# 抖动最多 10 秒：开局这一瞬间可能还差几秒才到点，过 20 秒再看
	var n := d.seed_due(20.0)
	_check(n == 1, "提前 5 分钟：20 秒内会放出 1 架", str(n))

	# 提前量为 0：0755 时 0800 那架还没到点，开局列表应当是空的
	var d2 := _desk("0755", 0.0, _plans())
	var n2 := d2.seed_due(0.0)
	_check(n2 == 0, "提前 0 分钟时开局没有航班", str(n2))
	_check(d2.flights.is_empty(), "列表为空")
	# 到 0800 才来第一架（留 10 秒抖动余量）
	_check(d2.maybe_spawn(620.0) != null, "08:00 之后才来第一架")


func _test_fallback() -> void:
	_section("没有计划时刻时退回按间隔补")
	var d := _desk("0755", 15.0, [])
	_check(d.plan.is_empty(), "计划为空")
	var n := d.seed_due(0.0)
	_check(n == 1, "没有计划时兜底放 1 架", str(n))
	# 兜底节奏仍然生效：过一段时间会有下一架
	_check(d.maybe_spawn(1.0) == null, "刚来过不会立刻再来")
	_check(d.maybe_spawn(30.0) != null, "间隔够了会再来一架")
	# 计划里某一条没有 std：跳过它，继续等有时刻的那条
	var d2 := _desk("0755", 15.0, [
		{"callsign": "XXX000", "type": "B738", "dest": "ZBAA", "sid": "RUMUK 8D"},
		{"std": "0900", "callsign": "DDD004", "type": "B738", "dest": "ZBAA",
			"stand": "A04", "sid": "RUMUK 8D", "alt": 6000},
	])
	_check(d2.plan_request_minute(0) < 0.0, "没有 std 的条目返回 -1")
	_check(d2.seed_due(0.0) == 1, "没有时刻的条目当作立刻准备好", str(d2.flights.size()))
	_check(d2.get_flight("XXX000") != null, "先放的是没有时刻的那条")
	_check(d2.get_flight("DDD004") == null, "0900 那条还没到点")


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
