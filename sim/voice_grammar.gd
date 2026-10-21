## 复诵识别用的**闭集语法**生成（08 §4「听」）。
##
## 思路（实测数据见 docs/voice-design.md）：
##   开放式听写 1047 ms、置信度 32%、"东方"听成"东方舞妖怪"；
##   同样的音频走闭集语法 46~94 ms、置信度 99~100%、逐字正确。
## 所以不给识别器自由，给它**当前这架飞机可能说的几句话**：
##
##   正确复诵 1 条 + 每个安全关键项各错一位的变体
##
## 每条候选带一个语义标签（v_ok / v_qnh / v_alt / v_squawk / v_sid / v_limit），
## 识别器返回哪条标签，就等于告诉我们**机组读错了哪一项** ——
## 与 DeliveryDesk 已有的逐项复诵判定是一一对应的，不是另加一套逻辑。
##
## 生成的文本必须是**口语读法**（幺两洞洞），因为识别器听到的是人话。
class_name VoiceGrammar
extends RefCounted

## 变体标签 → 对应的安全关键项（空串表示复诵正确）
const TAGS := {
	"v_ok": "",
	"v_alt": "alt",
	"v_squawk": "squawk",
	"v_qnh": "qnh",
	"v_sid": "sid",
	"v_limit": "limit",
}

const LIMIT_FALLBACK := "ZSPD"


## 生成复诵语法的 SRGS 文本。
## param 至少要有：callsign, sid, alt, squawk, qnh；limit 可缺省。
##
## ⚠️ 每个变体是**一条独立的 public 规则**（rule id 就是标签），
## 而不是一条规则里的多个 item + <tag>：
## SAPI 桌面引擎不启用 SRGS 语义标签（实测 Semantics.Value 恒为 null），
## 但**规则名**一定会跟着识别结果回来（RecognitionResult.Grammar.RuleName）。
## 所以识别端按规则名逐条加载，返回哪条规则就等于哪一项读错。
static func build(param: Dictionary) -> String:
	var variants := variant_lines(param)
	var body := ""
	for v in variants:
		body += "\t<rule id=\"%s\" scope=\"public\">%s</rule>\n" % [
			String(v.tag), _escape(String(v.text))]
	return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" \
		+ "<grammar version=\"1.0\" xml:lang=\"zh-CN\" root=\"v_ok\" " \
		+ "xmlns=\"http://www.w3.org/2001/06/grammar\">\n" \
		+ body + "</grammar>\n"


## 规则 id 列表（识别端按这个逐条加载）
static func rule_ids(param: Dictionary) -> Array:
	var out: Array = []
	for v in variant_lines(param):
		out.append(String(v.tag))
	return out


## 所有候选句：[{tag, text}]，第一条永远是正确复诵。
static func variant_lines(param: Dictionary) -> Array:
	var cs := _spoken_callsign(String(param.get("callsign", "")))
	var sid := _spoken_sid(String(param.get("sid", "")))
	var limit := _spoken_limit(String(param.get("limit", LIMIT_FALLBACK)))
	var alt := int(param.get("alt", 0))
	var sq := String(param.get("squawk", ""))
	var qnh := int(param.get("qnh", 0))

	var out: Array = []
	var seen := {}
	var add := func(tag: String, a: int, s: String, q: int, sd: String, lim: String) -> void:
		var line := _line(cs, lim, sd, a, s, q)
		if seen.has(line):
			return
		seen[line] = true
		out.append({"tag": tag, "text": line})

	add.call("v_ok", alt, sq, qnh, sid, limit)
	# 高度读错：换成另一个合法高度层（错一位的数字往往读不出来，工程上取整百档）
	var alt_bad := alt + 1000
	if DeliveryDesk.ALT_OPTIONS.has(alt):
		var i := DeliveryDesk.ALT_OPTIONS.find(alt)
		alt_bad = int(DeliveryDesk.ALT_OPTIONS[(i + 1) % DeliveryDesk.ALT_OPTIONS.size()])
	add.call("v_alt", alt_bad, sq, qnh, sid, limit)
	# 应答机读错：末位 +1（同一个读法位置错，最像真实口误）
	add.call("v_squawk", alt, _bump_last(sq), qnh, sid, limit)
	# 修正海压读错：末位 +1
	add.call("v_qnh", alt, sq, qnh + 1 if _qnh_ok(qnh + 1) else qnh - 1, sid, limit)
	# 离场程序读错：换成另一个程序
	add.call("v_sid", alt, sq, qnh, _other_sid(sid), limit)
	# 放行界限读错：换成另一个目的地
	add.call("v_limit", alt, sq, qnh, sid, _other_limit(limit))
	return out


