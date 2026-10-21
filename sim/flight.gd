## 一个航班的放行状态。
##
## 只描述"这架飞机在放行环节处于哪一步"，不含任何界面信息。
## 可以完整序列化进存档（将来席位状态要能存下来）。
class_name Flight
extends RefCounted

## 放行环节的状态机
enum State {
	PENDING,      # 机组已提出放行申请，等管制处理
	SENT,         # 管制已发放行许可，等机组复诵
	READBACK,     # 机组复诵已到，等管制判断
	CLEARED,      # 复诵正确，放行完成
}

var callsign := ""
var type := ""            # 机型
var stand := ""           # 停机位
var destination := ""     # 目的地四字码
var sid := ""             # 离场程序
var initial_alt_m := 5000 # 初始高度（米）
var squawk := ""          # 应答机

## 当日计划里这条航班的计划起飞时刻（"HHMM"）；随机生成的航班为空。
var planned_std := ""

## 放行许可要素（《民用航空空中交通管理规则》第二百九十一条）
## 许可界限：目的地或定位点
var clearance_limit := ""
## 飞行航路（放行许可第（四）项）
var route := ""
## 起飞后移交的进近频率（放行许可第（七）项"必要的管制指令"）
var dep_freq := ""
## 机组是否已在首次呼叫中报告收到当前通播（第一百五十九条）
var atis_ok := true

## ---- 飞行进程单（第一百三十三、一百三十四条：动态、许可、指令都要记入）----
## 计划是否已核对（放行前必须核对飞行计划与进程单）
var checked := false
## 已移交给地面席
var handed_off := false
## 各节点的时间戳（仿真秒）；-1 表示尚未发生
var t_check := -1.0
var t_sent := -1.0
var t_readback := -1.0
var t_cleared := -1.0
var t_handoff := -1.0
## 已经因为延误超过 30 分钟通知过机组（第二百九十三条），只通知一次
var delay_notified := false

var state := State.PENDING
var request_time := 0.0   # 提出申请的仿真时刻

## 复诵相关
var readback_text := ""
var readback_ok := true
var readback_diff := ""   # 不一致时的人话描述
var readback_at := 0.0    # 预计复诵到达的仿真时刻

## 复诵逐项比对（规范 §6.1）：每项 {key,label,expected,actual,critical,same}
var readback_items: Array = []
## 高阶模式下玩家对每一项的判定：key → true(一致) / false(不一致)
var readback_marks := {}
## 高阶模式的核对时限（仿真秒）；-1 表示没有时限
var readback_deadline := -1.0
## 高阶模式里把不一致项误判为一致的次数（进评分）
var missed_readback := 0
## 移交检查清单里玩家逐项确认过的项（规范 §7.2 高阶模式）
var handoff_confirmed := {}
## 从复诵确认到移交超时（规范 §7.2，影响评分不阻断）
var handoff_late := false

## 离场情报里玩家逐项通报过的条目（规范 §5.2）
var dep_info_notified: Array = []
## 发放行许可时还漏报了几条离场情报（进评分）
var dep_info_skipped := 0

## ---- AI 驾驶舱（07 文档）----
## 机组已经质疑过几次（连续质疑上限 2 次，第三次就接受）
var pilot_queries := 0
## 机组已经呼叫过几次（最多 3 次，之后转"机组等待中"）
var request_count := 1
## 最近一次呼叫的仿真时刻
var last_request_at := 0.0
## 三次申请都没人理 → 机组不再主动呼叫
var pilot_waiting := false

## 放行时引用的通播与实况不符（规范 §3.4：可能引发特情）
var atis_suspect := false
## 已经发生的特情描述；空串表示正常
var emergency := ""

## ---- 飞行计划原值：放行前要与"当前有效值"逐项对照（放行机制规范 §1.2）----
var plan_origin := ""      # 计划起飞机场
var plan_route := ""       # 计划航路
var plan_type := ""        # 计划机型
var plan_wake := ""        # 计划尾流类别
var plan_alternate := ""   # 计划备降场
var plan_alt_m := 0        # 计划初始高度（米）
var plan_tow_t := 0        # 起飞重量（吨，只显示）
var plan_endurance := ""   # 续航时间（只显示）

## 审查处置结果：字段 key → PlanReview 的处置状态
var review := {}
## 审查是否已经走到"完成审查"
var review_done := false
## 高阶模式下带着漏检完成审查的次数（进运行品质评分）
var missed_review := 0

