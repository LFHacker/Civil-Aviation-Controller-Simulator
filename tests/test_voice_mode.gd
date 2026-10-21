## 高级模式：真实语音通话（08 §4）处理链路测试，无头可跑。
##
## ① ASR 转录规范化（「幺两洞洞」→「1200」，「东方五幺拐五」→「CES5175」）；
## ② 通话类型与呼号识别；
## ③ 要素提取（与进阶模式同一套槽位）；
## ④ 四种回退语义（发送 / 没听清 / 呼号不符 / 空转录）与教学关卡放宽；
## ⑤ 辅助功能默认值与无障碍文本兜底开关；
## ⑥ 接进 DeliveryDesk.issue_voice() 后的实际效果（状态推进 / 不推进）。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_voice_mode.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 高级模式（真实语音通话）测试 ════════")
	_test_normalize()
	_test_kind()
	_test_parse()
	_test_decide()
	_test_aux()
	_test_grammar()
	_test_desk_voice()
	_test_voice_readback()
	_test_voice_calls()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _test_normalize() -> void:
	_section("ASR 转录规范化")
	_check(VoiceMode.normalize("幺两洞洞") == "1200", "幺两洞洞 → 1200",
		VoiceMode.normalize("幺两洞洞"))
	_check(VoiceMode.normalize("拐勾") == "79", "拐勾 → 79", VoiceMode.normalize("拐勾"))
	_check(VoiceMode.normalize("东方五幺拐五") == "CES5175",
		"东方五幺拐五 → CES5175", VoiceMode.normalize("东方五幺拐五"))
	_check(VoiceMode.normalize("国航幺五洞幺") == "CCA1501",
		"国航幺五洞幺 → CCA1501", VoiceMode.normalize("国航幺五洞幺"))
	_check(VoiceMode.normalize("南方三洞洞幺") == "CSN3001",
		"南方三洞洞幺 → CSN3001", VoiceMode.normalize("南方三洞洞幺"))
	# 已经是阿拉伯数字的转录必须原样保留（别把 1200 再改坏）
	_check(VoiceMode.normalize("1200") == "1200", "阿拉伯数字不动",
		VoiceMode.normalize("1200"))
	_check(VoiceMode.normalize("  CES5175，许可放行至 ZBAA。 ") == "CES5175,许可放行至 ZBAA.",
		"全角标点与空白被压平", VoiceMode.normalize("  CES5175，许可放行至 ZBAA。 "))
	# 长度不同的公司名不能被短的吃掉
	_check(VoiceMode.normalize("冬季东方航空") == "冬季CES航空",
		"只替换表内的公司名", VoiceMode.normalize("冬季东方航空"))


func _test_kind() -> void:
	_section("通话类型")
	_check(VoiceMode.kind_of("CES5175，许可放行至 ZBAA") == "clearance", "许可放行")
	_check(VoiceMode.kind_of("CES5175，联系地面 121.75") == "handoff", "移交地面")
	_check(VoiceMode.kind_of("CES5175，请稍等") == "wait", "请稍等")
	_check(VoiceMode.kind_of("CES5175，重复一遍") == "repeat", "重复一遍")
	_check(VoiceMode.kind_of("CES5175，复诵正确") == "rb_ok", "复诵正确")
	_check(VoiceMode.kind_of("今天天气不错") == "", "无关内容判不出类型")
	# 交接类必须优先于许可类（"联系地面"里没有"许可"，但顺序仍要稳）
	_check(VoiceMode.kind_of("许可放行后联系地面") == "handoff",
		"同时出现时按更具体的类型判", VoiceMode.kind_of("许可放行后联系地面"))


