## 语音播报的**片段拼装**（08 §4 语音档的第一半：机组"说"）。
##
## 思路：不按整句合成，而是把**固定短语**和**数字**做成小片段，
## 运行时按模板拼播放序列。好处：
##   · 片段库很小（10 个数字 + 几十条短语），一次性生成后随游戏分发；
##   · 不需要运行时联网、不把 API key 塞进游戏、没有合成延迟；
##   · 音色统一，不会一句话一个味。
##
## 这个文件只管"该播哪几段、什么顺序"，不碰播放器也不碰合成引擎。
class_name Voice
extends RefCounted

## 数字标准读法（与 Radio.DIGIT_READ 一致）
const DIGITS := ["洞", "幺", "两", "三", "四", "五", "六", "拐", "八", "勾"]

## 片段 id 的前缀约定：
##   d0..d9        单个数字
##   p_xxx         固定短语（短语表见 FIXED_PHRASES）
##   ap_xxx        航空公司呼号前缀
const DIGIT_PREFIX := "d"
const PHRASE_PREFIX := "p_"
const AIRLINE_PREFIX := "ap_"


## 固定短语表：id → 文本。生成音频时按这张表逐条合成。
const FIXED_PHRASES := {
	"p_clearance_to": "许可放行至",
	"p_via": "经",
	"p_departure": "离场",
	"p_initial_alt": "初始高度",
	"p_meter": "米",
	"p_squawk": "应答机",
	"p_qnh": "修正海压",
	"p_readback_ok": "复诵正确",
	"p_contact_ground": "联系地面",
	"p_goodbye": "再见",
	"p_request": "申请放行至",
	"p_stand": "停机位",
	"p_atis_received": "已抄收通播",
	"p_not_received": "未抄收通播",
	"p_say_again": "没听清，请再说一遍",
	"p_ground_ready": "地面准备好了",
	"p_copy": "收到",
	"p_wait": "请稍等",
	"p_repeat": "重复一遍",
	"p_query_alt": "高度不可用，请指定其他高度",
	"p_query_squawk": "应答机编码已被占用，请重新指定",
	"p_incomplete": "许可不完整，请重复",
}

const AIRLINES := ["CCA", "CES", "CSN", "CHH", "CQH"]


## 一个数字串 → 数字片段序列（1200 → [d1,d2,d0,d0]）
static func digits(num_text: String) -> Array:
	var out: Array = []
	for i in range(num_text.length()):
		var c := num_text[i]
		var idx := "0123456789".find(c)
		if idx >= 0:
			out.append(DIGIT_PREFIX + str(idx))
	return out


## 呼号 → 片段序列（CCA1501 → [ap_CCA, d1, d5, d0, d1]）
static func callsign(code: String) -> Array:
	var out: Array = []
	var prefix := ""
	for a in AIRLINES:
		if code.begins_with(a):
			prefix = a
			break
	if prefix != "":
		out.append(AIRLINE_PREFIX + prefix)
		out.append_array(digits(code.substr(prefix.length())))
	else:
		out.append_array(digits(code))
	return out


## 一条许可（放行 -> 机组）的播报片段
static func clearance(callsign_code: String, limit: String, sid: String,
		route: String, alt_m: int, squawk: String, qnh: int) -> Array:
	var out: Array = []
	out.append_array(callsign(callsign_code))
	out.append(PHRASE_PREFIX + "clearance_to")
	out.append_array(_spell(limit))
	out.append(PHRASE_PREFIX + "departure")
	out.append(PHRASE_PREFIX + "via")
	out.append_array(_spell(route))
	out.append(PHRASE_PREFIX + "initial_alt")
	out.append_array(digits(str(alt_m)))
	out.append(PHRASE_PREFIX + "meter")
	out.append(PHRASE_PREFIX + "squawk")
	out.append_array(digits(squawk))
	out.append(PHRASE_PREFIX + "qnh")
	out.append_array(digits(str(qnh)))
	return out


## 复诵（机组 -> 放行）：安全关键项 + 完整呼号
static func readback(callsign_code: String, limit: String, sid: String,
		alt_m: int, squawk: String, qnh: int) -> Array:
	var out: Array = []
	out.append(PHRASE_PREFIX + "clearance_to")
	out.append_array(_spell(limit))
	out.append(PHRASE_PREFIX + "departure")
	out.append_array(_spell(sid))
	out.append(PHRASE_PREFIX + "initial_alt")
	out.append_array(digits(str(alt_m)))
	out.append(PHRASE_PREFIX + "meter")
	out.append(PHRASE_PREFIX + "squawk")
	out.append_array(digits(squawk))
	out.append(PHRASE_PREFIX + "qnh")
	out.append_array(digits(str(qnh)))
	out.append_array(callsign(callsign_code))
	return out


## 首次呼叫（机组 -> 放行）
static func request(callsign_code: String, stand: String, dest: String,
		atis_ok: bool) -> Array:
	var out: Array = []
	out.append_array(callsign(callsign_code))
	out.append(PHRASE_PREFIX + "stand")
	out.append_array(_spell(stand))
	if atis_ok:
		out.append(PHRASE_PREFIX + "atis_received")
	else:
		out.append(PHRASE_PREFIX + "not_received")
	out.append(PHRASE_PREFIX + "request")
	out.append_array(_spell(dest))
	return out


## 移交地面
static func handoff(callsign_code: String, ground_freq: String) -> Array:
	var out: Array = []
	out.append_array(callsign(callsign_code))
	out.append(PHRASE_PREFIX + "contact_ground")
	out.append_array(digits(ground_freq.replace(".", "")))
	out.append(PHRASE_PREFIX + "goodbye")
	return out


## 把用户文字里认不出来的部分跳过：字母逐个用数字片段读不出来，
## 所以这里只保留"能读出来的片段"，宁可少念也不乱念。
static func _spell(text: String) -> Array:
	return digits(text)


## 片段总数（生成音频前用来核对清单）
static func piece_count() -> int:
	return DIGITS.size() + FIXED_PHRASES.size() + AIRLINES.size()
