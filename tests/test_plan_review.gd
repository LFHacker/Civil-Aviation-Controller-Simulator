## 飞行计划审查（放行机制规范 §1）与七态状态机（§0.2）测试，无头可跑。
##
## 重点不是"能算出不一致"，而是：
## ① 三项处置各自的效果与留痕；② 红项必须挡住"完成审查"；
## ③ 高阶模式允许带着漏检完成（漏检计入评分），不能把玩家锁死。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_plan_review.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 计划审查 / 状态机测试 ════════")
	_test_flow_states()
	_test_rows_basic()
	_test_mismatches()
	_test_fix()
	_test_waive()
	_test_coordinate()
	_test_blocking()
	_test_hard_mode()
	_test_serialize()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- 夹具

func _make_desk(difficulty: String = "normal") -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(20260101)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0755", "airport_id": "ZDEM",
	}
	d.review_ref = {
		"types": {
			"B738": {"wake": "M", "tow_t": 72, "endurance": "03:20"},
			"A320": {"wake": "M", "tow_t": 68, "endurance": "03:05"},
		},
		"alternates": ["ZBTJ", "ZBSJ"],
		"routes": {"RUMUK 8D": "W105 LADIX", "SASAN 5B": "A461 RUMUK"},
		"loa": [
			{"sid": "RUMUK 8D", "alt_min": 5000, "alt_max": 7000},
			{"sid": "SASAN 5B", "alt_min": 5000, "alt_max": 7000},
		],
	}
	d.difficulty = difficulty
	d.enable_plan_review = true
	return d


