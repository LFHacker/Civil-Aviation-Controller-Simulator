## 入口：装配塔台窗景 + 主菜单 + 存档系统。
##
## 调试命令行开关（放在 `--` 之后）：
##   --shot=<路径>        运行若干秒后自动截图并退出
##   --shot-time=<秒>     截图时机，默认 1.5
##   --open=<菜单项 id>   启动后直接打开某个菜单项（new/load/train/cfg）
##
## 调试热键（仅 DEBUG 构建）：
##   F9  生成一份演示存档，方便看"继续"列表
##   F10 打印当前存档目录与列表到控制台
extends Node

const SHOT_ARG := "--shot="
const SHOT_TIME_ARG := "--shot-time="
const OPEN_ARG := "--open="
const AUTO_LOAD_ARG := "--auto-load="
## 直接进入某个席位（训练模式），用于无人值守截图与快速回归验证。
const SEAT_ARG := "--seat="

var _shot_path := ""
var _shot_time := 1.5
var _auto_seat := ""
var _debug_atis_missing := false
var _open_item := ""
var _auto_load := ""
var _auto_load_at := 1.0
var _auto_load_done := false
var _elapsed := 0.0
var _shot_done := false

var _store: SaveStore
var _menu: MainMenu
var _session_ui: SessionScreen
var _loading: LoadingScreen
var _tower_view: TowerView
## 进场中（加载页在跑）。防止连点两次"新游戏"起两局。
var _booting := false
## 当前进行中的一局。null 表示在菜单里。
var _session: GameSession
## 载入确认框弹出期间，暂存"等玩家确认后要载入的那份存档"。
var _pending_load_save: SaveGame = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(SHOT_ARG):
			_shot_path = arg.substr(SHOT_ARG.length())
		elif arg.begins_with(SHOT_TIME_ARG):
			_shot_time = maxf(0.0, float(arg.substr(SHOT_TIME_ARG.length())))
		elif arg.begins_with(OPEN_ARG):
			_open_item = arg.substr(OPEN_ARG.length())
		elif arg.begins_with(AUTO_LOAD_ARG):
			_auto_load = arg.substr(AUTO_LOAD_ARG.length())
		elif arg.begins_with(SEAT_ARG):
			_auto_seat = arg.substr(SEAT_ARG.length())
		elif arg == "--atis-missing":
			# 调试：强制第一架航班漏报通播，用来验证"要求收听通播"这条分支
			_debug_atis_missing = true

	AtcLog.info("管制模拟器 v%s 启动" % AtcVersion.text())

	_tower_view = TowerView.new()
	add_child(_tower_view)
	AtcLog.info("塔台窗景构建完成")

	_store = SaveStore.new()
	AtcLog.info("存档目录：%s" % ProjectSettings.globalize_path(_store.base_dir))
	AtcLog.info("已有存档：%d 个" % _store.list().size())

	_menu = MainMenu.new()
	_menu.name = "MainMenu"
	_menu.save_store = _store
	_menu.load_requested.connect(_on_load_requested)
	_menu.start_requested.connect(_on_start_requested)
	add_child(_menu)
	AtcLog.info("主菜单就绪")

	_session_ui = SessionScreen.new()
	_session_ui.name = "SessionScreen"
	_session_ui.save_requested.connect(func() -> void: pass)
	_session_ui.load_requested.connect(_on_load_requested)
	_session_ui.exit_requested.connect(_on_session_exit)
	_session_ui.exit_decision.connect(_do_exit_session)
	_session_ui.load_decision.connect(_on_load_decision)
	add_child(_session_ui)
	AtcLog.info("会话界面就绪")

	_loading = LoadingScreen.new()
	_loading.name = "LoadingScreen"
	add_child(_loading)
	AtcLog.info("加载页就绪")

	if _open_item != "":
		AtcLog.info("调试：直接打开菜单项 %s" % _open_item)
		_menu.call_deferred("open_item", _open_item)

	if _auto_seat != "":
		AtcLog.info("调试：直接进入席位 %s" % _auto_seat)
		_menu.hide()
		call_deferred("_on_start_requested", GameSession.MODE_TRAINING, _auto_seat)

	if _shot_path != "":
		AtcLog.info("截图模式：%.1fs 后保存到 %s" % [_shot_time, _shot_path])


