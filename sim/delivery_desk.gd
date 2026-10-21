## 放行席（Delivery）的业务逻辑。
##
## 只管"航班排队 → 发放行许可 → 等复诵 → 判断复诵对不对"这条链路，
## 不碰任何界面。所有时间都以仿真秒传入，方便无头测试。
class_name DeliveryDesk
extends RefCounted

const SIDS := ["RUMUK 8D", "BETON 3A", "SASAN 5B", "KAMAN 2C"]
const ALT_OPTIONS := [3000, 4000, 5000, 6000]
const AIRLINES := ["CCA", "CES", "CSN", "CHH", "CQH"]
const DESTS := ["ZBAA", "ZSPD", "ZGGG", "ZUUU", "ZSSS"]
const TYPES := ["B738", "A320", "A321", "B789"]

## 离场程序 → 后续飞行航路。
## 放行许可第（四）项要求写明"飞行的航路或者航线"，只给 SID 是不够的。
## 这些航路点是配合虚拟机场 ZDEM 编的演示数据，不是真实航路。
const SID_ROUTES := {
	"RUMUK 8D": "W105 LADIX",
	"BETON 3A": "B330 SASAN",
	"SASAN 5B": "A461 RUMUK",
	"KAMAN 2C": "W102 KAMAN",
}

## 复诵延误差错类型：0 应答机、1 高度、2 离场程序、3 航路
const ERR_KINDS := 4

## 复诵延迟（仿真秒）与机组读错的概率
const READBACK_DELAY := 1.6
const ERROR_RATE := 0.35

## 通话记录最多保留多少条
const TRANSCRIPT_MAX := 300

var flights: Array = []
## 每条 {t: float, side: "pilot"|"atc"|"system", text: String}
var transcript: Array = []

var rng := RandomNumberGenerator.new()

## 统计
var cleared_count := 0
var reissue_total := 0
## 玩家误判次数（复诵不一致却点了"正确"）
var misjudge_count := 0

## 自动来航班的节奏：待放行少于 max_pending 时，每隔 spawn_interval 仿真秒来一架
var spawn_interval := 18.0
var max_pending := 3
var _last_spawn := -1.0e9

## 当日飞行计划（来自机场数据 schedule）。为空时退回随机生成，
## 这样单元测试里不设计划也能照常跑。
var plan: Array = []
## 计划里已经用掉多少条
var plan_index := 0

## 本场运行要素：跑道 / 风 / 能见度 / 修正海压 / 通播字母 / 进近频率。
## 由 GameSession 从机场数据灌进来，放行许可与离场情报都从这里取。
var field := {
	"runway": "18",
	"wind": "",
	"visibility": "",
	"qnh": 0,
	"atis_alpha": "A",
	"dep_freq": "",
}

## 是否启用"机组有没有报通播"这道检查。
## 默认关闭，让单元测试照旧；开局时由会话打开。
var enable_atis_check := false
## 启用后，每架航班漏报通播的概率
const ATIS_MISSING_RATE := 0.25

## 是否要求"计划已核对"才能发放行许可。
## 真实放行席必须先核对飞行计划与进程单；默认关闭让单元测试照旧。
var enable_strip_check := false

## 是否启用「审查飞行计划」窗口那套完整流程（字段对照 + 三种处置）。
## 关闭时仍可用 check_plan() 的一键核对，行为与旧版一致。
var enable_plan_review := false

## 计划审查的参照数据：机型库 / 航路结构 / 可用备降场 / 管制协议高度带
var review_ref := {}
## 难度："easy" / "normal" / "hard"（规范 §0.3）
var difficulty := "normal"

## CDM 时隙开关（规范 §2）。开启后每架航班有 EOBT/TOBT/CTOT/COBT，
## 受流量限制的航班不能早于 CTOT 放行。默认关闭，让老测试照旧。
var cdm_enabled := false
## 由 CTOT 反推 COBT 用的地面滑行时间（分钟）
const TAXI_MIN := 12
## 受 CTOT 约束的航班比例
const CTOT_RATE := 0.45

## QNH 确认闸门（规范 §5.1 模式 B）：机组收到 ATIS 也不是省掉 QNH 的理由，
## 管制员必须在许可里确认修正海压。默认关闭，让老测试照旧。
var enable_qnh_gate := false
## 数值校验（规范 §5.1 / §10）：应答机重复、高度不在协议带内
var enable_value_check := false

## ---- 通播（规范 §3）----
## 当前播发；代号是版本指针，过期本身就是必须拦截的错误状态
var atis := AtisBroadcast.new()
## 是否启用生命周期（过期要处置）。默认关闭，让老测试照旧。
var enable_atis_lifecycle := false
## 由 tick 维护：当前通播是否已过期
var atis_expired := false
## 由 tick 维护：实况与通播相比是否触发了"重大变化"
var atis_major := ""

## 进行中的「协调修改」：key 为 "呼号|字段"，value 为 {"ready_at": 秒}
var _coord := {}

## 调试用：置 true 后下一次复诵必定读错。给人工/自动化验证"复诵不一致"分支用。
var force_error_next := false


func setup(seed_value: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())


# ---------------------------------------------------------------- 航班

