## 放行许可的闸门与数值校验（放行机制规范 §5.1 / §10）测试，无头可跑。
##
## 两条都在真实运行中抓过错：
## ① QNH 不确认就发许可 —— 通播有 ATIS 也不是省掉 QNH 的理由；
## ② 应答机与空域里另一架重复 —— 二次雷达会认错飞机。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_guard.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 许可闸门 / 数值校验测试 ════════")
	_test_defaults_off()
	_test_qnh_gate()
	_test_squawk_dup()
	_test_alt_band()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(4242)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {
		"types": {"B738": {"wake": "M"}},
		"alternates": ["ZBTJ"],
		"routes": {"RUMUK 8D": "W105 LADIX", "KAMAN 2C": "W102 KAMAN"},
		"loa": [
			{"sid": "RUMUK 8D", "alt_min": 5000, "alt_max": 7000},
			{"sid": "KAMAN 2C", "alt_min": 3000, "alt_max": 5000},
		],
	}
	d.set_plan([
		{"callsign": "GUA001", "type": "B738", "dest": "ZBAA", "stand": "A05",
			"sid": "RUMUK 8D", "alt": 6000},
		{"callsign": "GUA002", "type": "B738", "dest": "ZSPD", "stand": "A06",
			"sid": "KAMAN 2C", "alt": 4000},
	])
	d.spawn_request(0.0)
	d.spawn_request(0.0)
	return d


func _test_defaults_off() -> void:
	_section("默认关闭时行为不变")
	var d := _desk()
	var r := d.issue_clearance("GUA001", "RUMUK 8D", 3000, "1000", 0.0)
	_check(bool(r.ok), "不问 QNH、不校验数值也能发（老测试靠这个）", String(r.error))


func _test_qnh_gate() -> void:
	_section("QNH 确认闸门")
	var d := _desk()
	d.enable_qnh_gate = true
	var r := d.issue_clearance("GUA001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(not bool(r.ok), "没确认 QNH 不能发许可", String(r.error))
	_check(String(r.error).contains("QNH"), "理由写明 QNH", String(r.error))

	var c := d.confirm_qnh("GUA001")
	_check(bool(c.ok), "确认动作成功")
	_check(d.get_flight("GUA001").qnh_confirmed, "状态记为已确认")

	var r2 := d.issue_clearance("GUA001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(bool(r2.ok), "确认后可以发", String(r2.error))

	# 第二架没确认，仍然要挡
	var r3 := d.issue_clearance("GUA002", "KAMAN 2C", 4000, "2345", 0.0)
	_check(not bool(r3.ok), "换一架仍然要各自确认", String(r3.error))

	# 确认结果进存档
	var back := Flight.from_dict(d.get_flight("GUA001").to_dict())
	_check(back.qnh_confirmed, "确认状态往返")


func _test_squawk_dup() -> void:
	_section("应答机重复校验")
	var d := _desk()
	d.enable_value_check = true
	var r := d.issue_clearance("GUA001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(bool(r.ok), "第一架正常发放", String(r.error))

	var r2 := d.issue_clearance("GUA002", "KAMAN 2C", 4000, "1234", 0.0)
	_check(not bool(r2.ok), "第二架用同一编码被挡", String(r2.error))
	_check(String(r2.error).contains("GUA001"), "提示里点名占用者",
		String(r2.error))

	var r3 := d.issue_clearance("GUA002", "KAMAN 2C", 4000, "2345", 0.0)
	_check(bool(r3.ok), "换一个编码就能发", String(r3.error))

	_check(d.squawk_owner("1234") == "GUA001", "能查到占用者",
		d.squawk_owner("1234"))
	_check(d.squawk_owner("1234", "GUA001") == "", "排除自己后不算重复")


func _test_alt_band() -> void:
	_section("高度必须在协议带内")
	var d := _desk()
	d.enable_value_check = true
	# RUMUK 8D 的协议带是 5000–7000
	var low := d.issue_clearance("GUA001", "RUMUK 8D", 3000, "1234", 0.0)
	_check(not bool(low.ok), "低于协议带被挡", String(low.error))
	_check(String(low.error).contains("5000"), "提示里给出带下限",
		String(low.error))
	var high := d.issue_clearance("GUA001", "RUMUK 8D", 8000, "1234", 0.0)
	_check(not bool(high.ok), "高于协议带被挡", String(high.error))
	var ok_r := d.issue_clearance("GUA001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(bool(ok_r.ok), "带内可以发", String(ok_r.error))

	# KAMAN 2C 的带更矮：4000 可以，6000 不行
	var d2 := _desk()
	d2.enable_value_check = true
	var a := d2.issue_clearance("GUA002", "KAMAN 2C", 4000, "3456", 0.0)
	_check(bool(a.ok), "低带 SID 用 4000 正常", String(a.error))
	var d3 := _desk()
	d3.enable_value_check = true
	var b := d3.issue_clearance("GUA002", "KAMAN 2C", 6000, "3456", 0.0)
	_check(not bool(b.ok), "低带 SID 用 6000 被挡", String(b.error))


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
