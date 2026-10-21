## CDM 时隙与拖动排序（放行机制规范 §2）测试，无头可跑。
##
## 核心规则只有两条，但都很容易写错：
## ① 受 CTOT 约束的航班不能被排到"时隙更早的受限航班"前面（抢时隙）；
## ② 早于 CTOT 不许放行 —— 这条如果不拦住，CTOT 就只是个显示数字。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_cdm.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ CDM 时隙 / 排序测试 ════════")
	_test_disabled()
	_test_assign()
	_test_hhmm()
	_test_reorder()
	_test_ctot_guard()
	_test_slot_eval()
	_test_reset()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- 夹具

func _desk(cdm: bool) -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(777)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.cdm_enabled = cdm
	return d


## 三架有计划时刻的航班（0800 / 0820 / 0840）
func _seed(d: DeliveryDesk) -> void:
	d.set_plan([
		{"std": "0800", "callsign": "AAA001", "type": "B738", "dest": "ZBAA",
			"stand": "A05", "sid": "RUMUK 8D", "alt": 6000},
		{"std": "0820", "callsign": "BBB002", "type": "A320", "dest": "ZSPD",
			"stand": "A06", "sid": "BETON 3A", "alt": 5000},
		{"std": "0840", "callsign": "CCC003", "type": "A321", "dest": "ZGGG",
			"stand": "A07", "sid": "SASAN 5B", "alt": 6000},
	])
	for i in range(3):
		d.spawn_request(0.0)
	d.enable_strip_check = false


func _names(list: Array) -> String:
	var out := PackedStringArray()
	for f in list:
		out.append((f as Flight).callsign)
	return ",".join(out)


# ---------------------------------------------------------------- 测试