## 生成一架申请放行的航班，并记下机组的申请通话。
## 有计划时按计划来（呼号/机型/目的地/机位/程序/高度都照计划），
## 计划用完后仍由随机生成补足。
func spawn_request(sim_time: float, callsign: String = "") -> Flight:
	var f := Flight.new()
	var pe := _take_plan_entry()
	if pe.is_empty():
		f.callsign = callsign if callsign != "" else _next_callsign()
		f.type = TYPES[rng.randi_range(0, TYPES.size() - 1)]
		f.stand = _pick_free_stand()
		f.destination = DESTS[rng.randi_range(0, DESTS.size() - 1)]
		f.sid = SIDS[rng.randi_range(0, SIDS.size() - 1)]
		f.initial_alt_m = ALT_OPTIONS[rng.randi_range(0, ALT_OPTIONS.size() - 1)]
		f.squawk = _random_squawk()
	else:
		f.callsign = callsign if callsign != "" else str(pe.get("callsign", ""))
		f.type = str(pe.get("type", "B738"))
		f.stand = str(pe.get("stand", ""))
		f.destination = str(pe.get("dest", ""))
		var sid := str(pe.get("sid", ""))
		f.sid = sid if SIDS.has(sid) else SIDS[0]
		var alt := int(pe.get("alt", 5000))
		f.initial_alt_m = alt if ALT_OPTIONS.has(alt) else ALT_OPTIONS[1]
		f.squawk = _random_squawk()
		# 计划机位如果已经被占（理论上不会），仍然退到空闲机位，
		# 绝不允许两架飞机停同一个机位。
		if f.stand == "" or _stand_taken(f.stand):
			f.stand = _pick_free_stand()
		f.planned_std = str(pe.get("std", ""))

	f.clearance_limit = f.destination
	f.route = str(SID_ROUTES.get(f.sid, ""))
	f.dep_freq = str(field.get("dep_freq", ""))

	# 飞行计划原值：审查窗口拿它跟"当前有效值"逐项对照。
	# 计划里能写错的地方（尾流、备降场）照抄计划，写没写就按机型库补，
	# 让"计划值 vs 当前有效值"有真实的差异来源，而不是写死几行假数据。
	f.plan_origin = str(field.get("airport_id", ""))
	f.plan_route = f.route
	f.plan_type = f.type
	var pw := str(pe.get("wake", ""))
	f.plan_wake = pw if pw != "" else PlanReview.wake_of(_types_ref(), f.type)
	var pa := str(pe.get("alternate", ""))
	f.plan_alternate = pa if pa != "" else _pick_alternate()
	f.plan_alt_m = f.initial_alt_m
	var tw := int(pe.get("tow_t", 0))
	f.plan_tow_t = tw if tw > 0 else int(_type_info(f.type).get("tow_t", 0))
	var en := str(pe.get("endurance", ""))
	f.plan_endurance = en if en != "" else str(_type_info(f.type).get("endurance", ""))

	# 机组首次呼叫有没有报"已收到通播"——真实里这是要抓的
	if enable_atis_check:
		f.atis_ok = rng.randf() >= ATIS_MISSING_RATE
	else:
		f.atis_ok = true

	f.state = Flight.State.PENDING
	f.request_time = sim_time
	_assign_slot(f, sim_time)
	flights.append(f)

	var alpha := str(field.get("atis_alpha", "A"))
	if f.atis_ok:
		_log(sim_time, "pilot",
			"放行，%s，停机位 %s，已收到通播 %s，申请放行至 %s。" % [
				f.callsign, f.stand, alpha, f.destination])
	else:
		_log(sim_time, "pilot",
			"放行，%s，停机位 %s，申请放行至 %s。" % [f.callsign, f.stand, f.destination])
	return f


## 从机场数据灌入本场运行要素。
func apply_field(data: Dictionary) -> void:
	var wx: Variant = data.get("weather", {})
	var w: Dictionary = wx if wx is Dictionary else {}
	field = {
		"runway": AirportData.primary_runway(data),
		"wind": str(w.get("wind", "")),
		"visibility": str(w.get("visibility", "")),
		"qnh": int(w.get("qnh_hpa", 0)),
		"atis_alpha": Atis.alpha_of(data),
		"dep_freq": AirportData.frequency(data, "approach"),
		"ground_freq": AirportData.frequency(data, "ground"),
		"clock_start": str(data.get("clock_start", "0000")),
		"airport_id": str(data.get("icao", "")),
	}
	var rr: Variant = data.get("review_ref", {})
	review_ref = rr if rr is Dictionary else {}

	# 开局时通播已按下发的字母播发过一次（发布时刻 = 开局时刻）
	atis = AtisBroadcast.new()
	atis.alpha = Atis.alpha_of(data)
	atis.issued_min = Atis.minutes_since(str(data.get("clock_start", "0000")), 0.0)
	atis.runway = str(field.get("runway", ""))
	atis.wind = str(field.get("wind", ""))
	atis.visibility = str(field.get("visibility", ""))
	atis.qnh = int(field.get("qnh", 0))


## 取走计划里的下一条；没有计划或已用完时返回空字典。
func _take_plan_entry() -> Dictionary:
	if plan_index >= plan.size():
		return {}
	var e: Variant = plan[plan_index]
	plan_index += 1
	return e if e is Dictionary else {}


## 设置当日计划并重置进度（新开局时用）。
func set_plan(list: Array) -> void:
	plan = []
	for e in list:
		if e is Dictionary:
			plan.append(e)
	plan_index = 0


func _stand_taken(stand: String) -> bool:
	for f in flights:
		if not (f as Flight).is_done() and (f as Flight).stand == stand:
			return true
	return false


