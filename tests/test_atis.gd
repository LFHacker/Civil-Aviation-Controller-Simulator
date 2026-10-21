## 通播生命周期与过期处置（放行机制规范 §3）测试，无头可跑。
##
## 三件事必须成立：
## ① 代号是版本指针 —— 按字母推进、Z 回到 A，玩家不能跳；
## ② 满 60 分钟就是"已过期"，过期本身就是必须拦截的错误状态；
## ③ 越过"重大变化"阈值要能检测出来（风 60°/5m/s、能见度 800 米）。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_atis.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 通播生命周期测试 ════════")
	_test_alpha()
	_test_state()
	_test_vis()
	_test_major()
	_test_update()
	_test_gate()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _test_alpha() -> void:
	_section("代号推进")
	_check(AtisBroadcast.next_alpha("A") == "B", "A → B")
	_check(AtisBroadcast.next_alpha("M") == "N", "M → N")
	_check(AtisBroadcast.next_alpha("Y") == "Z", "Y → Z")
	_check(AtisBroadcast.next_alpha("Z") == "A", "Z 之后回到 A")
	_check(AtisBroadcast.next_alpha("a") == "B", "小写也认")
	_check(AtisBroadcast.next_alpha("") == "A", "空值从 A 起")
	_check(AtisBroadcast.next_alpha("AB") == "A", "非单字母退回 A")


func _test_state() -> void:
	_section("有效期判定")
	var a := AtisBroadcast.new()
	a.issued_min = 480          # 08:00
	_check(a.state(480) == AtisBroadcast.FRESH, "刚发布是有效")
	_check(a.state(529) == AtisBroadcast.FRESH, "49 分钟仍有效")
	_check(a.state(530) == AtisBroadcast.AGING, "50 分钟算即将过期")
	_check(a.state(539) == AtisBroadcast.AGING, "59 分钟仍是将要过期")
	_check(a.state(540) == AtisBroadcast.EXPIRED, "60 分钟算已过期")
	_check(a.state(600) == AtisBroadcast.EXPIRED, "两小时后当然过期")
	_check(AtisBroadcast.state_text(AtisBroadcast.EXPIRED) == "已过期", "状态文案")

	# 跨零点：23:50 发布，00:10 只过了 20 分钟
	var b := AtisBroadcast.new()
	b.issued_min = 23 * 60 + 50
	_check(b.state(10) == AtisBroadcast.FRESH, "跨零点不误判过期",
		str(b.age(10)))
	_check(b.age(10) == 20, "跨零点时长算对", str(b.age(10)))


func _test_vis() -> void:
	_section("能见度解析")
	_check(AtisBroadcast.vis_meters("CAVOK") == 9999, "CAVOK 按 9999")
	_check(AtisBroadcast.vis_meters("8KM") == 8000, "8KM = 8000")
	_check(AtisBroadcast.vis_meters("800M") == 800, "800M = 800")
	_check(AtisBroadcast.vis_meters("3000") == 3000, "纯数字")
	_check(AtisBroadcast.vis_meters("") == -1, "空值认不出来")


func _test_major() -> void:
	_section("重大变化阈值")
	# 风向差 80°，两边风速都 ≥5 m/s → 重大变化
	_check(AtisBroadcast.major_change("18005MPS", "9999", "26005MPS", "9999") != "",
		"风向变化 ≥60° 且风速够 → 重大变化")
	# 风向差够但风速不足 → 不算
	_check(AtisBroadcast.major_change("18003MPS", "9999", "26003MPS", "9999") == "",
		"风速 <5 m/s 不算重大变化")
	# 风向差 40° → 不算
	_check(AtisBroadcast.major_change("18006MPS", "9999", "22006MPS", "9999") == "",
		"风向变化 <60° 不算")
	# 能见度跨 800 米
	_check(AtisBroadcast.major_change("18005MPS", "9999", "18005MPS", "500M") != "",
		"能见度从 >800 掉到 <800")
	_check(AtisBroadcast.major_change("18005MPS", "500M", "18005MPS", "CAVOK") != "",
		"能见度从 <800 恢复到 >800")
	_check(AtisBroadcast.major_change("18005MPS", "9999", "18005MPS", "3000M") == "",
		"两边都 >800 不算")