## 识别结果的标签 → {ok, wrong}。空标签当作"没判出来"，不当成正确。
static func parse_tag(tag: String) -> Dictionary:
	var t := tag.strip_edges()
	if t == "":
		return {"ok": false, "wrong": "", "known": false}
	if not TAGS.has(t):
		return {"ok": false, "wrong": "", "known": false}
	var wrong := String(TAGS[t])
	return {"ok": wrong == "", "wrong": wrong, "known": true}


## 口语里呼号的读法（CCA1501 → CCA幺五洞幺）
static func _spoken_callsign(code: String) -> String:
	var out := code
	for a in Voice.AIRLINES:
		if code.begins_with(a):
			out = String(Voice.AIRLINE_TEXT.get(a, a)) + Radio.read_digits(code.substr(a.length()))
			break
	return _flat(out)


static func _spoken_sid(sid: String) -> String:
	# 工程里的 SID 写成 "RUMUK 8D"，读法表里是 "RUMUK8D"，查表前先去掉空白
	var key := sid.replace(" ", "")
	if Voice.SID_TEXT.has(key):
		return _flat(String(Voice.SID_TEXT[key]))
	if Voice.SID_TEXT.has(sid):
		return _flat(String(Voice.SID_TEXT[sid]))
	return _flat(sid)


static func _spoken_limit(limit: String) -> String:
	if Voice.DEST_TEXT.has(limit):
		return _flat(String(Voice.DEST_TEXT[limit]))
	return _flat(limit)


## 一句完整复诵的口语文本。顺序与 DeliveryDesk.readback_text_of 一致：
## 许可放行至 <界限> 按 <程序> 离场 初始高度 <米> 应答机 <编码> 修正海压 <气压> <呼号>
static func _line(cs: String, limit: String, sid: String, alt: int,
		squawk: String, qnh: int) -> String:
	return "%s许可放行至%s按%s离场初始高度%s米应答机%s修正海压%s%s" % [
		_flat(cs), _flat(limit), _flat(sid),
		Radio.read_digits(str(alt)), Radio.read_digits(_flat(squawk)),
		Radio.read_digits(str(qnh)), _flat(cs)]


static func _bump_last(s: String) -> String:
	if s == "":
		return s
	var n := s[s.length() - 1]
	var v := "01234567".find(n)
	if v < 0:
		return s
	return s.substr(0, s.length() - 1) + "01234567"[(v + 1) % 8]


static func _qnh_ok(q: int) -> bool:
	return q >= 900 and q <= 1100


static func _other_sid(sid: String) -> String:
	for k in Voice.SID_TEXT.keys():
		if String(Voice.SID_TEXT[k]) != sid:
			return _flat(String(Voice.SID_TEXT[k]))
	return sid


static func _other_limit(limit: String) -> String:
	for k in Voice.DEST_TEXT.keys():
		if String(Voice.DEST_TEXT[k]) != limit:
			return _flat(String(Voice.DEST_TEXT[k]))
	return limit


## 读法的中文数字（幺拐勾）与字母混排时，识别器对空白很敏感，统一压掉
static func _flat(s: String) -> String:
	return s.replace(" ", "").replace("\t", "")


static func _escape(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