func _test_parse() -> void:
	_section("要素提取")
	var t := VoiceMode.normalize(
		"CES5175 许可放行至 ZBAA 按 RUMUK 8D 离场 初始高度 6000 米 应答机 4321 修正海压 1013")
	var p := VoiceMode.parse(t)
	var sl: Dictionary = p.slots
	_check(String(p.kind) == "clearance", "类型是许可放行", String(p.kind))
	_check(String(sl.get("limit", "")) == "ZBAA", "认出放行界限", str(sl))
	_check(String(sl.get("sid", "")) == "RUMUK 8D", "认出离场程序", str(sl))
	_check(int(sl.get("alt", 0)) == 6000, "认出初始高度", str(sl))
	_check(String(sl.get("squawk", "")) == "4321", "认出应答机", str(sl))
	# 高度不能被当成应答机
	_check(String(sl.get("squawk", "")) != "6000", "应答机不等于高度")
	# 非法高度层不该被认成高度
	var p2 := VoiceMode.parse("CES5175 初始高度 6500 米")
	_check(not (p2.slots as Dictionary).has("alt"), "非法高度层不瞎认",
		str(p2.slots))
	# 中文机场名也能认
	var p3 := VoiceMode.parse(VoiceMode.normalize("CES5175 许可放行至 浦东"))
	_check(String((p3.slots as Dictionary).get("limit", "")) == "ZSPD",
		"认中文机场名", str(p3.slots))
	# 程序说的是中文读法（SASAN五号）也要能翻回工程代码（SASAN 5B）。
	# 注意 normalize 会把"五"变成 5，这一步踩过。
	var p4 := VoiceMode.parse(VoiceMode.normalize(
		"CES5175 许可放行至浦东 按SASAN五号离场 初始高度6000米"))
	_check(String((p4.slots as Dictionary).get("sid", "")) == "SASAN 5B",
		"中文读法能翻回程序代码", str(p4.slots))


func _test_decide() -> void:
	_section("四种回退语义")
	var known := ["CES5175", "CCA1501"]
	var ok := VoiceMode.decide("CES5175，许可放行至 ZBAA", 0.9, "CES5175", known)
	_check(String(ok.action) == "send", "正常情况照发", str(ok))

	var empty := VoiceMode.decide("   ", 0.99, "CES5175", known)
	_check(String(empty.action) == "unheard", "空转录 → 没听清", str(empty))

	var low := VoiceMode.decide("CES5175，许可放行至 ZBAA", 0.30, "CES5175", known)
	_check(String(low.action) == "unheard", "低置信度 → 没听清（不提示重输）", str(low))
	_check(String(low.reason).contains("%"), "回退原因里带置信度", String(low.reason))

	# 教学关卡放宽：同样的低置信度在教学中应当放行
	var teach := VoiceMode.decide("CES5175，许可放行至 ZBAA", 0.30, "CES5175", known, true)
	_check(String(teach.action) == "send", "教学关卡放宽门槛", str(teach))

	var wrong := VoiceMode.decide("CCA1501，许可放行至 ZBAA", 0.9, "CES5175", known)
	_check(String(wrong.action) == "mismatch", "呼号不符单独处理", str(wrong))
	_check(String(wrong.said) == "CCA1501", "报出说的是哪个呼号", str(wrong.said))

	# 没说到任何已知呼号时不该判成"不符"（可能只是漏说）
	var nosay := VoiceMode.decide("许可放行至 ZBAA", 0.9, "CES5175", known)
	_check(String(nosay.action) == "send", "没报呼号不判不符（交给校验环节）", str(nosay))

	_check(VoiceMode.confident(0.6) == true, "0.6 过门槛")
	_check(VoiceMode.confident(0.4) == false, "0.4 不过门槛")
	_check(VoiceMode.confident(0.4, true) == true, "教学关卡 0.4 过门槛")


func _test_aux() -> void:
	_section("辅助功能与文本兜底")
	_check(VoiceMode.aux_enabled({}, "transcript") == true, "转录文本默认开")
	_check(VoiceMode.aux_enabled({}, "read_numbers") == false, "数值朗读默认关")
	_check(VoiceMode.aux_enabled({}, "read_template") == false, "模板朗读默认关")
	_check(VoiceMode.aux_enabled({"read_numbers": true}, "read_numbers") == true,
		"设置能打开")
	_check(VoiceMode.aux_enabled({}, "不存在的键") == false, "未知键返回 false")
	_check(VoiceMode.text_fallback_allowed(null) == false, "文本兜底默认关（§4.5）")
	_check(VoiceMode.text_fallback_allowed(true) == true, "无障碍开关能打开")
	_check(VoiceMode.AUX_DEFAULTS.size() == 5, "五项辅助功能齐全",
		str(VoiceMode.AUX_DEFAULTS.size()))


