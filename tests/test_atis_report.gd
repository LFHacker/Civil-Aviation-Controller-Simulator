## 07 §2.3 / §7：机组申请通话里的 ATIS 抄收状态分级。
##
## 文档口径：
##   简易 100% 报现行代号；进阶 80% 现行 + 20% 没抄收；高阶 60 / 20 / 20（20% 报过期代号）。
## 报过期代号时通话里照旧说"已收到通播 X"，管制员要自己听出代号不对。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_atis_report.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ ATIS 抄收状态分级（07 §2.3 / §7） ════════")
	_test_prev_alpha()
	_test_rates_easy()
	_test_rates_normal()
	_test_rates_hard()
	_test_expired_table()
	_test_stale_depth()
	_test_error_atis_reports_current()
	_test_request_text()
	_test_require_atis()
	_test_gate_effect()
	_test_deterministic()
	_test_check_disabled()
	_test_save_roundtrip()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- 夹具

func _desk(seed_value: int = 606) -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(seed_value)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.atis.alpha = "A"
	d.atis.runway = "18"
	d.atis.qnh = 1013
	return d


## 跑 n 次掷骰，返回三种状态的计数。
func _sample(d: DeliveryDesk, n: int) -> Array:
	var c := [0, 0, 0]
	for i in range(n):
		var r := d.roll_atis_report()
		if r < 0 or r > 2:
			c[0] = -9999
		else:
			c[r] += 1
	return c


## 同上，但按"通波已过期"那张表掷。
func _sample_expired(d: DeliveryDesk, n: int) -> Array:
	var c := [0, 0, 0]
	for i in range(n):
		c[d.roll_atis_report(true)] += 1
	return c


# ---------------------------------------------------------------- 用例

func _test_prev_alpha() -> void:
	_section("过期代号 = 上一版（Z 之后回 A 的镜像）")
	_check(AtisBroadcast.prev_alpha("B") == "A", "B 的上一版是 A",
		AtisBroadcast.prev_alpha("B"))
	_check(AtisBroadcast.prev_alpha("A") == "Z", "A 的上一版是 Z（跨零点）",
		AtisBroadcast.prev_alpha("A"))
	_check(AtisBroadcast.prev_alpha("Z") == "Y", "Z 的上一版是 Y",
		AtisBroadcast.prev_alpha("Z"))
	_check(AtisBroadcast.prev_alpha(" a ") == "Z", "小写带空格也认",
		AtisBroadcast.prev_alpha(" a "))
	_check(AtisBroadcast.prev_alpha("") == "Z", "非法输入退回 Z",
		AtisBroadcast.prev_alpha(""))
	# 与 next_alpha 互为逆运算
	var a := "D"
	_check(AtisBroadcast.prev_alpha(AtisBroadcast.next_alpha(a)) == a,
		"prev(next(x)) == x")


func _test_rates_easy() -> void:
	_section("简易模式：永远报现行代号")
	var d := _desk()
	d.difficulty = "easy"
	var c := _sample(d, 300)
	_check(c[0] == 300, "300 次全是现行代号", str(c))
	_check(c[1] == 0, "不会没抄收", str(c))
	_check(c[2] == 0, "不会报过期代号", str(c))
	_check(is_equal_approx(d.atis_stale_chance(), 0.0), "过期概率 0",
		str(d.atis_stale_chance()))


func _test_rates_normal() -> void:
	_section("进阶模式：80% 现行 + 20% 没抄收")
	var d := _desk()
	d.difficulty = "normal"
	var c := _sample(d, 400)
	var cur := float(c[0]) / 400.0
	var miss := float(c[1]) / 400.0
	_check(c[2] == 0, "进阶模式不出现过期代号（文档只给高阶）", str(c))
	_check(cur > 0.72 and cur < 0.88, "现行比例约 80%", "%.2f" % cur)
	_check(miss > 0.12 and miss < 0.28, "没抄收比例约 20%", "%.2f" % miss)
	_check(is_equal_approx(d.atis_stale_chance(), 0.0), "过期概率 0")


