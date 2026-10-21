## 气象解析 / 通播生成 / 当日计划的无头测试。
##
## 这三块都是纯逻辑，与界面无关，所以能在这里逐条钉死。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_info.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 气象 / 通播 / 当日计划测试 ════════")
	_test_wind()
	_test_components()
	_test_clock()
	_test_atis()
	_test_plan()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _test_wind() -> void:
	_section("风组解析")

	var a := Meteo.parse_wind("18005MPS")
	_check(bool(a.get("ok", false)), "18005MPS 可解析")
	_check(int(a.get("dir", 0)) == 180, "风向 180", str(a))
	_check(int(a.get("speed", 0)) == 5, "风速 5", str(a))
	_check(String(a.get("unit", "")) == "MPS", "单位 MPS", str(a))

	var b := Meteo.parse_wind("27012G20KT")
	_check(bool(b.get("ok", false)), "27012G20KT 可解析")
	_check(int(b.get("dir", 0)) == 270, "风向 270", str(b))
	_check(int(b.get("speed", 0)) == 12, "风速 12", str(b))
	_check(int(b.get("gust", 0)) == 20, "阵风 20", str(b))
	_check(String(b.get("unit", "")) == "KT", "单位 KT", str(b))

	var c := Meteo.parse_wind("VRB03KT")
	_check(bool(c.get("ok", false)) and bool(c.get("variable", false)), "VRB 标记为风向不定")

	_check(not bool(Meteo.parse_wind("").get("ok", true)), "空串解析失败")
	_check(not bool(Meteo.parse_wind("1805MPS").get("ok", true)),
		"风向不足三位判定失败（否则 18/05 会被读错）")
	_check(not bool(Meteo.parse_wind("ABC").get("ok", true)), "乱码判定失败")

	_check(absf(Meteo.to_mps(10.0, "KT") - 5.144) < 0.001, "10 KT 约 5.144 m/s",
		str(Meteo.to_mps(10.0, "KT")))
	_check(absf(Meteo.to_mps(7.0, "MPS") - 7.0) < 0.0001, "MPS 原样返回")


func _test_components() -> void:
	_section("跑道风分量")

	# 风 180° 5 m/s，落在 18 号跑道（航向 180）上：正顶风
	var r18 := Meteo.runway_wind("18005MPS", 180.0)
	_check(bool(r18.get("ok", false)), "18 号跑道可算")
	_check(absf(float(r18.get("headwind", 0.0)) - 5.0) < 0.001, "18 号跑道顶风 5",
		str(r18.get("headwind")))
	_check(absf(float(r18.get("crosswind", 0.0))) < 0.001, "18 号跑道无侧风",
		str(r18.get("crosswind")))

	# 同一股风对 36 号跑道就是顺风
	var r36 := Meteo.runway_wind("18005MPS", 360.0)
	_check(float(r36.get("headwind", 0.0)) < -4.99, "36 号跑道为顺风 5",
		str(r36.get("headwind")))

	# 风从 180°（正南）来，飞机向东落地（航向 090）：风从右侧来
	var r09 := Meteo.runway_wind("18005MPS", 90.0)
	_check(absf(float(r09.get("headwind", 9.0))) < 0.001, "09 号跑道顶风为 0",
		str(r09.get("headwind")))
	_check(float(r09.get("crosswind", 0.0)) > 4.99, "09 号跑道侧风为右 5",
		str(r09.get("crosswind")))

	_check(not bool(Meteo.runway_wind("VRB03KT", 180.0).get("ok", true)),
		"风向不定时不硬算分量")

	_check(Meteo.is_crosswind_high(16.0), "16 m/s 侧风判定为超限")
	_check(not Meteo.is_crosswind_high(8.0), "8 m/s 侧风不算超限")


func _test_clock() -> void:
	_section("仿真时码")
	_check(Atis.clock_text("0755", 0.0) == "0755", "起点时刻", Atis.clock_text("0755", 0.0))
	_check(Atis.clock_text("0755", 300.0) == "0800", "过了 5 分钟",
		Atis.clock_text("0755", 300.0))
	_check(Atis.clock_text("0755", 3600.0) == "0855", "过了一小时",
		Atis.clock_text("0755", 3600.0))
	_check(Atis.clock_text("2350", 900.0) == "0005", "跨零点回绕",
		Atis.clock_text("2350", 900.0))
	_check(Atis.clock_text("", 0.0) == "0800", "非法起点回落到 08:00",
		Atis.clock_text("", 0.0))