## ---- CDM 时隙（放行机制规范 §2）----
## 全部是"当天第几分钟"，-1 表示还没算过
var eobt_min := -1        # 预计撤轮挡：来自飞行计划
var tobt_min := -1        # 目标撤轮挡：承运人/地面服务给出
var ctot_min := -1        # 计算起飞时间：受流量限制才有
var cobt_min := -1        # 计算撤轮挡：由 CTOT 反推
var ctot_restricted := false
## 手动排序：0 起；-1 表示没被玩家拖过，按计划时刻排
var order_rank := -1
## 放行时刻相对时隙的结果："提前" / "准时" / "延误" / ""
var slot_eval := ""
var slot_delay_min := 0

## 修正海压是否由管制员确认过（第二百九十四条：QNH 不可因 ATIS 而豁免）
var qnh_confirmed := false

## 机组在首次呼叫里报的通播代号；没报就是空串
var atis_reported := ""
## 管制员已就该机组的过期通播做过处置（通知最新通播 / 逐项通报变化）
var atis_notified := false

## 统计
var reissue_count := 0


func to_dict() -> Dictionary:
	return {
		"callsign": callsign,
		"type": type,
		"stand": stand,
		"destination": destination,
		"sid": sid,
		"initial_alt_m": initial_alt_m,
		"squawk": squawk,
		"planned_std": planned_std,
		"clearance_limit": clearance_limit,
		"route": route,
		"dep_freq": dep_freq,
		"atis_ok": atis_ok,
		"checked": checked,
		"handed_off": handed_off,
		"t_check": t_check,
		"t_sent": t_sent,
		"t_readback": t_readback,
		"t_cleared": t_cleared,
		"t_handoff": t_handoff,
		"delay_notified": delay_notified,
		"state": int(state),
		"request_time": request_time,
		"readback_text": readback_text,
		"readback_ok": readback_ok,
		"readback_diff": readback_diff,
		"readback_at": readback_at,
		"reissue_count": reissue_count,
		"plan_origin": plan_origin,
		"plan_route": plan_route,
		"plan_type": plan_type,
		"plan_wake": plan_wake,
		"plan_alternate": plan_alternate,
		"plan_alt_m": plan_alt_m,
		"plan_tow_t": plan_tow_t,
		"plan_endurance": plan_endurance,
		"review": review.duplicate(),
		"review_done": review_done,
		"missed_review": missed_review,
		"eobt_min": eobt_min,
		"tobt_min": tobt_min,
		"ctot_min": ctot_min,
		"cobt_min": cobt_min,
		"ctot_restricted": ctot_restricted,
		"order_rank": order_rank,
		"slot_eval": slot_eval,
		"slot_delay_min": slot_delay_min,
		"qnh_confirmed": qnh_confirmed,
		"atis_reported": atis_reported,
		"readback_items": readback_items.duplicate(true),
		"readback_marks": readback_marks.duplicate(),
		"readback_deadline": readback_deadline,
		"missed_readback": missed_readback,
		"handoff_confirmed": handoff_confirmed.duplicate(),
		"handoff_late": handoff_late,
		"dep_info_notified": dep_info_notified.duplicate(),
		"dep_info_skipped": dep_info_skipped,
		"pilot_queries": pilot_queries,
		"request_count": request_count,
		"last_request_at": last_request_at,
		"pilot_waiting": pilot_waiting,
		"atis_suspect": atis_suspect,
		"emergency": emergency,
		"atis_notified": atis_notified,
	}