func _process(delta: float) -> void:
	_elapsed += delta

	# 调试：定时自动载入某个槽位，用来在无人值守截图里抓到 toast。
	if _auto_load != "" and not _auto_load_done and _elapsed >= _auto_load_at:
		_auto_load_done = true
		_on_load_requested(_auto_load)
		# --open=save / exit 时顺便打开对应对话框，用于无人值守截图
		if _open_item == "save" and _session_ui != null:
			_session_ui.call_deferred("open_save_dialog")
		elif _open_item == "exit" and _session_ui != null:
			_session_ui.call_deferred("ask_exit_confirmation")

	if _shot_path == "" or _shot_done:
		return
	if _elapsed < _shot_time:
		return
	_shot_done = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	if err == OK:
		AtcLog.info("截图已保存：%s (%dx%d)" % [_shot_path, img.get_width(), img.get_height()])
	else:
		AtcLog.error("截图保存失败，错误码 %d" % err)
	get_tree().quit()


# ---------------------------------------------------------------- 会话流程

## 开局：新游戏或训练选定席位后走到这里。
func _on_start_requested(mode: String, seat_id: String) -> void:
	var mode_text := "训练" if mode == GameSession.MODE_TRAINING else "主线"
	var label := "%s %s" % [mode_text, SaveFormat.seat_label(seat_id)]
	await _boot_session(null, mode, seat_id, label)


## 从菜单或会话内的载入界面载入某个槽位。
func _on_load_requested(slot_id: String) -> void:
	# 先确认存档真的能读，免得问完玩家一堆最后又载不进来
	var r := _store.read(slot_id)
	if not r.ok:
		_active_ui_toast("载入失败：%s" % r.error, true)
		return

	# 会话内载入会顶掉当前这局：有未保存进度就先问一句
	if _session != null and _session.has_unsaved_progress():
		_pending_load_save = r.save
		AtcLog.info("载入前有未保存进度，弹确认框（目标 %s）" % slot_id)
		_session_ui.ask_load_confirmation(r.save.label)
		return

	await _boot_session(r.save, "", "", "")


## 玩家在"载入确认框"里的选择。
func _on_load_decision(save_first: bool) -> void:
	var save: SaveGame = _pending_load_save
	_pending_load_save = null
	if save == null:
		return

	if save_first:
		var sr := _save_session_now()
		if not sr.ok:
			_active_ui_toast("保存失败，已取消载入：%s" % sr.error, true)
			return
		AtcLog.info("载入前保存 -> %s" % sr.slot)

	await _boot_session(save, "", "", "")


