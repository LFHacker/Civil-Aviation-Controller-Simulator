## 本地神经 TTS 客户端（IndexTTS2，08 §4「说」的新后端）。
##
## 为什么走 HTTP：IndexTTS2 是 PyTorch 模型，Godot 里跑不了。
## 标准做法是把它跑成本地服务（tools/tts_server.py），游戏用 HTTPRequest
## 要一段 WAV 字节，再 AudioStreamWAV.from_data 播出来 —— 全程不联网、不要 key。
##
## 情绪：IndexTTS2 的情绪向量是 8 维，顺序固定（官方 README）：
##   [happy, angry, sad, afraid, disgusted, melancholic, surprised, calm]
## 可以给"愤怒 70% + 平静 30%"这种组合；emo_alpha 再整体调强度。
class_name VoiceTts
extends Node

## 没有指定端口时用服务端默认值
const DEFAULT_URL := "http://127.0.0.1:8731"

## 官方情绪维度顺序，不要改
const EMOTIONS := ["happy", "angry", "sad", "afraid",
	"disgusted", "melancholic", "surprised", "calm"]

## 各类通话的默认情绪。放行席是职业无线电通话，主体是"平静"，
## 只在特定场合加一点点别的味道，别演过头。
const PRESETS := {
	"request": {"calm": 0.65},
	"readback": {"calm": 0.60},
	"clearance": {"calm": 0.70},
	"confirm": {"calm": 0.55, "happy": 0.10},
	"unheard": {"surprised": 0.35, "calm": 0.30},
	"query": {"angry": 0.20, "calm": 0.40},
	"handoff": {"calm": 0.70},
	"default": {"calm": 0.60},
}

var base_url := DEFAULT_URL
var last_error := ""
## 服务端报的可用音色与后端名（health 之后才有）
var backend := ""
var voices: Array = []

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "TtsHttp"
	_http.timeout = 30.0
	add_child(_http)


## {"angry":0.7} → 8 维向量（按官方顺序），越界的值夹到 0..1
static func emotion_vector(named: Dictionary) -> Array:
	var vec: Array = []
	vec.resize(EMOTIONS.size())
	vec.fill(0.0)
	for k in named.keys():
		var key := String(k).strip_edges().to_lower()
		var idx := EMOTIONS.find(key)
		if idx < 0:
			continue
		vec[idx] = clampf(float(named[k]), 0.0, 1.0)
	return vec


static func preset_vector(kind: String) -> Array:
	return emotion_vector(PRESETS.get(kind, PRESETS["default"]))


## 服务在不在、模型加载没有
func health() -> Dictionary:
	last_error = ""
	var err := _http.request(base_url.path_join("health"))
	if err != OK:
		last_error = "连接不上本地 TTS 服务（%s）" % base_url
		return {"ok": false, "error": last_error}
	var res: Array = await _http.request_completed
	var code := int(res[1])
	var body: PackedByteArray = res[3]
	if code != 200:
		last_error = "TTS 服务返回 %d" % code
		return {"ok": false, "error": last_error}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		last_error = "TTS 服务返回了非 JSON"
		return {"ok": false, "error": last_error}
	var d := parsed as Dictionary
	backend = String(d.get("backend", ""))
	voices = d.get("voices", [])
	return d


## 合成一句话，返回 AudioStreamWAV；失败返回 null 并把原因写进 last_error。
func synthesize(text: String, role: String = "controller",
		kind: String = "default", emo_alpha: float = 0.8) -> AudioStreamWAV:
	if text.strip_edges() == "":
		last_error = "空文本"
		return null
	last_error = ""
	var payload := {
		"text": text,
		"speaker": role,
		"emo_vector": preset_vector(kind),
		"emo_alpha": clampf(emo_alpha, 0.0, 1.0),
	}
	var err := _http.request(base_url.path_join("tts"),
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		last_error = "请求发不出去（%s）" % base_url
		return null
	var res: Array = await _http.request_completed
	var code := int(res[1])
	var body: PackedByteArray = res[3]
	if code != 200:
		last_error = "合成失败（HTTP %d）" % code
		return null
	return wav_from_bytes(body)


## WAV 字节 → AudioStreamWAV。Godot 自带解析，不用自己拆头。
static func wav_from_bytes(data: PackedByteArray) -> AudioStreamWAV:
	if data.size() < 44:
		return null
	# 先自己认一下头再交给引擎：不是 WAV 就直接退回，
	# 否则引擎会打一条 "Not a WAV file" 的 ERROR 日志刷屏。
	if data.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var stream := AudioStreamWAV.new()
	# ⚠️ Godot 4 里 load_from_buffer 是**静态**函数，返回一个新的 AudioStreamWAV，
	# 不是"往实例里装"。先按静态调，拿不到再退回实例写法。
	var made: Variant = AudioStreamWAV.load_from_buffer(data)
	if made is AudioStreamWAV:
		return made as AudioStreamWAV
	if not stream.load_from_buffer(data):
		return null
	return stream


## 猜这条通话属于哪一类（决定情绪）。看文字就够，不必让逻辑层再传一遍。
static func kind_of_line(side: String, text: String) -> String:
	if text.contains("没听清") or text.contains("再说一遍"):
		return "unheard"
	if text.contains("许可不完整") or text.contains("复诵有误"):
		return "query"
	if text.contains("复诵正确"):
		return "confirm"
	if text.contains("联系地面"):
		return "handoff"
	if side == "pilot":
		if text.contains("许可放行至") and text.contains("应答机"):
			return "readback"
		if text.contains("申请放行"):
			return "request"
		return "default"
	if text.contains("许可放行至"):
		return "clearance"
	return "default"