## 一条完全合规的计划
func _clean_desk(difficulty: String = "normal") -> DeliveryDesk:
	var d := _make_desk(difficulty)
	d.set_plan([{"std": "0800", "callsign": "TST001", "type": "B738",
		"dest": "ZBAA", "stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	return d


func _row(rows: Array, key: String) -> Dictionary:
	for r in rows:
		if String((r as Dictionary).get("key", "")) == key:
			return r
	return {}


# ---------------------------------------------------------------- 七态

func _test_flow_states() -> void:
	_section("七态状态机（§0.2）")
	var S := Flight.State
	_check(Flight.flow_of(S.PENDING, false, false) == 2, "未核对计划 → 已申请",
		str(Flight.flow_of(S.PENDING, false, false)))
	_check(Flight.flow_of(S.PENDING, true, false) == 3, "已核对 → 计划已审查")
	_check(Flight.flow_of(S.SENT, true, false) == 4, "已发许可 → 许可已发布")
	_check(Flight.flow_of(S.READBACK, true, false) == 5, "复诵到 → 复诵待确认")
	_check(Flight.flow_of(S.CLEARED, true, false) == 6, "复诵正确 → 复诵已确认")
	_check(Flight.flow_of(S.CLEARED, true, true) == 7, "移交后 → 已移交地面")

	var f := Flight.new()
	f.state = S.PENDING
	_check(f.state_text() == "已申请", "初始文案是已申请", f.state_text())
	f.checked = true
	_check(f.state_text() == "计划已审查", "核对后文案", f.state_text())
	f.state = S.SENT
	_check(f.state_text() == "许可已发布", "发许可后文案", f.state_text())
	f.state = S.CLEARED
	f.handed_off = true
	_check(f.state_text() == "已移交地面", "移交后文案", f.state_text())


# ---------------------------------------------------------------- 对照行

func _test_rows_basic() -> void:
	_section("对照行（合规计划）")
	var d := _clean_desk()
	var rows := d.review_rows("TST001")
	_check(rows.size() == 8, "共 8 行（6 项判定 + 2 项只显示）", str(rows.size()))
	_check(int(_row(rows, "airport").state) == PlanReview.OK, "起降机场一致")
	_check(int(_row(rows, "route").state) == PlanReview.OK, "航路一致",
		str(_row(rows, "route")))
	_check(int(_row(rows, "wake").state) == PlanReview.OK, "尾流一致")
	_check(int(_row(rows, "altitude").state) == PlanReview.OK, "高度在协议带内")
	_check(int(_row(rows, "weight").state) == PlanReview.INFO, "起飞重量只显示")
	_check(int(_row(rows, "endurance").state) == PlanReview.INFO, "续航时间只显示")
	_check(String(_row(rows, "weight").planned) == "72 吨", "重量从机型库补齐",
		String(_row(rows, "weight").planned))
	_check(not d.review_blocking("TST001"), "合规计划没有红项")


func _test_mismatches() -> void:
	_section("不一致的三种来源")

	# 1) 尾流类别写错（计划写 H，机型库是 M）
	var d1 := _make_desk()
	d1.set_plan([{"callsign": "TST002", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000, "wake": "H"}])
	d1.spawn_request(0.0)
	var r1 := _row(d1.review_rows("TST002"), "wake")
	_check(int(r1.state) == PlanReview.BAD, "尾流写错被标成不一致")
	_check(String(r1.planned) == "H" and String(r1.current) == "M",
		"计划值/当前有效值两边都对", "%s vs %s" % [r1.planned, r1.current])

	# 2) 备降场不在当前可用清单里
	var d2 := _make_desk()
	d2.set_plan([{"callsign": "TST003", "type": "B738", "dest": "ZBAA",
		"stand": "A06", "sid": "RUMUK 8D", "alt": 6000, "alternate": "ZUUU"}])
	d2.spawn_request(0.0)
	var r2 := _row(d2.review_rows("TST003"), "alternate")
	_check(int(r2.state) == PlanReview.BAD, "备降场不可用被标出")
	_check(String(r2.current).contains("ZBTJ"), "当前值列出可用的备降场",
		String(r2.current))

	# 3) 初始高度超出该 SID 的管制协议高度带
	var d3 := _make_desk()
	d3.set_plan([{"callsign": "TST004", "type": "B738", "dest": "ZBAA",
		"stand": "A07", "sid": "SASAN 5B", "alt": 4000}])
	d3.spawn_request(0.0)
	var r3 := _row(d3.review_rows("TST004"), "altitude")
	_check(int(r3.state) == PlanReview.BAD, "高度不在协议带内被标出")
	_check(String(r3.current) == "5000–7000 米", "当前值给出协议带",
		String(r3.current))
	_check(d3.review_blocking("TST004"), "有红项 → 阻挡完成审查")


# ---------------------------------------------------------------- 三种处置

func _test_fix() -> void:
	_section("处置一：修正计划")
	var d := _make_desk()
	d.set_plan([{"callsign": "TST010", "type": "B738", "dest": "ZBAA",
		"stand": "A08", "sid": "SASAN 5B", "alt": 4000}])
	d.spawn_request(0.0)
	var r := d.fix_review_row("TST010", "altitude", 10.0)
	_check(bool(r.ok), "修正成功", String(r.error))
	var row := _row(d.review_rows("TST010"), "altitude")
	_check(int(row.state) == PlanReview.FIXED, "行状态变为已修正", str(row.state))
	_check(String(row.planned) == "5000 米", "计划值被改成协议下限",
		String(row.planned))
	var f := d.get_flight("TST010")
	_check(f.initial_alt_m == 5000, "航班的初始高度同步改了（会进许可）",
		str(f.initial_alt_m))
	_check(not d.review_blocking("TST010"), "修正后不再阻挡")

	var bad := d.fix_review_row("TST010", "weight", 11.0)
	_check(not bool(bad.ok), "只显示的字段不能处置")


func _test_waive() -> void:
	_section("处置三：标记为已审查（有保留）")
	var d := _make_desk()
	d.set_plan([{"callsign": "TST011", "type": "B738", "dest": "ZBAA",
		"stand": "A09", "sid": "RUMUK 8D", "alt": 6000, "wake": "H"}])
	d.spawn_request(0.0)
	var r := d.waive_review_row("TST011", "wake", 12.0)
	_check(bool(r.ok), "标记成功", String(r.error))
	var row := _row(d.review_rows("TST011"), "wake")
	_check(int(row.state) == PlanReview.WAIVED, "行状态变为已审查", str(row.state))
	_check(String(row.planned) == "H", "计划值保持原样（有保留，不改数据）",
		String(row.planned))
	_check(not d.review_blocking("TST011"), "标记后不再阻挡")


func _test_coordinate() -> void:
	_section("处置二：协调修改（有延迟）")
	var d := _make_desk()
	d.set_plan([{"callsign": "TST012", "type": "B738", "dest": "ZBAA",
		"stand": "A10", "sid": "RUMUK 8D", "alt": 6000, "wake": "H"}])
	d.spawn_request(0.0)
	var r := d.coordinate_review_row("TST012", "wake", 20.0)
	_check(bool(r.ok), "提交协调成功", String(r.error))
	var ready := float(r.get("ready_at", 0.0))
	_check(ready > 20.0, "协调有延迟，不是立刻生效", str(ready))
	_check(d.review_coordinating("TST012", "wake"), "协调中可查")
	_check(int(_row(d.review_rows("TST012"), "wake").state) == PlanReview.BAD,
		"协调期间仍是红项")

	# 再点一次不能重复提交
	var again := d.coordinate_review_row("TST012", "wake", 21.0)
	_check(not bool(again.ok), "同一项不能重复提交协调")

	# 到点前不动
	d.tick(ready - 1.0)
	_check(int(_row(d.review_rows("TST012"), "wake").state) == PlanReview.BAD,
		"没到点不落地")
	# 到点后落地
	d.tick(ready + 0.1)
	var row := _row(d.review_rows("TST012"), "wake")
	_check(int(row.state) == PlanReview.FIXED, "到点后变为已修正", str(row.state))
	_check(not d.review_coordinating("TST012", "wake"), "协调记录被清掉")


# ---------------------------------------------------------------- 完成审查

func _test_blocking() -> void:
	_section("红项挡住「完成审查」")
	var d := _make_desk()
	d.set_plan([{"callsign": "TST020", "type": "B738", "dest": "ZBAA",
		"stand": "A11", "sid": "SASAN 5B", "alt": 4000}])
	d.spawn_request(0.0)
	var r := d.finish_review("TST020", 30.0)
	_check(not bool(r.ok), "有红项时不能完成审查", String(r.error))
	_check(String(r.error).contains("未处置"), "提示里说明原因", String(r.error))
	var f := d.get_flight("TST020")
	_check(not f.checked, "状态没有被偷偷推进")
	_check(f.flow_state() == 2, "仍在「已申请」", str(f.flow_state()))

	d.fix_review_row("TST020", "altitude", 31.0)
	var r2 := d.finish_review("TST020", 32.0)
	_check(bool(r2.ok), "处置完可以完成审查", String(r2.error))
	_check(f.checked and f.review_done, "checked / review_done 都置起")
	_check(f.flow_state() == 3, "状态推进到「计划已审查」", str(f.flow_state()))
	_check(f.t_check == 32.0, "记录核对时刻", str(f.t_check))

	var r3 := d.finish_review("TST020", 33.0)
	_check(not bool(r3.ok), "不能重复完成审查")


func _test_hard_mode() -> void:
	_section("高阶模式：允许带着漏检完成，记进评分")
	var d := _make_desk("hard")
	d.set_plan([{"callsign": "TST021", "type": "B738", "dest": "ZBAA",
		"stand": "A12", "sid": "SASAN 5B", "alt": 4000}])
	d.spawn_request(0.0)
	_check(not d.review_blocking("TST021"), "高阶模式不阻断（系统不标红）")
	var r := d.finish_review("TST021", 40.0)
	_check(bool(r.ok), "可以完成审查", String(r.error))
	_check(int(r.get("missed", 0)) == 1, "漏检 1 项被记下", str(r.get("missed")))
	var f := d.get_flight("TST021")
	_check(f.missed_review == 1, "累计到航班的漏检计数",
		str(f.missed_review))
	_check(f.flow_state() == 3, "仍然推进到计划已审查")

	# 普通难度下同一份计划必须被挡住
	var n := _make_desk("normal")
	n.set_plan([{"callsign": "TST022", "type": "B738", "dest": "ZBAA",
		"stand": "A13", "sid": "SASAN 5B", "alt": 4000}])
	n.spawn_request(0.0)
	_check(not bool(n.finish_review("TST022", 41.0).ok), "普通难度必须挡住")


func _test_serialize() -> void:
	_section("存档往返")
	var d := _clean_desk()
	d.fix_review_row("TST001", "wake", 5.0)
	var f := d.get_flight("TST001")
	var back := Flight.from_dict(f.to_dict())
	_check(back.plan_type == f.plan_type, "机型往返")
	_check(back.plan_wake == f.plan_wake, "尾流往返")
	_check(back.plan_alt_m == f.plan_alt_m, "计划高度往返")
	_check(back.plan_tow_t == f.plan_tow_t, "起飞重量往返")
	_check(back.plan_endurance == f.plan_endurance, "续航往返")
	_check(int(back.review.get("wake", -1)) == PlanReview.FIXED, "处置结果往返",
		str(back.review))
	_check(back.missed_review == f.missed_review, "漏检计数往返")


# ---------------------------------------------------------------- 报表

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
