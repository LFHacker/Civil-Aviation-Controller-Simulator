## 通播（ATIS）播发的**状态与内容**（放行机制规范 §3 + 《通播 ATIS 介绍》第一百六十条）。
##
## 纯数据层：代号推进、有效期判定、重大变化阈值、可编辑要素。不碰界面。
## 关键点：代号本身不携带信息，它是一个**版本指针** ——
## 机组报的代号和当前不一致，就是"信息可能已过期"的告警来源。
class_name AtisBroadcast
extends RefCounted

## 有效期状态
const FRESH := 0        # 有效
const AGING := 1        # 即将过期
const EXPIRED := 2      # 已过期

## 距上次发布满 50 分钟算"即将过期"，满 60 分钟算"已过期"
const AGING_MIN := 50
const EXPIRE_MIN := 60

var alpha := "A"
var issued_min := 0
var runway := ""
var transition_level := ""
var wind := ""
var visibility := ""
var ceiling := ""
var qnh := 0
var brake := ""
var hazards: Array = []
## 玩家更新时选了与实况不符的值（会作为"通播有误"的输入，后续可触发特情）
var has_error := false
## 累计更新次数
var update_count := 0


## 代号按字母顺序推进，Z 之后回到 A（玩家不能跳字母）
static func next_alpha(a: String) -> String:
	var u := a.strip_edges().to_upper()
	if u.length() != 1 or u < "A" or u > "Z":
		return "A"
	if u == "Z":
		return "A"
	return String.chr(u.unicode_at(0) + 1)


## 反向：上一版代号（A 之前回到 Z）。
## 用在 07 §7 的"机组报了个过期代号"——它报的正是上一版，而不是随便一个字母。
static func prev_alpha(a: String) -> String:
	var u := a.strip_edges().to_upper()
	if u.length() != 1 or u < "A" or u > "Z":
		return "Z"
	if u == "A":
		return "Z"
	return String.chr(u.unicode_at(0) - 1)


static func state_text(s: int) -> String:
	match s:
		FRESH: return "有效"
		AGING: return "即将过期"
		EXPIRED: return "已过期"
		_: return "未知"


## 以分钟计的播发时长（跨零点也算对）
static func age_minutes(issued: int, now_min: int) -> int:
	var age := now_min - issued
	if age < 0:
		age += 24 * 60
	return age


func state(now_min: int) -> int:
	var age := age_minutes(issued_min, now_min)
	if age >= EXPIRE_MIN:
		return EXPIRED
	if age >= AGING_MIN:
		return AGING
	return FRESH


func age(now_min: int) -> int:
	return age_minutes(issued_min, now_min)


## 能见度 → 米。CAVOK 按 9999 处理，认不出来的返回 -1。
static func vis_meters(text: String) -> int:
	var t := text.strip_edges().to_upper()
	if t == "CAVOK":
		return 9999
	var digits := ""
	for i in range(t.length()):
		var c := t[i]
		if c >= "0" and c <= "9":
			digits += c
		else:
			break
	if digits == "":
		return -1
	var v := int(digits)
	if t.contains("KM"):
		return v * 1000
	return v


## 重大变化判定（《通播 ATIS 介绍》阈值表）。返回原因；没有重大变化返回空串。
##   风向：变化 ≥ 60°，且变化前后平均风速均 ≥ 5 m/s
##   能见度：跨越 800 米阈值
##   跑道刹车效应变差、跑道/进近方式/NOTAM 变更由调用方另行判断
static func major_change(old_wind: String, old_vis: String,
		new_wind: String, new_vis: String) -> String:
	var ow := Meteo.parse_wind(old_wind)
	var nw := Meteo.parse_wind(new_wind)
	if bool(ow.get("ok", false)) and bool(nw.get("ok", false)):
		var os := Meteo.to_mps(float(ow.get("speed", 0)), String(ow.get("unit", "")))
		var ns := Meteo.to_mps(float(nw.get("speed", 0)), String(nw.get("unit", "")))
		if os >= 5.0 and ns >= 5.0:
			var d := absf(angle_difference(deg_to_rad(float(ow.get("dir", 0))),
				deg_to_rad(float(nw.get("dir", 0)))))
			if rad_to_deg(d) >= 60.0:
				return "风向变化超过 60 度"

	var ov := vis_meters(old_vis)
	var nv := vis_meters(new_vis)
	if ov >= 0 and nv >= 0:
		if (ov >= 800 and nv < 800) or (ov < 800 and nv >= 800):
			return "能见度跨越 800 米阈值"
	return ""


## 与实况是否一致（玩家选了错值 → has_error）
static func values_differ(atis_v: Dictionary, actual: Dictionary) -> bool:
	for k in ["runway", "wind", "visibility", "qnh"]:
		if not actual.has(k):
			continue
		if k == "qnh":
			if int(atis_v.get(k, 0)) != int(actual.get(k, 0)):
				return true
		elif String(atis_v.get(k, "")) != String(actual.get(k, "")):
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"alpha": alpha, "issued_min": issued_min, "runway": runway,
		"transition_level": transition_level, "wind": wind,
		"visibility": visibility, "ceiling": ceiling, "qnh": qnh,
		"brake": brake, "hazards": hazards.duplicate(),
		"has_error": has_error, "update_count": update_count,
	}


static func from_dict(d: Dictionary) -> AtisBroadcast:
	var a := AtisBroadcast.new()
	a.alpha = str(d.get("alpha", "A"))
	a.issued_min = int(d.get("issued_min", 0))
	a.runway = str(d.get("runway", ""))
	a.transition_level = str(d.get("transition_level", ""))
	a.wind = str(d.get("wind", ""))
	a.visibility = str(d.get("visibility", ""))
	a.ceiling = str(d.get("ceiling", ""))
	a.qnh = int(d.get("qnh", 0))
	a.brake = str(d.get("brake", ""))
	var hz: Variant = d.get("hazards", [])
	a.hazards = hz if hz is Array else []
	a.has_error = bool(d.get("has_error", false))
	a.update_count = int(d.get("update_count", 0))
	return a