## 核对飞行计划（进程单上的第一道工序）。
## 这是"一键核对"的旧路径，保留给关闭审查窗口时用；开启完整流程后
## 由 finish_review() 承担（两者都会把 checked 置起来，状态口径一致）。
func check_plan(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.checked:
		return {"ok": false, "error": "%s 的计划已经核对过了" % callsign}
	if f.state != Flight.State.PENDING:
		return {"ok": false, "error": "%s 已进入放行流程，不能再核对计划" % callsign}
	f.checked = true
	f.review_done = true
	f.t_check = sim_time
	_log(sim_time, "system", "%s 飞行计划已与进程单核对一致。" % f.callsign)
	return {"ok": true, "error": ""}


# ---------------------------------------------------------------- 审查飞行计划

## 该航班的对照行（已叠上玩家此前的处置结果）。
func review_rows(callsign: String) -> Array:
	var f := get_flight(callsign)
	if f == null:
		return []
	var ref := review_ref.duplicate()
	ref["airport_id"] = str(field.get("airport_id", ""))
	return PlanReview.with_decisions(PlanReview.rows(f, ref), f.review)


## 还有几项没处置（界面用来决定"完成审查"是否可点）。
func review_blocking(callsign: String) -> bool:
	return PlanReview.has_blocking(review_rows(callsign), difficulty)


## 处置一：按当前有效值修正计划（规范 §1.4「修正计划」）。
func fix_review_row(callsign: String, key: String, sim_time: float) -> Dictionary:
	var g := _review_guard(callsign, key)
	if not bool(g.ok):
		return g
	var f := get_flight(callsign)
	_apply_current(f, key)
	f.review[key] = PlanReview.FIXED
	_log(sim_time, "system", "%s 计划的%s已按当前有效值修正。"
		% [f.callsign, PlanReview.label_of(key)])
	return {"ok": true, "error": ""}


## 处置二：协调修改（规范 §1.4「协调修改」）——有 5~15 秒延迟，
## 真正的改动在 tick() 里落地，期间界面显示"协调中"。
func coordinate_review_row(callsign: String, key: String, sim_time: float) -> Dictionary:
	var g := _review_guard(callsign, key)
	if not bool(g.ok):
		return g
	var k := "%s|%s" % [callsign, key]
	if _coord.has(k):
		return {"ok": false, "error": "该项正在协调中", "ready_at": float(_coord[k].ready_at)}
	var delay := 5.0 + rng.randf() * 10.0
	_coord[k] = {"ready_at": sim_time + delay, "callsign": callsign, "key": key}
	var f := get_flight(callsign)
	_log(sim_time, "system", "%s 计划的%s正在与相关单位协调…"
		% [f.callsign, PlanReview.label_of(key)])
	return {"ok": true, "error": "", "ready_at": sim_time + delay}


## 处置三：标记为已审查（有保留，规范 §1.4）。只有玩家判断不影响安全时才能用。
func waive_review_row(callsign: String, key: String, sim_time: float) -> Dictionary:
	var g := _review_guard(callsign, key)
	if not bool(g.ok):
		return g
	var f := get_flight(callsign)
	f.review[key] = PlanReview.WAIVED
	_log(sim_time, "system", "%s 计划的%s标记为已审查（有保留）。"
		% [f.callsign, PlanReview.label_of(key)])
	return {"ok": true, "error": ""}


## 完成审查 → 状态推进到「计划已审查」。
## 有一致性未处置的红项时不允许完成（高阶模式不标红，允许带着漏检完成，
## 漏检记进 missed_review，最终由运行品质评分承担后果）。
func finish_review(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.checked:
		return {"ok": false, "error": "%s 的计划已经核对过了" % callsign}
	if f.state != Flight.State.PENDING:
		return {"ok": false, "error": "%s 已进入放行流程，不能再核对计划" % callsign}
	var rows := review_rows(callsign)
	if PlanReview.has_blocking(rows, difficulty):
		var n := PlanReview.missed_count(rows)
		return {"ok": false, "error": "还有 %d 项不一致未处置" % n}
	var missed := PlanReview.missed_count(rows)
	f.missed_review += missed
	f.review_done = true
	f.checked = true
	f.t_check = sim_time
	if missed > 0:
		_log(sim_time, "system", "%s 计划已审查（有 %d 项未发现的不一致）。"
			% [f.callsign, missed])
	else:
		_log(sim_time, "system", "%s 飞行计划审查完成，与当前有效数据一致。"
			% f.callsign)
	return {"ok": true, "error": "", "missed": missed}


## 该项是否正在协调中（界面显示「协调中…」）
func review_coordinating(callsign: String, key: String) -> bool:
	return _coord.has("%s|%s" % [callsign, key])


func _review_guard(callsign: String, key: String) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state != Flight.State.PENDING:
		return {"ok": false, "error": "%s 已进入放行流程，不能再改计划" % callsign}
	if not PlanReview.is_fixable(key):
		return {"ok": false, "error": "该项只能查看，不能处置"}
	return {"ok": true, "error": ""}


## 把计划值改成"当前有效值"。修正会真的改到航班字段上，
## 因为高度/航路这些会进放行许可，光在表格里改数字等于没改。
func _apply_current(f: Flight, key: String) -> void:
	var types := _types_ref()
	var routes: Dictionary = review_ref.get("routes", {})
	var alts: Array = review_ref.get("alternates", [])
	if key == "airport":
		f.plan_origin = str(field.get("airport_id", ""))
	elif key == "route":
		f.plan_route = str(routes.get(f.sid, f.route))
		f.route = f.plan_route
	elif key == "type":
		f.plan_type = f.type
	elif key == "wake":
		f.plan_wake = PlanReview.wake_of(types, f.plan_type)
	elif key == "alternate":
		f.plan_alternate = str(alts[0]) if not alts.is_empty() else ""
	elif key == "altitude":
		var band := PlanReview.loa_band(review_ref, f.sid)
		if not band.is_empty():
			var v := clampi(f.plan_alt_m, int(band.get("alt_min", 0)),
				int(band.get("alt_max", 0)))
			f.plan_alt_m = v
			f.initial_alt_m = v
			f.plan_alt_m = v


func _types_ref() -> Dictionary:
	var t: Variant = review_ref.get("types", {})
	return t if t is Dictionary else {}


## 机型库里该机型的补充信息（尾流/重量/续航）；没有就返回空字典。
func _type_info(type_code: String) -> Dictionary:
	var t: Variant = _types_ref().get(type_code, {})
	return t if t is Dictionary else {}


func _pick_alternate() -> String:
	var t: Variant = review_ref.get("alternates", [])
	if t is Array and not (t as Array).is_empty():
		var arr: Array = t
		return str(arr[rng.randi_range(0, arr.size() - 1)])
	return ""


# ---------------------------------------------------------------- 通播（规范 §3）

## 当前通播状态（有效 / 即将过期 / 已过期）
func atis_state(sim_time: float) -> int:
	return atis.state(now_minutes(sim_time))


## "BRAVO 有效（12 分钟前发布）" 这种给人看的一行字
func atis_status_text(sim_time: float) -> String:
	var m := now_minutes(sim_time)
	return "%s %s（%d 分钟前发布）" % [
		atis.alpha, AtisBroadcast.state_text(atis.state(m)),
		AtisBroadcast.age_minutes(atis.issued_min, m)]


## 实况相对通播是否触发"重大变化"（风/能见度阈值）
func atis_major_now() -> String:
	return AtisBroadcast.major_change(atis.wind, atis.visibility,
		str(field.get("wind", "")), str(field.get("visibility", "")))


## 更新通播：代号由系统按字母推进，要素按玩家给的值写入。
## **允许写入与实况不符的值**（规范 §3.2）—— 这就是"通播有误"的来源，
## 会记在 has_error 上，供后续特情使用。
func update_atis(opts: Dictionary, sim_time: float) -> Dictionary:
	var qnh := int(opts.get("qnh", field.get("qnh", 0)))
	if qnh <= 0:
		return {"ok": false, "error": "通播必须包含修正海压（QNH）"}
	var runway := str(opts.get("runway", field.get("runway", "")))
	var wind := str(opts.get("wind", field.get("wind", "")))
	var vis := str(opts.get("visibility", field.get("visibility", "")))
	if runway == "":
		return {"ok": false, "error": "通播必须写明使用跑道"}

	atis.alpha = AtisBroadcast.next_alpha(atis.alpha)
	atis.issued_min = now_minutes(sim_time)
	atis.runway = runway
	atis.wind = wind
	atis.visibility = vis
	atis.qnh = qnh
	atis.transition_level = str(opts.get("transition_level", atis.transition_level))
	if opts.has("brake"):
		atis.brake = str(opts.get("brake", ""))
	var hz: Variant = opts.get("hazards", null)
	if hz is Array:
		atis.hazards = hz
	atis.has_error = AtisBroadcast.values_differ(
		{"runway": runway, "wind": wind, "visibility": vis, "qnh": qnh},
		{"runway": str(field.get("runway", "")),
			"wind": str(field.get("wind", "")),
			"visibility": str(field.get("visibility", "")),
			"qnh": int(field.get("qnh", 0))})
	atis.update_count += 1
	atis_expired = false
	atis_major = ""
	_log(sim_time, "atc", "通播 %s 已发布：使用跑道 %s，修正海压 %d。" % [
		atis.alpha, runway, qnh])
	return {"ok": true, "error": "", "alpha": atis.alpha, "has_error": atis.has_error}


## 过期处置之一：通知机组最新通播代号
func notify_latest_atis(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	f.atis_notified = true
	f.atis_reported = atis.alpha
	_log(sim_time, "atc", "%s，最新通播是 %s，请抄收后再申请放行。"
		% [f.callsign, atis.alpha])
	return {"ok": true, "error": ""}


## 过期处置之二：把变化的部分逐项通报给机组
func report_atis_changes(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	f.atis_notified = true
	f.atis_reported = atis.alpha
	var parts := PackedStringArray()
	parts.append("使用跑道 %s" % atis.runway)
	if atis.wind != "":
		parts.append("地面风 %s" % atis.wind)
	if atis.visibility != "":
		parts.append("能见度 %s" % atis.visibility)
	if atis.qnh > 0:
		parts.append("修正海压 %d" % atis.qnh)
	_log(sim_time, "atc", "%s，通播 %s 已更新：%s。" % [
		f.callsign, atis.alpha, "，".join(parts)])
	return {"ok": true, "error": ""}


## 通播闸门：过期且机组没被处置过 → 不许放行
func atis_gate_ok(f: Flight) -> bool:
	if not enable_atis_lifecycle:
		return true
	if f.atis_notified:
		return true
	return not atis_expired


# ---------------------------------------------------------------- 移交


## 放行完成后把航班移交给地面席（第二百条（八）：滑行至等待点后转频）。
func handoff_ground(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state != Flight.State.CLEARED:
		return {"ok": false, "error": "%s 还没有完成放行，不能移交地面" % callsign}
	if f.handed_off:
		return {"ok": false, "error": "%s 已经移交给地面席" % callsign}
	f.handed_off = true
	f.t_handoff = sim_time
	var ground_freq := str(field.get("ground_freq", ""))
	var tail := "" if ground_freq == "" else "，地面 %s" % ground_freq
	_log(sim_time, "atc", "%s，联系地面%s，再见。" % [f.callsign, tail])
	_log(sim_time, "pilot", "%s，联系地面，再见。" % f.callsign)
	return {"ok": true, "error": ""}


## 放行后的航班是否已全部移交（用于界面分区）
func handed_off_count() -> int:
	var n := 0
	for f in flights:
		if (f as Flight).handed_off:
			n += 1
	return n


## 计划时刻（"HHMM"）→ 当天分钟数；没有计划或格式不对返回 -1。
static func plan_minutes(f: Flight) -> int:
	var s := f.planned_std.strip_edges()
	if s.length() < 4:
		return -1
	for i in range(4):
		if s[i] < "0" or s[i] > "9":
			return -1
	return int(s.substr(0, 2)) * 60 + int(s.substr(2, 2))


## 尾流等级：重型 H / 中型 M。用于放行排序与将来的尾流间隔配备。
static func wake_class(type: String) -> String:
	var t := type.strip_edges().to_upper()
	if t.begins_with("B74") or t.begins_with("B77") or t.begins_with("B78") \
			or t.begins_with("A33") or t.begins_with("A35") or t.begins_with("A38"):
		return "H"
	return "M"


## 当前延误分钟数（本场时钟 − 计划时刻）。没有计划的航班返回 0。
func delay_minutes(f: Flight, sim_time: float) -> int:
	var pm := plan_minutes(f)
	if pm < 0:
		return 0
	var nowm := Atis.minutes_since(str(field.get("clock_start", "0000")), sim_time)
	return nowm - pm


## 放行顺序（第二百九十二条）：按计划起飞时刻先后；没有计划的排在最后。
## 玩家拖过之后按手动顺序（order_rank），没拖过的仍按计划时刻排在后面。
## 同刻按呼号排，保证结果稳定、可测。
func ordered_pending() -> Array:
	var list := pending()
	list.sort_custom(func(a: Flight, b: Flight) -> bool:
		var ra := a.order_rank if a.order_rank >= 0 else 10000 + _rank_key(a)
		var rb := b.order_rank if b.order_rank >= 0 else 10000 + _rank_key(b)
		if ra != rb:
			return ra < rb
		return a.callsign < b.callsign)
	return list


func _rank_key(f: Flight) -> int:
	var m := plan_minutes(f)
	return m if m >= 0 else 99999


# ---------------------------------------------------------------- CDM 时隙（规范 §2）

## 给一架航班算时隙。有计划的按计划时刻推，临时航班按当前时刻推。
## 数值全部由种子决定，同一局结果可复现。
func _assign_slot(f: Flight, sim_time: float) -> void:
	if not cdm_enabled:
		return
	var base := 0
	if f.planned_std != "":
		base = Atis.minutes_since(f.planned_std, 0.0)
	else:
		base = now_minutes(sim_time)
	f.eobt_min = base
	# TOBT 是承运人/地面服务给的，比计划略有出入
	f.tobt_min = base + rng.randi_range(-3, 8)
	f.ctot_restricted = rng.randf() < CTOT_RATE
	if f.ctot_restricted:
		f.ctot_min = f.tobt_min + rng.randi_range(6, 22)
		f.cobt_min = maxi(f.tobt_min - 2, f.ctot_min - TAXI_MIN)
	else:
		f.ctot_min = -1
		f.cobt_min = maxi(0, f.tobt_min - 8)


## 一天内分钟数 → "HHMM"（跨零点也正常）
static func slot_hhmm(minute_of_day: int) -> String:
	if minute_of_day < 0:
		return "—"
	var m := posmod(minute_of_day, 24 * 60)
	return "%02d%02d" % [m / 60, m % 60]


## 当前仿真时刻对应的一天内分钟数
func now_minutes(sim_time: float) -> int:
	return Atis.minutes_since(str(field.get("clock_start", "0000")), sim_time)


## 能不能把某架拖到第 to_index 位（规范 §2.3）。
## 受 CTOT 约束的航班不能排到"时隙更早的受限航班"前面 —— 那等于抢别人的时隙。
func can_move(callsign: String, to_index: int) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state != Flight.State.PENDING:
		return {"ok": false, "error": "%s 已进入放行流程，不能再调整顺序" % callsign}
	var ordered := ordered_pending()
	var cur := ordered.find(f)
	if cur < 0:
		return {"ok": false, "error": "%s 不在待放行列表里" % callsign}
	var target := ordered.duplicate()
	target.remove_at(cur)
	target.insert(clampi(to_index, 0, target.size()), f)
	# 受限航班之间的先后必须符合 CTOT 先后 —— 否则就是抢别人的时隙。
	# 注意要检查**整份新列表**：只看被拖那一架前面是不够的，
	# 把时隙晚的抽到最前、把时隙早的挤到后面，同样违反规则。
	var last_ctot := -1
	var last_call := ""
	for e in target:
		var o := e as Flight
		if not (o.ctot_restricted and o.ctot_min >= 0):
			continue
		if last_ctot >= 0 and o.ctot_min < last_ctot:
			return {"ok": false,
				"error": "%s 受 CTOT %s 约束，不能排到 %s（CTOT %s）前面" % [
					o.callsign, slot_hhmm(o.ctot_min), last_call,
					slot_hhmm(last_ctot)]}
		last_ctot = o.ctot_min
		last_call = o.callsign
	return {"ok": true, "error": ""}


## 拖动进程单调整放行顺序（规范 §2.3）。被拒绝时返回原因，界面把卡片弹回原位。
func move_flight(callsign: String, to_index: int) -> Dictionary:
	var chk := can_move(callsign, to_index)
	if not bool(chk.ok):
		return chk
	var f := get_flight(callsign)
	var ordered := ordered_pending()
	var cur := ordered.find(f)
	ordered.remove_at(cur)
	ordered.insert(clampi(to_index, 0, ordered.size()), f)
	for i in range(ordered.size()):
		(ordered[i] as Flight).order_rank = i
	return {"ok": true, "error": ""}


## 恢复按计划时刻排（「整理进程单」用）
func reset_order() -> void:
	for f in flights:
		(f as Flight).order_rank = -1


## 预计延误超过 30 分钟必须通知机组（第二百九十三条）；每架只通知一次。
func check_delay_notices(sim_time: float) -> int:
	var n := 0
	for f in flights:
		var fl := f as Flight
		if fl.is_done() or fl.delay_notified:
			continue
		var d := delay_minutes(fl, sim_time)
		if d <= 30:
			continue
		fl.delay_notified = true
		_log(sim_time, "atc",
			"%s，由于流量原因，预计起飞延误约 %d 分钟，请稍候，放行时另行通知。" % [
				fl.callsign, d])
		n += 1
	return n


func pending() -> Array:
	var out: Array = []
	for f in flights:
		if not f.is_done():
			out.append(f)
	return out


func done_flights() -> Array:
	var out: Array = []
	for f in flights:
		if f.is_done():
			out.append(f)
	return out


func get_flight(callsign: String) -> Flight:
	for f in flights:
		if f.callsign == callsign:
			return f
	return null


## 开局先塞几架，免得列表空着。
func seed_initial(sim_time: float, count: int = 2) -> void:
	for i in range(count):
		spawn_request(sim_time)
	_last_spawn = sim_time


## 到点自动来一架新的放行申请；不该来的时候返回 null。
func maybe_spawn(sim_time: float) -> Flight:
	if pending().size() >= max_pending:
		return null
	if sim_time - _last_spawn < spawn_interval:
		return null
	_last_spawn = sim_time
	return spawn_request(sim_time)


## 挑一个没被占用的机位。
## 一个机位同一时刻只停一架飞机——之前随机分配会撞车，场面图上两架叠在一起。
func _pick_free_stand() -> String:
	var used := {}
	for f in flights:
		if not f.is_done():
			used[f.stand] = true

	var free: Array = []
	for i in range(1, 25):
		var s := "A%02d" % i
		if not used.has(s):
			free.append(s)

	if free.is_empty():
		# 机位全满（理论上不会，待放行上限 3），退回随机
		return "A%02d" % rng.randi_range(1, 24)
	return String(free[rng.randi_range(0, free.size() - 1)])


func _next_callsign() -> String:
	for attempt in range(200):
		var cs := "%s%d" % [AIRLINES[rng.randi_range(0, AIRLINES.size() - 1)],
			rng.randi_range(1000, 9999)]
		if get_flight(cs) == null:
			return cs
	return "ATC%d" % rng.randi_range(1000, 9999)


func _random_squawk() -> String:
	var s := ""
	for i in range(4):
		s += str(rng.randi_range(0, 7))
	# 应答机首位为 0 不常见，换一个
	if s.begins_with("0"):
		s = "1" + s.substr(1)
	return s


# ---------------------------------------------------------------- 发放许可

## 该应答机当前被哪架航班占着（不含自己）。没人占用返回空串。
## 规范 §5.1：同一空域同一时间要尽量减少编码重复，否则二次雷达识别会错。
func squawk_owner(squawk: String, except_callsign: String = "") -> String:
	for f in flights:
		var fl := f as Flight
		if fl.callsign == except_callsign:
			continue
		if fl.squawk != squawk:
			continue
		if fl.state == Flight.State.PENDING or fl.handed_off:
			continue
		return fl.callsign
	return ""


## 管制员确认修正海压（QNH）。确认后才能发放行许可。
func confirm_qnh(callsign: String) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	f.qnh_confirmed = true
	return {"ok": true, "error": ""}


## 校验应答机：必须 4 位、每位 0-7（八进制）。
static func is_valid_squawk(s: String) -> bool:
	if s.length() != 4:
		return false
	for i in range(4):
		var c := s[i]
		if c < "0" or c > "7":
			return false
	return true


## 发放行许可。返回 {ok, error}。
func issue_clearance(callsign: String, sid: String, alt_m: int, squawk: String,
		sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state == Flight.State.CLEARED:
		return {"ok": false, "error": "%s 已经放行完毕" % callsign}
	if f.state == Flight.State.SENT or f.state == Flight.State.READBACK:
		return {"ok": false, "error": "%s 正在等待复诵，不能重复发放" % callsign}
	if sid.strip_edges() == "":
		return {"ok": false, "error": "离场程序不能为空"}
	if alt_m <= 0:
		return {"ok": false, "error": "初始高度必须大于 0"}
	if not is_valid_squawk(squawk):
		return {"ok": false, "error": "应答机必须是 4 位八进制数（0-7）"}
	if enable_qnh_gate and not f.qnh_confirmed:
		return {"ok": false, "error": "请先在许可表单里确认修正海压（QNH）"}
	if enable_atis_lifecycle and not atis_gate_ok(f):
		return {"ok": false, "error":
			"通播 %s 已过期，请先「通知最新通播」或「逐项通报变化」" % atis.alpha}
	if enable_value_check:
		var dup := squawk_owner(squawk, callsign)
		if dup != "":
			return {"ok": false, "error": "应答机 %s 已被 %s 占用，请重新指定" % [
				squawk, dup]}
		var band := PlanReview.loa_band(review_ref, sid)
		if not band.is_empty():
			var lo := int(band.get("alt_min", 0))
			var hi := int(band.get("alt_max", 0))
			if alt_m < lo or alt_m > hi:
				return {"ok": false, "error":
					"高度 %d 米不在 %s 的协议高度带 %d–%d 米内" % [alt_m, sid, lo, hi]}
	if enable_strip_check and not f.checked:
		return {"ok": false, "error": "请先核对 %s 的飞行计划（进程单）" % callsign}

	# CTOT 闸门（规范 §2.3）：受流量限制的航班不能早于时隙放行
	if cdm_enabled and f.ctot_restricted and f.ctot_min >= 0:
		var now_m := now_minutes(sim_time)
		if now_m < f.ctot_min:
			return {"ok": false, "error": "%s 受 CTOT %s 约束，最早放行时间 %s（现在 %s）"
				% [callsign, slot_hhmm(f.ctot_min), slot_hhmm(f.ctot_min),
					slot_hhmm(now_m)]}

	# 换了离场程序，航路也要跟着换——只给 SID 不给航路不符合第二百九十一条
	var new_route := str(SID_ROUTES.get(sid, ""))
	if new_route == "":
		return {"ok": false, "error": "离场程序 %s 没有配航路，请核对飞行计划" % sid}

	f.sid = sid
	f.route = new_route
	f.clearance_limit = f.destination if f.clearance_limit == "" else f.clearance_limit
	f.dep_freq = str(field.get("dep_freq", ""))
	f.initial_alt_m = alt_m
	f.squawk = squawk
	f.state = Flight.State.SENT
	f.t_sent = sim_time
	f.readback_at = sim_time + READBACK_DELAY
	f.readback_text = ""
	f.readback_ok = true
	f.readback_diff = ""

	_eval_slot(f, sim_time)
	_log(sim_time, "atc", full_clearance_text(f))
	return {"ok": true, "error": ""}


## 放行时刻相对时隙的结果（规范 §2.4）：提前 / 准时 / 延误。
## 不受 CTOT 约束的航班按 TOBT 衡量 —— 早于目标撤轮挡就是提前。
func _eval_slot(f: Flight, sim_time: float) -> void:
	var now_m := now_minutes(sim_time)
	var anchor := -1
	if f.ctot_restricted and f.ctot_min >= 0:
		anchor = f.ctot_min
	elif f.tobt_min >= 0:
		anchor = f.tobt_min
	if anchor < 0:
		f.slot_eval = ""
		f.slot_delay_min = 0
		return
	var d := now_m - anchor
	f.slot_delay_min = d
	if d <= -3:
		f.slot_eval = "提前"
	elif d <= 3:
		f.slot_eval = "准时"
	else:
		f.slot_eval = "延误"


## 按《民用航空空中交通管理规则》第二百九十一条的七项要素拼放行许可：
##   识别标志 / 许可界限 / 离场程序 / 航路 / 飞行高度 / 应答机 / 必要的管制指令
static func clearance_text(f: Flight) -> String:
	var limit := f.clearance_limit if f.clearance_limit != "" else f.destination
	var route_part := "" if f.route == "" else "，经 %s" % f.route
	var contact := "" if f.dep_freq == "" else "，起飞后联系进近 %s" % f.dep_freq
	return "%s，许可放行至 %s，按 %s 离场%s，初始高度 %d 米，应答机 %s%s。" % [
		f.callsign, limit, f.sid, route_part, f.initial_alt_m, f.squawk, contact]


## 离场情报。
##
## 第二百九十四条：使用跑道、风向风速、能见度、高度表拨正值等；
## 但机组已报告从通播收到这些情报时不必重复，**只补高度表拨正值**
## （第一百五十九条同样要求）。这条分支按真实规则实现，不做简化。
func departure_info_text(f: Flight) -> String:
	var qnh := int(field.get("qnh", 0))
	var qnh_part := "修正海压 %d" % qnh if qnh > 0 else ""
	if f.atis_ok:
		return qnh_part
	var parts := PackedStringArray()
	var rwy := str(field.get("runway", ""))
	if rwy != "":
		parts.append("使用跑道 %s" % rwy)
	var wind := str(field.get("wind", ""))
	if wind != "":
		parts.append("地面风 %s" % wind)
	var vis := str(field.get("visibility", ""))
	if vis != "":
		parts.append("能见度 %s" % vis)
	if qnh_part != "":
		parts.append(qnh_part)
	return "，".join(parts)


## 一条完整的放行通话（许可 + 离场情报）。
func full_clearance_text(f: Flight) -> String:
	var info := departure_info_text(f)
	if info == "":
		return clearance_text(f)
	return clearance_text(f) + " " + info + "。"


## 机组报告漏了通播时，管制要求先收听。
func require_atis(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.atis_ok:
		return {"ok": false, "error": "%s 已经报告收到通播" % callsign}
	f.atis_ok = true
	var alpha := str(field.get("atis_alpha", "A"))
	_log(sim_time, "atc", "%s，请先收听通播 %s 后再申请放行。" % [f.callsign, alpha])
	_log(sim_time, "pilot", "%s，收到，通播 %s 已抄收。" % [f.callsign, alpha])
	return {"ok": true, "error": ""}


# ---------------------------------------------------------------- 复诵

## 推进时间：到点的复诵自动到达；延误超限的航班通知机组；
## 进行中的「协调修改」到点后落地。
func tick(sim_time: float) -> void:
	check_delay_notices(sim_time)
	_tick_coordination(sim_time)
	_tick_atis(sim_time)
	for f in flights:
		if f.state != Flight.State.SENT:
			continue
		if sim_time < f.readback_at:
			continue
		_generate_readback(f, sim_time)


## 通播随仿真时钟自然变旧；实况与通播的差异在这里检测。
func _tick_atis(sim_time: float) -> void:
	if not enable_atis_lifecycle:
		return
	var st := atis_state(sim_time)
	if st == AtisBroadcast.EXPIRED and not atis_expired:
		atis_expired = true
		_log(sim_time, "system",
			"通播 %s 已超过 %d 分钟未更新，已过期。" % [
				atis.alpha, AtisBroadcast.EXPIRE_MIN])
	elif st != AtisBroadcast.EXPIRED:
		atis_expired = false
	var reason := atis_major_now()
	if reason != "" and atis_major == "":
		atis_major = reason
		_log(sim_time, "system", "实况出现重大变化（%s），应立即更新通播。" % reason)


func _tick_coordination(sim_time: float) -> void:
	if _coord.is_empty():
		return
	var done: Array = []
	for k in _coord.keys():
		var rec: Dictionary = _coord[k]
		if sim_time < float(rec.get("ready_at", 0.0)):
			continue
		done.append(k)
		var f := get_flight(str(rec.get("callsign", "")))
		if f == null:
			continue
		var key := str(rec.get("key", ""))
		_apply_current(f, key)
		f.review[key] = PlanReview.FIXED
		_log(sim_time, "system", "%s 计划的%s协调完成，已按协调结果更新。"
			% [f.callsign, PlanReview.label_of(key)])
	for k in done:
		_coord.erase(k)


## 复诵措辞与放行许可同构，这样"有没有读错"一眼可比。
static func readback_text_of(callsign: String, limit: String, sid: String,
		route: String, alt_m: int, squawk: String) -> String:
	var route_part := "" if route == "" else "，经 %s" % route
	return "%s，许可放行至 %s，按 %s 离场%s，初始高度 %d 米，应答机 %s。" % [
		callsign, limit, sid, route_part, alt_m, squawk]


func _generate_readback(f: Flight, sim_time: float) -> void:
	var wrong := false
	if force_error_next:
		wrong = true
		force_error_next = false
	else:
		wrong = rng.randf() < ERROR_RATE

	var limit := f.clearance_limit if f.clearance_limit != "" else f.destination
	var text := DeliveryDesk.readback_text_of(f.callsign, limit, f.sid, f.route,
		f.initial_alt_m, f.squawk)
	var diff := ""
	var ok := true

	if wrong:
		var kind := rng.randi_range(0, ERR_KINDS - 1)
		if kind == 0:
			var bad := _corrupt_digit(f.squawk)
			text = DeliveryDesk.readback_text_of(f.callsign, limit, f.sid, f.route,
				f.initial_alt_m, bad)
			diff = "应答机读成 %s，应为 %s" % [bad, f.squawk]
		elif kind == 1:
			var bad_alt := f.initial_alt_m + 1000
			text = DeliveryDesk.readback_text_of(f.callsign, limit, f.sid, f.route,
				bad_alt, f.squawk)
			diff = "初始高度读成 %d 米，应为 %d 米" % [bad_alt, f.initial_alt_m]
		elif kind == 2:
			var bad_sid := SIDS[0]
			for s in SIDS:
				if s != f.sid:
					bad_sid = s
					break
			text = DeliveryDesk.readback_text_of(f.callsign, limit, bad_sid,
				SID_ROUTES.get(bad_sid, ""), f.initial_alt_m, f.squawk)
			diff = "离场程序读成 %s，应为 %s" % [bad_sid, f.sid]
		else:
			# 航路读错：真实里最常见的错误之一，前面只校验 SID 是抓不到的
			var bad_route := "A461 RUMUK" if f.route != "A461 RUMUK" else "W105 LADIX"
			text = DeliveryDesk.readback_text_of(f.callsign, limit, f.sid,
				bad_route, f.initial_alt_m, f.squawk)
			diff = "航路读成 %s，应为 %s" % [bad_route, f.route]
		ok = false

	f.readback_text = text
	f.readback_ok = ok
	f.readback_diff = diff
	f.state = Flight.State.READBACK
	f.t_readback = sim_time
	_log(sim_time, "pilot", text)


func _corrupt_digit(squawk: String) -> String:
	if squawk.length() != 4:
		return squawk
	var idx := rng.randi_range(0, 3)
	var d := int(squawk[idx])
	var nd := (d + 1) % 8
	return squawk.substr(0, idx) + str(nd) + squawk.substr(idx + 1)


## 复核通过：复诵一致才允许放行。
func accept_readback(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign, "correct": false}
	if f.state != Flight.State.READBACK:
		return {"ok": false, "error": "%s 当前没有待复核的复诵" % callsign, "correct": false}
	if not f.readback_ok:
		misjudge_count += 1
		return {"ok": false, "correct": false,
			"error": "复诵与许可不一致（%s），不能作为放行依据，请重发。" % f.readback_diff}

	f.state = Flight.State.CLEARED
	f.t_cleared = sim_time
	cleared_count += 1
	_log(sim_time, "atc", "%s，复诵正确，放行完成，联系地面。" % f.callsign)
	return {"ok": true, "error": "", "correct": true}


## 退回重发：复诵有问题时应当这么做。
func reissue(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state != Flight.State.READBACK:
		return {"ok": false, "error": "%s 当前没有待复核的复诵" % callsign}

	var was_correct: bool = f.readback_ok
	f.state = Flight.State.PENDING
	f.reissue_count += 1
	reissue_total += 1
	f.readback_text = ""
	f.readback_ok = true
	f.readback_diff = ""
	f.readback_at = 0.0
	f.t_sent = -1.0
	f.t_readback = -1.0

	_log(sim_time, "atc", "%s，复诵有误，请重新抄收。" % f.callsign)
	return {"ok": true, "error": "", "was_correct": was_correct}


# ---------------------------------------------------------------- 通话记录

func _log(sim_time: float, side: String, text: String) -> void:
	transcript.append({"t": sim_time, "side": side, "text": text})
	if transcript.size() > TRANSCRIPT_MAX:
		transcript = transcript.slice(transcript.size() - TRANSCRIPT_MAX)


## 最近 n 条通话（新的在前）。
func recent(n: int) -> Array:
	var out: Array = []
	var start: int = maxi(0, transcript.size() - n)
	for i in range(start, transcript.size()):
		out.append(transcript[i])
	return out


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	var fs: Array = []
	for f in flights:
		fs.append(f.to_dict())
	return {
		"flights": fs,
		"transcript": transcript.duplicate(true),
		"cleared_count": cleared_count,
		"reissue_total": reissue_total,
		"misjudge_count": misjudge_count,
		"plan": plan.duplicate(true),
		"plan_index": plan_index,
	}


static func from_dict(d: Dictionary) -> DeliveryDesk:
	var desk := DeliveryDesk.new()
	for raw in d.get("flights", []):
		if raw is Dictionary:
			desk.flights.append(Flight.from_dict(raw))
	var tr: Variant = d.get("transcript", [])
	desk.transcript = tr if tr is Array else []
	desk.cleared_count = int(d.get("cleared_count", 0))
	desk.reissue_total = int(d.get("reissue_total", 0))
	desk.misjudge_count = int(d.get("misjudge_count", 0))
	var pl: Variant = d.get("plan", [])
	if pl is Array:
		for e in pl:
			if e is Dictionary:
				desk.plan.append(e)
	desk.plan_index = int(d.get("plan_index", 0))
	return desk
