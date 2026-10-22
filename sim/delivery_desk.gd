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

## 07 §2.2：每架航班按 TOBT 倒推，提前 lead_minutes 分钟进入"准备好申请"，
## 再叠加 0–10 秒随机延迟（模拟飞行员完成最后检查）。默认 15 分钟，可配置。
var lead_minutes := 15.0
## 计划里没有 std 时刻时的兜底节奏：待放行少于 max_pending 时每 spawn_interval 秒来一架
var spawn_interval := 18.0
var max_pending := 3
var _last_spawn := -1.0e9
## 开局时今天已经过去多少分钟（来自 clock_start），计划时刻换算要用
var _clock_origin := -1.0

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
var enable_atis_lifecycle := false## 由 tick 维护：当前通播是否已过期
var atis_expired := false
## 由 tick 维护：实况与通播相比是否触发了"重大变化"
var atis_major := ""

## 通播有误的航班放行后多久暴露出特情（仿真秒）
const EMERGENCY_DELAY := 45.0

## ---- 复诵核对（规范 §6）----
## true = 高阶模式：系统不高亮不一致项，玩家逐项自己判，还有 60 秒时限
var readback_hard := false
## 高阶模式的核对时限（仿真秒）
const READBACK_LIMIT := 60.0
## 高阶模式超时退回的次数（进评分）
var readback_timeouts := 0

## ---- 移交地面（规范 §7）----
## 是否启用移交检查清单。默认关闭，让老测试照旧。
var enable_handoff_check := false
## true = 高阶模式：清单不自动打勾，要玩家逐项确认，还有 90 秒时限
var handoff_hard := false
const HANDOFF_LIMIT := 90.0

## 整理进程单的冷却（规范 §4.2：2 秒）
const TIDY_COOLDOWN := 2.0
var _tidy_at := -1.0
## 通播发布时选错值的次数（进评分）
var atis_err_count := 0

## ---- AI 驾驶舱（07 文档）----
## 是否让机组对许可做完整性检查并质疑（默认关闭，让老测试照旧）
var pilot_check_enabled := false
## 连续质疑上限：到这个次数后机组就接受现有内容（规范 §4.4，避免死循环）
const MAX_PILOT_QUERIES := 2
## 没人理时多久重新呼叫一次（规范 §4.3：60 秒，最多 3 次）
const REQUEST_INTERVAL := 60.0
const MAX_REQUESTS := 3

## ---- 许可发布模式（规范 §5.1）----
## "preset" 预设一键 / "form" 填空式 / "text" 自由文本 / "voice" 真实语音（08 §4）
var issue_mode := "form"
## ---- 高级模式：真实语音通话（08 §4）----
## 语音播报（08 §4「说」）：管制发的许可、机组的复诵是否朗读出来。
## 片段库是离线生成的；没有片段库时这一项自动无效（不会报错）。
var speak_enabled := false
## 神经语音（IndexTTS2 本地服务）：开了就实时合成，连不上自动退回片段库
var tts_enabled := false
## 最近一次语音判定结果 {action, text, reason, kind...}，供面板回显
var last_voice := {}
## 被判"没听清"的次数（进评分；教学关卡不该被扣太多）
var voice_unheard := 0
## 高级模式的无障碍开关：语音失败时是否允许文本兜底（§4.5，默认关闭）
var allow_text_fallback := false
## 教学关卡（08 §4.6）：语音识别容错放宽，避免玩家因发音被卡住
var teaching := false
## 语音辅助功能开关（§4.4），缺省值见 VoiceMode.AUX_DEFAULTS
var voice_aux := {}
## ---- 离场情报通报（规范 §5.2）----
var enable_dep_info := false
## 离场情报的条目；QNH 是刚性项（不因 ATIS 省略），其余可因已抄收 ATIS 省略
const DEP_ITEMS := [
	{"key": "runway", "label": "使用跑道"},
	{"key": "wind", "label": "风向风速"},
	{"key": "vis", "label": "能见度"},
	{"key": "qnh", "label": "修正海压", "required": true},
	{"key": "taxi", "label": "地面滑行路线"},
	{"key": "rvr", "label": "跑道视程"},
	{"key": "windshear", "label": "低空风切变"},
]

## 进行中的「协调修改」：key 为 "呼号|字段"，value 为 {"ready_at": 秒}
var _coord := {}

## 调试用：置 true 后下一次复诵必定读错。给人工/自动化验证"复诵不一致"分支用。
var force_error_next := false
## 调试用：置 true 后下一次复诵必定读对（教学关、测试夹具用）
var force_ok_next := false


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
	f.last_request_at = sim_time
	f.request_count = 1
	_assign_slot(f, sim_time)
	flights.append(f)

	var alpha := str(field.get("atis_alpha", "A"))
	# 机组第一次呼叫：这句话必须真的念出来（玩家最常抱怨"从来没听到申请"）
	var say := Voice.request(f.callsign, f.stand, f.destination, f.atis_ok)
	if f.atis_ok:
		_log(sim_time, "pilot",
			"放行，%s，停机位 %s，已收到通播 %s，申请放行至 %s。" % [
				f.callsign, f.stand, alpha, f.destination], say)
	else:
		_log(sim_time, "pilot",
			"放行，%s，停机位 %s，申请放行至 %s。" % [f.callsign, f.stand, f.destination],
			say)
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


# ---------------------------------------------------------------- 移交检查（规范 §7）

## 五项检查（规范 §7.1）。每项 {key,label,ok}。
func handoff_checklist(f: Flight) -> Array:
	var atis_ok_now := true
	if enable_atis_lifecycle:
		atis_ok_now = f.atis_notified or not atis_expired
	var cleared := f.state == Flight.State.CLEARED
	return [
		{"key": "plan", "label": "飞行计划已审查", "ok": f.checked},
		{"key": "clearance", "label": "放行许可已发布",
			"ok": cleared or f.state == Flight.State.SENT
				or f.state == Flight.State.READBACK},
		{"key": "readback", "label": "复诵已确认", "ok": cleared},
		{"key": "qnh", "label": "修正海压已确认",
			"ok": (not enable_qnh_gate) or f.qnh_confirmed},
		{"key": "atis", "label": "通播状态已核对", "ok": atis_ok_now},
	]