func _test_rates_hard() -> void:
	_section("高阶模式：60% 现行 + 20% 没抄收 + 20% 过期")
	var d := _desk()
	d.difficulty = "hard"
	var c := _sample(d, 600)
	var cur := float(c[0]) / 600.0
	var miss := float(c[1]) / 600.0
	var stale := float(c[2]) / 600.0
	_check(c[0] > 0 and c[1] > 0 and c[2] > 0, "三种形态都会出现", str(c))
	_check(cur > 0.52 and cur < 0.68, "现行比例约 60%", "%.2f" % cur)
	_check(miss > 0.13 and miss < 0.27, "没抄收比例约 20%", "%.2f" % miss)
	_check(stale > 0.13 and stale < 0.27, "过期比例约 20%", "%.2f" % stale)
	_check(is_equal_approx(d.atis_stale_chance(), 0.2), "过期概率 20%",
		str(d.atis_stale_chance()))


## 07 §4.2 第二行：通波已过期（>1 小时未更新）时，概率整张表换掉。
func _test_expired_table() -> void:
	_section("通波已过期时概率换表（07 §4.2 第二行）")
	# 进阶：有效时 80/20/0，过期后 50/30/20
	var dn := _desk(3030)
	dn.difficulty = "normal"
	dn.enable_atis_lifecycle = true
	dn.atis.issued_min = dn.now_minutes(0.0) - 120   # 两小时前发布 → 已过期
	_check(dn.atis_state(0.0) == AtisBroadcast.EXPIRED, "夹具里通波确实过期了",
		str(dn.atis_state(0.0)))
	var cn := _sample_expired(dn, 500)
	var cur := float(cn[0]) / 500.0
	var miss := float(cn[1]) / 500.0
	var stale := float(cn[2]) / 500.0
	_check(cur > 0.42 and cur < 0.58, "过期后现行比例降到约 50%", "%.2f" % cur)
	_check(miss > 0.22 and miss < 0.38, "没抄收升到约 30%", "%.2f" % miss)
	_check(stale > 0.13 and stale < 0.27, "开始出现过期代号（约 20%）", "%.2f" % stale)

	# 高阶：有效时 60/20/20，过期后 30/20/50
	var dh := _desk(3031)
	dh.difficulty = "hard"
	dh.enable_atis_lifecycle = true
	dh.atis.issued_min = dh.now_minutes(0.0) - 120
	var ch := _sample_expired(dh, 600)
	var sth := float(ch[2]) / 600.0
	_check(sth > 0.42 and sth < 0.58, "高阶过期后过期代号升到约 50%", "%.2f" % sth)
	_check(is_equal_approx(dh.atis_stale_chance(true), 0.5), "过期表里过期概率 50%",
		str(dh.atis_stale_chance(true)))
	_check(is_equal_approx(dh.atis_stale_chance(false), 0.2), "有效表里还是 20%",
		str(dh.atis_stale_chance(false)))

	# 简易任何通波状态都报现行代号
	var de := _desk(3032)
	de.difficulty = "easy"
	de.enable_atis_lifecycle = true
	de.atis.issued_min = de.now_minutes(0.0) - 120
	var ce := _sample_expired(de, 200)
	_check(ce == [200, 0, 0], "简易模式过期也照报现行代号", str(ce))


## 过期代号往回退几个字母：有效 1–2 个，已过期 1–3 个（§4.2）。
func _test_stale_depth() -> void:
	_section("过期代号往回退几个字母（07 §4.2）")
	var d := _desk(4040)
	var seen2 := {}
	for i in range(200):
		seen2[d.stale_alpha_of("D", DeliveryDesk.ATIS_STALE_BACK_VALID)] = true
	var keys := seen2.keys()
	keys.sort()
	_check(keys == ["B", "C"], "有效通波：D 退 1–2 个 = B/C", str(keys))

	var seen3 := {}
	for i in range(300):
		seen3[d.stale_alpha_of("D", DeliveryDesk.ATIS_STALE_BACK_EXPIRED)] = true
	var keys3 := seen3.keys()
	keys3.sort()
	_check(keys3 == ["A", "B", "C"], "过期通波：D 退 1–3 个 = A/B/C", str(keys3))
	# 跨 A 回绕
	var seenz := {}
	for i in range(300):
		seenz[d.stale_alpha_of("A", DeliveryDesk.ATIS_STALE_BACK_EXPIRED)] = true
	var keysz := seenz.keys()
	keysz.sort()
	_check(keysz == ["X", "Y", "Z"], "A 往回退会绕到 X/Y/Z", str(keysz))