## 统一的进场流程：加载页 + 四个真实步骤。
##
## 每步之间的停顿只是为了让进度条可读；真实工作都在对应步骤里完成，
## 任何一步失败都会停在加载页上说清楚，而不是带着半份数据进游戏。
func _boot_session(save: SaveGame, mode: String, seat_id: String, label: String) -> void:
	if _booting:
		AtcLog.warn("已经在进场过程中，忽略这次请求")
		return
	_booting = true

	var is_load := save != null
	var s: GameSession
	if is_load:
		s = GameSession.from_save(save)
		s.auto_slot = _pick_auto_slot()
	else:
		s = GameSession.create(mode, seat_id, label)
		s.auto_slot = _pick_auto_slot()

	_loading.begin(s.mode_label(), s.seat_label(), "机场 %s" % s.airport_id)

	# ① 会话就绪（上面已经建好，这里只是等一帧让加载页先画出来）
	_loading.set_step("校验会话数据", 0.18)
	await _pace(0.30)

	# ② 载入机场数据
	_loading.set_step("载入机场数据", 0.46)
	await _pace(0.30)
	var ar := AirportData.load_airport(s.airport_id)
	if not ar.ok:
		_booting = false
		await _loading_fail("机场数据加载失败：%s" % ar.error)
		return
	if is_load:
		s.apply_airport(ar.data, false)
	else:
		s.apply_airport(ar.data, true)

	if _debug_atis_missing and s.delivery != null and not s.delivery.flights.is_empty():
		(s.delivery.flights[0] as Flight).atis_ok = false
		AtcLog.info("调试：强制 %s 漏报通播" % (s.delivery.flights[0] as Flight).callsign)
	var airport_name := str(ar.data.get("name", s.airport_id))
	var rwy := AirportData.primary_runway(ar.data)
	_loading.set_airport_line("%s · %s · 主跑道 %s" % [s.airport_id, airport_name, rwy])

	# ③ 绑定席位与频率
	_loading.set_step("绑定席位与频率", 0.72)
	await _pace(0.26)
	var freq := AirportData.frequency(ar.data, s.seat_id)
	s.state.extra["freq"] = freq
	s.state.extra["runway"] = rwy
	s.state.extra["aircraft_count"] = s.state.flights.size()

	# ④ 切入会话界面
	_loading.set_step("进入塔台", 0.94)
	await _pace(0.22)
	_session = s
	_enter_session_ui(s)
	_session_ui.refresh()

	_loading.set_step("就绪", 1.0)
	await _pace(0.12)
	await _loading.finish()
	_booting = false

	if is_load:
		AtcLog.info("载入存档 %s（%s，%s，仿真 %s，%s）" % [
			save.slot_id, save.label, s.mode_label(), save.state.sim_time_text(), freq])
		_session_ui.show_toast("已载入：%s" % save.label)
	else:
		AtcLog.info("开始新局：mode=%s seat=%s auto=%s freq=%s" % [
			mode, seat_id, s.auto_slot, freq])
		_autosave("开局")
		_session_ui.show_toast("已开始：%s · %s %s（自动存档 %s）" % [
			s.seat_label(), s.airport_id, freq, s.auto_slot])

	# 此刻的状态与磁盘一致（新局写了 auto，载入本来就一致），
	# 所以清了未保存标记——否则玩家刚落座就退出会被拦一次。
	s.mark_saved()


## 加载页上停住并报告失败，然后退回主菜单。
func _loading_fail(msg: String) -> void:
	AtcLog.error(msg)
	_loading.set_step(msg, 1.0)
	await _pace(1.3)
	await _loading.finish()
	_session = null
	_session_ui.close()
	_menu.set_ui_visible(true)
	_menu.show_toast(msg, true)