## 可以移交了吗：条件全满足，且（高阶模式）玩家逐项确认过。
func handoff_ready(f: Flight) -> bool:
	for it in handoff_checklist(f):
		if not bool((it as Dictionary).get("ok", false)):
			return false
		if handoff_hard and not f.handoff_confirmed.has(String((it as Dictionary).key)):
			return false
	return true


## 高阶模式：逐项确认。条件不满足的项不允许确认（规范 §7.2）。
func confirm_handoff_item(callsign: String, key: String) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if not handoff_hard:
		return {"ok": false, "error": "简易模式不需要逐项确认"}
	for it in handoff_checklist(f):
		var d: Dictionary = it
		if String(d.key) != key:
			continue
		if not bool(d.ok):
			return {"ok": false, "error": "「%s」还不满足，不能确认" % String(d.label)}
		f.handoff_confirmed[key] = true
		return {"ok": true, "error": ""}
	return {"ok": false, "error": "清单里没有这一项"}


# ---------------------------------------------------------------- 整理进程单（规范 §4）

## 一键整理：按计划时刻重排、清掉已移交航班的残留排序位。
## 不改变任何航班的状态与数据；2 秒冷却，防止频繁点击。
func tidy_strips(sim_time: float) -> Dictionary:
	if _tidy_at >= 0.0 and sim_time - _tidy_at < TIDY_COOLDOWN:
		return {"ok": false, "error": "刚整理过，稍等一下再整理"}
	_tidy_at = sim_time
	reset_order()
	var n := 0
	for f in flights:
		var fl := f as Flight
		if fl.handed_off:
			fl.order_rank = -1
			n += 1
	return {"ok": true, "error": "", "handed_off": n}


# ---------------------------------------------------------------- 运行品质评分（规范 §11）

## 评分不判负，只决定关卡星级/绩效等级。
## 返回 {total, grade, lines:[{label, delta}]}，lines 按发生顺序给玩家看。
func score_report() -> Dictionary:
	var lines: Array = []
	var total := 0

	var on_time := 0
	var late := 0
	for f in flights:
		var fl := f as Flight
		if fl.state != Flight.State.CLEARED:
			continue
		if fl.slot_eval == "延误":
			late += 1
		else:
			on_time += 1
	if on_time > 0:
		_add_line(lines, "按时放行 %d 架" % on_time, on_time * 2)
		total += on_time * 2
	if late > 0:
		_add_line(lines, "顺序调整导致延误 %d 架" % late, -late)
		total -= late

	var missed_rb := 0
	var missed_rev := 0
	var late_ho := 0
	var clean_ho := 0
	var dep_skip := 0
	for f in flights:
		var fl := f as Flight
		missed_rb += fl.missed_readback
		missed_rev += fl.missed_review
		dep_skip += fl.dep_info_skipped
		if fl.handoff_late:
			late_ho += 1
		elif fl.handed_off:
			clean_ho += 1
	if clean_ho > 0:
		_add_line(lines, "干净移交 %d 架" % clean_ho, clean_ho)
		total += clean_ho
	if missed_rb > 0:
		_add_line(lines, "复诵漏检 %d 项" % missed_rb, -3 * missed_rb)
		total -= 3 * missed_rb
	if missed_rev > 0:
		_add_line(lines, "计划异常漏检 %d 项" % missed_rev, -2 * missed_rev)
		total -= 2 * missed_rev
	if late_ho > 0:
		_add_line(lines, "移交超时 %d 架" % late_ho, -late_ho)
		total -= late_ho
	if readback_timeouts > 0:
		_add_line(lines, "复诵核对超时 %d 次" % readback_timeouts,
			-2 * readback_timeouts)
		total -= 2 * readback_timeouts
	if misjudge_count > 0:
		_add_line(lines, "误判复诵 %d 次" % misjudge_count, -misjudge_count)
		total -= misjudge_count
	if atis_err_count > 0:
		_add_line(lines, "通播要素与实况不符 %d 次" % atis_err_count,
			-3 * atis_err_count)
		total -= 3 * atis_err_count
	if dep_skip > 0:
		_add_line(lines, "离场情报漏报 %d 项" % dep_skip, -dep_skip)
		total -= dep_skip

	var taxi_skipped := 0
	for f in flights:
		if (f as Flight).dep_taxi_skip:
			taxi_skipped += 1
	if taxi_skipped > 0:
		_add_line(lines, "滑行路线未通报 %d 架" % taxi_skipped, -taxi_skipped)
		total -= taxi_skipped
	if emergency_count > 0:
		_add_line(lines, "通播有误导致特情 %d 起" % emergency_count,
			-5 * emergency_count)
		total -= 5 * emergency_count

	return {"total": total, "grade": _grade(total), "lines": lines}


func _add_line(lines: Array, label: String, delta: int) -> void:
	lines.append({"label": label, "delta": delta})


static func _grade(total: int) -> String:
	if total >= 10:
		return "A"
	if total >= 1:
		return "B"
	return "C"


# ---------------------------------------------------------------- AI 驾驶舱（07 文档）

## 机组对许可做完整性检查（规范 §4.4）。返回质疑内容列表，空表示接受。
## 只有"必质疑"的几类：编码被占用、高度不可用、离场程序不兼容、缺修正海压。
func pilot_check(f: Flight, sid: String, alt_m: int, squawk: String) -> Array:
	var out: Array = []
	var owner := squawk_owner(squawk, f.callsign)
	if owner != "":
		out.append("应答机编码 %s 已被占用，请重新指定" % squawk)
	var band := PlanReview.loa_band(review_ref, sid)
	if not band.is_empty():
		var lo := int(band.get("alt_min", 0))
		var hi := int(band.get("alt_max", 0))
		if alt_m < lo or alt_m > hi:
			out.append("高度 %d 米不可用，请指定其他高度（%d–%d 米）"
				% [alt_m, lo, hi])
	if not SID_ROUTES.has(sid):
		out.append("不能执行该离场程序，请确认离场程序与计划航路")
	if int(field.get("qnh", 0)) <= 0:
		out.append("缺少高度表拨正值，请提供 QNH")
	return out


