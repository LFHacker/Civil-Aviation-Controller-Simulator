## 一局游戏（会话）。
##
## 会话是"活的"，存档是它的快照：会话推进时改 SimState，
## 保存时把 SimState 序列化进 SaveGame，载入时再从 SaveGame 重建会话。
## 逻辑层对象，零渲染依赖。
class_name GameSession
extends RefCounted

const MODE_MAIN := "main"
const MODE_TRAINING := "training"

var mode := MODE_MAIN
var label := ""
var seat_id := "delivery"
var airport_id := "DEMO"
## 当前绑定的存档槽位；空串表示还没存过。
var save_slot := ""
## 本会话使用的自动存档槽位（开局时分配，整局不变）。
var auto_slot := ""
var created_unix := 0

## 自上次成功存档以来是否有新进度。
## 退出时靠它决定要不要弹确认框——不能默默把玩家的进度丢掉。
var dirty := false
## 上次存档时的仿真时刻，用来吞掉"刚存完又走了 0.3 秒"这种噪音。
var _saved_sim := 0.0

var state: SimState
## 本局使用的机场数据（从 data/airports/*.json 载入）。不参与存档序列化，
## 每次开局/载入都会重新读取，避免把静态数据塞进存档里。
var airport: Dictionary = {}
## 放行席逻辑。席位模块只管自己的状态，序列化进 state.extra["delivery"]。
var delivery: DeliveryDesk


func _init() -> void:
	state = SimState.new()


## 开一局新游戏。
static func create(p_mode: String, p_seat: String, p_label: String) -> GameSession:
	var s := GameSession.new()
	s.mode = p_mode
	s.seat_id = p_seat
	s.airport_id = "DEMO"
	s.label = p_label
	s.created_unix = int(Time.get_unix_time_from_system())

	s.state.seat_id = p_seat
	s.state.airport_id = "DEMO"
	s.state.sim_time = 0.0
	s.state.play_time = 0.0
	s.state.paused = false
	# 起步数据：给几架占位航班，免得界面空得像坏掉了。
	s.state.flights = [
		{"callsign": "CCA1501", "type": "B738", "phase": "delivery", "stand": "A12"},
		{"callsign": "CES2302", "type": "A320", "phase": "ground", "stand": "A07"},
		{"callsign": "CSN7788", "type": "A321", "phase": "approach", "alt": 3200.0},
	]
	s.state.extra = {"runway": "18", "weather": "CAVOK"}
	s.ensure_seats()
	return s


## 从存档恢复一局。
static func from_save(save: SaveGame) -> GameSession:
	var s := GameSession.new()
	s.mode = save.mode
	s.label = save.label
	s.seat_id = save.state.seat_id
	s.airport_id = save.state.airport_id
	s.save_slot = save.slot_id
	s.created_unix = save.created_unix
	s.state = save.state
	s.ensure_seats()
	return s


# ---------------------------------------------------------------- 席位状态

## 建好（或从存档恢复）各席位模块。目前只有放行席。
func ensure_seats() -> void:
	if delivery == null:
		var raw: Variant = state.extra.get("delivery", null)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			delivery = DeliveryDesk.from_dict(raw)
			delivery.setup(0)
		else:
			delivery = DeliveryDesk.new()
			delivery.setup(0)
			delivery.seed_initial(state.sim_time, 2)


## 把各席位状态写回 state.extra，保存前调用。
func sync_seats() -> void:
	if delivery != null:
		state.extra["delivery"] = delivery.to_dict()


## 绑定机场数据。
##
## 无论新局还是读档都要绑定：放行许可/离场情报要用的跑道、风、修正海压、
## 通播字母、进近频率全在这里。
## 只有新开局才用当日计划重建放行列表——存档里已经带着 plan 与进度。
func apply_airport(data: Dictionary, seed_plan: bool = true) -> void:
	airport = data
	if delivery == null:
		return
	delivery.apply_field(data)
	# 本席位的三道关：机组报没报通播、计划有没有核对、审查走不走完整流程。
	# 放在 seed_plan 判断之前——读档进来时同样要生效。
	delivery.enable_atis_check = true
	delivery.enable_strip_check = true
	delivery.enable_plan_review = true
	delivery.cdm_enabled = true
	delivery.enable_qnh_gate = true
	delivery.enable_value_check = true
	delivery.enable_atis_lifecycle = true
	if delivery.difficulty == "":
		delivery.difficulty = "normal"
	if not seed_plan:
		return
	var raw: Variant = data.get("schedule", [])
	if not (raw is Array):
		return
	var arr: Array = raw
	if arr.is_empty():
		return
	delivery.set_plan(arr)
	# 全新一局：把开局随机塞的占位航班换成计划里的前几架
	delivery.flights = []
	delivery.transcript = []
	delivery.cleared_count = 0
	delivery.reissue_total = 0
	delivery.misjudge_count = 0
	delivery.seed_initial(state.sim_time, mini(2, arr.size()))
## 推进时钟。暂停时不走。
func tick(delta: float) -> void:
	if state.paused:
		return
	state.sim_time += delta
	state.play_time += delta
	dirty = true


## 存档成功后调用：此刻起"没有未保存的进度"。
func mark_saved() -> void:
	dirty = false
	_saved_sim = state.sim_time


## 是否值得为"未保存进度"弹一次确认。
## 只过了零点几秒不算——否则玩家刚存档就退出也会被拦一次，很烦。
func has_unsaved_progress() -> bool:
	if not dirty:
		return false
	return absf(state.sim_time - _saved_sim) > 1.0


## 打包成可写入的存档对象。
func to_save(slot_id: String) -> SaveGame:
	sync_seats()
	var g := SaveGame.new()
	g.slot_id = slot_id
	g.label = label
	g.mode = mode
	g.created_unix = created_unix if created_unix > 0 else int(Time.get_unix_time_from_system())
	g.updated_unix = int(Time.get_unix_time_from_system())
	g.app_version = AtcVersion.text()
	g.state = state
	return g


func mode_label() -> String:
	return "训练" if mode == MODE_TRAINING else "主线"


func seat_label() -> String:
	return SaveFormat.seat_label(seat_id)


## 会话摘要，给界面顶部用。
func summary() -> String:
	return "%s · %s · %s · 仿真 %s" % [
		mode_label(), seat_label(), airport_id, state.sim_time_text()]