static func from_dict(d: Dictionary) -> Flight:
	var f := Flight.new()
	f.callsign = str(d.get("callsign", ""))
	f.type = str(d.get("type", ""))
	f.stand = str(d.get("stand", ""))
	f.destination = str(d.get("destination", ""))
	f.sid = str(d.get("sid", ""))
	f.initial_alt_m = int(d.get("initial_alt_m", 5000))
	f.squawk = str(d.get("squawk", ""))
	f.planned_std = str(d.get("planned_std", ""))
	f.clearance_limit = str(d.get("clearance_limit", ""))
	f.route = str(d.get("route", ""))
	f.dep_freq = str(d.get("dep_freq", ""))
	f.atis_ok = bool(d.get("atis_ok", true))
	f.checked = bool(d.get("checked", false))
	f.handed_off = bool(d.get("handed_off", false))
	f.t_check = float(d.get("t_check", -1.0))
	f.t_sent = float(d.get("t_sent", -1.0))
	f.t_readback = float(d.get("t_readback", -1.0))
	f.t_cleared = float(d.get("t_cleared", -1.0))
	f.t_handoff = float(d.get("t_handoff", -1.0))
	f.delay_notified = bool(d.get("delay_notified", false))
	f.state = int(d.get("state", State.PENDING))
	f.request_time = float(d.get("request_time", 0.0))
	f.readback_text = str(d.get("readback_text", ""))
	f.readback_ok = bool(d.get("readback_ok", true))
	f.readback_diff = str(d.get("readback_diff", ""))
	f.readback_at = float(d.get("readback_at", 0.0))
	f.reissue_count = int(d.get("reissue_count", 0))
	f.plan_origin = str(d.get("plan_origin", ""))
	f.plan_route = str(d.get("plan_route", ""))
	f.plan_type = str(d.get("plan_type", ""))
	f.plan_wake = str(d.get("plan_wake", ""))
	f.plan_alternate = str(d.get("plan_alternate", ""))
	f.plan_alt_m = int(d.get("plan_alt_m", 0))
	f.plan_tow_t = int(d.get("plan_tow_t", 0))
	f.plan_endurance = str(d.get("plan_endurance", ""))
	var rv: Variant = d.get("review", {})
	f.review = rv if rv is Dictionary else {}
	f.review_done = bool(d.get("review_done", false))
	f.missed_review = int(d.get("missed_review", 0))
	f.eobt_min = int(d.get("eobt_min", -1))
	f.tobt_min = int(d.get("tobt_min", -1))
	f.ctot_min = int(d.get("ctot_min", -1))
	f.cobt_min = int(d.get("cobt_min", -1))
	f.ctot_restricted = bool(d.get("ctot_restricted", false))
	f.order_rank = int(d.get("order_rank", -1))
	f.slot_eval = str(d.get("slot_eval", ""))
	f.slot_delay_min = int(d.get("slot_delay_min", 0))
	f.qnh_confirmed = bool(d.get("qnh_confirmed", false))
	f.atis_reported = str(d.get("atis_reported", ""))
	f.atis_notified = bool(d.get("atis_notified", false))
	var ri: Variant = d.get("readback_items", [])
	f.readback_items = ri if ri is Array else []
	var rm: Variant = d.get("readback_marks", {})
	f.readback_marks = rm if rm is Dictionary else {}
	f.readback_deadline = float(d.get("readback_deadline", -1.0))
	f.missed_readback = int(d.get("missed_readback", 0))
	var hc: Variant = d.get("handoff_confirmed", {})
	f.handoff_confirmed = hc if hc is Dictionary else {}
	f.handoff_late = bool(d.get("handoff_late", false))
	var dn: Variant = d.get("dep_info_notified", [])
	f.dep_info_notified = dn if dn is Array else []
	f.dep_info_skipped = int(d.get("dep_info_skipped", 0))
	f.pilot_queries = int(d.get("pilot_queries", 0))
	f.request_count = int(d.get("request_count", 1))
	f.last_request_at = float(d.get("last_request_at", 0.0))
	f.pilot_waiting = bool(d.get("pilot_waiting", false))
	f.atis_suspect = bool(d.get("atis_suspect", false))
	f.emergency = str(d.get("emergency", ""))
	return f


## 放行环节的完整状态（《放行管制机制规范》§0.2 的七态）：
## 等待申请 → 已申请 → 计划已审查 → 许可已发布 → 复诵待确认 → 复诵已确认 → 已移交地面
## 内部仍用 4 个枚举 + checked/handed_off 两个标记表示，这里换算成规范口径的序号，
## 免得为了"看起来有七态"去改一遍所有调用点（改枚举会波及存档与全部测试）。
static func flow_of(state_v: int, checked_v: bool, handed_off_v: bool) -> int:
	if state_v == State.SENT:
		return 4
	if state_v == State.READBACK:
		return 5
	if state_v == State.CLEARED:
		return 7 if handed_off_v else 6
	return 3 if checked_v else 2


func flow_state() -> int:
	return flow_of(state, checked, handed_off)


func state_text() -> String:
	match flow_state():
		2: return "已申请"
		3: return "计划已审查"
		4: return "许可已发布"
		5: return "复诵待确认"
		6: return "复诵已确认"
		7: return "已移交地面"
		_: return "等待申请"


## 放行环节是否已经处理完（列表可以把它归到"已完成"）。
func is_done() -> bool:
	return state == State.CLEARED