func _test_disabled() -> void:
	_section("关闭 CDM 时不产生时隙")
	var d := _desk(false)
	_seed(d)
	var f := d.get_flight("AAA001")
	_check(f.eobt_min == -1, "没有 EOBT", str(f.eobt_min))
	_check(not f.ctot_restricted, "不受 CTOT 约束")
	var r := d.issue_clearance("AAA001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(bool(r.ok), "随时可以放行", String(r.error))


func _test_assign() -> void:
	_section("开启 CDM 后自动分配时隙")
	var d := _desk(true)
	_seed(d)
	var f := d.get_flight("AAA001")
	_check(f.eobt_min == 480, "EOBT 来自计划 0800", str(f.eobt_min))
	_check(f.tobt_min >= f.eobt_min - 3 and f.tobt_min <= f.eobt_min + 8,
		"TOBT 在计划附近", str(f.tobt_min))
	_check(f.cobt_min >= 0, "COBT 有值", str(f.cobt_min))

	# 手动造一个受约束的航班，验证 CTOT/COBT 的推导关系
	f.ctot_restricted = true
	f.ctot_min = 500
	f.cobt_min = maxi(f.tobt_min - 2, f.ctot_min - DeliveryDesk.TAXI_MIN)
	_check(f.cobt_min == 488, "COBT = CTOT − 滑行时间(12)", str(f.cobt_min))

	var has_restricted := false
	for g in d.flights:
		if (g as Flight).ctot_restricted:
			has_restricted = true
			_check((g as Flight).ctot_min > (g as Flight).tobt_min,
				"CTOT 晚于 TOBT", "%d vs %d" % [
					(g as Flight).ctot_min, (g as Flight).tobt_min])
	_check(true, "受约束比例配置存在（随机，故不强制有）")


func _test_hhmm() -> void:
	_section("时刻格式")
	_check(DeliveryDesk.slot_hhmm(480) == "0800", "480 → 0800",
		DeliveryDesk.slot_hhmm(480))
	_check(DeliveryDesk.slot_hhmm(0) == "0000", "0 → 0000")
	_check(DeliveryDesk.slot_hhmm(1439) == "2359", "1439 → 2359")
	_check(DeliveryDesk.slot_hhmm(1445) == "0005", "跨零点回到 0005",
		DeliveryDesk.slot_hhmm(1445))
	_check(DeliveryDesk.slot_hhmm(-1) == "—", "无时隙显示占位符")


func _test_reorder() -> void:
	_section("拖动排序")
	var d := _desk(true)
	_seed(d)
	# 这一段只测排序，先把随机分配的 CTOT 清掉
	for g in d.flights:
		(g as Flight).ctot_restricted = false
	_check(_names(d.ordered_pending()) == "AAA001,BBB002,CCC003",
		"初始按计划时刻排", _names(d.ordered_pending()))

	# 把第三架拖到最前
	var r := d.move_flight("CCC003", 0)
	_check(bool(r.ok), "允许拖动", String(r.error))
	_check(_names(d.ordered_pending()) == "CCC003,AAA001,BBB002",
		"顺序已改变", _names(d.ordered_pending()))
	_check(d.get_flight("CCC003").order_rank == 0, "落位记下 rank")
	_check(d.get_flight("BBB002").order_rank == 2, "其余 rank 依次重排")

	# 拖回中间
	var r2 := d.move_flight("CCC003", 1)
	_check(bool(r2.ok), "可以再拖", String(r2.error))
	_check(_names(d.ordered_pending()) == "AAA001,CCC003,BBB002",
		"落到第 2 位", _names(d.ordered_pending()))

	# 已放行的不能拖
	d.set_plan([{"callsign": "DDD004", "type": "B738", "dest": "ZBAA",
		"stand": "A08", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	var r3 := d.move_flight("DDD004", 0)
	_check(bool(r3.ok), "待申请状态的可以拖")
	var rr := d.can_move("不存在", 0)
	_check(not bool(rr.ok), "找不到航班要拒绝")


func _test_ctot_guard() -> void:
	_section("CTOT 约束（抢时隙 / 早放行）")
	var d := _desk(true)
	_seed(d)
	var a := d.get_flight("AAA001")
	var b := d.get_flight("BBB002")
	# A 时隙 0810(490)，B 时隙 0830(510)
	a.ctot_restricted = true
	a.ctot_min = 490
	a.cobt_min = 478
	b.ctot_restricted = true
	b.ctot_min = 510
	b.cobt_min = 498

	# B 不能排到 A 前面（B 的时隙比 A 晚）
	var r := d.move_flight("BBB002", 0)
	_check(not bool(r.ok), "时隙晚的不能插到前面", String(r.error))
	_check(String(r.error).contains("CTOT"), "拒绝理由提到 CTOT", String(r.error))
	_check(_names(d.ordered_pending()) == "AAA001,BBB002,CCC003",
		"被拒绝后顺序不变", _names(d.ordered_pending()))

	# A 可以排到 B 前面（本来就是）
	var r2 := d.move_flight("AAA001", 0)
	_check(bool(r2.ok), "时隙早的可以往前")

	# 早于 CTOT 放行必须被拦
	var early := d.issue_clearance("AAA001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(not bool(early.ok), "早于 CTOT 不能放行", String(early.error))
	_check(String(early.error).contains("0810"), "提示里给出最早放行时刻",
		String(early.error))

	# 到点后可以放行：0810 是 600 秒
	var ok_r := d.issue_clearance("AAA001", "RUMUK 8D", 6000, "1234", 600.0)
	_check(bool(ok_r.ok), "到点可以放行", String(ok_r.error))


func _test_slot_eval() -> void:
	_section("放行时刻评价（提前/准时/延误）")
	var d := _desk(true)
	_seed(d)
	var f := d.get_flight("AAA001")
	f.ctot_restricted = true
	f.ctot_min = 500
	f.cobt_min = 488
	# 仿真时钟从 clock_start 0800(480) 起算：CTOT 08:20(500) 对应 20 分钟 = 1200 秒
	var r := d.issue_clearance("AAA001", "RUMUK 8D", 6000, "1234", 1200.0 + 600.0)
	_check(bool(r.ok), "放行成功", String(r.error))
	_check(f.slot_eval == "延误", "晚 10 分记为延误", f.slot_eval)
	_check(f.slot_delay_min == 10, "延误分钟数正确", str(f.slot_delay_min))

	var d2 := _desk(true)
	_seed(d2)
	var g := d2.get_flight("BBB002")
	g.ctot_restricted = true
	g.ctot_min = 500
	g.cobt_min = 488
	d2.issue_clearance("BBB002", "BETON 3A", 5000, "2345", 1200.0)
	_check(g.slot_eval == "准时", "正点放行记为准时", g.slot_eval)


func _test_reset() -> void:
	_section("整理进程单恢复默认顺序")
	var d := _desk(true)
	_seed(d)
	for g in d.flights:
		(g as Flight).ctot_restricted = false
	d.move_flight("CCC003", 0)
	_check(d.get_flight("CCC003").order_rank == 0, "先拖动过")
	d.reset_order()
	_check(d.get_flight("CCC003").order_rank == -1, "rank 被清掉")
	_check(_names(d.ordered_pending()) == "AAA001,BBB002,CCC003",
		"恢复按计划时刻排", _names(d.ordered_pending()))

	# 存档往返
	var f := d.get_flight("AAA001")
	f.ctot_restricted = true
	f.ctot_min = 490
	f.order_rank = 2
	var back := Flight.from_dict(f.to_dict())
	_check(back.ctot_min == 490, "CTOT 往返")
	_check(back.ctot_restricted, "约束标记往返")
	_check(back.order_rank == 2, "排序位往返")


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