## 没人理时机组会再叫两遍；三遍之后转"机组等待中"（规范 §4.3）。
func _tick_pilot_requery(sim_time: float) -> void:
	if not pilot_check_enabled:
		return
	for f in flights:
		var fl := f as Flight
		if fl.state != Flight.State.PENDING or fl.pilot_waiting:
			continue
		if fl.request_count >= MAX_REQUESTS:
			fl.pilot_waiting = true
			_log(sim_time, "system", "%s 机组等待中（已呼叫 %d 次）。"
				% [fl.callsign, fl.request_count])
			continue
		if sim_time - fl.last_request_at < REQUEST_INTERVAL:
			continue
		fl.request_count += 1
		fl.last_request_at = sim_time
		_log(sim_time, "pilot", "%s 再次呼叫放行，申请放行至 %s。" % [
			fl.callsign, fl.destination])


## 按难度决定这一轮机组读错的概率（规范 §4.6）：0% / 30% / 60%，
## 每纠正一次概率减半，连续纠正两次后不再读错。
func readback_error_rate(f: Flight) -> float:
	if difficulty == "easy":
		return 0.0
	var base := 0.60 if difficulty == "hard" else 0.30
	var n := mini(f.reissue_count, 2)
	if n >= 2:
		return 0.0
	return base * pow(0.5, float(n))


## 一次复诵里最多注入几处错误（规范 §4.6：简易 0 / 进阶 1 / 高阶 2）
func max_readback_errors() -> int:
	if difficulty == "easy":
		return 0
	return 2 if difficulty == "hard" else 1


# ---------------------------------------------------------------- 简易模式候选通话（08 §2）

## 是否在候选里混一条数值错误的（规范 §2.4，默认关闭）
var candidate_error := false

## 当前这架能发哪些通话。返回 [{id,text,kind,correct,hint}]，2-4 条。
## 候选不是随机拼的，全部按当前状态过滤——复诵没确认时不会冒出移交指令。
func radio_candidates(callsign: String) -> Array:
	var f := get_flight(callsign)
	if f == null:
		return []
	var out: Array = []
	var limit := f.clearance_limit if f.clearance_limit != "" else f.destination

	if f.state == Flight.State.PENDING:
		# 完整许可（正确的一条）
		var good := "%s，许可放行至 %s，按 %s 离场，经 %s，初始高度 %d 米，应答机 %s，修正海压 %d。" % [
			f.callsign, limit, f.sid, f.route, f.initial_alt_m, f.squawk,
			int(field.get("qnh", 0))]
		out.append({"id": "clr", "text": good, "kind": "clearance",
			"correct": true, "hint": "完整许可"})
		# 含错误候选（规范 §2.4）：把修正海压改错
		if candidate_error:
			var qnh := int(field.get("qnh", 0))
			var bad_qnh := qnh + 5 if qnh > 0 else 1013
			var bad := good.replace("修正海压 %d" % qnh, "修正海压 %d" % bad_qnh)
			out.append({"id": "clr_bad", "text": bad, "kind": "clearance",
				"correct": false, "hint": "修正海压写错"})
		out.append({"id": "wait", "text": "%s，请稍等。" % f.callsign,
			"kind": "wait", "correct": true, "hint": "让机组等一下"})
		out.append({"id": "repeat", "text": "%s，重复一遍。" % f.callsign,
			"kind": "repeat", "correct": true, "hint": "没听清"})
	elif f.state == Flight.State.READBACK:
		out.append({"id": "rb_ok", "text": "%s，复诵正确。" % f.callsign,
			"kind": "accept", "correct": true, "hint": "复诵一致"})
		out.append({"id": "rb_bad", "text": "%s，复诵有误，重新发布许可。" % f.callsign,
			"kind": "reissue", "correct": true, "hint": "复诵不一致"})
	elif f.state == Flight.State.CLEARED and not f.handed_off:
		var g := str(field.get("ground_freq", ""))
		out.append({"id": "handoff", "text": "%s，联系地面 %s，再见。" % [f.callsign, g],
			"kind": "handoff", "correct": true, "hint": "移交给地面席"})
	else:
		out.append({"id": "wait", "text": "%s，请稍等。" % f.callsign,
			"kind": "wait", "correct": true, "hint": "让机组等一下"})
	return out