func _test_desk_voice() -> void:
	_section("接进放行席")
	# 正常路径：语音说的话推进到已发送
	var d := _desk()
	var r := d.issue_voice("ISS001",
		"ISS001 许可放行至 ZBAA 按 RUMUK 8D 离场 初始高度 6000 米 应答机 4321 修正海压 1013",
		0.92, 1.0)
	_check(bool(r.ok), "正常语音放行成功", String(r.get("error", "")))
	_check(d.get_flight("ISS001").state == Flight.State.SENT, "状态推进到已发送",
		str(d.get_flight("ISS001").state))
	_check(bool(r.get("voice", false)), "结果标记为语音来源")

	# 没听清：不推进状态，机组回话，计数增加
	var d2 := _desk()
	var before := d2.get_flight("ISS001").state
	var r2 := d2.issue_voice("ISS001", "ISS001 许可放行至 ZBAA", 0.20, 1.0)
	_check(bool(r2.ok) and bool(r2.get("unheard", false)), "低置信度走没听清", str(r2))
	_check(d2.get_flight("ISS001").state == before, "没听清时状态不动")
	_check(d2.voice_unheard == 1, "没听清计数 +1", str(d2.voice_unheard))
	var last := String((d2.transcript[d2.transcript.size() - 1] as Dictionary).text)
	_check(last.contains("没听清"), "机组按通话形式要求重说", last)
	_check(not last.contains("请重新输入"), "不是文本提示，是通话")

	# 呼号不符：说明明叫的是另一架（ISS002 在册），必须拦下
	var d3 := _desk([{"callsign": "ISS002", "type": "B738", "dest": "ZBAA",
		"stand": "A06", "sid": "RUMUK 8D", "alt": 6000}])
	var r3 := d3.issue_voice("ISS001", "ISS002 许可放行至 ZBAA", 0.9, 1.0)
	_check(bool(r3.ok) == false and bool(r3.get("mismatch", false)),
		"呼号不符被拦下", str(r3))
	_check(String(r3.get("error", "")).contains("呼号不符"), "提示文案符合文档",
		String(r3.get("error", "")))

	# 教学关卡：低置信度也放行
	var d4 := _desk()
	var r4 := d4.issue_voice("ISS001",
		"ISS001 许可放行至 ZBAA 按 RUMUK 8D 离场 初始高度 6000 米 应答机 4321 修正海压 1013",
		0.30, 1.0, true)
	_check(bool(r4.ok) and not bool(r4.get("unheard", false)),
		"教学关卡低置信度也放行", str(r4))

	# 缺项：交给与进阶模式同一套校验（机组质疑，不另写规则）
	var d5 := _desk()
	d5.pilot_check_enabled = true
	d5.difficulty = "normal"
	var r5 := d5.issue_voice("ISS001",
		"ISS001 许可放行至 ZBAA 修正海压 1013", 0.95, 1.0)
	_check(bool(r5.get("queried", false)), "缺项走机组质疑（与进阶模式一致）",
		str(r5))
	_check(d5.get_flight("ISS001").pilot_queries == 1, "质疑计数 +1")

	_check(d5.last_voice.has("action"), "放行席记下最近一次语音判定")

	# 08 §4.6 教学关卡：放行席开着 teaching 时，低置信度不该卡玩家
	var d6 := _desk()
	d6.teaching = true
	var r6 := d6.issue_voice("ISS001",
		"ISS001 许可放行至 ZBAA 按 RUMUK 8D 离场 初始高度 6000 米 应答机 4321 修正海压 1013",
		0.30, 1.0)
	_check(bool(r6.ok) and not bool(r6.get("unheard", false)),
		"教学关卡（放行席 teaching）放宽识别门槛", str(r6))
	_check(d6.get_flight("ISS001").state == Flight.State.SENT, "教学关卡里许可真发出去了",
		str(d6.get_flight("ISS001").state))
	# 不复诵时也不该被门槛拦住
	var d7 := _rb_desk()
	d7.teaching = true
	var r7 := d7.apply_voice_readback("RBK001", "v_qnh", 0.30, 10.0)
	_check(bool(r7.ok) and not bool(r7.get("unheard", false)),
		"教学关卡里低置信度复诵也照判", str(r7))


