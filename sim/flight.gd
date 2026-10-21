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
	return f


func state_text() -> String:
	match state:
		State.PENDING: return "等待放行"
		State.SENT: return "许可已发"
		State.READBACK: return "等待复核"
		State.CLEARED: return "已放行"
		_: return "未知"


## 放行环节是否已经处理完（列表可以把它归到"已完成"）。
func is_done() -> bool:
	return state == State.CLEARED
