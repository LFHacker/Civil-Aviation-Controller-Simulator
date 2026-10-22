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
	"p_by": "按",
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

## 进离场程序的中文读法：中文管制通话里读「字母 + 序号」，
## 不读航路号（航路在飞行计划里，放行通话不念），所以这里每个程序一整段。
const SID_TEXT := {
	"RUMUK8D": "RUMUK 八号",
	"BETON3A": "BETON 三号",
	"SASAN5B": "SASAN 五号",
	"KAMAN2C": "KAMAN 二号",
}

## 目的地机场读法（demo 机场的常用目的地）
const DEST_TEXT := {
	"ZSPD": "浦东",
	"ZBAA": "首都",
	"ZBTJ": "滨海",
	"ZBSJ": "正定",
	"ZSNJ": "禄口",
	"ZUUU": "双流",
	"ZSSS": "虹桥",
	"ZGGG": "白云",
}

const AIRLINES := ["CCA", "CES", "CSN", "CHH", "CQH"]

## 公司呼号的中文读法（生成音频片段时用；中国管制通话里读中文名，不读字母）
const AIRLINE_TEXT := {
	"CCA": "国航",
	"CES": "东方",
	"CSN": "南方",
	"CHH": "海南",
	"CQH": "春秋",
}


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
## 注意：中国管制放行通话**不念航路号**，只念进离场程序，航路在飞行计划里。
static func clearance(callsign_code: String, sid_id: String, dest_id: String,
		alt_m: int, squawk: String, qnh: int) -> Array:
	var out: Array = []
	out.append_array(callsign(callsign_code))
	out.append(PHRASE_PREFIX + "clearance_to")
	out.append_array(dest(dest_id))
	out.append(PHRASE_PREFIX + "by")
	out.append_array(sid(sid_id))
	out.append(PHRASE_PREFIX + "departure")
	out.append(PHRASE_PREFIX + "initial_alt")
	out.append_array(digits(str(alt_m)))
	out.append(PHRASE_PREFIX + "meter")
	out.append(PHRASE_PREFIX + "squawk")
	out.append_array(digits(squawk))
	out.append(PHRASE_PREFIX + "qnh")
	out.append_array(digits(str(qnh)))
	return out


## 复诵（机组 -> 放行）：安全关键项 + 完整呼号
static func readback(callsign_code: String, sid_id: String, dest_id: String,
		alt_m: int, squawk: String, qnh: int) -> Array:
	var out: Array = []
	out.append(PHRASE_PREFIX + "clearance_to")
	out.append_array(dest(dest_id))
	out.append(PHRASE_PREFIX + "by")
	out.append_array(sid(sid_id))
	out.append(PHRASE_PREFIX + "departure")
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
static func request(callsign_code: String, stand: String, dest_id: String,
		atis_ok: bool) -> Array:
	var out: Array = []
	out.append_array(callsign(callsign_code))
	out.append(PHRASE_PREFIX + "stand")
	out.append_array(digits(stand))
	if atis_ok:
		out.append(PHRASE_PREFIX + "atis_received")
	else:
		out.append(PHRASE_PREFIX + "not_received")
	out.append(PHRASE_PREFIX + "request")
	out.append_array(dest(dest_id))
	return out


## 移交地面
static func handoff(callsign_code: String, ground_freq: String) -> Array:
	var out: Array = []
	out.append_array(callsign(callsign_code))
	out.append(PHRASE_PREFIX + "contact_ground")
	out.append_array(digits(ground_freq.replace(".", "")))
	out.append(PHRASE_PREFIX + "goodbye")
	return out


## 进离场程序：有中文读法就用专门片段，没有就退回逐位读（宁可少念不乱念）
##
## ⚠️ 工程里存的是 "RUMUK 8D"（带空格），读法表的键是 "RUMUK8D"。
## 不先去掉空白就查不到，结果**整段离场程序被静默丢掉**（真的发生过：
## 播出来的许可里只有"许可放行至…初始高度…"，没有"按 XX 离场"）。
static func sid(sid_id: String) -> Array:
	if sid_id == "":
		return []
	var key := sid_id.replace(" ", "").replace("\t", "")
	if SID_TEXT.has(key):
		return ["sid_" + key]
	if SID_TEXT.has(sid_id):
		return ["sid_" + sid_id]
	return digits(sid_id)


## 目的地：同上
static func dest(dest_id: String) -> Array:
	if dest_id == "":
		return []
	var key := dest_id.replace(" ", "").replace("\t", "")
	if DEST_TEXT.has(key):
		return ["dest_" + key]
	if DEST_TEXT.has(dest_id):
		return ["dest_" + dest_id]
	return digits(dest_id)


## 片段总数（生成音频前用来核对清单）
static func piece_count() -> int:
	return DIGITS.size() + FIXED_PHRASES.size() + AIRLINES.size() \
		+ SID_TEXT.size() + DEST_TEXT.size()
