## 语音片段拼装（08 §4 语音档）测试，无头可跑。
##
## ① 数字/呼号的片段切分；
## ② 许可、复诵、首次呼叫、移交的片段序列完整且顺序正确；
## ③ 片段 id 全部能在清单里落地（生成音频前的一致性检查）。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_voice.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 语音片段测试 ════════")
	_test_digits()
	_test_callsign()
	_test_clearance()
	_test_readback()
	_test_other_lines()
	_test_manifest()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _test_digits() -> void:
	_section("数字片段")
	_check(Voice.digits("1200") == ["d1", "d2", "d0", "d0"],
		"1200 → d1 d2 d0 d0", str(Voice.digits("1200")))
	_check(Voice.digits("7309") == ["d7", "d3", "d0", "d9"],
		"7309 逐位切分", str(Voice.digits("7309")))
	_check(Voice.digits("").is_empty(), "空串没有片段")
	_check(Voice.digits("A1B").size() == 1, "字母被跳过，只留数字", str(Voice.digits("A1B")))
	_check(Voice.DIGITS.size() == 10 and Voice.DIGITS[1] == "幺"
		and Voice.DIGITS[7] == "拐" and Voice.DIGITS[9] == "勾",
		"数字读法与 Radio 一致（1=幺 7=拐 9=勾）")


func _test_callsign() -> void:
	_section("呼号片段")
	var c := Voice.callsign("CCA1501")
	_check(c == ["ap_CCA", "d1", "d5", "d0", "d1"],
		"CCA1501 → 公司片段 + 4 个数字", str(c))
	var c2 := Voice.callsign("CES5175")
	_check(c2[0] == "ap_CES", "CES 前缀能识别", str(c2))
	var c3 := Voice.callsign("3001")
	_check(c3 == ["d3", "d0", "d0", "d1"], "没有公司前缀时只读数字", str(c3))


func _test_clearance() -> void:
	_section("放行许可播报")
	var s := Voice.clearance("CCA1501", "18", "RUMUK8D", "W105", 6000, "4215", 1013)
	_check(s.size() > 15, "片段数量足够表达一条完整许可", str(s.size()))
	_check(s[0] == "ap_CCA", "开头是呼号（机组先听到叫自己）", str(s.slice(0, 3)))
	_check(s.has("p_clearance_to"), "含『许可放行至』")
	_check(s.has("p_initial_alt"), "含『初始高度』")
	_check(s.has("p_meter"), "高度后面跟『米』")
	_check(s.has("p_squawk"), "含『应答机』")
	_check(s.has("p_qnh"), "含『修正海压』")
	# 高度 6000 → 六洞洞洞 紧跟 米
	var i := s.find("p_initial_alt")
	_check(String(s[i + 5]) == "p_meter", "高度四位数字后紧跟『米』", str(s.slice(i, i + 6)))
	_check(s.count("p_clearance_to") == 1, "『许可放行至』只出现一次")


func _test_readback() -> void:
	_section("复诵播报")
	var r := Voice.readback("CES5175", "18", "SASAN5B", 6900, "4215", 1013)
	_check(r[0] == "p_clearance_to", "复诵不以呼号开头（机组接话）", str(r[0]))
	_check(r[r.size() - 1] == "d1" or r.has("ap_CES"), "结尾带呼号", str(r.slice(r.size() - 6)))
	var tail := r.slice(r.size() - 6)
	_check(tail.has("ap_CES"), "复诵末段是完整呼号", str(tail))
	# 复诵必须包含安全关键三项：高度、应答机、修正海压
	_check(r.has("p_initial_alt") and r.has("p_squawk") and r.has("p_qnh"),
		"三种安全关键项都在复诵里")


func _test_other_lines() -> void:
	_section("首次呼叫与移交")
	var q := Voice.request("CCA1501", "215", "ZSPD", true)
	_check(q[0] == "ap_CCA", "首次呼叫先报呼号")
	_check(q.has("p_atis_received"), "已抄收通播时明说")
	var q2 := Voice.request("CCA1501", "215", "ZSPD", false)
	_check(q2.has("p_not_received") and not q2.has("p_atis_received"),
		"未抄收时播另一句")
	var h := Voice.handoff("CCA1501", "121.7")
	_check(h.has("p_contact_ground"), "移交含『联系地面』")
	_check(h.has("p_goodbye"), "移交以『再见』结束")
	var i := h.find("p_contact_ground")
	_check(String(h[i + 1]).begins_with("d"), "地面频率按数字读（1-2-1-7）",
		str(h.slice(i, i + 6)))


func _test_manifest() -> void:
	_section("片段清单一致性")
	# 模板里出现的每个 id，都必须能在短语表或数字/公司表里找到
	var used: Array = []
	used.append_array(Voice.clearance("CCA1501", "18", "RUMUK8D", "W105", 6000, "4215", 1013))
	used.append_array(Voice.readback("CES5175", "18", "SASAN5B", 6900, "4215", 1013))
	used.append_array(Voice.request("CSN3001", "215", "ZSPD", true))
	used.append_array(Voice.handoff("CHH7801", "121.7"))
	var unknown: Array = []
	for id in used:
		var s := String(id)
		if s.begins_with(Voice.PHRASE_PREFIX):
			if not Voice.FIXED_PHRASES.has(s):
				unknown.append(s)
		elif s.begins_with(Voice.AIRLINE_PREFIX):
			if not Voice.AIRLINES.has(s.substr(Voice.AIRLINE_PREFIX.length())):
				unknown.append(s)
		elif s.begins_with(Voice.DIGIT_PREFIX):
			var d := s.substr(Voice.DIGIT_PREFIX.length())
			if not (d.is_valid_int() and int(d) >= 0 and int(d) <= 9):
				unknown.append(s)
		else:
			unknown.append(s)
	_check(unknown.is_empty(), "所有播放片段都有对应音频条目", str(unknown))
	_check(Voice.piece_count() == 10 + Voice.FIXED_PHRASES.size() + Voice.AIRLINES.size(),
		"片段总数 = 数字 + 短语 + 公司", str(Voice.piece_count()))
	_check(Voice.piece_count() < 60, "片段库足够小，可以一次性生成随包分发",
		str(Voice.piece_count()))


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
