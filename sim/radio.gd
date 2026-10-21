## 陆空通话的文本工具（08 陆空对话机制 / MH/T 4014 通话用语）。
##
## 纯静态函数，零依赖：数字标准读法、频率读法、通话骨架（槽位）。
## 语音识别（ASR）不在这里 —— 它转出来的文本最后也是走这套规范化。
class_name Radio
extends RefCounted

## 民航数字标准读法：洞幺两三四五六拐八勾
const DIGIT_READ := ["洞", "幺", "两", "三", "四", "五", "六", "拐", "八", "勾"]

const GLYPHS := "0123456789"


## 逐位读：1200 → 幺两洞洞
static func read_digits(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		out += _read_char(text[i])
	return out


## 整数读法（带单位）
static func read_number(n: int, unit: String = "") -> String:
	var s := read_digits(str(absi(n)))
	if n < 0:
		s = "负" + s
	return s + unit


## 频率读法：121.950 → 幺两幺点九五洞
static func read_freq(freq: String) -> String:
	var out := ""
	for i in range(freq.length()):
		var c := freq[i]
		if c == ".":
			out += "点"
		else:
			out += _read_char(c)
	return out


## 呼号读法：CCA1501 → CCA幺五洞幺（字母照读，数字按读法）
static func read_callsign(callsign: String) -> String:
	var out := ""
	for i in range(callsign.length()):
		out += _read_char(callsign[i])
	return out


static func _read_char(c: String) -> String:
	var idx := GLYPHS.find(c)
	if idx >= 0:
		return DIGIT_READ[idx]
	return c


## 放行许可的通话骨架（08 §3.3）。每个元素是 {text: 固定文本} 或
## {slot: 键名, label: 提示}。进阶模式按这个骨架逐槽填入。
static func clearance_slots() -> Array:
	return [
		{"slot": "atc", "label": "放行席呼号"},
		{"text": "，"},
		{"slot": "callsign", "label": "己方呼号"},
		{"text": "，许可放行至 "},
		{"slot": "limit", "label": "放行界限"},
		{"text": "，按 "},
		{"slot": "sid", "label": "离场程序"},
		{"text": " 离场，经 "},
		{"slot": "route", "label": "航路"},
		{"text": "，初始高度 "},
		{"slot": "alt", "label": "初始高度"},
		{"text": " 米，应答机 "},
		{"slot": "squawk", "label": "应答机"},
		{"text": "，修正海压 "},
		{"slot": "qnh", "label": "修正海压"},
		{"text": "。"},
	]


## 初始联系骨架（08 §7.1 申请放行）
static func request_slots() -> Array:
	return [
		{"slot": "atc", "label": "放行席呼号"},
		{"text": "，"},
		{"slot": "callsign", "label": "己方呼号"},
		{"text": "，停机位 "},
		{"slot": "stand", "label": "机位"},
		{"text": "，"},
		{"slot": "type", "label": "机型"},
		{"text": "，"},
		{"slot": "atis", "label": "通播抄收状态"},
		{"text": "，请求放行至 "},
		{"slot": "dest", "label": "目的地"},
		{"text": "。"},
	]


## 把填写结果拼成完整通话。空槽位原样保留 [标签]，方便一眼看出缺什么。
static func assemble(slots: Array, filled: Dictionary) -> String:
	var out := ""
	for it in slots:
		var d: Dictionary = it
		if d.has("text"):
			out += String(d.text)
			continue
		var key := String(d.get("slot", ""))
		var v := str(filled.get(key, ""))
		out += v if v != "" else "[%s]" % String(d.get("label", key))
	return out


## 还差哪些槽位没填（进阶模式的"发送"按钮靠这个判断）
static func missing_slots(slots: Array, filled: Dictionary) -> Array:
	var out: Array = []
	for it in slots:
		var d: Dictionary = it
		if not d.has("slot"):
			continue
		var key := String(d.slot)
		if str(filled.get(key, "")) == "":
			out.append(key)
	return out


## 各席位的通话类型清单（08 §7）。地面/塔台/进近还没有玩法，先把清单落成数据，
## 后面做那些席位时按这张表实现，不用再翻文档。
const CALL_TYPES := {
	"delivery": [
		{"type": "申请放行", "dir": "pilot",
			"items": ["位置", "机型", "ATIS 状态", "目的地"]},
		{"type": "发布放行许可", "dir": "atc",
			"items": ["七项法定要素", "离场情报"]},
		{"type": "复诵", "dir": "pilot", "items": ["安全关键项", "完整呼号"]},
		{"type": "复诵确认/纠正", "dir": "atc", "items": ["确认", "或正确内容"]},
		{"type": "移交地面", "dir": "atc", "items": ["地面席频率"]},
	],
	"ground": [
		{"type": "申请推出/开车", "dir": "pilot", "items": ["呼号", "位置", "请求"]},
		{"type": "发布推出/开车许可", "dir": "atc",
			"items": ["推出方向", "使用跑道", "开车许可"]},
		{"type": "申请滑行", "dir": "pilot", "items": ["呼号", "位置", "请求"]},
		{"type": "发布滑行许可", "dir": "atc",
			"items": ["滑行路线", "等待点", "跑道号"]},
		{"type": "移交塔台", "dir": "atc", "items": ["塔台频率"]},
	],
	"tower": [
		{"type": "申请起飞", "dir": "pilot", "items": ["呼号", "位置", "请求"]},
		{"type": "发布起飞许可", "dir": "atc",
			"items": ["跑道号", "起飞许可", "风向风速"]},
		{"type": "移交进近/区调", "dir": "atc", "items": ["后续管制单位频率"]},
	],
	"approach": [],
	"center": [],
}


## 某席位需要支持的通话类型（08 §7）
static func call_types(seat: String) -> Array:
	var t: Variant = CALL_TYPES.get(seat, [])
	return t if t is Array else []


## 教学引导（08 §10）：首次上手时按对话模式给一句话提示
static func teaching_hint(mode: String) -> String:
	if mode == "preset":
		return "点下面任意一条候选通话即可发出；不确定就先用「请稍等」。"
	if mode == "text":
		return "输入完整通话，系统按关键词校验七项要素。"
	if mode == "voice":
		return "按住通话键，把完整许可说出来（含呼号、界限、程序、高度、编码、修正海压）。先看下方参考值再开口。"
	return "逐项选好离场程序、高度、应答机，再点「发放行许可」。"

static func check_slots(slots: Array, filled: Dictionary) -> Dictionary:
	var miss := missing_slots(slots, filled)
	if not miss.is_empty():
		return {"ok": false, "error": "还有 %d 个槽位没填：%s" % [
			miss.size(), "、".join(miss)]}
	return {"ok": true, "error": ""}
