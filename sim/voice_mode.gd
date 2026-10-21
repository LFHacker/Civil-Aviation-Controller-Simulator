## 高级模式（真实语音通话，08 §4）的**处理链路**——纯逻辑，零渲染依赖。
##
## 文档在这里只规定了"ASR 转录 → 语义解析 → 要素提取 → 校验"这条链，
## 明确写「此处不做技术选型」。本工程的选型是**确定性解析**而不是 LLM：
##   · 管制通话是闭集（08 §3.3 已经把七项要素固定成槽位），不需要语义模型；
##   · 确定性解析可测、零延迟、不依赖网络，也不会今天对明天错。
##
## 这个文件只管两件事：
##   ① 把 ASR 的原始转录**规范成可解析的文本**（「幺两洞洞」→「1200」）；
##   ② 按文档给出的四种回退语义判定该干什么（发送 / 没听清 / 呼号不符 / 缺项）。
## 麦克风与识别引擎不在这里，接在 issue_voice() 的入参上。
class_name VoiceMode
extends RefCounted

## 08 §4.4 五项辅助功能的默认状态（可在设置里开关）
const AUX_DEFAULTS := {
	"transcript": true,        # 转录文本显示
	"phrase_hint": true,       # 标准用语提示（只给结构，不给具体数值）
	"reference": true,         # 参考面板（ATIS / 飞行计划）保持可见
	"read_numbers": false,     # 点击数值朗读标准读法
	"read_template": false,    # 「听示例」朗读一条标准通话（只示范，不发送）
}

## 08 §4.4 / §4.5：高级模式默认**不允许**文本输入兜底，
## 只有无障碍开关打开时才放行（"语音失败时允许文本输入"，默认关闭）。
const TEXT_FALLBACK_DEFAULT := false

## ASR 置信度门槛：低于这个值就模拟"驾驶舱没听清"，而不是提示玩家重输（§4.3）
const CONF_THRESHOLD := 0.55
## 教学关卡的放宽门槛（§4.6：教学关卡不得因发音问题卡住玩家）
const CONF_THRESHOLD_TEACHING := 0.25

## 通话类型关键词：顺序有意义（先匹配更具体的）
const KINDS := [
	{"kind": "handoff", "keys": ["联系地面", "联系塔台", "移交"]},
	{"kind": "clearance", "keys": ["许可放行", "放行至", "可以放行"]},
	{"kind": "rb_ok", "keys": ["复诵正确", "复诵无误", "正确"]},
	{"kind": "rb_bad", "keys": ["复诵有误", "复诵不正确", "有误"]},
	{"kind": "repeat", "keys": ["重复一遍", "再说一遍", "重复"]},
	{"kind": "wait", "keys": ["请稍等", "等一下", "稍等"]},
	{"kind": "request", "keys": ["申请放行", "请求放行"]},
]


## 把 ASR 转录规范成可解析文本：
##   · 航空公司中文名 → ICAO 代码（「东方五幺拐五」→「CES5175」）
##   · 标准读法数字 → 阿拉伯数字（「幺两洞洞」→「1200」）
##   · 全角标点/空白压平
## 只做替换，不猜内容 —— 猜错了比没猜更糟（玩家要在发送前核对转录）。
static func normalize(raw: String) -> String:
	var t := raw.strip_edges()
	# 全角转半角（ASR 常带全角逗号句号）
	t = t.replace("，", ",").replace("。", ".").replace("、", ",")
	t = t.replace("；", ";").replace("：", ":")
	# 航空公司中文名 → ICAO（长名在前，避免"南方"吃掉"南方航空"）
	var names: Array = Voice.AIRLINE_TEXT.keys()
	names.sort_custom(func(a, b): return String(a).length() > String(b).length())
	for code in names:
		t = t.replace(String(Voice.AIRLINE_TEXT[code]), String(code))
	# 标准读法数字 → 阿拉伯数字
	for i in range(10):
		t = t.replace(Radio.DIGIT_READ[i], str(i))
	return t


## 通话类型（08 §4.2：先要判出玩家说的是哪一类）
static func kind_of(text: String) -> String:
	for row in KINDS:
		for k in row.keys:
			if text.contains(String(k)):
				return String(row.kind)
	return ""


## 从转录里找呼号（用于 §4.3 的"呼号与当前选中航班不符"）
## known：当前席位所有在册呼号；返回找到的那个，找不到返回 ""。
static func find_callsign(text: String, known: Array) -> String:
	for c in known:
		if text.contains(String(c)):
			return String(c)
	return ""