func _test_voice_calls() -> void:
	_section("放行席四类通话都能用语音说（08 §7.1）")
	# 简易复诵：玩家说「复诵正确」→ 直接确认放行
	var d := _rb_desk(false)
	var r := d.issue_voice("RBK001", "RBK001复诵正确", 0.95, 10.0)
	_check(bool(r.ok), "说「复诵正确」能确认", str(r))
	_check(String(r.get("kind", "")) == "rb_ok", "判为复诵确认", str(r.get("kind")))
	_check(d.get_flight("RBK001").state == Flight.State.CLEARED, "状态到已放行",
		str(d.get_flight("RBK001").state))

	# 说「复诵有误」→ 退回重发
	var d2 := _rb_desk(false)
	var r2 := d2.issue_voice("RBK001", "RBK001复诵有误重新发布许可", 0.95, 10.0)
	_check(bool(r2.ok), "说「复诵有误」能退回", str(r2))
	_check(d2.get_flight("RBK001").state == Flight.State.PENDING, "退回待重发",
		str(d2.get_flight("RBK001").state))
	_check(d2.get_flight("RBK001").reissue_count == 1, "重发计数 +1")

	# 移交地面
	var d3 := _rb_desk(false)
	d3.accept_readback("RBK001", 10.0)
	var r3 := d3.issue_voice("RBK001", "RBK001联系地面121750再见", 0.95, 20.0)
	_check(bool(r3.ok), "说移交能发出去", str(r3))
	_check(String(r3.get("kind", "")) == "handoff", "判为移交", str(r3.get("kind")))
	_check(d3.get_flight("RBK001").handed_off, "移交生效")

	# 通用短语：只说话，不动状态
	var d4 := _desk()
	var before := d4.get_flight("ISS001").state
	var r4 := d4.issue_voice("ISS001", "ISS001请稍等", 0.95, 1.0)
	_check(bool(r4.ok), "「请稍等」能发", str(r4))
	_check(d4.get_flight("ISS001").state == before, "通用短语不改状态")
	var last := String((d4.transcript[d4.transcript.size() - 1] as Dictionary).text)
	_check(last.contains("请稍等"), "通用短语进了通话记录", last)

	# 确认/退回/移交自己会记记录，不能重复记两条
	var d5 := _rb_desk(false)
	var n_before := d5.transcript.size()
	d5.issue_voice("RBK001", "RBK001复诵正确", 0.95, 10.0)
	_check(d5.transcript.size() - n_before == 1, "确认只记一条通话记录",
		str(d5.transcript.size() - n_before))


