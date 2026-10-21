## 识别助手客户端测试（08 §4 听），无头可跑、**不需要麦克风也不需要说话**。
##
## 覆盖：WAV 写入格式、JSON 解析、进程启动、ping、载入闭集语法、错误路径。
## 真正"听一句话"的验证在 tools/test-listen.ps1（它要合成音频，依赖 edge-tts）。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_asr.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 识别助手客户端测试 ════════")
	var exe := VoiceAsr.exe_path()
	if not FileAccess.file_exists(exe):
		print("  未找到 AtcListen.exe，尝试用 csc 现场编译…")
		_compile(exe)
	if not FileAccess.file_exists(exe):
		print("")
		print("✗ 没有识别助手，无法测试（先跑 tools/test-listen.ps1）")
		quit(1)
		return
	_test_wav()
	_test_json()
	_test_protocol()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _compile(exe: String) -> void:
	var csc := OS.get_environment("WINDIR").path_join(
		"Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	if not FileAccess.file_exists(csc):
		return
	var cs := ProjectSettings.globalize_path("res://tools/atc-listen/AtcListen.cs")
	var sink: Array = []
	# OS.execute 返回的是退出码，输出走 out 参数
	var code := OS.execute(csc, ["/nologo", "/target:exe", "/out:" + exe,
		"/r:System.Speech.dll", cs], sink, true)
	if code != 0:
		print("  编译失败: ", " ".join(PackedStringArray(sink)))


func _test_wav() -> void:
	_section("WAV 写入（识别引擎只吃 16-bit PCM）")
	var path := OS.get_user_data_dir().path_join("asr_test.wav")
	var n := 16000
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		buf[i] = sin(float(i) / 20.0) * 0.3
	_check(VoiceAsr.write_wav_f32(path, buf, 16000), "写 WAV 成功")
	_check(FileAccess.file_exists(path), "文件确实落盘")
	var info := VoiceAsr.wav_info(path)
	_check(bool(info.get("ok", false)), "RIFF/WAVE 头正确", str(info))
	_check(int(info.get("fmt", 0)) == 1, "格式是 PCM", str(info))
	_check(int(info.get("channels", 0)) == 1, "单声道", str(info))
	_check(int(info.get("rate", 0)) == 16000, "16 kHz", str(info))
	# 文件长度 = 44 字节头 + 采样数 × 2
	var f := FileAccess.open(path, FileAccess.READ)
	_check(f.get_length() == 44 + n * 2, "字节数正确",
		str(f.get_length()))
	f.close()
	# 削顶保护：超过 ±1 的采样不能环绕成刺耳噪声
	var loud := PackedFloat32Array([2.0, -2.0, 0.0])
	VoiceAsr.write_wav_f32(path, loud, 16000)
	var g := FileAccess.open(path, FileAccess.READ)
	g.seek(44)
	var a := g.get_16()
	var b := g.get_16()
	g.close()
	_check(a == 32767, "超上界的采样削到 32767", str(a))
	_check(b != 32767 and b != 0, "超下界的采样不是 0 也不是正数", str(b))
	DirAccess.remove_absolute(path)


func _test_json() -> void:
	_section("JSON 解析（坏数据不能当结果）")
	var ok := VoiceAsr.parse_json_line("{\"ok\":true,\"tag\":\"v_qnh\",\"ms\":42}")
	_check(bool(ok.get("ok", false)), "正常 JSON 能解析")
	_check(String(ok.get("tag", "")) == "v_qnh", "字段取值正确", str(ok))
	var bad := VoiceAsr.parse_json_line("随便说点什么")
	_check(not bool(bad.get("ok", true)), "非 JSON 判为失败")
	var broke := VoiceAsr.parse_json_line("{\"ok\":")
	_check(not bool(broke.get("ok", true)), "残缺 JSON 判为失败")
	var empty := VoiceAsr.parse_json_line("")
	_check(not bool(empty.get("ok", true)), "空行判为失败")
	# 原始文本绝不能透出来当识别结果
	var raw := VoiceAsr.parse_json_line("This is a multi-part message")
	_check(not raw.has("text"), "失败结果里没有 text 字段")


func _test_protocol() -> void:
	_section("与助手通信")
	_check(VoiceAsr.available(), "能找到识别助手")
	var asr := VoiceAsr.new()
	_check(asr.start(), "助手启动并应答 ping", asr.last_error)
	if not asr.is_running():
		return
	# 载入一条真实语法（用逻辑层生成，不依赖任何音频）
	var param := {"callsign": "CES5175", "limit": "ZSPD", "sid": "SASAN 5B",
		"alt": 6900, "squawk": "4215", "qnh": 1013}
	var xml := VoiceGrammar.build(param)
	var path := OS.get_user_data_dir().path_join("asr_test.srgs")
	var wf := FileAccess.open(path, FileAccess.WRITE)
	wf.store_string(xml)
	wf.close()
	var ids := VoiceGrammar.rule_ids(param)
	var g := asr.load_grammar(path, ids)
	_check(bool(g.get("ok", false)), "语法载入成功", str(g))
	_check(int(g.get("rules", 0)) == ids.size(), "规则数对得上",
		str(g.get("rules", 0)))
	# 不存在的音频：必须返回失败，不能假装识别出了东西
	var miss := asr.recognize(OS.get_user_data_dir().path_join("nope.wav"))
	_check(not bool(miss.get("ok", true)), "缺少音频时返回失败", str(miss))
	# 静音音频：引擎识别不出内容，同样要如实返回失败
	var silent := OS.get_user_data_dir().path_join("asr_silence.wav")
	var zeros := PackedFloat32Array()
	zeros.resize(16000)
	VoiceAsr.write_wav_f32(silent, zeros, 16000)
	var sr := asr.recognize(silent)
	_check(not bool(sr.get("ok", true)), "静音不产生识别结果（不瞎猜）", str(sr))
	asr.stop()
	_check(not asr.is_running(), "停止后不再运行")
	# 停掉之后再问必须失败，而不是挂住
	var after := asr.ping()
	_check(not bool(after.get("ok", true)), "停掉后调用返回失败")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(silent)


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
