## AI 驾驶舱机制（07 文档）测试，无头可跑。
##
## 四件事：
## ① 机组对许可做完整性检查，命中必质疑项就质疑、且不改状态；
## ② 连续质疑到上限后机组接受（防死循环）；
## ③ 没人理时 60 秒一次重新呼叫，第三次之后转"机组等待中"；
## ④ 复诵错误注入按难度（0% / 30% / 60%，最多 0/1/2 处），纠正后减半。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_pilot.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ AI 驾驶舱测试 ════════")
	_test_query()
	_test_query_limit()
	_test_requery()
	_test_error_rate()
	_test_multi_error()
	_test_seed()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _desk(difficulty: String = "normal") -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(8888)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {
		"types": {}, "alternates": [], "routes": {},
		"loa": [{"sid": "RUMUK 8D", "alt_min": 5000, "alt_max": 7000}],
	}
	d.difficulty = difficulty
	d.pilot_check_enabled = true
	d.set_plan([{"callsign": "PLT001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	d.spawn_request(0.0)
	var f := d.get_flight("PLT001")
	f.checked = true
	return d


func _test_query() -> void:
	_section("完整性检查与质疑（§4.4 / §7 分级）")
	# 高度不在协议带：只有高阶模式才查（07 §7「质疑触发」表）
	var dh := _desk("hard")
	var fh := dh.get_flight("PLT001")
	var rh := dh.issue_clearance("PLT001", "RUMUK 8D", 3000, "1234", 0.0)
	_check(bool(rh.get("queried", false)), "高阶：机组对高度提出质疑", String(rh.error))
	_check(String(rh.error).contains("高度"), "质疑内容说高度", String(rh.error))
	_check(fh.state == Flight.State.PENDING, "状态没有推进（不能进入复诵）",
		str(fh.state))
	_check(fh.pilot_queries == 1, "质疑计数 +1", str(fh.pilot_queries))

	# 简易/进阶不查高度带：同样的越界高度照发不误
	var dn := _desk("normal")
	var rn := dn.issue_clearance("PLT001", "RUMUK 8D", 3000, "1234", 0.0)
	_check(not bool(rn.get("queried", false)), "进阶不查高度带（07 §7）",
		String(rn.error))
	var de := _desk("easy")
	var re := de.issue_clearance("PLT001", "RUMUK 8D", 3000, "1234", 0.0)
	_check(not bool(re.get("queried", false)), "简易不查高度带", String(re.error))

	# 应答机被另一架占用 → 质疑
	var d2 := _desk()
	var g := d2.get_flight("PLT001")
	d2.set_plan([{"callsign": "PLT002", "type": "A320", "dest": "ZSPD",
		"stand": "A06", "sid": "RUMUK 8D", "alt": 6000}])
	d2.spawn_request(0.0)
	var h := d2.get_flight("PLT002")
	h.checked = true
	h.squawk = "1234"
	# 先让第一架正常发出，编码就被占了
	var r0 := d2.issue_clearance("PLT001", "RUMUK 8D", 6000, "1234", 0.0)
	_check(bool(r0.ok), "第一架正常", String(r0.error))
	var r2 := d2.issue_clearance("PLT002", "RUMUK 8D", 6000, "1234", 1.0)
	_check(bool(r2.get("queried", false)), "编码被占用被质疑", String(r2.error))
	_check(String(r2.error).contains("占用"), "质疑内容说占用", String(r2.error))

	# 合规许可：不质疑，正常发
	var d3 := _desk()
	d3.get_flight("PLT001").squawk = "4321"
	var r3 := d3.issue_clearance("PLT001", "RUMUK 8D", 6000, "4321", 0.0)
	_check(not bool(r3.get("queried", false)), "合规许可不被质疑")
	_check(d3.get_flight("PLT001").state == Flight.State.SENT, "直接进入复诵")


func _test_query_limit() -> void:
	_section("连续质疑上限（§4.4 防死循环）")
	var d := _desk("hard")
	var f := d.get_flight("PLT001")
	var q1 := d.issue_clearance("PLT001", "RUMUK 8D", 3000, "1234", 0.0)
	var q2 := d.issue_clearance("PLT001", "RUMUK 8D", 3000, "1234", 1.0)
	_check(bool(q1.get("queried", false)) and bool(q2.get("queried", false)), "前两次都质疑")
	var q3 := d.issue_clearance("PLT001", "RUMUK 8D", 3000, "1234", 2.0)
	_check(not bool(q3.get("queried", false)), "第三次机组接受", String(q3.error))
	_check(f.state == Flight.State.SENT, "第三次进入复诵", str(f.state))


func _test_requery() -> void:
	_section("没人理时的重新呼叫（§4.3）")
	var d := _desk()
	var f := d.get_flight("PLT001")
	_check(f.request_count == 1, "开局算第一次呼叫")
	d.tick(59.0)
	_check(f.request_count == 1, "不到 60 秒不打扰")
	d.tick(60.5)
	_check(f.request_count == 2, "满 60 秒再叫一次", str(f.request_count))
	d.tick(121.0)
	_check(f.request_count == 3, "第三次呼叫", str(f.request_count))
	d.tick(182.0)
	_check(f.pilot_waiting, "三次之后机组等待中")
	var before := f.request_count
	d.tick(600.0)
	_check(f.request_count == before, "等待中不再呼叫", str(f.request_count))

	# 关掉机组检查时完全不打扰（老测试依赖这个）
	var d2 := _desk()
	d2.pilot_check_enabled = false
	var g := d2.get_flight("PLT001")
	d2.tick(600.0)
	_check(g.request_count == 1, "关闭时不重新呼叫", str(g.request_count))


func _test_error_rate() -> void:
	_section("复诵错误概率按难度（§4.6）")
	var easy := _desk("easy")
	_check(easy.readback_error_rate(easy.get_flight("PLT001")) == 0.0,
		"简易模式 0%")
	var normal := _desk("normal")
	_check(is_equal_approx(normal.readback_error_rate(normal.get_flight("PLT001")),
		0.30), "进阶模式 30%")
	var hard := _desk("hard")
	_check(is_equal_approx(hard.readback_error_rate(hard.get_flight("PLT001")),
		0.60), "高阶模式 60%")

	# 纠正一次概率减半，两次之后归零
	var f := normal.get_flight("PLT001")
	f.reissue_count = 1
	_check(is_equal_approx(normal.readback_error_rate(f), 0.15),
		"纠正一次减半", str(normal.readback_error_rate(f)))
	f.reissue_count = 2
	_check(normal.readback_error_rate(f) == 0.0, "纠正两次后不再读错")

	# 最多注入几处
	_check(easy.max_readback_errors() == 0, "简易不注入")
	_check(normal.max_readback_errors() == 1, "进阶最多 1 处")
	_check(hard.max_readback_errors() == 2, "高阶最多 2 处")


func _test_multi_error() -> void:
	_section("高阶模式一处以上错误")
	var d := _desk("hard")
	var f := d.get_flight("PLT001")
	d.force_error_next = true
	f.checked = true
	d.issue_clearance("PLT001", "RUMUK 8D", 6000, "4321", 0.0)
	d.tick(f.readback_at + 0.1)
	var bad := 0
	for it in f.readback_items:
		var x: Dictionary = it
		if bool(x.critical) and not bool(x.same):
			bad += 1
	_check(bad >= 1, "至少有 1 处读错", str(bad))
	# SID 读错会连带航路一起错，所以按"注入条数"判定，不按受影响项数
	var segs := f.readback_diff.split("；")
	_check(segs.size() <= 2, "注入的错误条数不超过 2", str(segs.size()))
	_check(f.readback_diff != "", "差异描述不为空", f.readback_diff)


func _test_seed() -> void:
	_section("同一随机种子结果可复现（§4.5 / §8）")
	var a := _run_seeded(4242)
	var b := _run_seeded(4242)
	_check(a == b, "同种子两次跑出一样的结果", "%s vs %s" % [a, b])
	var c := _run_seeded(9999)
	_check(typeof(c) == TYPE_STRING, "换种子也能跑完")


## 连开 4 架，把每次复诵的差异串起来当作指纹
func _run_seeded(seed_value: int) -> String:
	var d := DeliveryDesk.new()
	d.setup(seed_value)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.difficulty = "hard"
	var out := PackedStringArray()
	for i in range(4):
		var f := d.spawn_request(0.0)
		f.checked = true
		d.issue_clearance(f.callsign, f.sid, f.initial_alt_m, f.squawk, 0.0)
		d.tick(f.readback_at + 0.1)
		out.append(f.readback_diff)
	return "|".join(out)


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