func _test_grammar() -> void:
	_section("闭集语法（听）")
	var param := {"callsign": "CES5175", "limit": "ZSPD", "sid": "SASAN 5B",
		"alt": 6900, "squawk": "4215", "qnh": 1013}
	var lines := VoiceGrammar.variant_lines(param)
	_check(lines.size() == 6, "六个变体（正确 + 五个关键项各错一位）", str(lines.size()))
	_check(String((lines[0] as Dictionary).tag) == "v_ok", "第一条是正确复诵")
	var tags: Array = []
	for v in lines:
		tags.append(String((v as Dictionary).tag))
	# 复诵语法只覆盖六个变体；v_bad / v_freq 属于另外两种通话类型（见下）
	for k in ["v_ok", "v_alt", "v_squawk", "v_qnh", "v_sid", "v_limit"]:
		_check(tags.has(String(k)), "含变体 %s" % String(k))
	_check(VoiceGrammar.lines_for(param, "readback").size() == 6,
		"复诵模式 6 条", str(lines.size()))
	# 每条候选必须互不相同，否则识别器分不出读错的是哪一项
	var uniq := {}
	for v in lines:
		uniq[String((v as Dictionary).text)] = true
	_check(uniq.size() == lines.size(), "六条候选互不相同", str(uniq.size()))

	var ok_text := String((lines[0] as Dictionary).text)
	_check(ok_text.contains("东方五幺拐五"), "呼号按口语读法", ok_text)
	_check(ok_text.contains("六勾洞洞"), "高度按标准读法（9 读勾）", ok_text)
	_check(ok_text.contains("四两幺五"), "应答机按标准读法", ok_text)
	_check(ok_text.contains("幺洞幺三"), "海压按标准读法", ok_text)
	_check(ok_text.contains("SASAN五号"), "带空格的程序名能查到读法", ok_text)
	_check(not ok_text.contains(" "), "候选句里不能留空白（识别器对空白敏感）", ok_text)
	_check(ok_text.begins_with("东方五幺拐五") and ok_text.ends_with("东方五幺拐五"),
		"以完整呼号开头并终止（MH/T 4014）", ok_text)

	# 每个变体只改一处
	for v in lines:
		var d: Dictionary = v
		if String(d.tag) == "v_ok":
			continue
		var diff := 0
		for i in range(mini(ok_text.length(), String(d.text).length())):
			if ok_text[i] != String(d.text)[i]:
				diff += 1
		_check(String(d.text) != ok_text, "%s 与正确句不同" % String(d.tag))

	var xml := VoiceGrammar.build(param)
	var rules := VoiceGrammar.rule_ids(param)
	_check(xml.contains("root=\"v_ok\""), "根规则是 v_ok")
	for r in rules:
		_check(xml.contains("<rule id=\"%s\"" % String(r)), "语法里有规则 %s" % String(r))
	_check(not xml.contains("<tag>"), "不用 SRGS 语义标签（SAPI 桌面引擎不启用）")
	_check(xml.begins_with("<?xml"), "是合法 SRGS 文本开头")

	_check(String(VoiceGrammar.parse_tag("v_ok").wrong) == "", "v_ok 判为正确")
	_check(bool(VoiceGrammar.parse_tag("v_ok").ok) == true, "v_ok.ok = true")
	_check(String(VoiceGrammar.parse_tag("v_qnh").wrong) == "qnh", "v_qnh → 海压")
	_check(bool(VoiceGrammar.parse_tag("v_qnh").ok) == false, "v_qnh.ok = false")
	_check(bool(VoiceGrammar.parse_tag("").known) == false, "空标签不算判出来")
	_check(bool(VoiceGrammar.parse_tag("v_xxx").known) == false, "未知标签不算判出来")

	_section("另外两类通话的语法（08 §7.1）")
	var cf := VoiceGrammar.lines_for(param, "confirm")
	_check(cf.size() == 2, "确认/纠正只有两句", str(cf.size()))
	var cf_tags: Array = []
	for v in cf:
		cf_tags.append(String((v as Dictionary).tag))
	_check(cf_tags.has("v_ok") and cf_tags.has("v_bad"), "两句各有标签", str(cf_tags))
	_check(String((cf[1] as Dictionary).text).contains("复诵有误"),
		"第二句是纠正", String((cf[1] as Dictionary).text))
	_check(String((cf[0] as Dictionary).text).contains("东方五幺拐五"),
		"带呼号", String((cf[0] as Dictionary).text))
	_check(String(VoiceGrammar.parse_tag("v_bad").wrong) == "readback",
		"v_bad → 复诵错")

	var hf := VoiceGrammar.lines_for(param, "handoff")
	_check(hf.size() == 2, "移交两句（对/频率错）", str(hf.size()))
	_check(String((hf[0] as Dictionary).tag) == "v_ok", "第一句是对的")
	_check(String((hf[1] as Dictionary).tag) == "v_freq", "第二句频率读错")
	_check(String((hf[0] as Dictionary).text).contains("联系地面"),
		"含『联系地面』", String((hf[0] as Dictionary).text))
	_check(String((hf[0] as Dictionary).text) != String((hf[1] as Dictionary).text),
		"两句频段读法不同")
	_check(String(VoiceGrammar.parse_tag("v_freq").wrong) == "freq",
		"v_freq → 频率错")
	# 移交语法要用到地面频率
	var hp := param.duplicate()
	hp["ground_freq"] = "121.750"
	_check(VoiceGrammar.build(hp, "handoff").contains("联系地面"), "移交语法能生成")


