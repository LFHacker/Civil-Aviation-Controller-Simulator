## 飞行计划审查（《放行管制机制规范》第一节）。
##
## 纯逻辑：把"计划值"与"当前有效值"逐项对照，给出每行状态；
## 三种处置（修正 / 协调 / 标记已审查）的结果由调用方记在 flight.review 里。
## 这里不碰任何 Control，可以在无头环境跑断言。
class_name PlanReview
extends RefCounted

## 单行状态
const OK := 0        # 一致
const BAD := 1       # 不一致且尚未处置
const FIXED := 2     # 已按当前有效值修正
const WAIVED := 3    # 已审查（有保留）
const INFO := 4      # 只显示，不参与判定（起飞重量 / 续航时间）

## 对照字段表：顺序就是界面上从上到下的顺序
const FIELDS := [
	{"key": "airport", "label": "起降机场"},
	{"key": "route", "label": "航路"},
	{"key": "type", "label": "机型"},
	{"key": "wake", "label": "尾流类别"},
	{"key": "alternate", "label": "备降场"},
	{"key": "altitude", "label": "初始高度"},
	{"key": "weight", "label": "起飞重量"},
	{"key": "endurance", "label": "续航时间"},
]

## 可以处置的字段（起飞重量/续航时间只显示，不参与）
const FIXABLE := ["airport", "route", "type", "wake", "alternate", "altitude"]


static func is_fixable(key: String) -> bool:
	return FIXABLE.has(key)


static func label_of(key: String) -> String:
	for f in FIELDS:
		if String(f.key) == key:
			return String(f.label)
	return key


## 尾流类别（ICAO Doc 8643 口径，这里只用到 M/H 两档）
static func wake_of(types: Dictionary, type_code: String) -> String:
	var t: Variant = types.get(type_code, null)
	if t is Dictionary:
		return str((t as Dictionary).get("wake", ""))
	# 也允许写成 {"B738": "M"}
	if t is String:
		return String(t)
	return ""


## 生成对照行。ref 需要包含：airport_id / types / routes / alternates / loa
static func rows(f: Flight, ref: Dictionary) -> Array:
	var out: Array = []
	var types: Dictionary = ref.get("types", {})
	var routes: Dictionary = ref.get("routes", {})
	var alts: Array = ref.get("alternates", [])
	var airport_id := str(ref.get("airport_id", ""))

	# 1) 起降机场：计划写的起飞机场必须是本场
	out.append(_row("airport", "起降机场", f.plan_origin, airport_id,
		f.plan_origin == "" or f.plan_origin == airport_id))

	# 2) 航路：该 SID 在当前航路结构里对应的航路
	var want_route := str(routes.get(f.sid, ""))
	var shown_route := want_route if want_route != "" else (f.route if f.route != "" else "—")
	out.append(_row("route", "航路", f.plan_route, shown_route,
		f.plan_route == "" or want_route == "" or f.plan_route == want_route))

	# 3) 机型：必须在机型库里
	var type_ok := types.has(f.plan_type) and f.plan_type != ""
	out.append(_row("type", "机型", f.plan_type,
		f.plan_type if type_ok else "机型库无此机型", type_ok or f.plan_type == ""))

	# 4) 尾流类别：必须与机型库一致
	var want_wake := wake_of(types, f.plan_type)
	out.append(_row("wake", "尾流类别", f.plan_wake,
		want_wake if want_wake != "" else "—",
		f.plan_wake == "" or want_wake == "" or f.plan_wake == want_wake))

	# 5) 备降场：必须在当前天气下可用的备降场清单里
	var alt_ok := f.plan_alternate == "" or alts.is_empty() \
		or alts.has(f.plan_alternate)
	out.append(_row("alternate", "备降场", f.plan_alternate,
		_alt_text(alts) if not alt_ok else f.plan_alternate, alt_ok))

	# 6) 初始高度：必须落在该 SID 的管制协议高度带里
	var band := loa_band(ref, f.sid)
	var alt_in := band.is_empty() or (f.plan_alt_m >= int(band.alt_min)
		and f.plan_alt_m <= int(band.alt_max))
	out.append(_row("altitude", "初始高度",
		"%d 米" % f.plan_alt_m if f.plan_alt_m > 0 else "",
		("%d–%d 米" % [int(band.get("alt_min", 0)), int(band.get("alt_max", 0))]) \
			if not band.is_empty() else "—",
		alt_in))

	# 7/8) 只显示
	var tow := ""
	if f.plan_tow_t > 0:
		tow = "%d 吨" % f.plan_tow_t
	var r7 := _row("weight", "起飞重量", tow, tow, true)
	r7.state = INFO
	out.append(r7)
	var r8 := _row("endurance", "续航时间", f.plan_endurance, f.plan_endurance, true)
	r8.state = INFO
	out.append(r8)
	return out


## 把 player 的处置结果叠到行上。
static func with_decisions(base: Array, decisions: Dictionary) -> Array:
	var out: Array = []
	for r in base:
		var d: Dictionary = (r as Dictionary).duplicate()
		var key := String(d.get("key", ""))
		if decisions.has(key):
			var s := int(decisions[key])
			if s == FIXED or s == WAIVED:
				d["state"] = s
		out.append(d)
	return out


## 还有没有"红色未处置"的项。高阶模式下系统不标红，所以这里也返回 false
## —— 玩家可以带着漏检完成审查，后果由评分承担（规范 §11）。
static func has_blocking(rows_in: Array, difficulty: String) -> bool:
	if difficulty == "hard":
		return false
	for r in rows_in:
		if int((r as Dictionary).get("state", OK)) == BAD:
			return true
	return false


## 漏检了几项（高阶模式完成审查时统计，进评分）
static func missed_count(rows_in: Array) -> int:
	var n := 0
	for r in rows_in:
		if int((r as Dictionary).get("state", OK)) == BAD:
			n += 1
	return n


static func state_text(state: int) -> String:
	match state:
		OK: return "一致"
		BAD: return "不一致"
		FIXED: return "已修正"
		WAIVED: return "已审查"
		INFO: return "—"
		_: return "—"


## 该 SID 当前生效的管制协议高度带；没有协议就返回空字典。
static func loa_band(ref: Dictionary, sid: String) -> Dictionary:
	var loa: Variant = ref.get("loa", [])
	if not (loa is Array):
		return {}
	for e in loa:
		if e is Dictionary and String((e as Dictionary).get("sid", "")) == sid:
			return e
	return {}


static func _alt_text(alts: Array) -> String:
	if alts.is_empty():
		return "—"
	var parts := PackedStringArray()
	for a in alts:
		parts.append(str(a))
	return "不可用，当前可用：" + " / ".join(parts)


static func _row(key: String, label: String, planned: String,
		current: String, same: bool) -> Dictionary:
	return {
		"key": key,
		"label": label,
		"planned": planned,
		"current": current,
		"state": OK if same else BAD,
		"same": same,
	}