## §4.2 第三行：通波被玩家选错了气象值时，机组照样报现行代号。
func _test_error_atis_reports_current() -> void:
	_section("通波含错误值时照报现行代号（07 §4.2 第三行）")
	var d := _desk(5050)
	d.difficulty = "hard"
	d.enable_atis_check = true
	d.enable_atis_lifecycle = true
	# 把通播 QNH 写错 → has_error
	var o := d.atis_edit_options()
	d.update_atis({"qnh": (o.qnh as Array)[3]}, 0.0)
	_check(d.atis.has_error, "通播被标记为与实况不符")
	for i in range(30):
		var f := d.spawn_request(0.0)
		if f.atis_report != 0:
			_check(false, "第 %d 架报了非现行代号（%d）" % [i, f.atis_report],
				f.atis_reported)
			return
	_check(true, "30 架全都报现行代号（高阶原本有 20% 会报过期）")


## 三种形态分别落到通话文本、atis_ok、atis_reported 上。
func _test_request_text() -> void:
	_section("申请通话随抄收状态变化（07 §2.3）")
	var d := _desk(2024)
	d.difficulty = "hard"
	d.enable_atis_check = true
	# 不放计划，随机生成足够多的航班把三种形态都撞出来
	for i in range(80):
		d.spawn_request(0.0)
	var seen := {0: 0, 1: 0, 2: 0}
	var stale_flight: Flight = null
	var missing_flight: Flight = null
	var current_flight: Flight = null
	for f in d.flights:
		if seen.has(f.atis_report):
			seen[f.atis_report] = int(seen[f.atis_report]) + 1
		if f.atis_report == 2 and stale_flight == null:
			stale_flight = f
		elif f.atis_report == 1 and missing_flight == null:
			missing_flight = f
		elif f.atis_report == 0 and current_flight == null:
			current_flight = f
	_check(stale_flight != null, "80 架里出现了报过期代号的", str(seen))
	_check(missing_flight != null, "80 架里出现了没抄收的", str(seen))
	_check(current_flight != null, "80 架里出现了报现行代号的", str(seen))

	if stale_flight != null:
		_check(stale_flight.atis_ok == false, "报过期代号不算抄收有效（离场情报不能省）")
		# §4.2：通波有效时报的过期代号是"前 1–2 个字母"（现行 A → Y 或 Z）
		_check(stale_flight.atis_reported == "Y" or stale_flight.atis_reported == "Z",
			"报的是前 1–2 个字母（Y 或 Z）", stale_flight.atis_reported)
		_check(stale_flight.atis_reported != "A", "不是现行代号", stale_flight.atis_reported)
		var row := _pilot_request_row(d, stale_flight.callsign)
		_check(row != "", "有这通申请记录", stale_flight.callsign)
		_check(row.contains("已收到通播 " + stale_flight.atis_reported),
			"通话里说的是它自己报的那个代号", row)
		_check(not row.contains("已收到通播 A"), "不会误报现行代号 A", row)

	if missing_flight != null:
		_check(missing_flight.atis_ok == false, "没抄收不算抄收有效")
		var row := _pilot_request_row(d, missing_flight.callsign)
		_check(row != "", "有这通申请记录", missing_flight.callsign)
		_check(not row.contains("通播"), "没抄收时通话里不提通播", row)

	if current_flight != null:
		_check(current_flight.atis_ok == true, "报现行代号即抄收有效")
		_check(current_flight.atis_reported == "A",
			"报的是现行代号 A", current_flight.atis_reported)
		var row := _pilot_request_row(d, current_flight.callsign)
		_check(row.contains("已收到通播 A"), "通话里说现行代号 A", row)


