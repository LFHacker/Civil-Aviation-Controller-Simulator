## 麦克风采集（08 §4.2 按住通话）——表现层，逻辑层不依赖它。
##
## 职责只有一件：把麦克风的声音变成识别引擎能吃的 16 kHz 单声道 WAV。
## 识别、判定、校验都不在这里（在 sim/voice_asr.gd 与 sim/voice_mode.gd）。
##
## 测试钩子：环境变量 ATC_VOICE_WAV 指向一个 WAV 时，不走麦克风，
## 直接用那个文件。这样面板上的整条链路（按下→转录→落标记）能在
## 没有真人说话的机器上被自动化验证。这不是给玩家用的开关。
class_name VoiceInput
extends Node

signal finished(wav_path: String)
signal failed(reason: String)

const RATE := 16000
## 最短有效时长：短于这个基本是误触，直接判失败，别送去识别
const MIN_SECONDS := 0.4
const BUS_NAME := "VoiceMic"

var asr := VoiceAsr.new()
var recording := false
var last_reason := ""

var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _bus_idx := -1
var _buf := PackedFloat32Array()
var _test_wav := ""


func _ready() -> void:
	_test_wav = OS.get_environment("ATC_VOICE_WAV")
	set_process(false)


## 本机能不能用语音（助手在 + 有麦克风或测试钩子）
func usable() -> bool:
	if _test_wav != "":
		return FileAccess.file_exists(_test_wav)
	if not VoiceAsr.available():
		return false
	return AudioServer.get_input_device_list().size() > 0


func using_test_wav() -> bool:
	return _test_wav != "" and FileAccess.file_exists(_test_wav)


## 开始采集。返回是否真的开始了。
func begin() -> bool:
	if recording:
		return true
	last_reason = ""
	if using_test_wav():
		recording = true
		return true
	if not VoiceAsr.available():
		last_reason = "识别助手不可用"
		failed.emit(last_reason)
		return false
	if not _ensure_mic():
		failed.emit(last_reason)
		return false
	_capture.clear_buffer()
	_buf = PackedFloat32Array()
	recording = true
	set_process(true)
	return true


## 结束采集并交出 WAV 路径（识别由调用方发起，方便先显示"正在识别"）
func end() -> String:
	if not recording:
		return ""
	recording = false
	set_process(false)
	if using_test_wav():
		finished.emit(_test_wav)
		return _test_wav
	# 收尾：把 capture 里剩下的帧取干净
	if _capture != null:
		_drain()
	var secs := float(_buf.size()) / float(RATE)
	if secs < MIN_SECONDS:
		last_reason = "说话太短（%.1f 秒）" % secs
		failed.emit(last_reason)
		return ""
	var dir := OS.get_user_data_dir().path_join("voice")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("utterance.wav")
	if not VoiceAsr.write_wav_f32(path, _buf, RATE):
		last_reason = "写不了临时音频"
		failed.emit(last_reason)
		return ""
	last_reason = ""
	finished.emit(path)
	return path


func cancel() -> void:
	recording = false
	set_process(false)
	_buf = PackedFloat32Array()


func _process(_dt: float) -> void:
	if recording and _capture != null:
		_drain()


func _drain() -> void:
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	# ⚠️ AudioEffectCapture.get_buffer() 返回的是**立体声帧** PackedVector2Array，
	# 不是 float 数组（踩过）。取左右平均当单声道。
	var chunk := _capture.get_buffer(frames)
	var mono := PackedFloat32Array()
	mono.resize(chunk.size())
	for i in range(chunk.size()):
		var v: Vector2 = chunk[i]
		mono[i] = (v.x + v.y) * 0.5
	# 混音总线通常是 44100/48000，识别引擎要 16k，线性重采样够用
	var in_rate := int(AudioServer.get_mix_rate())
	if in_rate == RATE:
		_buf.append_array(mono)
		return
	var ratio := float(in_rate) / float(RATE)
	var out_n := int(float(mono.size()) / ratio)
	for i in range(out_n):
		var src := int(float(i) * ratio)
		if src >= mono.size():
			break
		_buf.append(mono[src])


func _ensure_mic() -> bool:
	if _capture != null and _player != null:
		return true
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx < 0:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
	if AudioServer.get_bus_effect_count(_bus_idx) == 0:
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 10.0
		AudioServer.add_bus_effect(_bus_idx, cap)
	_capture = AudioServer.get_bus_effect(_bus_idx, 0)
	if _capture == null:
		last_reason = "无法创建采集效果"
		return false
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS_NAME
		add_child(_player)
	_player.play()
	if not _player.playing:
		last_reason = "麦克风打不开（可能没有输入设备或被占用）"
		return false
	return true
