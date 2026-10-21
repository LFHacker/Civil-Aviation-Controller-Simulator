## 片段播放（08 §4「说」）。
##
## 一片一段地播（片段之间有自然停顿），播完自动续下一片。
## 同一时刻只有一个发射机：管制与机组的通话会互相盖掉，真实无线电就是这样，
## 所以新的一通话会打断/排队，而不是两条叠在一起。
##
## 表现层组件；决定"播什么"的是 sim/voice.gd（逻辑层），这里只负责播。
class_name VoicePlayer
extends Node

signal finished
signal started(count: int)

## 两片之间的停顿（真塔台里字与字之间几乎无缝，但拼接音频需要一点余量）
const GAP := 0.045

var enabled := false
var library := VoiceLibrary.new()

var _player: AudioStreamPlayer
var _queue: Array = []
var _role := "controller"
var _wait := 0.0
var _playing := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "ClipPlayer"
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_clip_finished)
	set_process(false)


func is_playing() -> bool:
	return _playing


## 是否具备播放条件（片段库存在 + 开着开关）
func available(role: String = "controller") -> bool:
	return enabled and library.ready_for(role)


## 播一串片段 id。会顶掉正在播的内容（无线电半双工）。
func play(ids: Array, role: String = "controller") -> bool:
	if not enabled:
		return false
	var plan := library.plan(ids, role)
	if plan.is_empty():
		return false
	_queue = plan
	_role = role
	_playing = true
	_wait = 0.0
	started.emit(plan.size())
	set_process(true)
	_next()
	return true


func stop() -> void:
	_queue.clear()
	_playing = false
	if _player != null:
		_player.stop()
	set_process(false)


func _next() -> void:
	if _queue.is_empty():
		_playing = false
		set_process(false)
		finished.emit()
		return
	var item: Dictionary = _queue.pop_front()
	var stream := VoiceLibrary.load_stream(String(item.get("path", "")))
	if stream == null:
		# 读不出来的片段直接跳过，不能让一句许可卡死在这里
		_next()
		return
	_player.stream = stream
	_player.play()


func _on_clip_finished() -> void:
	_wait = GAP
	set_process(true)


func _process(dt: float) -> void:
	if not _playing:
		set_process(false)
		return
	if _player.playing:
		return
	if _wait > 0.0:
		_wait -= dt
		return
	_next()