func _airport() -> Dictionary:
	return {
		"icao": "ZDEM",
		"clock_start": "0800",
		"runways": [{"id": "18", "heading_deg": 180, "length_m": 3200},
			{"id": "36", "heading_deg": 360, "length_m": 3200}],
		"frequencies": {"delivery": "121.950", "ground": "121.750",
			"tower": "118.100", "approach": "119.000", "center": "125.600",
			"apron": "121.800"},
		"weather": {"wind": "18005MPS", "visibility": "CAVOK",
			"qnh_hpa": 1013, "temperature_c": 18},
		"atis": "INFO A",
		"atis_alpha": "A",
	}


func _desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(2026)
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.apply_field(_airport())
	d.enable_atis_lifecycle = true
	d.set_plan([{"callsign": "ATI001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	return d


func _test_update() -> void:
	_section("更新通播")
	var d := _desk()
	_check(d.atis.alpha == "A", "开局沿用机场数据的代号", d.atis.alpha)
	_check(d.atis.qnh == 1013, "开局带上修正海压", str(d.atis.qnh))

	# 按实况更新 → 代号 +1，没有错误
	var r := d.update_atis({}, 0.0)
	_check(bool(r.ok), "更新成功", String(r.error))
	_check(d.atis.alpha == "B", "代号自动推进到 B", d.atis.alpha)
	_check(not d.atis.has_error, "按实况更新不算有误")
	_check(d.atis.update_count == 1, "计一次更新")

	# 玩家把 QNH 选错 → 记 has_error，但仍然发布
	var r2 := d.update_atis({"qnh": 1018}, 60.0)
	_check(bool(r2.ok), "选错值也允许发布", String(r2.error))
	_check(d.atis.has_error, "选了与实况不符的值被标记")
	_check(d.atis.alpha == "C", "再推进到 C")

	# 缺 QNH 不给发
	var r3 := d.update_atis({"qnh": 0}, 120.0)
	_check(not bool(r3.ok), "没有 QNH 不允许发布", String(r3.error))
	_check(d.atis.alpha == "C", "被拒绝时代号不推进")

	# 存档往返
	var back := AtisBroadcast.from_dict(d.atis.to_dict())
	_check(back.alpha == d.atis.alpha, "代号往返")
	_check(back.qnh == d.atis.qnh, "QNH 往返")
	_check(back.has_error == d.atis.has_error, "错误标记往返")


func _test_gate() -> void:
	_section("过期闸门与两种处置")
	var d := _desk()
	var f := d.get_flight("ATI001")
	# 开局时通播刚发布 → 可以放行
	_check(d.atis_gate_ok(f), "有效期内可以放行")

	# 推到 70 分钟之后：过期
	var later := 70.0 * 60.0
	d.tick(later)
	_check(d.atis_expired, "超过 60 分钟被标记过期")
	var r := d.issue_clearance("ATI001", "RUMUK 8D", 6000, "1234", later)
	_check(not bool(r.ok), "过期时不许放行", String(r.error))
	_check(String(r.error).contains("通播"), "提示说明是通播问题",
		String(r.error))

	# 处置一：通知最新通播
	var n := d.notify_latest_atis("ATI001", later)
	_check(bool(n.ok), "通知动作成功")
	_check(f.atis_notified, "机组被标记已处置")
	_check(d.atis_gate_ok(f), "处置之后闸门放行")
	var r2 := d.issue_clearance("ATI001", "RUMUK 8D", 6000, "1234", later)
	_check(bool(r2.ok), "可以放行了", String(r2.error))

	# 更新通播也会解除过期
	var d2 := _desk()
	d2.tick(70.0 * 60.0)
	_check(d2.atis_expired, "第二局同样过期")
	d2.update_atis({}, 70.0 * 60.0)
	_check(not d2.atis_expired, "更新之后不再过期")
	_check(d2.atis_gate_ok(d2.get_flight("ATI001")), "更新后闸门放行")


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