## 让加载页的进度可读，不是凑时长：每次只等一帧多一点。
func _pace(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 返回主菜单：有未保存进度就先问一句。
func _on_session_exit() -> void:
	if _session == null:
		_leave_to_menu()
		return
	if _session.has_unsaved_progress():
		AtcLog.info("退出前有未保存进度，弹确认框")
		_session_ui.ask_exit_confirmation()
		return
	_do_exit_session(false)


## 玩家在确认框里的选择。save_first=true 表示"保存并退出"。
func _do_exit_session(save_first: bool) -> void:
	if _session == null:
		_leave_to_menu()
		return

	if save_first:
		var sr := _save_session_now()
		if not sr.ok:
			_active_ui_toast("保存失败，已取消退出：%s" % sr.error, true)
			return
		AtcLog.info("退出前保存 -> %s" % sr.slot)

	_leave_to_menu()


## 把当前会话存到它绑定的槽位；从没存过就落到第一个空手动槽。
## 退出保护和载入保护共用这一段，避免两处保存逻辑走偏。
func _save_session_now() -> Dictionary:
	if _session == null:
		return {"ok": false, "error": "没有进行中的会话", "slot": ""}

	var slot := _session.save_slot
	if slot == "":
		slot = _store.next_free_manual_slot()
		if slot == "":
			return {"ok": false, "error": "手动槽位已满，先删一个存档", "slot": ""}
		_session.label = "%s %s" % [_session.mode_label(), _session.seat_label()]

	_session.save_slot = slot
	var w := _store.write(_session.to_save(slot))
	if not w.ok:
		return {"ok": false, "error": String(w.error), "slot": ""}
	_session.mark_saved()
	return {"ok": true, "error": "", "slot": slot}


func _leave_to_menu() -> void:
	_session = null
	_session_ui.close()
	if _tower_view != null:
		_tower_view.visible = true
	_menu.set_ui_visible(true)
	_menu.refresh_load_screen()
	AtcLog.info("返回主菜单")


func _enter_session_ui(s: GameSession) -> void:
	_menu.set_ui_visible(false)
	# 进了游戏就不需要塔台窗景在背后渲染，省 GPU 也不会透出来
	if _tower_view != null:
		_tower_view.visible = false
	_session_ui.open(s, _store)


## 自动存档：整局固定用一个 auto 槽位，避免刷满。
func _autosave(reason: String) -> void:
	if _session == null or _session.auto_slot == "":
		return
	var w := _store.write(_session.to_save(_session.auto_slot))
	if w.ok:
		AtcLog.info("自动存档（%s）-> %s" % [reason, _session.auto_slot])
	else:
		AtcLog.error("自动存档失败：%s" % w.error)


## 选一个最旧（或空）的自动槽位。
func _pick_auto_slot() -> String:
	var best := SaveFormat.auto_slot(1)
	var best_ts := 0x7FFFFFFF
	for i in range(1, SaveFormat.AUTO_SLOT_COUNT + 1):
		var id := SaveFormat.auto_slot(i)
		var r := _store.read(id)
		if not r.ok:
			return id
		var ts: int = r.save.updated_unix
		if ts < best_ts:
			best_ts = ts
			best = id
	return best


func _active_ui_toast(text: String, is_error: bool = false) -> void:
	if _session_ui != null and _session_ui.is_open():
		_session_ui.show_toast(text, is_error)
	else:
		_menu.show_toast(text, is_error)


# ---------------------------------------------------------------- 调试热键

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not OS.is_debug_build():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_F9:
		_create_demo_save()
		get_viewport().set_input_as_handled()
	elif key == KEY_F10:
		_dump_saves()
		get_viewport().set_input_as_handled()
	elif key == KEY_F8:
		# 让下一次机组复诵必定读错，方便验证"复诵不一致"这条分支
		if _session != null and _session.delivery != null:
			_session.delivery.force_error_next = true
			AtcLog.info("调试：下一次复诵将强制读错")
			_active_ui_toast("调试：下一次复诵会读错")
		get_viewport().set_input_as_handled()


## 造一份有内容的演示存档，写进第一个空的手动槽位。
func _create_demo_save() -> void:
	var slot := _store.next_free_manual_slot()
	if slot == "":
		_menu.show_toast("手动槽位已满，请先删除一个存档", true)
		return

	var g := SaveGame.new()
	g.slot_id = slot
	g.app_version = AtcVersion.text()
	var now := int(Time.get_unix_time_from_system())
	g.created_unix = now
	g.updated_unix = now

	var st := g.state
	st.sim_time = float(3600 * 6 + 1245)
	st.play_time = 780.0
	st.seat_id = "tower"
	st.airport_id = "DEMO"
	st.paused = true
	st.flights = [
		{"callsign": "CCA1501", "type": "B738", "phase": "final", "alt": 900.0, "spd": 145},
		{"callsign": "CES2302", "type": "A320", "phase": "ground", "stand": "A12"},
		{"callsign": "CSN7788", "type": "A321", "phase": "delivery"},
	]
	st.extra = {"runway": "18", "weather": "CAVOK", "tower_atis": "INFO A"}

	# 取一个像样的名字：演示存档 N
	var n := 1
	for e in _store.list():
		if e.ok and e.save.label.begins_with("演示存档"):
			n += 1
	g.label = "演示存档 %d" % n

	var w := _store.write(g)
	if w.ok:
		AtcLog.info("演示存档已写入：%s" % slot)
		_menu.show_toast("已生成演示存档：%s" % g.label)
		_menu.refresh_load_screen()
	else:
		AtcLog.error("演示存档写入失败：%s" % w.error)
		_menu.show_toast("写入失败：%s" % w.error, true)


func _dump_saves() -> void:
	AtcLog.info("存档目录：%s" % ProjectSettings.globalize_path(_store.base_dir))
	var entries := _store.list()
	AtcLog.info("共 %d 个槽位" % entries.size())
	for e in entries:
		if e.ok:
			AtcLog.info("  [OK]   %-10s %-16s seat=%-9s sim=%s" % [
				e.slot_id, e.save.label, e.save.state.seat_id, e.save.state.sim_time_text()])
		else:
			AtcLog.info("  [BAD]  %-10s %s" % [e.slot_id, e.error])
