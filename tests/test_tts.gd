## 本地神经 TTS 客户端测试（IndexTTS2 后端）。
##
## 纯逻辑部分（情绪向量 / 分类 / WAV 解析）总是跑；
## HTTP 部分只在给了 ATC_TTS_URL 时跑（由 tools/test-tts.ps1 启 mock 服务后注入），
## 这样默认不依赖外部进程，又能在需要时做真链路验证。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_tts.gd
extends SceneTree

var _checks := 0
var _fails := 0
var _step := 0
var _tts: VoiceTts


func _initialize() -> void:
	print("")
	print("════════ 本地神经 TTS 客户端测试 ════════")
	_test_emotion()
	_test_kind()
	_test_wav()
	_run_http()


func _test_emotion() -> void:
	_section("情绪向量（官方 8 维顺序）")
	_check(VoiceTts.EMOTIONS.size() == 8, "八个维度")
	_check(VoiceTts.EMOTIONS == ["happy", "angry", "sad", "afraid",
		"disgusted", "melancholic", "surprised", "calm"], "顺序与官方一致",
		str(VoiceTts.EMOTIONS))
	var v := VoiceTts.emotion_vector({"angry": 0.7, "calm": 0.3})
	_check(absf(float(v[1]) - 0.7) < 0.001, "愤怒 70% 落在第 2 维", str(v))
	_check(absf(float(v[7]) - 0.3) < 0.001, "平静 30% 落在第 8 维", str(v))
	_check(v.size() == 8 and float(v[0]) == 0.0, "没给的维度是 0", str(v))
	# 越界的值要夹住，不能让服务端收到 1.7
	var v2 := VoiceTts.emotion_vector({"angry": 1.7, "sad": -0.5})
	_check(float(v2[1]) == 1.0 and float(v2[2]) == 0.0, "越界值被夹到 0..1", str(v2))
	# 不认识的名字忽略，而不是把整个向量搞乱
	var v3 := VoiceTts.emotion_vector({"unknown": 0.9, "calm": 0.2})
	_check(float(v3[7]) == 0.2, "未知情绪被忽略", str(v3))
	_check(VoiceTts.emotion_vector({}).size() == 8, "空字典返回全零向量")

	# 预设：职业无线电通话以平静为主，别演过头
	var req := VoiceTts.preset_vector("request")
	_check(float(req[7]) > 0.5, "机组申请以平静为主", str(req))
	_check(float(req[1]) == 0.0, "申请不带怒气")
	var unheard := VoiceTts.preset_vector("unheard")
	_check(float(unheard[6]) > 0.2, "没听清带一点意外", str(unheard))
	var query := VoiceTts.preset_vector("query")
	_check(float(query[1]) > 0.0, "质疑带一点点不满", str(query))
	_check(VoiceTts.preset_vector("default").size() == 8, "未知类型退回默认")


func _test_kind() -> void:
	_section("按文字判断通话类型（决定情绪）")
	_check(VoiceTts.kind_of_line("pilot", "放行，CCA1501，申请放行至 ZBAA。") == "request",
		"申请放行")
	_check(VoiceTts.kind_of_line("pilot", "CCA1501，许可放行至 ZBAA，应答机 4321。") == "readback",
		"复诵")
	_check(VoiceTts.kind_of_line("atc", "CCA1501，许可放行至 ZBAA，应答机 4321。") == "clearance",
		"管制许可")
	_check(VoiceTts.kind_of_line("pilot", "CCA1501，没听清，请再说一遍。") == "unheard",
		"没听清")
	_check(VoiceTts.kind_of_line("pilot", "CCA1501，许可不完整，请重复。") == "query",
		"质疑")
	_check(VoiceTts.kind_of_line("atc", "CCA1501，复诵正确，放行完成。") == "confirm",
		"复诵正确")
	_check(VoiceTts.kind_of_line("atc", "CCA1501，联系地面 121.750，再见。") == "handoff",
		"移交地面")


func _test_wav() -> void:
	_section("WAV 解析")
	# 造一段 16-bit 单声道 PCM WAV
	var rate := 16000
	var n := 1600
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in range(n):
		var s := int(8000.0 * sin(float(i) / 12.0))
		pcm[i * 2] = s & 0xFF
		pcm[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := _make_wav(pcm, rate)
	var stream := VoiceTts.wav_from_bytes(wav)
	_check(stream != null, "合法 WAV 能解析")
	if stream != null:
		_check(stream.get_length() > 0.05, "时长解析出来了", str(stream.get_length()))
		_check(stream.mix_rate == rate, "采样率对", str(stream.mix_rate))
	_check(VoiceTts.wav_from_bytes(PackedByteArray()) == null, "空数据返回 null")
	var junk := PackedByteArray()
	junk.resize(100)
	_check(VoiceTts.wav_from_bytes(junk) == null, "垃圾数据返回 null")


func _run_http() -> void:
	_section("HTTP 链路（需要本地服务）")
	var url := OS.get_environment("ATC_TTS_URL")
	if url == "":
		print("    未设置 ATC_TTS_URL，跳过 HTTP 部分（用 tools/test-tts.ps1 跑）")
		_finish()
		return
	_tts = VoiceTts.new()
	_tts.base_url = url
	root.add_child(_tts)


func _process(_dt: float) -> bool:
	_step += 1
	if _step == 2:
		_http_checks()
	return false


func _http_checks() -> void:
	var h: Dictionary = await _tts.health()
	_check(bool(h.get("ok", false)), "health 通", str(h))
	_check(String(h.get("backend", "")) == "mock", "后端是 mock（测试用）",
		String(h.get("backend", "")))
	_check((h.get("emotions", []) as Array).size() == 8, "服务端情绪维度一致")

	var stream: AudioStreamWAV = await _tts.synthesize("许可放行至首都", "pilot", "clearance")
	_check(stream != null, "合成返回音频", _tts.last_error)
	if stream != null:
		_check(stream.get_length() > 0.1, "音频有时长", str(stream.get_length()))
	# 换一种情绪也必须成功
	var s2: AudioStreamWAV = await _tts.synthesize("没听清，请再说一遍", "pilot", "unheard")
	_check(s2 != null, "带情绪合成成功", _tts.last_error)
	# 空文本要就地挡掉，不浪费一次请求
	var s3: AudioStreamWAV = await _tts.synthesize("   ", "pilot")
	_check(s3 == null and _tts.last_error != "", "空文本直接失败", _tts.last_error)
	_finish()


func _make_wav(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	var n := pcm.size()
	out.append_array(_le32(36 + n))
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array("fmt ".to_ascii_buffer())
	out.append_array(_le32(16))
	out.append_array(_le16(1))
	out.append_array(_le16(1))
	out.append_array(_le32(rate))
	out.append_array(_le32(rate * 2))
	out.append_array(_le16(2))
	out.append_array(_le16(16))
	out.append_array("data".to_ascii_buffer())
	out.append_array(_le32(n))
	out.append_array(pcm)
	return out


func _le32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(4):
		b.append((v >> (8 * i)) & 0xFF)
	return b


func _le16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	for i in range(2):
		b.append((v >> (8 * i)) & 0xFF)
	return b


func _finish() -> void:
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


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
