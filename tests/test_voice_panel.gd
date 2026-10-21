## 语音面板（08 §4.2 按住通话）的面板级测试 —— 无头、真按钮回调、不需要真人说话。
##
## 为什么不用"造一段人声"来测：识别→变体标签这条链已经由
## tools/test-listen.ps1 用真实语音验过（六变体全对）。
## 这里要验的是**面板这条线**：模式切换时语音行出不出来、
## 按下/松开两个回调有没有走通、语法有没有真的生成并载入、
## 识别失败时界面是不是如实说"没听清"而不是假装成功。
##
## 所以用 ATC_VOICE_WAV 指向一段**静音**音频：识别必然失败，
## 正好用来验错误路径；成功路径的判定另行覆盖。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_voice_panel.gd
extends SceneTree

var _checks := 0
var _fails := 0
var _step := 0
var _panel: Control = null
var _desk: DeliveryDesk = null
var _silent := ""


func _process(_dt: float) -> bool:
	_step += 1
	match _step:
		2: _setup()
		4: _open()
		6: _check_layout()
		8: _press()
		10: _release()
		12: _check_result()
		14: _check_modes()
		16: _finish()
	return false


func _setup() -> void:
	print("")
	print("════════ 语音面板测试 ════════")
	if not FileAccess.file_exists(VoiceAsr.exe_path()):
		print("")
		print("✗ 没有识别助手（先跑 tools/test-listen.ps1）")
		quit(1)
		return
	# 静音 1 秒：够长（过 MIN_SECONDS），但识别不出任何内容
	_silent = OS.get_user_data_dir().path_join("voice_silent.wav")
	var buf := PackedFloat32Array()
	buf.resize(VoiceInput.RATE)
	VoiceAsr.write_wav_f32(_silent, buf, VoiceInput.RATE)
	OS.set_environment("ATC_VOICE_WAV", _silent)

	_desk = DeliveryDesk.new()
	_desk.setup(2718)
	_desk.field = {"runway": "18", "wind": "18005MPS", "visibility": "CAVOK",
		"qnh": 1013, "atis_alpha": "A", "dep_freq": "119.000",
		"ground_freq": "121.750", "clock_start": "0800", "airport_id": "ZDEM"}
	_desk.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	_desk.set_plan([{"callsign": "ISS001", "type": "B738", "dest": "ZBAA",
		"stand": "A05", "sid": "RUMUK 8D", "alt": 6000}])
	_desk.spawn_request(0.0)
	var f := _desk.get_flight("ISS001")
	f.checked = true
	f.atis_ok = true
	f.squawk = "4321"
	f.clearance_limit = "ZBAA"
	_desk.issue_mode = "voice"
	_panel = DeliveryPanel.new()
	root.add_child(_panel)


func _open() -> void:
	_panel.open(_desk)
	_panel.tick(1.0)


func _check_layout() -> void:
	_section("布局：语音行只在该出现时出现")
	_check(_panel._voice_row != null, "语音行已创建")
	_check(_panel._voice_row.visible, "真实语音模式下语音行可见")
	_check(not _panel._cand_box.visible, "真实语音模式不显示候选列表")
	_check(not _panel._text_row.visible, "真实语音模式不显示文本输入")
	_check(_panel._voice_state.text.contains("按住"), "有按住的提示",
		_panel._voice_state.text)


func _press() -> void:
	_section("按下通话")
	_panel._on_voice_down()
	_check(_panel._vin != null, "语音输入组件已创建")
	_check(_panel._vin.using_test_wav(), "走的是测试音频（无麦克风也能量）")
	_check(_panel._vin.recording, "进入采集状态")
	_check(_panel._voice_btn.text.contains("松开"), "按钮变成「松开结束」",
		_panel._voice_btn.text)


func _release() -> void:
	_section("松开识别（静音音频应当识别失败）")
	_panel._on_voice_up()
	_check(not _panel._vin.recording, "已停止采集")
	_check(_panel._voice_btn.text == "按下通话", "按钮文案复位",
		_panel._voice_btn.text)


func _check_result() -> void:
	_section("失败路径要如实说没听清")
	var txt := String(_panel._voice_state.text)
	_check(txt.contains("没听清"), "界面提示没听清", txt)
	# 静音不该把许可发出去
	_check(_desk.get_flight("ISS001").state == Flight.State.PENDING,
		"没识别出内容时不发许可", str(_desk.get_flight("ISS001").state))
	# 且助手是常驻的：连续两次不必重启进程
	_check(_panel._vin.asr.is_running(), "助手保持常驻，下一句不用重启")
	var srgs := OS.get_user_data_dir().path_join("voice").path_join("voice.srgs")
	_check(FileAccess.file_exists(srgs), "语法文件真的生成了")


func _check_modes() -> void:
	_section("切模式")
	_desk.issue_mode = "preset"
	_panel.refresh()
	_check(not _panel._voice_row.visible, "预设模式下语音行隐藏")
	_desk.issue_mode = "voice"
	_panel.refresh()
	_check(_panel._voice_row.visible, "切回语音模式又出现")


func _finish() -> void:
	if _panel._vin != null:
		_panel._vin.asr.stop()
	DirAccess.remove_absolute(_silent)
	OS.set_environment("ATC_VOICE_WAV", "")
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