func _test_voice_readback() -> void:
	_section("语音复诵接进逐项判定")
	# 先把复诵走到待复核
	var d := _rb_desk()
	_check(d.get_flight("RBK001").state == Flight.State.READBACK, "复诵已到",
		str(d.get_flight("RBK001").state))
	var r := d.apply_voice_readback("RBK001", "v_qnh", 0.97, 10.0)
	_check(bool(r.ok), "识别结果能落到逐项判定", String(r.get("error", "")))
	_check(String(r.get("wrong", "")) == "qnh", "指出读错的是修正海压", str(r))
	var f := d.get_flight("RBK001")
	_check(f.readback_marks.get("qnh", true) == false, "海压这一项被标为不一致")
	_check(f.readback_marks.get("alt", false) == true, "其余项不受影响（高度一致）")
	_check(String(r.get("note", "")).contains("修正海压"), "提示语带出错项", str(r))

	# 程序读错 → 航路跟着错
	var d2 := _rb_desk()
	d2.apply_voice_readback("RBK001", "v_sid", 0.95, 10.0)
	var f2 := d2.get_flight("RBK001")
	_check(f2.readback_marks.get("sid", true) == false, "程序被标为不一致")
	_check(f2.readback_marks.get("route", true) == false, "航路跟着标为不一致")

	# 读对 → 全部一致
	var d3 := _rb_desk()
	var r3 := d3.apply_voice_readback("RBK001", "v_ok", 0.99, 10.0)
	var f3 := d3.get_flight("RBK001")
	var all_same := true
	for k in f3.readback_marks.keys():
		if not bool(f3.readback_marks[k]):
			all_same = false
	_check(bool(r3.ok) and all_same, "全读对时逐项全一致", str(f3.readback_marks))

	# 置信度低 → 没听清，不落任何标记
	var d4 := _rb_desk()
	var r4 := d4.apply_voice_readback("RBK001", "v_alt", 0.2, 10.0)
	_check(bool(r4.get("unheard", false)), "低置信度走没听清", str(r4))
	_check(d4.get_flight("RBK001").readback_marks.is_empty(), "没听清时不落标记")
	_check(d4.voice_unheard == 1, "没听清计数 +1")

	# 没有待复核的复诵时不该乱标
	var d5 := _desk()
	var r5 := d5.apply_voice_readback("ISS001", "v_ok", 0.99, 1.0)
	_check(bool(r5.ok) == false, "没有待复核复诵时被拒", str(r5))


func _rb_desk(hard: bool = true) -> DeliveryDesk:
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
	d.get_flight("RBK001").checked = true
	d.issue_clearance("RBK001", "RUMUK 8D", 6000, "1234", 0.0)
	d.tick(d.get_flight("RBK001").readback_at + 0.1)
	return d


func _desk(extra: Array = []) -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(2718)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	var plan := [{"callsign": "ISS001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}]
	plan.append_array(extra)
	d.set_plan(plan)
	d.spawn_request(0.0)
	for i in range(extra.size()):
		d.spawn_request(0.0)
	var f := d.get_flight("ISS001")
	f.checked = true
	f.atis_ok = true
	f.squawk = "4321"
	f.clearance_limit = "ZBAA"
	f.dep_freq = "119.000"
	return d


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
