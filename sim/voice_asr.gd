## 常驻识别助手的**客户端**（08 §4「听」的执行端接入）。
##
## 为什么是常驻进程：SAPI 引擎初始化要几百毫秒，每句话起一个进程就白等了。
## 实测：常驻 + 逐句识别 38~81 ms；进程重启一次就多 300 ms 起。
##
## 这里只做"管道 + 协议"，不碰麦克风也不碰 UI：
##   麦克风采集在 ui/voice_input.gd，判定在 sim/voice_mode.gd。
## 所以这条链路能在无头环境下测（test_asr.gd）。
##
## 协议见 tools/atc-listen/AtcListen.cs 顶部注释。
class_name VoiceAsr
extends RefCounted

## 每句话最多等多久（毫秒）。识别本身几十毫秒，超时说明助手卡死了。
const RECOG_TIMEOUT_MS := 2500
const PING_TIMEOUT_MS := 3000

var _stdio: FileAccess = null
var _pid := -1
var _running := false
## 最近一次失败原因（面板要显示"识别不可用"时就靠它）
var last_error := ""


## 助手可执行文件路径（工程内）
static func exe_path() -> String:
	return ProjectSettings.globalize_path("res://tools/atc-listen/AtcListen.exe")


## 本机有没有可用助手（没有就让面板退回文本模式，不要假装能听）
static func available() -> bool:
	return FileAccess.file_exists(exe_path())


## 启动常驻进程。重复调用无副作用。
func start() -> bool:
	if _running:
		return true
	last_error = ""
	if not available():
		last_error = "找不到 AtcListen.exe（先跑 tools/test-listen.ps1 或 csc 编译）"
		return false
	var d := OS.execute_with_pipe(exe_path(), [], false)
	if d.is_empty() or not d.has("stdio"):
		last_error = "识别助手启动失败"
		return false
	_stdio = d.get("stdio")
	_pid = int(d.get("pid", -1))
	_running = true
	var hello := ping()
	if not bool(hello.get("ok", false)):
		last_error = String(hello.get("error", "识别引擎不可用"))
		stop()
		return false
	return true


func stop() -> void:
	if _stdio != null and _stdio.is_open():
		_stdio.store_line("quit")
		_stdio.flush()
	_stdio = null
	_running = false


func is_running() -> bool:
	return _running


func ping() -> Dictionary:
	if not _send("ping"):
		return {"ok": false, "error": last_error}
	return _read_json(PING_TIMEOUT_MS)


## 载入闭集语法。ids 是 VoiceGrammar.rule_ids() 给的规则名列表。
func load_grammar(path: String, ids: Array) -> Dictionary:
	if not _send("grammar %s %s" % [path, ",".join(PackedStringArray(ids))]):
		return {"ok": false, "error": last_error}
	return _read_json(PING_TIMEOUT_MS)


## 识别一个 WAV 文件，返回 {ok, text, tag, confidence, ms}
func recognize(wav_path: String) -> Dictionary:
	if not _send("recog %s" % wav_path):
		return {"ok": false, "error": last_error}
	return _read_json(RECOG_TIMEOUT_MS)


func _send(line: String) -> bool:
	if not _running or _stdio == null or not _stdio.is_open():
		last_error = "识别助手没有在跑"
		return false
	# 路径里空格会被助手按"最后一个空格"切开，所以路径本身不能带空格；
	# 调用方负责把临时文件放在无空格的目录（游戏里用 user:// 下的临时名）。
	_stdio.store_line(line)
	_stdio.flush()
	return true


func _read_json(timeout_ms: int) -> Dictionary:
	if _stdio == null:
		return {"ok": false, "error": "没有管道"}
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var line := _stdio.get_line()
		if line == null or line == "":
			if not _stdio.is_open():
				last_error = "识别助手已退出"
				_running = false
				return {"ok": false, "error": last_error}
			continue
		return parse_json_line(line)
	last_error = "识别超时（>%d ms）" % timeout_ms
	return {"ok": false, "error": last_error}


## 助手回的一行 JSON → 字典。坏数据一律当失败，绝不把原文当结果。
static func parse_json_line(line: String) -> Dictionary:
	var t := line.strip_edges()
	if t == "" or not t.begins_with("{") or not t.ends_with("}"):
		# 先做结构自检再交给 JSON.parse_string：残缺报文它会打 ERROR 日志，
		# 在游戏里刷屏，所以宁可在门口拦掉。
		return {"ok": false, "error": "识别助手返回了非 JSON 内容"}
	var parsed: Variant = JSON.parse_string(t)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "error": "识别助手返回的 JSON 解析失败"}
	return parsed as Dictionary


## 把内存里的单声道 float 采样写成 16-bit PCM WAV（识别引擎只吃这个）。
## 采集用（ui/voice_input.gd）与测试共用，避免两处各写一份格式。
static func write_wav_f32(path: String, samples: PackedFloat32Array,
		rate: int) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var n := samples.size()
	var data_bytes := n * 2
	f.store_32(0x46464952)          # "RIFF"
	f.store_32(36 + data_bytes)
	f.store_32(0x45564157)          # "WAVE"
	f.store_32(0x20746d66)          # "fmt "
	f.store_32(16)
	f.store_16(1)                   # PCM
	f.store_16(1)                   # 单声道
	f.store_32(rate)
	f.store_32(rate * 2)            # 字节率
	f.store_16(2)                   # 块对齐
	f.store_16(16)                  # 位深
	f.store_32(0x61746164)          # "data"
	f.store_32(data_bytes)
	for i in range(n):
		var v := clampf(samples[i], -1.0, 1.0)
		var s := int(round(v * 32767.0))
		f.store_16(s & 0xFFFF)
	f.close()
	return true


## WAV 头是否是我们认得的 16-bit 单声道 PCM（客户端自检用）
static func wav_info(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false}
	var riff := f.get_32()
	f.get_32()                      # RIFF 块长度（这里不校验）
	var wave := f.get_32()          # "WAVE" 在偏移 8，不是 4
	f.seek(20)
	var fmt := f.get_16()
	var ch := f.get_16()
	var rate := f.get_32()
	f.close()
	return {"ok": riff == 0x46464952 and wave == 0x45564157,
		"fmt": fmt, "channels": ch, "rate": rate}
