## 仿真状态根对象。
##
## 这是"逻辑层"的一部分：不含任何 Node、Camera、Mesh 引用，
## 可以完整序列化成 JSON，也可以在无头环境里构造与断言。
## 将来各席位模块把自己那部分状态挂到 extra 里，不去改根结构。
class_name SimState
extends RefCounted

## 仿真时间（秒）。暂停时也不增长。
var sim_time := 0.0
## 玩家真实游玩时间（秒），用于存档列表显示。
var play_time := 0.0
## 玩家当前所在席位（见 SaveFormat.SEATS）。
var seat_id := "delivery"
## 机场 id。
var airport_id := "DEMO"
## 是否处于暂停。
var paused := false
## 航班列表。每个元素是一个字典，结构由航班模块自己定义，这里只负责搬运。
var flights: Array = []
## 事件/日志流水，供回放与复盘。
var events: Array = []
## 席位模块的自有状态，键为模块 id。
var extra: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"sim_time": sim_time,
		"play_time": play_time,
		"seat_id": seat_id,
		"airport_id": airport_id,
		"paused": paused,
		"flights": flights.duplicate(true),
		"events": events.duplicate(true),
		"extra": extra.duplicate(true),
	}


## 从字典恢复。任何缺失或类型不对的字段回落到默认值，绝不抛异常——
## 存档是整个游戏里最不能"崩"的东西。
static func from_dict(d: Dictionary) -> SimState:
	var s := SimState.new()
	s.sim_time = float(d.get("sim_time", 0.0))
	s.play_time = float(d.get("play_time", 0.0))
	s.seat_id = str(d.get("seat_id", "delivery"))
	s.airport_id = str(d.get("airport_id", "DEMO"))
	s.paused = bool(d.get("paused", false))

	var f: Variant = d.get("flights", [])
	s.flights = f if f is Array else []

	var e: Variant = d.get("events", [])
	s.events = e if e is Array else []

	var x: Variant = d.get("extra", {})
	s.extra = x if x is Dictionary else {}

	return s


## 供 UI 显示：把仿真秒数格式化成 HH:MM:SS。
func sim_time_text() -> String:
	return format_duration(sim_time)


static func format_duration(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	return "%02d:%02d:%02d" % [h, m, s]