## 管制要求机组补收通播后，状态要归到"现行"。
func _test_require_atis() -> void:
	_section("要求补收通播后状态归零（08 §3.2）")
	var d := _desk(11)
	d.difficulty = "hard"
	d.enable_atis_check = true
	var f: Flight = null
	for i in range(60):
		var nf := d.spawn_request(0.0)
		if nf.atis_report != 0:
			f = nf
			break
	_check(f != null, "找到一架没抄收/报错的")
	if f == null:
		return
	var before := f.atis_report
	var r := d.require_atis(f.callsign, 0.0)
	_check(bool(r.ok), "要求补收成功", String(r.error))
	_check(f.atis_report == 0, "状态归到现行（原 %d）" % before, str(f.atis_report))
	_check(f.atis_ok, "算作抄收有效")
	_check(f.atis_reported == d.atis.alpha, "记录的是现行代号",
		f.atis_reported)
	var r2 := d.require_atis(f.callsign, 0.0)
	_check(not bool(r2.ok), "已经抄收的不能再要求补收", String(r2.error))


## 报过期代号时，离场情报不能被"机组已抄收"省略。
func _test_gate_effect() -> void:
	_section("报过期代号不豁免离场情报（§5.2）")
	var d := _desk(31)
	d.enable_atis_check = true
	d.enable_dep_info = true
	var f: Flight = null
	for i in range(80):
		var nf := d.spawn_request(0.0)
		if nf.atis_report != 0:
			f = nf
			break
	if f == null:
		# 这档难度只会有 0/1，报告"没抄收"也满足本用例
		f = d.spawn_request(0.0)
	_check(f != null, "有航班可用于比对")
	if f == null:
		return
	var miss := d.dep_info_missing(f)
	_check(miss > 0, "没抄收/报错时存在必须通报的条目", str(miss))
	# 把状态改成现行后，可省条目变少
	f.atis_ok = true
	f.atis_report = 0
	var miss2 := d.dep_info_missing(f)
	_check(miss2 < miss, "抄收现行后条目变少", "%d -> %d" % [miss, miss2])


## 同一 seed 必须掷出同一串结果（错误注入可复现，07 §5）。
func _test_deterministic() -> void:
	_section("随机可复现（07 §8 随机种子管理器）")
	var a := _desk(707)
	a.difficulty = "hard"
	var b := _desk(707)
	b.difficulty = "hard"
	var seq_a: Array = []
	var seq_b: Array = []
	for i in range(30):
		seq_a.append(a.roll_atis_report())
		seq_b.append(b.roll_atis_report())
	_check(seq_a == seq_b, "同 seed 两次序列完全一致", str(seq_a))
	var c := _desk(708)
	c.difficulty = "hard"
	var seq_c: Array = []
	for i in range(30):
		seq_c.append(c.roll_atis_report())
	_check(seq_a != seq_c, "换 seed 序列不同")


## 关掉检查时一律按"已抄收现行"处理（老存档/单元测试兼容）。
func _test_check_disabled() -> void:
	_section("关闭检查时一律现行")
	var d := _desk(99)
	d.difficulty = "hard"
	d.enable_atis_check = false
	for i in range(20):
		var f := d.spawn_request(0.0)
		if f.atis_report != 0 or not f.atis_ok:
			_check(false, "第 %d 架不该有抄收状态偏差" % i, str(f.atis_report))
			return
	_check(true, "20 架全是现行代号")


func _test_save_roundtrip() -> void:
	_section("存档往返（07 §十 数据通道）")
	var f := Flight.new()
	f.callsign = "ATSRT1"
	f.atis_report = 2
	f.atis_reported = "Z"
	f.atis_ok = false
	var back := Flight.from_dict(f.to_dict())
	_check(back.atis_report == 2, "atis_report 往返", str(back.atis_report))
	_check(back.atis_reported == "Z", "atis_reported 往返", back.atis_reported)
	_check(back.atis_ok == false, "atis_ok 往返")
	# 老存档没有这个字段时按 0 处理，不会崩
	var d := f.to_dict()
	d.erase("atis_report")
	var old := Flight.from_dict(d)
	_check(old.atis_report == 0, "缺字段时退回 0", str(old.atis_report))


# ---------------------------------------------------------------- 工具

## 取该机组的首条申请通话（transcript 里 side == "pilot" 且带"申请放行"）。
func _pilot_request_row(d: DeliveryDesk, callsign: String) -> String:
	for row in d.transcript:
		var r: Dictionary = row
		if String(r.get("side", "")) != "pilot":
			continue
		var text := String(r.get("text", ""))
		if text.contains(callsign) and text.contains("申请放行"):
			return text
	return ""


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