## 置信度是否够（§4.3 低于阈值 → 模拟驾驶舱没听清）
static func confident(conf: float, teaching: bool = false) -> bool:
	var thr := CONF_THRESHOLD_TEACHING if teaching else CONF_THRESHOLD
	return conf >= thr


## 解析转录里的通话要素。返回 {kind, callsign, slots, error}
## slots 的键与 Radio.clearance_slots() 对齐：callsign/limit/sid/route/alt/squawk/qnh
## 只填**能确定**的项，缺的留空由调用方按文档判定（不要瞎猜高度）。
##
## ⚠️ 呼号里本身带 4 位数字（CES5175），和应答机编码会撞。
## 真实通话里这两者确实有歧义，所以扫数字之前必须先把呼号整段遮掉，
## 否则「CES5175…应答机 4321」会被读成应答机 5175 —— 真的踩过。
static func parse(text: String, known: Array = []) -> Dictionary:
	var t := text
	var scan := mask_callsigns(t, known)
	var out := {"kind": kind_of(t), "slots": {}}
	var slots: Dictionary = out.slots
	# 放行界限 / 目的地：常见机场中文名或代码
	for code in Voice.DEST_TEXT.keys():
		if t.contains(String(code)) or t.contains(String(Voice.DEST_TEXT[code])):
			slots["limit"] = String(code)
			break
	# 离场程序：数据驱动，认代码本身
	for sid in DeliveryDesk.SIDS:
		if t.contains(String(sid)):
			slots["sid"] = String(sid)
			break
	# 初始高度：只在合法高度层里认（避免把应答机读成高度）
	for a in DeliveryDesk.ALT_OPTIONS:
		if scan.contains(str(a)):
			slots["alt"] = int(a)
			break
	# 应答机：四位八进制，且不等于已经认到的高度
	var alt := int(slots.get("alt", 0))
	var sq := DeliveryDesk.find_squawk_in_text(scan, alt)
	if sq != "":
		slots["squawk"] = sq
	out["slots"] = slots
	return out


## 把呼号从文本里遮成等长空白，避免它的数字被当成高度/应答机。
## 认两种：ICAO 形如 CCA1501；以及调用方给的已知呼号表。
static func mask_callsigns(text: String, known: Array = []) -> String:
	var out := text
	for c in known:
		var cs := String(c)
		if cs != "" and out.contains(cs):
			out = out.replace(cs, _blank(cs))
	var re := RegEx.new()
	re.compile("[A-Z]{3}[0-9]{3,4}")
	for m in re.search_all(text):
		var seg := m.get_string()
		if out.contains(seg):
			out = out.replace(seg, _blank(seg))
	return out


static func _blank(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		out += " "
	return out


## 完整判定：给定转录、置信度、当前选中航班，返回该做什么。
##   action = "send"      照发（交给 issue_free_text 走与进阶模式一致的校验）
##          = "unheard"   模拟驾驶舱没听清（§4.3 / §4.6 表里的两行"没听清"）
##          = "mismatch"  呼号不符，请确认（§4.3）
##          = "empty"     转录为空（等同没听清）
## 注意：这里**不**判七项要素齐不齐 —— 那是校验环节（与进阶模式同一套），
## 由 issue_free_text 负责，避免两处各写一套规则。
static func decide(raw: String, conf: float, selected: String, known: Array,
		teaching: bool = false) -> Dictionary:
	var text := normalize(raw)
	if text.strip_edges() == "":
		return {"action": "unheard", "text": text, "reason": "转写为空"}
	if not confident(conf, teaching):
		return {"action": "unheard", "text": text,
			"reason": "置信度 %.0f%% 低于门槛" % (conf * 100.0)}
	var said := find_callsign(text, known)
	if said != "" and said != selected:
		return {"action": "mismatch", "text": text, "said": said,
			"reason": "说的呼号是 %s" % said}
	return {"action": "send", "text": text, "kind": kind_of(text)}


## 高级模式是否允许用文本代替语音（§4.5 无障碍开关，默认关闭）
static func text_fallback_allowed(flag: Variant) -> bool:
	if flag == null:
		return TEXT_FALLBACK_DEFAULT
	return bool(flag)


## 辅助开关的当前值（缺省即默认）
static func aux_enabled(settings: Dictionary, key: String) -> bool:
	if not AUX_DEFAULTS.has(key):
		return false
	if settings.has(key):
		return bool(settings[key])
	return bool(AUX_DEFAULTS[key])