func _test_atis() -> void:
	_section("通播全文")

	var airport := {
		"icao": "ZDEM",
		"clock_start": "0755",
		"atis_alpha": "B",
		"runways": [{"id": "18", "heading_deg": 180}],
		"weather": {"wind": "18005MPS", "visibility": "CAVOK",
			"qnh_hpa": 1013, "temperature_c": 18},
	}
	var t := Atis.compose(airport, 0.0)
	_check(t.contains("ZDEM"), "含机场四字码")
	_check(t.contains("通播 B"), "含通播字母")
	_check(t.contains("0755"), "含时刻")
	_check(t.contains("使用跑道 18"), "含使用跑道")
	_check(t.contains("地面风 180 度 5 米每秒"), "风组转成人话", t)
	_check(t.contains("CAVOK"), "含能见度")
	_check(t.contains("修正海压 1013"), "含修正海压")
	_check(t.contains("温度 18"), "含温度")
	_check(not t.contains("露点"), "没有露点数据就不写露点")

	var gusty := airport.duplicate(true)
	gusty["weather"] = {"wind": "27012G20KT", "visibility": "8000",
		"qnh_hpa": 1008, "temperature_c": 22}
	var t2 := Atis.compose(gusty, 0.0)
	_check(t2.contains("阵风 20 节"), "阵风按原始单位表述", t2)

	_check(Atis.compose({}, 0.0).contains("不可用"), "空机场数据给出明确提示")


func _test_plan() -> void:
	_section("当日计划")

	var plan: Array = [
		{"std": "0800", "callsign": "CCA1501", "type": "B738", "dest": "ZBAA",
			"stand": "A05", "sid": "RUMUK 8D", "alt": 6000},
		{"std": "0815", "callsign": "CES2302", "type": "A320", "dest": "ZSPD",
			"stand": "A12", "sid": "BETON 3A", "alt": 5000},
	]

	var desk := DeliveryDesk.new()
	desk.setup(1234)
	desk.set_plan(plan)

	var f1 := desk.spawn_request(0.0)
	_check(f1.callsign == "CCA1501", "第一架取计划首条", f1.callsign)
	_check(f1.type == "B738", "机型来自计划", f1.type)
	_check(f1.stand == "A05", "机位来自计划", f1.stand)
	_check(f1.destination == "ZBAA", "目的地来自计划", f1.destination)
	_check(f1.sid == "RUMUK 8D", "离场程序来自计划", f1.sid)
	_check(f1.initial_alt_m == 6000, "初始高度来自计划", str(f1.initial_alt_m))
	_check(f1.planned_std == "0800", "带上计划时刻", f1.planned_std)
	_check(desk.plan_index == 1, "计划进度推进", str(desk.plan_index))

	var f2 := desk.spawn_request(10.0)
	_check(f2.callsign == "CES2302", "第二架取计划次条", f2.callsign)
	_check(desk.plan_index == 2, "计划进度到 2", str(desk.plan_index))

	# 计划用完：退回随机，且不能再撞已占用的机位
	var f3 := desk.spawn_request(20.0)
	_check(f3 != null and f3.callsign != "", "计划用完后仍能生成航班", str(f3.callsign))
	var used := {"A05": true, "A12": true}
	_check(not used.has(f3.stand), "随机补的航班避开已占用机位", f3.stand)
	_check(desk.plan_index == 2, "计划进度不因随机航班前进", str(desk.plan_index))

	# 计划机位已被占用时必须改派
	var desk2 := DeliveryDesk.new()
	desk2.setup(99)
	var squatter := desk2.spawn_request(0.0)
	squatter.stand = "A07"
	desk2.set_plan([{"std": "0900", "callsign": "CHH1120", "type": "B789",
		"dest": "ZUUU", "stand": "A07", "sid": "KAMAN 2C", "alt": 4000}])
	var f4 := desk2.spawn_request(5.0)
	_check(f4.callsign == "CHH1120", "呼号仍按计划", f4.callsign)
	_check(f4.stand != "A07", "计划机位被占时改派其他机位", f4.stand)

	# 存档往返
	var desk3 := DeliveryDesk.new()
	desk3.setup(7)
	desk3.set_plan(plan)
	desk3.spawn_request(0.0)
	var back := DeliveryDesk.from_dict(desk3.to_dict())
	_check(back.plan.size() == 2, "存档带回计划条目", str(back.plan.size()))
	_check(back.plan_index == 1, "存档带回计划进度", str(back.plan_index))
	_check(back.flights.size() == 1, "存档带回航班", str(back.flights.size()))
	_check(String((back.flights[0] as Flight).planned_std) == "0800", "航班计划时刻随存档保留")

	# 没有计划时行为不变（老存档 / 单元测试都走这条路）
	var plain := DeliveryDesk.new()
	plain.setup(5)
	var p1 := plain.spawn_request(0.0)
	_check(p1.planned_std == "", "无计划时 planned_std 为空")
	_check(p1.callsign != "", "无计划时照样能生成航班")


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
