## 复诵核对（放行机制规范 §6）测试，无头可跑。
##
## 三个部件：
## ① 逐项比对表（关键项/非关键项分开）；
## ② 简易模式：有红项不许确认；
## ③ 高阶模式：必须逐项判、60 秒时限、误判不拦截但记账。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_readback.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 复诵核对测试 ════════")
	_test_items()
	_test_easy()
	_test_hard()
	_test_flag_wrong()
	_test_deadline()
	_test_serialize()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _desk(hard: bool = false) -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(999)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.readback_hard = hard
	d.set_plan([{"callsign": "RBK001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	# 真实流程里必须先审查计划才能发许可，这里直接把状态摆到位
	d.get_flight("RBK001").checked = true
	d.issue_clearance("RBK001", "RUMUK 8D", 6000, "1234", 0.0)
	return d


## 走到"复诵已到"的状态；wrong=true 时强制读错一项
func _to_readback(hard: bool = false, wrong: bool = false) -> DeliveryDesk:
	var d := _desk(hard)
	if wrong:
		d.force_error_next = true
	d.tick(d.get_flight("RBK001").readback_at + 0.1)
	return d


func _find(items: Array, key: String) -> Dictionary:
	for it in items:
		if String((it as Dictionary).get("key", "")) == key:
			return it
	return {}


func _test_items() -> void:
	_section("逐项比对表")
	var d := _to_readback(false, false)
	var f := d.get_flight("RBK001")
	_check(f.state == Flight.State.READBACK, "复诵已到")
	_check(f.readback_items.size() == 9, "9 项（7 关键 + 2 非关键）",
		str(f.readback_items.size()))
	var crit := 0
	for it in f.readback_items:
		if bool((it as Dictionary).critical):
			crit += 1
	_check(crit == 7, "关键项 7 个", str(crit))
	_check(f.readback_ok, "全对时 readback_ok 为真")
	_check(not bool(_find(f.readback_items, "wind").critical), "地面风是非关键项")

	# 强制读错：必须恰好命中一个关键项
	var d2 := _to_readback(false, true)
	var f2 := d2.get_flight("RBK001")
	var bad := 0
	for it in f2.readback_items:
		var x: Dictionary = it
		if bool(x.critical) and not bool(x.same):
			bad += 1
	_check(bad == 1, "注入错误只命中一个关键项", str(bad))
	_check(not f2.readback_ok, "有错时 readback_ok 为假")
	_check(f2.readback_diff != "", "给出人话描述", f2.readback_diff)


func _test_easy() -> void:
	_section("简易模式")
	var d := _to_readback(false, false)
	var r := d.accept_readback("RBK001", 100.0)
	_check(bool(r.ok), "全对时可以直接确认", String(r.error))
	_check(d.get_flight("RBK001").state == Flight.State.CLEARED, "状态到已放行")

	# 有错时不许确认，并计入误判
	var d2 := _to_readback(false, true)
	var r2 := d2.accept_readback("RBK001", 100.0)
	_check(not bool(r2.ok), "有红项不能确认", String(r2.error))
	_check(d2.misjudge_count == 1, "误判计数 +1", str(d2.misjudge_count))
	_check(d2.get_flight("RBK001").state == Flight.State.READBACK, "状态不动")


func _test_hard() -> void:
	_section("高阶模式：逐项判定")
	var d := _to_readback(true, false)
	var f := d.get_flight("RBK001")
	_check(f.readback_deadline > 0.0, "有核对时限", str(f.readback_deadline))

	var early := d.accept_readback("RBK001", 100.0)
	_check(not bool(early.ok), "没逐项判完不能确认", String(early.error))
	_check(String(early.error).contains("没有核对"), "提示未核对项",
		String(early.error))

	# 全部标为一致
	for it in f.readback_items:
		d.mark_readback_item("RBK001", String((it as Dictionary).key), true, 101.0)
	_check(d.readback_unmarked(f) == 0, "都标记完了")
	var okr := d.accept_readback("RBK001", 102.0)
	_check(bool(okr.ok), "全对时可以确认", String(okr.error))

	# 有错但被玩家标成一致：放过去，但记账
	var d2 := _to_readback(true, true)
	var f2 := d2.get_flight("RBK001")
	for it in f2.readback_items:
		d2.mark_readback_item("RBK001", String((it as Dictionary).key), true, 101.0)
	var okr2 := d2.accept_readback("RBK001", 102.0)
	_check(bool(okr2.ok), "误判不拦截（规范 §6.2）", String(okr2.error))
	_check(f2.missed_readback == 1, "误判记进评分", str(f2.missed_readback))
	_check(d2.get_flight("RBK001").state == Flight.State.CLEARED, "仍然放行")

	# 玩家自己标了不一致：要求重发
	var d3 := _to_readback(true, true)
	var f3 := d3.get_flight("RBK001")
	for it in f3.readback_items:
		var x: Dictionary = it
		var same := true
		if bool(x.critical) and not bool(x.same):
			same = false
		d3.mark_readback_item("RBK001", String(x.key), same, 101.0)
	var r3 := d3.accept_readback("RBK001", 102.0)
	_check(not bool(r3.ok), "标了不一致要重发", String(r3.error))
	_check(f3.missed_readback == 0, "这不算误判")

	# 简易模式下不能逐项标记
	var d4 := _to_readback(false, false)
	var r4 := d4.mark_readback_item("RBK001", "sid", true, 101.0)
	_check(not bool(r4.ok), "简易模式不需要逐项标记", String(r4.error))


## 07 §九：玩家指出复诵错误但未给出正确值 → 机组追问正确值，状态保持 READBACK_SENT。
func _test_flag_wrong() -> void:
	_section("只指出读错项、不给正确值（07 §九）")
	var d := _to_readback(false, true)
	var f := d.get_flight("RBK001")
	var wrong_keys: Array = []
	for it in f.readback_items:
		var x: Dictionary = it
		if not bool(x.same):
			wrong_keys.append(String(x.key))
	_check(wrong_keys.size() > 0, "复诵确实读错了至少一项", str(wrong_keys))

	var before := f.readback_asks
	var r := d.flag_readback_wrong("RBK001", wrong_keys, 100.0)
	_check(bool(r.ok), "允许指出读错项", String(r.error))
	_check(f.state == Flight.State.READBACK, "状态保持复诵待确认",
		str(f.state))
	_check(f.readback_asks == before + 1, "追问计数 +1", str(f.readback_asks))
	var need: Array = r.get("need", [])
	_check(need.size() == wrong_keys.size(), "追问里点名了读错的项",
		str(need))
	var asked := String(r.get("asked", ""))
	_check(asked != "", "给出了项目名", asked)
	# 通话记录里机组确实追问了"正确值"
	var pilot_line := ""
	for row in d.transcript:
		var t := String((row as Dictionary).get("text", ""))
		if t.contains("请给出正确的"):
			pilot_line = t
	_check(pilot_line != "", "通话记录里有『请给出正确的…』", pilot_line)
	_check(pilot_line.contains(asked), "追问的项目与点名一致", pilot_line)

	# 什么都没指就点"复诵有误"：机组反问哪一项
	var d2 := _to_readback(false, true)
	var r2 := d2.flag_readback_wrong("RBK001", [], 100.0)
	_check(bool(r2.ok), "空项也允许", String(r2.error))
	_check((r2.get("need", []) as Array).is_empty(), "没有点名项")
	_check(String(r2.get("asked", "")) == "请指出读错项", "机组反问哪一项",
		String(r2.get("asked", "")))
	_check(d2.get_flight("RBK001").state == Flight.State.READBACK, "状态不动")

	# 不在复诵状态就拒绝
	var d3 := _desk(false)
	var r3 := d3.flag_readback_wrong("RBK001", ["squawk"], 100.0)
	_check(not bool(r3.ok), "还没复诵时不能指出错误", String(r3.error))

	# 追问之后仍然必须真的重发（纠错只能发完整许可）
	var d4 := _to_readback(false, true)
	var f4 := d4.get_flight("RBK001")
	d4.flag_readback_wrong("RBK001", wrong_keys, 100.0)
	var acc := d4.accept_readback("RBK001", 101.0)
	_check(not bool(acc.ok), "追问不等于修正，仍不能确认", String(acc.error))
	_check(f4.state == Flight.State.READBACK, "状态还是复诵待确认")
	# 存档往返
	var back := Flight.from_dict(f4.to_dict())
	_check(back.readback_asks == f4.readback_asks, "追问计数进存档",
		str(back.readback_asks))


func _test_deadline() -> void:
	_section("高阶模式 60 秒时限")
	var d := _to_readback(true, false)
	var f := d.get_flight("RBK001")
	var dl := f.readback_deadline
	_check(dl > f.t_readback, "时限在复诵之后")
	d.tick(dl - 1.0)
	_check(d.get_flight("RBK001").state == Flight.State.READBACK, "没到点不退")
	d.tick(dl + 1.0)
	_check(d.get_flight("RBK001").state == Flight.State.PENDING,
		"超时退回可重发状态", str(d.get_flight("RBK001").state))
	_check(d.get_flight("RBK001").flow_state() == 3, "语义上是计划已审查",
		str(d.get_flight("RBK001").flow_state()))
	_check(d.readback_timeouts == 1, "超时计数 +1", str(d.readback_timeouts))

	# 简易模式没有时限
	var d2 := _to_readback(false, false)
	d2.tick(10000.0)
	_check(d2.get_flight("RBK001").state == Flight.State.READBACK,
		"简易模式不会超时退回")


func _test_serialize() -> void:
	_section("存档往返")
	var d := _to_readback(true, true)
	var f := d.get_flight("RBK001")
	d.mark_readback_item("RBK001", "sid", false, 101.0)
	var back := Flight.from_dict(f.to_dict())
	_check(back.readback_items.size() == f.readback_items.size(),
		"逐项表往返", str(back.readback_items.size()))
	_check(back.readback_marks.has("sid"), "判定结果往返")
	_check(back.readback_deadline == f.readback_deadline, "时限往返")
	_check(back.missed_readback == f.missed_readback, "误判计数往返")


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
