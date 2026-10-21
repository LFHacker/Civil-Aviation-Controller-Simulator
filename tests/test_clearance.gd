## 放行许可要素 / 离场情报 / 通播确认的测试。
##
## 依据《民用航空空中交通管理规则》：
##   第二百九十一条 —— 放行许可七项内容
##   第二百九十四条 —— 离场情报，已从通播收到的不必重复，但仍须给高度表拨正值
##   第一百五十九条 —— 建立联络应当表明已收到通播
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_clearance.gd
extends SceneTree

var _checks := 0
var _fails := 0

const AIRPORT := {
	"id": "DEMO",
	"icao": "ZDEM",
	"clock_start": "0755",
	"atis_alpha": "A",
	"runways": [{"id": "18", "heading_deg": 180}],
	"frequencies": {"delivery": "121.950", "approach": "119.000"},
	"weather": {"wind": "18005MPS", "visibility": "CAVOK",
		"qnh_hpa": 1013, "temperature_c": 18},
}


func _initialize() -> void:
	print("")
	print("════════ 放行许可要素测试 ════════")
	_test_elements()
	_test_departure_info()
	_test_atis()
	_test_route()
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
	d.setup(4242)
	d.apply_field(AIRPORT)
	return d


func _test_elements() -> void:
	_section("许可七项要素")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CCA1501")
	f.destination = "ZBAA"
	f.clearance_limit = "ZBAA"
	var r := d.issue_clearance("CCA1501", "RUMUK 8D", 6000, "4521", 1.0)
	_check(r.ok, "许可发放成功", String(r.error))

	var t := DeliveryDesk.clearance_text(f)
	_check(t.find("CCA1501") >= 0, "①识别标志", t)
	_check(t.find("ZBAA") >= 0, "②许可界限", t)
	_check(t.find("RUMUK 8D") >= 0, "③离场程序", t)
	_check(t.find("W105 LADIX") >= 0, "④飞行航路", t)
	_check(t.find("6000") >= 0, "⑤飞行高度", t)
	_check(t.find("4521") >= 0, "⑥应答机编码", t)
	_check(t.find("119.000") >= 0, "⑦必要的管制指令（进近频率）", t)
	_check(t.ends_with("。"), "以句号收尾")

	# 换离场程序 → 航路必须跟着换
	d.issue_clearance("CCA1501", "BETON 3A", 5000, "4521", 2.0)
	# 第二次会因为仍在等待复诵被拒，这里只验证拒绝不影响已写字段
	var g := d.get_flight("CCA1501")
	_check(g.route == "W105 LADIX", "被拒绝的重发不改动原航路", g.route)


func _test_departure_info() -> void:
	_section("离场情报（第二百九十四条）")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CES2302")
	f.atis_ok = true
	var got_atis := d.departure_info_text(f)
	_check(got_atis.find("1013") >= 0, "已收到通播时仍给修正海压", got_atis)
	_check(got_atis.find("使用跑道") < 0, "已收到通播时不重复跑道", got_atis)
	_check(got_atis.find("地面风") < 0, "已收到通播时不重复风", got_atis)

	f.atis_ok = false
	var no_atis := d.departure_info_text(f)
	_check(no_atis.find("使用跑道 18") >= 0, "未收到通播时给使用跑道", no_atis)
	_check(no_atis.find("18005MPS") >= 0, "未收到通播时给地面风", no_atis)
	_check(no_atis.find("CAVOK") >= 0, "未收到通播时给能见度", no_atis)
	_check(no_atis.find("1013") >= 0, "未收到通播时给修正海压", no_atis)

	var full := d.full_clearance_text(f)
	_check(full.find("许可放行至") >= 0, "完整通话含许可", full)
	_check(full.find("使用跑道") >= 0, "完整通话含离场情报", full)


func _test_atis() -> void:
	_section("通播确认（第一百五十九条）")

	var d := _new_desk()
	d.enable_atis_check = true
	var missing := 0
	for i in range(40):
		var f := d.spawn_request(float(i), "T%d" % i)
		if not f.atis_ok:
			missing += 1
	_check(missing > 0, "开着检查时会随机出现漏报通播的机组", "漏报 %d / 40" % missing)
	_check(missing < 40, "也不是全部漏报", "漏报 %d / 40" % missing)

	d.enable_atis_check = false
	var d2 := _new_desk()
	var ok_always := true
	for i in range(20):
		var f := d2.spawn_request(float(i), "U%d" % i)
		if not f.atis_ok:
			ok_always = false
	_check(ok_always, "关掉检查时默认都已收到通播（单元测试不受影响）")

	var d3 := _new_desk()
	var f3 := d3.spawn_request(0.0, "CHH1120")
	f3.atis_ok = false
	var before := d3.transcript.size()
	var r := d3.require_atis("CHH1120", 5.0)
	_check(r.ok, "要求收听通播成功", String(r.error))
	_check(f3.atis_ok, "机组改为已收到通播")
	_check(d3.transcript.size() == before + 2, "记录了一问一答两条",
		"%d -> %d" % [before, d3.transcript.size()])
	_check(not d3.require_atis("CHH1120", 6.0).ok, "已收到通播后不能重复要求")
	_check(not d3.require_atis("NOPE", 6.0).ok, "不存在的航班返回失败")


func _test_route() -> void:
	_section("航路与复诵")

	_check(DeliveryDesk.SID_ROUTES.size() == DeliveryDesk.SIDS.size(),
		"每个离场程序都配了航路",
		"%d / %d" % [DeliveryDesk.SID_ROUTES.size(), DeliveryDesk.SIDS.size()])
	var all_have := true
	for s in DeliveryDesk.SIDS:
		if String(DeliveryDesk.SID_ROUTES.get(s, "")) == "":
			all_have = false
	_check(all_have, "没有空航路")

	var rb := DeliveryDesk.readback_text_of("CCA1501", "ZBAA", "RUMUK 8D",
		"W105 LADIX", 6000, "4521")
	_check(rb.find("W105 LADIX") >= 0, "复诵里带航路（否则抓不到读错航路）", rb)
	_check(rb.find("ZBAA") >= 0, "复诵里带许可界限", rb)

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CSN7788")
	f.destination = "ZGGG"
	f.clearance_limit = "ZGGG"
	d.issue_clearance("CSN7788", "SASAN 5B", 4000, "1234", 0.0)
	d.tick(10.0)
	_check(f.state == Flight.State.READBACK, "到点产生复诵", f.state_text())
	_check(f.readback_text.find("ZGGG") >= 0, "复诵含许可界限", f.readback_text)


func _test_serialization() -> void:
	_section("新增字段随存档往返")

	var d := _new_desk()
	var f := d.spawn_request(0.0, "CQH8890")
	f.clearance_limit = "ZSPD"
	f.route = "B330 SASAN"
	f.dep_freq = "119.000"
	f.atis_ok = false

	var back := DeliveryDesk.from_dict(d.to_dict())
	_check(back.flights.size() == 1, "航班数量往返一致")
	var g: Flight = back.flights[0]
	_check(g.clearance_limit == "ZSPD", "许可界限往返一致", g.clearance_limit)
	_check(g.route == "B330 SASAN", "航路往返一致", g.route)
	_check(g.dep_freq == "119.000", "进近频率往返一致", g.dep_freq)
	_check(g.atis_ok == false, "通播确认状态往返一致")

	var field_ok := String(d.field.get("runway", "")) == "18" \
		and int(d.field.get("qnh", 0)) == 1013 \
		and String(d.field.get("dep_freq", "")) == "119.000"
	_check(field_ok, "本场要素从机场数据正确灌入", str(d.field))


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