## 简易模式：把选中的那条候选真正执行掉。返回值与对应动作一致。
func send_candidate(callsign: String, cand_id: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	var cand: Dictionary = {}
	for c in radio_candidates(callsign):
		if String((c as Dictionary).id) == cand_id:
			cand = c
			break
	if cand.is_empty():
		return {"ok": false, "error": "这条通话现在不适用"}

	var text := String(cand.text)
	match String(cand.kind):
		"clearance":
			# issue_clearance 自己会把完整许可写进通话记录，这里不要再记一遍
			return issue_clearance(callsign, f.sid, f.initial_alt_m, f.squawk, sim_time)
		"accept":
			return accept_readback(callsign, sim_time)
		"reissue":
			return reissue(callsign, sim_time)
		"handoff":
			return handoff_ground(callsign, sim_time)
		"repeat":
			_log(sim_time, "atc", text)
			_log(sim_time, "pilot", "%s，重复：许可放行至 %s。" % [
				f.callsign,
				f.clearance_limit if f.clearance_limit != "" else f.destination])
			return {"ok": true, "error": ""}
		_:
			# 请稍等：机组回一句就完事
			_log(sim_time, "atc", text)
			_log(sim_time, "pilot", "%s，收到，稍等。" % f.callsign)
			return {"ok": true, "error": ""}


## 通播与实况不符导致机组出特情的次数（进评分）
var emergency_count := 0

## 通播编辑界面的可选项（规范 §3.2）。每项给出"当前值 + 邻近值"，
## 玩家选到非当前值就是"通播有误"——这是特情的来源之一。
func atis_edit_options() -> Dictionary:
	var qnh := int(field.get("qnh", 0))
	var rwy := str(field.get("runway", ""))
	var wind := str(field.get("wind", ""))
	var vis := str(field.get("visibility", ""))
	var tl := atis.transition_level if atis.transition_level != "" else "3600"
	return {
		"alpha": AtisBroadcast.next_alpha(atis.alpha),
		"runway": [rwy, _flip_runway(rwy)],
		"transition_level": [tl, "3000", "3600", "4200"],
		"wind": [wind, _shift_wind(wind, 20), _shift_wind(wind, -20)],
		"visibility": [vis, "3000M", "1500M", "500M"],
		"qnh": [qnh, qnh - 1, qnh + 1, qnh + 5],
		"brake": ["良好", "中等", "偏差"],
		"hazards": ["风切变", "雷雨", "积冰"],
	}


## 反过来那条跑道（18 ↔ 36）。跑道号是磁航向/10（01–36），不是度数。
static func _flip_runway(rwy: String) -> String:
	if rwy == "":
		return ""
	var n := int(rwy)
	if n <= 0 or n > 36:
		return rwy
	var f := n + 18 if n <= 18 else n - 18
	return "%02d" % f


## 把风向转一个角度，其余（风速/单位）不变；解析不了就原样返回
static func _shift_wind(wind: String, delta: float) -> String:
	var p := Meteo.parse_wind(wind)
	if not bool(p.get("ok", false)):
		return wind
	var dir := fposmod(float(p.get("dir", 0)) + delta, 360.0)
	return "%03d%02d%s" % [int(dir), int(p.get("speed", 0)),
		String(p.get("unit", "MPS"))]


## 通播有误 → 机组可能出特情（规范 §3.4）。检查在 tick 里推进。
func _tick_emergency(sim_time: float) -> void:
	if not enable_atis_lifecycle:
		return
	for f in flights:
		var fl := f as Flight
		if not fl.atis_suspect or fl.emergency != "":
			continue
		if fl.state != Flight.State.SENT and fl.state != Flight.State.READBACK \
				and fl.state != Flight.State.CLEARED:
			continue
		if fl.t_sent < 0.0 or sim_time - fl.t_sent < EMERGENCY_DELAY:
			continue
		# 按通播错在哪一项决定特情类型
		var kind := "高度偏差"
		if atis.qnh != int(field.get("qnh", 0)):
			kind = "高度表指示偏差"
		elif atis.runway != str(field.get("runway", "")):
			kind = "航向偏差"
		elif atis.wind != str(field.get("wind", "")):
			kind = "遭遇风切变未预警"
		fl.emergency = kind
		emergency_count += 1
		_log(sim_time, "pilot",
			"%s 报告 %s，请求处置。" % [fl.callsign, kind])
		_log(sim_time, "system",
			"特情：%s —— 通播要素与实况不符（%s）。" % [fl.callsign, kind])


## 复诵到了却一直没人判（规范 §4.7：180 秒后机组不催，只把卡片标成"机组等待中"）
const READBACK_WAIT := 180.0


func _tick_readback_waiting(sim_time: float) -> void:
	for f in flights:
		var fl := f as Flight
		if fl.state != Flight.State.READBACK or fl.pilot_waiting:
			continue
		if fl.t_readback < 0.0 or sim_time - fl.t_readback < READBACK_WAIT:
			continue
		fl.pilot_waiting = true
		_log(sim_time, "system", "%s 机组等待中（复诵已到 %d 秒未确认）。" % [
			fl.callsign, int(sim_time - fl.t_readback)])


## 07 §5.1：复诵确认后机组主动报"地面准备好了，呼号"（2–5 秒后，只说一次）
func _tick_ground_ready(sim_time: float) -> void:
	for f in flights:
		var fl := f as Flight
		if fl.ground_ready_said or fl.ground_ready_at < 0.0:
			continue
		if fl.handed_off or sim_time < fl.ground_ready_at:
			continue
		fl.ground_ready_said = true
		_log(sim_time, "pilot", "地面准备好了，%s。" % fl.callsign)


## 该项是否正在协调中（界面显示「协调中…」）
func review_coordinating(callsign: String, key: String) -> bool:	return _coord.has("%s|%s" % [callsign, key])


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
	if atis.has_error:
		atis_err_count += 1
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

	# 移交检查清单（规范 §7）：条件不满足不许移交，高阶模式还要逐项确认
	if enable_handoff_check:
		for it in handoff_checklist(f):
			var d: Dictionary = it
			if not bool(d.ok):
				return {"ok": false, "error": "移交条件未满足：%s" % String(d.label)}
		if handoff_hard:
			for it in handoff_checklist(f):
				var d2: Dictionary = it
				if not f.handoff_confirmed.has(String(d2.key)):
					return {"ok": false,
						"error": "请先逐项确认：%s" % String(d2.label)}
		# 90 秒时限：超了照常能移交，但打上标记进评分
		if f.t_cleared >= 0.0 and sim_time - f.t_cleared > HANDOFF_LIMIT:
			f.handoff_late = true

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


## 开局把"已经到点该申请"的航班放出来（按计划时刻，不硬塞）。
## 返回放了几架。没有计划时会放一架兜底，免得列表空着。
func seed_due(sim_time: float) -> int:
	var n := 0
	while n < 8:
		var f := maybe_spawn(sim_time)
		if f == null:
			break
		n += 1
	return n


## 无条件塞几架（单元测试 / 关卡脚本用）。正常开局请用 seed_due。
func seed_initial(sim_time: float, count: int = 2) -> void:
	for i in range(count):
		spawn_request(sim_time)
	_last_spawn = sim_time


## 到点自动来一架新的放行申请；不该来的时候返回 null。
##
## 07 §2.2：按当日计划的起飞时刻倒推，提前 lead_minutes 分钟才允许申请 ——
## 不是"每 18 秒冒一架"的无脑节奏。计划里没有时刻（或已经用完）时，
## 才退回按间隔补，保证列表不会一直空着。
func maybe_spawn(sim_time: float) -> Flight:
	if pending().size() >= max_pending:
		return null
	var due := plan_request_minute(plan_index)
	if plan_index < plan.size() and due >= 0.0:
		var now_m := clock_origin() + sim_time / 60.0
		if now_m + 0.001 < due:
			return null
		_last_spawn = sim_time
		return spawn_request(sim_time)
	if sim_time - _last_spawn < spawn_interval:
		return null
	_last_spawn = sim_time
	return spawn_request(sim_time)


## 开局时刻（当日分钟）。clock_start "0755" → 475。
func clock_origin() -> float:
	if _clock_origin < 0.0:
		_clock_origin = float(Atis.minutes_since(
			str(field.get("clock_start", "0000")), 0.0))
	return _clock_origin


## 计划第 i 条的"可以申请时刻"（当日分钟）。没有 std 返回 -1。
## 每条只算一次（含 0–10 秒抖动），同一次运行里结果稳定。
func plan_request_minute(i: int) -> float:
	if i < 0 or i >= plan.size():
		return -1.0
	var pe: Dictionary = plan[i]
	if pe.has("_req_min"):
		return float(pe["_req_min"])
	var std := str(pe.get("std", ""))
	if std.length() != 4 or not std.is_valid_int():
		pe["_req_min"] = -1.0
		return -1.0
	var m := float(int(std.substr(0, 2)) * 60 + int(std.substr(2, 2)))
	var jitter := rng.randf_range(0.0, 10.0) / 60.0
	var req := m - lead_minutes + jitter
	pe["_req_min"] = req
	return req


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


# ---------------------------------------------------------------- 三模式发布（规范 §5.1）

## 预设一键模式：按飞行计划 + 当前运行要素直接生成一份完整许可。
func preset_clearance(callsign: String) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	var squawk := f.squawk
	if not is_valid_squawk(squawk):
		squawk = _random_squawk()
	return {
		"ok": true, "error": "",
		"sid": f.sid if SIDS.has(f.sid) else SIDS[0],
		"alt_m": f.initial_alt_m,
		"squawk": squawk,
		"text": clearance_text(f),
	}


## 预设一键发送：校验交给 issue_clearance，这里只负责把要素取出来。
func issue_preset(callsign: String, sim_time: float) -> Dictionary:
	var p := preset_clearance(callsign)
	if not bool(p.ok):
		return p
	return issue_clearance(callsign, String(p.sid), int(p.alt_m),
		String(p.squawk), sim_time)


## 自由文本模式：用关键词 + 数值把七项要素抠出来再校验（规范 §5.1 模式 C）。
## 语音识别不在这一步；ASR 转成文本之后走的也是这条路径。
##
## 缺项分两类（07 §4.4）：
##   · 呼号 / 放行界限 / 修正海压 —— 管制侧直接拒绝（打错飞机、漏 QNH 都是硬错误）
##   · 离场程序 / 初始高度 / 应答机 —— 进阶及以上交给机组质疑"许可不完整，请重复"
func issue_free_text(callsign: String, text: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	var t := text.strip_edges()
	if t == "":
		return {"ok": false, "error": "通话内容为空"}
	if not t.contains(f.callsign):
		return {"ok": false, "error": "缺少呼号 %s" % f.callsign}
	var limit := f.clearance_limit if f.clearance_limit != "" else f.destination
	if limit != "" and not t.contains(limit):
		return {"ok": false, "error": "缺少放行界限 %s" % limit}
	var qnh := int(field.get("qnh", 0))
	if qnh > 0 and not t.contains(str(qnh)):
		return {"ok": false, "error": "缺少修正海压 %d" % qnh}

	var missing: Array = []
	var sid := ""
	for s in SIDS:
		if t.contains(s):
			sid = s
			break
	if sid == "":
		missing.append("离场程序")
	# 扫数字之前先把呼号遮掉：CES5175 里的 5175 不能被当成应答机/高度（真踩过）
	var scan := VoiceMode.mask_callsigns(t, [f.callsign])
	var alt := 0
	for a in ALT_OPTIONS:
		if scan.contains(str(a)):
			alt = a
			break
	if alt == 0:
		missing.append("初始高度")
	var sq := find_squawk_in_text(scan, alt)
	if sq == "":
		missing.append("应答机编码")

	if not missing.is_empty():
		# 进阶/高阶：机组质疑"许可不完整"，状态不动，玩家补全后重发
		if pilot_check_enabled and difficulty != "easy":
			f.pilot_queries += 1
			_log(sim_time, "atc", t)
			_log(sim_time, "pilot",
				"%s，许可不完整，请重复。" % f.callsign, Voice.simple(f.callsign, "p_incomplete"))
			return {"ok": true, "queried": true,
				"error": "机组质疑：许可不完整，请重复（缺 %s）"
					% "、".join(PackedStringArray(missing))}
		return {"ok": false, "error": "缺少 %s"
			% "、".join(PackedStringArray(missing))}

	return issue_clearance(callsign, sid, alt, sq, sim_time)


## 高级模式（真实语音通话，08 §4）的入口：ASR 转录 + 置信度 → 该干什么。
##
## 文档 §4.3 规定三种回退语义，都在这里判：
##   · 置信度低于门槛 → 不提示玩家重输，而是**模拟驾驶舱没听清**，AI 重新呼叫；
##   · 解析不出内容 → 同上（"没听清"）；
##   · 呼号与当前选中航班不符 → 系统提示"呼号不符，请确认"。
## 转录先经 VoiceMode.normalize() 规范化（「幺两洞洞」→「1200」），
## 再交给 issue_free_text() 走与进阶模式**完全一致**的七项要素校验，不另写一套。
##
## mic/ASR 引擎不在这里：它的输出是入参。这样这条链路能在无头环境下测。
func issue_voice(callsign: String, transcript: String, confidence: float,
		sim_time: float, teaching: bool = false) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	var known: Array = []
	for fl in flights:
		known.append(fl.callsign)
	var dec := VoiceMode.decide(transcript, confidence, callsign, known,
		teaching or self.teaching)
	last_voice = dec
	var action := String(dec.get("action", ""))
	if action == "unheard":
		voice_unheard += 1
		var line := "%s，没听清，请再说一遍。" % f.callsign
		_log(sim_time, "pilot", line, Voice.simple(f.callsign, "p_say_again"))
		return {"ok": true, "unheard": true, "line": line,
			"text": String(dec.get("text", "")),
			"error": "机组没听清（%s），请重新说" % String(dec.get("reason", ""))}
	if action == "mismatch":
		return {"ok": false, "mismatch": true,
			"said": String(dec.get("said", "")),
			"error": "呼号不符，请确认（说的是 %s）" % String(dec.get("said", ""))}
	# 08 §7.1：放行席有四类玩家要说的通话，按类型分派到各自的动作。
	# 注意：确认/退回/移交这三个动作**自己会记通话记录**，这里不能再记一遍。
	var text := String(dec.get("text", ""))
	var kind := String(dec.get("kind", ""))
	var res: Dictionary
	match kind:
		"rb_ok":
			res = accept_readback(callsign, sim_time)
		"rb_bad":
			res = reissue(callsign, sim_time)
		"handoff":
			res = handoff_ground(callsign, sim_time)
		"wait", "repeat":
			# 通用短语：不用改状态，只是把话说出去
			_speak_atc(sim_time, text)
			res = {"ok": true, "error": ""}
		_:
			res = issue_free_text(callsign, text, sim_time)
	res["voice"] = true
	res["kind"] = kind
	return res


## 把管制说的这句记进通话记录（真说了才算说过）
func _speak_atc(sim_time: float, text: String) -> void:
	if text.strip_edges() != "":
		_log(sim_time, "atc", text)


## 从一段通话里找 4 位八进制应答机编码（排除高度之类已经用掉的数字）。
static func find_squawk_in_text(text: String, alt_m: int) -> String:
	var alt_txt := str(alt_m)
	var i := 0
	while i + 4 <= text.length():
		var s := text.substr(i, 4)
		var ok := true
		for k in range(4):
			var c := s[k]
			if c < "0" or c > "7":
				ok = false
				break
		if ok and s != alt_txt:
			var before_ok := i == 0 or text[i - 1] < "0" or text[i - 1] > "9"
			var after_ok := i + 4 >= text.length() \
				or text[i + 4] < "0" or text[i + 4] > "9"
			if before_ok and after_ok:
				return s
		i += 1
	return ""


# ---------------------------------------------------------------- 离场情报（规范 §5.2）

## 当前应通报的离场情报条目；每条 {key,label,value,required,notified,covered}
## covered = 机组已抄收现行 ATIS，这一条可以口头省略（QNH 除外）。
func departure_info_items(f: Flight) -> Array:
	var out: Array = []
	var qnh := int(field.get("qnh", 0))
	var values := {
		"runway": str(field.get("runway", "")),
		"wind": str(field.get("wind", "")),
		"vis": str(field.get("visibility", "")),
		"qnh": str(qnh) if qnh > 0 else "",
		"taxi": "",
		"rvr": "",
		"windshear": "",
	}
	for it in DEP_ITEMS:
		var d: Dictionary = it
		var key := String(d.key)
		var required := bool(d.get("required", false))
		var covered := f.atis_ok and not required
		out.append({
			"key": key, "label": String(d.label), "value": String(values[key]),
			"required": required, "covered": covered,
			"notified": covered or f.dep_info_notified.has(key),
		})
	return out


## 通报（勾选）一条离场情报
func toggle_dep_info(callsign: String, key: String) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.dep_info_notified.has(key):
		f.dep_info_notified.erase(key)
	else:
		f.dep_info_notified.append(key)
	return {"ok": true, "error": ""}


## 一键全部通报
func notify_all_dep_info(callsign: String) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	for it in departure_info_items(f):
		f.dep_info_notified.append(String((it as Dictionary).key))
	return {"ok": true, "error": ""}


## 还有几条该通报没通报（机组没抄 ATIS 时才存在这个问题）
## 明确选了"不通报滑行路线"的那一条不算漏（08 §5.2 的策略选择），
## 但会在评分里单独记一笔"滑行路线未通报"。
func dep_info_missing(f: Flight) -> int:
	var n := 0
	for it in departure_info_items(f):
		var d: Dictionary = it
		if bool(d.get("required", false)):
			continue
		if String(d.get("key", "")) == "taxi" and f.dep_taxi_skip:
			continue
		if not bool(d.get("notified", false)):
			n += 1
	return n


## 策略选择：滑行路线不通报（机组到地面席再拿）
func set_dep_taxi_skip(callsign: String, skip: bool) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	f.dep_taxi_skip = skip
	if skip:
		f.dep_info_notified.erase("taxi")
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
	if enable_value_check and not pilot_check_enabled:
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

	# 机组对许可做完整性检查（规范 §4.4）：有问题就质疑，不改状态、不进入复诵。
	# 连续质疑到上限后机组接受现有内容，避免死循环。
	if pilot_check_enabled:
		var queries := pilot_check(f, f.sid, f.initial_alt_m, f.squawk)
		if not queries.is_empty() and f.pilot_queries < MAX_PILOT_QUERIES:
			f.pilot_queries += 1
			f.state = Flight.State.PENDING
			f.t_sent = -1.0
			f.readback_at = 0.0
			_log(sim_time, "atc", full_clearance_text(f), Voice.clearance(f.callsign, f.sid, f.clearance_limit if f.clearance_limit != "" else f.destination, f.initial_alt_m, f.squawk, int(field.get("qnh", 0))))
			_log(sim_time, "pilot", "%s，%s" % [f.callsign, queries[0]])
			return {"ok": true, "queried": true,
				"error": "机组质疑：" + String(queries[0])}
		elif not queries.is_empty():
			_log(sim_time, "system",
				"%s 已连续质疑 %d 次，机组按现有内容接受。" % [
					f.callsign, f.pilot_queries])

	_eval_slot(f, sim_time)
	# 这次放行引用的通播如果与实况不符，记下来 —— 之后可能出特情（§3.4）
	if enable_atis_lifecycle and atis.has_error:
		f.atis_suspect = true
	if enable_dep_info:
		f.dep_info_skipped = dep_info_missing(f)
	_log(sim_time, "atc", full_clearance_text(f), Voice.clearance(f.callsign, f.sid, f.clearance_limit if f.clearance_limit != "" else f.destination, f.initial_alt_m, f.squawk, int(field.get("qnh", 0))))
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
	_tick_readback_deadline(sim_time)
	_tick_pilot_requery(sim_time)
	_tick_emergency(sim_time)
	_tick_readback_waiting(sim_time)
	_tick_ground_ready(sim_time)
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


## 高阶模式复诵核对超时：退回「计划已审查」，需要重新发布许可（规范 §6.2）。
## 规范原文说退回"许可已发布"，但那个状态下没法重新发布，
## 所以这里退到可以重发的状态，语义上仍然是"这架没放成、要重来"。
func _tick_readback_deadline(sim_time: float) -> void:
	if not readback_hard:
		return
	for f in flights:
		var fl := f as Flight
		if fl.state != Flight.State.READBACK:
			continue
		if fl.readback_deadline < 0.0 or sim_time < fl.readback_deadline:
			continue
		fl.state = Flight.State.PENDING
		fl.readback_deadline = -1.0
		fl.readback_text = ""
		fl.readback_items = []
		fl.readback_marks = {}
		fl.readback_at = 0.0
		fl.t_sent = -1.0
		fl.t_readback = -1.0
		readback_timeouts += 1
		_log(sim_time, "system",
			"%s 复诵核对超时，退回「计划已审查」，需重新发布许可。" % fl.callsign)


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
	var limit := f.clearance_limit if f.clearance_limit != "" else f.destination
	# 机组报出来的值（可能读错）；文本与逐项表用同一份，避免"念一套、比一套"
	var sid := f.sid
	var route := f.route
	var alt := f.initial_alt_m
	var squawk := f.squawk
	var diffs := PackedStringArray()

	var want := 0
	if force_ok_next:
		# 教学关/测试用：强制这一轮机组读对
		force_ok_next = false
		want = 0
	elif force_error_next:
		force_error_next = false
		want = maxi(1, max_readback_errors())
	elif rng.randf() < readback_error_rate(f):
		want = max_readback_errors()
	want = mini(want, max_readback_errors())

	var kinds := [0, 1, 2, 3]
	for _i in range(want):
		if kinds.is_empty():
			break
		var pick := rng.randi_range(0, kinds.size() - 1)
		var kind: int = kinds[pick]
		kinds.remove_at(pick)
		if kind == 0:
			squawk = _corrupt_digit(f.squawk)
			diffs.append("应答机读成 %s，应为 %s" % [squawk, f.squawk])
		elif kind == 1:
			alt = f.initial_alt_m + 1000
			diffs.append("初始高度读成 %d 米，应为 %d 米" % [alt, f.initial_alt_m])
		elif kind == 2:
			var bad_sid := SIDS[0]
			for s in SIDS:
				if s != f.sid:
					bad_sid = s
					break
			sid = bad_sid
			route = str(SID_ROUTES.get(bad_sid, ""))
			diffs.append("离场程序读成 %s，应为 %s" % [bad_sid, f.sid])
		else:
			# 航路读错：真实里最常见的错误之一，只校验 SID 是抓不到的
			route = "A461 RUMUK" if f.route != "A461 RUMUK" else "W105 LADIX"
			diffs.append("航路读成 %s，应为 %s" % [route, f.route])

	var text := DeliveryDesk.readback_text_of(f.callsign, limit, sid, route, alt, squawk)
	f.readback_text = text
	f.readback_items = _readback_items(f, sid, route, alt, squawk)
	f.readback_ok = not _has_critical_mismatch(f.readback_items)
	f.readback_diff = "；".join(diffs)
	f.readback_marks = {}
	f.state = Flight.State.READBACK
	f.t_readback = sim_time
	f.readback_deadline = sim_time + READBACK_LIMIT if readback_hard else -1.0
	_log(sim_time, "pilot", text,
		Voice.readback(f.callsign, sid, limit, alt, squawk, int(field.get("qnh", 0))))


## 逐项比对表（规范 §6.1）。关键项不一致必须拦，非关键项只记录。
func _readback_items(f: Flight, sid: String, route: String, alt: int,
		squawk: String) -> Array:
	var qnh := int(field.get("qnh", 0))
	var rwy := str(field.get("runway", ""))
	var wind := str(field.get("wind", ""))
	var vis := str(field.get("visibility", ""))
	return [
		_item("runway", "使用跑道", rwy, rwy, true),
		_item("sid", "离场程序", f.sid, sid, true),
		_item("route", "航路", f.route, route, true),
		_item("alt", "初始高度", "%d 米" % f.initial_alt_m, "%d 米" % alt, true),
		_item("squawk", "应答机", f.squawk, squawk, true),
		_item("qnh", "修正海压", "%d" % qnh, "%d" % qnh, true),
		_item("freq", "离场频率", f.dep_freq, f.dep_freq, true),
		_item("wind", "地面风", wind, wind, false),
		_item("vis", "能见度", vis, vis, false),
	]


static func _item(key: String, label: String, expected: String, actual: String,
		critical: bool) -> Dictionary:
	return {
		"key": key, "label": label, "expected": expected, "actual": actual,
		"critical": critical, "same": expected == actual,
	}


func _has_critical_mismatch(items: Array) -> bool:
	for it in items:
		var d: Dictionary = it
		if bool(d.get("critical", false)) and not bool(d.get("same", true)):
			return true
	return false


## 高阶模式：玩家逐项标记"一致/不一致"（规范 §6.2）。
func mark_readback_item(callsign: String, key: String, same: bool,
		sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state != Flight.State.READBACK:
		return {"ok": false, "error": "%s 当前没有待复核的复诵" % callsign}
	if not readback_hard:
		return {"ok": false, "error": "简易模式不需要逐项标记"}
	f.readback_marks[key] = same
	return {"ok": true, "error": ""}


## 语音复诵（08 §4）：识别端返回的变体标签 → 逐项标记。
##
## 标签就是"机组把哪一项读错了"：v_ok / v_alt / v_squawk / v_qnh / v_sid / v_limit。
## 所以这一步不是"再判一次真伪"，而是把识别结果**翻译成**已有的逐项标记，
## 与高阶模式玩家手点的 mark_readback_item() 落到同一份数据里。
func apply_voice_readback(callsign: String, tag: String, confidence: float,
		sim_time: float, teaching: bool = false) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign}
	if f.state != Flight.State.READBACK:
		return {"ok": false, "error": "%s 当前没有待复核的复诵" % callsign}
	if not VoiceMode.confident(confidence, teaching or self.teaching):
		voice_unheard += 1
		var line := "%s，没听清，请再说一遍。" % f.callsign
		_log(sim_time, "pilot", line, Voice.simple(f.callsign, "p_say_again"))
		last_voice = {"action": "unheard", "reason": "复诵置信度低"}
		return {"ok": true, "unheard": true, "line": line,
			"error": "机组复诵没听清，请重新说"}
	var pt := VoiceGrammar.parse_tag(tag)
	if not bool(pt.get("known", false)):
		voice_unheard += 1
		var line2 := "%s，没听清，请再说一遍。" % f.callsign
		_log(sim_time, "pilot", line2, Voice.simple(f.callsign, "p_say_again"))
		last_voice = {"action": "unheard", "reason": "没识别出是哪一条"}
		return {"ok": true, "unheard": true, "line": line2,
			"error": "没听清复诵内容，请重新说"}
	var wrong := String(pt.get("wrong", ""))
	var marked := 0
	for it in f.readback_items:
		var d: Dictionary = it
		var key := String(d.get("key", ""))
		var same := true
		if wrong == "sid":
			# 程序读错，航路必然跟着错（程序与航路是一对）
			same = not (key == "sid" or key == "route")
		elif wrong == "limit":
			# 放行界限不在逐项复诵表里（它属于通话一开头），单独提示
			same = true
		elif wrong != "":
			same = key != wrong
		if readback_hard:
			f.readback_marks[key] = same
		marked += 1
	last_voice = {"action": "readback", "tag": tag, "wrong": wrong}
	var note := "复诵正确" if wrong == "" else "复诵把「%s」读错了" % _voice_item_label(wrong)
	return {"ok": true, "tag": tag, "wrong": wrong, "marked": marked,
		"note": note, "error": "" if wrong == "" else note}


## 变体标签对应的中文名（面板提示用）
static func _voice_item_label(key: String) -> String:
	match key:
		"alt": return "初始高度"
		"squawk": return "应答机"
		"qnh": return "修正海压"
		"sid": return "离场程序"
		"limit": return "放行界限"
		"readback": return "复诵"
		"freq": return "地面频率"
	return key


## 还有几项没核对（高阶模式界面上用来决定按钮是否可用）
func readback_unmarked(f: Flight) -> int:
	if f == null:
		return 0
	return maxi(0, f.readback_items.size() - f.readback_marks.size())


func _corrupt_digit(squawk: String) -> String:
	if squawk.length() != 4:
		return squawk
	var idx := rng.randi_range(0, 3)
	var d := int(squawk[idx])
	var nd := (d + 1) % 8
	return squawk.substr(0, idx) + str(nd) + squawk.substr(idx + 1)


## 复核通过：复诵一致才允许放行。
## 简易模式：系统已经高亮出不一致项，直接按结果判。
## 高阶模式：玩家必须逐项标记；把不一致的标成一致**不拦截，但记进评分**
## （规范 §6.2 的原话："系统不拦截，但该错误会在后续飞行阶段触发告警"）。
func accept_readback(callsign: String, sim_time: float) -> Dictionary:
	var f := get_flight(callsign)
	if f == null:
		return {"ok": false, "error": "找不到航班 %s" % callsign, "correct": false}
	if f.state != Flight.State.READBACK:
		return {"ok": false, "error": "%s 当前没有待复核的复诵" % callsign, "correct": false}

	if readback_hard:
		var unmarked := readback_unmarked(f)
		if unmarked > 0:
			return {"ok": false, "correct": false,
				"error": "还有 %d 项没有核对，请逐项判定后再确认" % unmarked}
		# 玩家标了"不一致"的关键项：说明复诵有问题，应当重发
		for it in f.readback_items:
			var d: Dictionary = it
			if not bool(d.get("critical", false)):
				continue
			if f.readback_marks.has(d.key) and not bool(f.readback_marks[d.key]):
				return {"ok": false, "correct": false,
					"error": "你把「%s」判为不一致，请重发完整许可" % String(d.label)}
		# 实际不一致却被标成一致：放过去，但记账
		var missed := 0
		for it in f.readback_items:
			var d2: Dictionary = it
			if not bool(d2.get("critical", false)) or bool(d2.get("same", true)):
				continue
			if bool(f.readback_marks.get(d2.key, false)):
				missed += 1
		if missed > 0:
			f.missed_readback += missed
			_log(sim_time, "system",
				"%s 复诵中有 %d 项与许可不一致未被发现。" % [f.callsign, missed])
	else:
		if _has_critical_mismatch(f.readback_items):
			misjudge_count += 1
			return {"ok": false, "correct": false,
				"error": "复诵与许可不一致（%s），不能作为放行依据，请重发。"
					% f.readback_diff}

	f.state = Flight.State.CLEARED
	f.t_cleared = sim_time
	f.readback_deadline = -1.0
	# 07 §5.1：复诵确认后机组会主动报"地面准备好了"（随机 2–5 秒）
	f.ground_ready_at = sim_time + 2.0 + rng.randf() * 3.0
	f.ground_ready_said = false
	cleared_count += 1
	_log(sim_time, "atc", "%s，复诵正确，放行完成，联系地面。" % f.callsign,
		Voice.simple(f.callsign, "p_readback_ok"))
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
	f.readback_items = []
	f.readback_marks = {}
	f.readback_deadline = -1.0
	f.readback_at = 0.0
	f.t_sent = -1.0
	f.t_readback = -1.0

	_log(sim_time, "atc", "%s，复诵有误，请重新抄收。" % f.callsign,
		Voice.simple(f.callsign, "p_incomplete"))
	return {"ok": true, "error": "", "was_correct": was_correct}


# ---------------------------------------------------------------- 通话记录

## 记一条通话。voice 是这句话该念的片段 id（由 sim/voice.gd 决定），
## 表现层只管照着播——"播什么"永远在逻辑层定。
func _log(sim_time: float, side: String, text: String, voice: Array = []) -> void:
	var row := {"t": sim_time, "side": side, "text": text}
	if not voice.is_empty():
		row["voice"] = voice
	transcript.append(row)
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
