## 游戏内界面（会话 HUD）。
##
## 目前还没有席位面板，这里先把"一局游戏"的骨架立起来：
## 顶部状态条、时钟、暂停、以及保存 / 载入 / 返回主菜单三个出口。
## 席位面板做好后直接替换中间的占位区，不需要动这里的状态逻辑。
class_name SessionScreen
extends CanvasLayer

signal save_requested
signal load_requested(slot_id: String)
signal exit_requested
signal pause_toggled(paused: bool)
## 退出确认的结果：save_first=true 表示"保存并退出"。
signal exit_decision(save_first: bool)
## 载入确认的结果：save_first=true 表示"先保存当前进度再载入"。
signal load_decision(save_first: bool)

var session: GameSession

var _root: Control
var _store_ref: SaveStore
var _confirm: ConfirmDialog
var _body_host: Control
var _placeholder_box: Control
var _seat_panel: Control
## 顶栏正中央：放信息标签栏（机场/天气/停机位/…）
var _top_tabs_host: Control
var _mode_badge: Label
var _seat_label: Label
var _clock: Label
var _options_btn: Button
var _view_menu: ViewMenu
var _window_menu: WindowMenu

var _flight_box: VBoxContainer
var _save_screen: SaveScreen
var _load_screen: LoadScreen
var _toast_box: PanelContainer
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_backdrop()
	_build_top_bar()
	_build_body()
	_build_options_menu()
	_build_toast()

	# 语音辅助（08 §4.4 / §4.5）：五项辅助 + 无障碍兜底
	_aux_win = VoiceAuxWindow.new()
	_aux_win.name = "VoiceAuxWindow"
	_root.add_child(_aux_win)
	_aux_win.closed.connect(func() -> void: _refresh_seat_panel())
	_aux_win.changed.connect(func() -> void:
		_save_game_settings()
		_refresh_seat_panel())

	_save_screen = SaveScreen.new()
	_save_screen.name = "SaveScreen"
	_root.add_child(_save_screen)
	_save_screen.close_requested.connect(func() -> void: _save_screen.close())
	_save_screen.save_requested.connect(_on_save_pressed)

	_load_screen = LoadScreen.new()
	_load_screen.name = "LoadScreen"
	_root.add_child(_load_screen)
	_load_screen.close_requested.connect(func() -> void: _load_screen.close())
	_load_screen.load_requested.connect(func(id: String) -> void:
		_load_screen.close()
		load_requested.emit(id))

	_confirm = ConfirmDialog.new()
	_confirm.name = "ConfirmDialog"
	_root.add_child(_confirm)
	_confirm.choice.connect(_on_confirm_choice)

	_root.visible = false


# ---------------------------------------------------------------- 背景

## 进了游戏就不该再看见塔台窗景：整块不透明底铺满，只留席位自己的界面。
func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color("070c10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)


# ---------------------------------------------------------------- 顶部状态条

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 0)
	bar.offset_bottom = 74.0 * AtcTheme.UI_SCALE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.031, 0.047, 0.055, 0.94)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.border_width_bottom = 1
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	bar.add_theme_stylebox_override("panel", sb)
	_root.add_child(bar)

	var stage := Control.new()
	bar.add_child(stage)

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 18)
	stage.add_child(hb)

	# 信息标签栏的挂载点：直接放进顶栏 HBox 里当"中间那一格"，
	# 由 CenterContainer 在**剩余空间**里居中 —— 既不用手算宽度（手算踩过坑：
	# 首次布局时最小宽度还是 0），也不会和左右两组重叠（叠加定位就会压到时钟上）。
	_top_tabs_host = CenterContainer.new()
	_top_tabs_host.name = "TopTabsCenter"
	_top_tabs_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_tabs_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_mode_badge = Label.new()
	_mode_badge.add_theme_font_override("font", AtcTheme.font(700))
	_mode_badge.add_theme_font_size_override("font_size", AtcTheme.fs(17))
	_mode_badge.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
	_mode_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_mode_badge)

	_seat_label = Label.new()
	_seat_label.add_theme_font_override("font", AtcTheme.font(500))
	_seat_label.add_theme_font_size_override("font_size", AtcTheme.fs(17))
	_seat_label.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	_seat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_seat_label)

	# 标签栏吃掉左组与右组之间的全部空隙，自己内部居中
	hb.add_child(_top_tabs_host)

	_clock = Label.new()
	_clock.add_theme_font_override("font", AtcTheme.font(700))
	_clock.add_theme_font_size_override("font_size", AtcTheme.fs(26))
	_clock.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_clock)

	# 视图按钮：开关界面面板（进程单/场面监视/许可证编辑器/通话记录…）+ 布局预设
	_view_menu = ViewMenu.new()
	_view_menu.state_changed.connect(_apply_view)
	_view_menu.layout_reset.connect(_on_layout_reset)
	hb.add_child(_view_menu)

	# 窗口按钮：显示模式 / 尺寸 / 置顶 / 最小化（设置会被记住）
	_window_menu = WindowMenu.new()
	hb.add_child(_window_menu)

	_options_btn = _bar_button("选项", Callable(), 120.0)
	_options_btn.pressed.connect(_on_options_pressed)
	hb.add_child(_options_btn)


# ---------------------------------------------------------------- 中间区域

func _build_body() -> void:
	var card := PanelContainer.new()
	card.name = "Body"
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 14
	card.offset_right = -14
	card.offset_top = 86.0 * AtcTheme.UI_SCALE
	card.offset_bottom = -14.0 * AtcTheme.UI_SCALE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.024, 0.035, 0.043, 0.96)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	_root.add_child(card)

	# 席位面板的宿主：中间区域由具体席位决定放什么界面
	_body_host = Control.new()
	_body_host.name = "BodyHost"
	_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(_body_host)

	var col := VBoxContainer.new()
	col.name = "Placeholder"
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	_body_host.add_child(col)
	_placeholder_box = col

	var title := Label.new()
	title.text = "席位面板"
	title.add_theme_font_override("font", AtcTheme.font(700))
	title.add_theme_font_size_override("font_size", AtcTheme.fs(24))
	title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(title)

	var hint := Label.new()
	hint.text = "这是席位操作台的位置。下一步会在这里接上进程单、陆空通话记录与指令输入。"
	hint.add_theme_font_override("font", AtcTheme.font(400))
	hint.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	hint.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.07)
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)

	var list_title := Label.new()
	list_title.text = "当前航班"
	list_title.add_theme_font_override("font", AtcTheme.font(500))
	list_title.add_theme_font_size_override("font_size", AtcTheme.fs(16))
	list_title.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	col.add_child(list_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_flight_box = VBoxContainer.new()
	_flight_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flight_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_flight_box)


# ---------------------------------------------------------------- 选项菜单

## 原来的"保存游戏 / 载入存档 / 暂停 / 返回主菜单"分散在顶部和底部两条栏上，
## 占掉了整整一行高度。现在合并成顶栏右上角的一个「选项」按钮，
## 底部那一行空间全部让给信息显示面板。
##
## 用自绘面板而不是 PopupMenu：PopupMenu 在这个暗色主题下会把条目样式
## 全渲染成悬停态（实测过），自绘才能跟界面其它部分保持一致。
## 设置窗口取代了原来那条下拉菜单（十来行堆在一起，项目一多就没人找得到）。
## 布局按常规软件来：左边分类（常规/对话/语音/关于），右边设置项，底下恢复默认与关闭。
const DIFF_NAMES := ["简易", "进阶", "高阶"]
const DIFF_KEYS := ["easy", "normal", "hard"]
const MODE_NAMES := ["预设一键", "填空式", "自由文本", "真实语音"]
const MODE_KEYS := ["preset", "form", "text", "voice"]

var _options_layer: Control
var _settings_win: SettingsWindow
var _aux_win: VoiceAuxWindow


func _build_options_menu() -> void:
	_options_layer = Control.new()
	_options_layer.name = "OptionsLayer"
	_options_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_layer.visible = false
	# 整层放在最上面，否则会被信息面板盖住
	_root.add_child(_options_layer)

	_settings_win = SettingsWindow.new()
	_settings_win.name = "SettingsWindow"
	_settings_win.version_text = AtcVersion.display()
	_settings_win.closed.connect(func() -> void: _options_layer.visible = false)
	_settings_win.action.connect(_on_settings_action)
	_options_layer.add_child(_settings_win)


func _on_options_pressed() -> void:
	if _options_layer == null:
		return
	if _options_layer.visible:
		_options_layer.visible = false
		return
	_open_settings()


func _open_settings() -> void:
	if _settings_win == null:
		return
	_settings_win.desk = session.delivery if session != null else null
	_settings_win.paused = session != null and session.state.paused
	_settings_win.open()
	_options_layer.visible = true


## 设置窗口发来的一次性动作。设置项的读写留在这里，
## 是因为它们要用到 session 与存档系统，塞进窗口会把界面和数据层搅在一起。
func _on_settings_action(id: String) -> void:
	var d := session.delivery if session != null else null
	if id.begins_with("pick:mode:"):
		var i := MODE_KEYS.find(id.substr(10))
		if i >= 0:
			_set_issue_mode(i)
		_open_settings()
		return
	if id.begins_with("pick:diff:"):
		var j := DIFF_KEYS.find(id.substr(10))
		if j >= 0:
			_set_difficulty(j)
		_open_settings()
		return
	if id == "toggle:cand":
		if d != null:
			d.candidate_error = not d.candidate_error
			_save_game_settings()
			_refresh_seat_panel()
		_open_settings()
		return
	if id == "toggle:speak":
		if d != null:
			d.speak_enabled = not d.speak_enabled
			_save_game_settings()
			_refresh_seat_panel()
		_open_settings()
		return
	if id == "aux":
		if d != null and _aux_win != null:
			_options_layer.visible = false
			_aux_win.open(d)
		return
	if id == "demo":
		if _settings_win != null:
			_settings_win.play_demo()
		return
	if id == "reset":
		_reset_settings()
		return
	if id == "save":
		_options_layer.visible = false
		_on_open_save()
	elif id == "load":
		_options_layer.visible = false
		_on_open_load()
	elif id == "pause":
		_on_pause_pressed()
		_open_settings()
	elif id == "exit":
		_options_layer.visible = false
		exit_requested.emit()


func _reset_settings() -> void:
	if session == null or session.delivery == null:
		return
	var d := session.delivery
	d.difficulty = "normal"
	d.readback_hard = false
	d.handoff_hard = false
	d.issue_mode = "form"
	_next_issue_mode = "form"
	d.candidate_error = false
	d.speak_enabled = false
	d.allow_text_fallback = false
	d.voice_aux = {}
	_save_game_settings()
	_refresh_seat_panel()
	_open_settings()



## 难度/模式/候选开关变了，席位面板要重画（候选列表、哪个控件可见都跟着变）
func _refresh_seat_panel() -> void:
	if _seat_panel != null and _seat_panel.has_method("refresh"):
		_seat_panel.call("refresh")


## 难度切换（规范 §0.3）：同时决定复诵/移交要不要逐项自己判
func _set_difficulty(i: int) -> void:
	if session == null or session.delivery == null:
		return
	if i < 0 or i >= DIFF_KEYS.size():
		return
	var d := session.delivery
	d.difficulty = DIFF_KEYS[i]
	d.readback_hard = DIFF_KEYS[i] == "hard"
	d.handoff_hard = DIFF_KEYS[i] == "hard"
	_save_game_settings()


## 08 §6.2：对话模式「游戏进行中不可切换，设置中修改仅对下一局生效」。
## 所以这里**只记下偏好**，不动正在跑的放行席；下一局 _load_game_settings 才套上。
func _set_issue_mode(i: int) -> void:
	if session == null or session.delivery == null:
		return
	if i < 0 or i >= MODE_KEYS.size():
		return
	var want := String(MODE_KEYS[i])
	_next_issue_mode = want
	_save_game_settings()
	if want != session.delivery.issue_mode:
		show_toast("陆空对话模式改为「%s」，下一局生效" % MODE_NAMES[i])


## 下一局要用的对话模式（本局不变）
var _next_issue_mode := ""


## 难度/发布模式写进同一个设置文件，下一局沿用
func _save_game_settings() -> void:
	if session == null or session.delivery == null:
		return
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("game", "difficulty", session.delivery.difficulty)
	# 存的是"下一局用的模式"（§6.2：本局不可切换）
	var save_mode := session.delivery.issue_mode
	if _next_issue_mode != "":
		save_mode = _next_issue_mode
	cfg.set_value("game", "issue_mode", save_mode)
	cfg.set_value("game", "candidate_error", session.delivery.candidate_error)
	cfg.set_value("game", "speak_enabled", session.delivery.speak_enabled)
	cfg.set_value("game", "allow_text_fallback", session.delivery.allow_text_fallback)
	cfg.set_value("game", "voice_aux", session.delivery.voice_aux)
	cfg.save("user://settings.cfg")


## 开局时把上次的设置套上
func _load_game_settings() -> void:
	if session == null or session.delivery == null:
		return
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	var d := session.delivery
	d.difficulty = str(cfg.get_value("game", "difficulty", d.difficulty))
	d.issue_mode = str(cfg.get_value("game", "issue_mode", d.issue_mode))
	_next_issue_mode = d.issue_mode
	d.candidate_error = bool(cfg.get_value("game", "candidate_error", d.candidate_error))
	# 片段库生成过的话，语音播报默认打开 —— 否则玩家永远听不到机组开口
	var lib := VoiceLibrary.new()
	var have_voice := bool(lib.ready_for("controller") and lib.ready_for("pilot"))
	d.speak_enabled = bool(cfg.get_value("game", "speak_enabled", have_voice))
	d.allow_text_fallback = bool(cfg.get_value("game", "allow_text_fallback",
		d.allow_text_fallback))
	var aux: Variant = cfg.get_value("game", "voice_aux", d.voice_aux)
	if aux is Dictionary:
		d.voice_aux = aux as Dictionary
	d.readback_hard = d.difficulty == "hard"
	d.handoff_hard = d.difficulty == "hard"


func _bar_button(text: String, on_pressed: Callable = Callable(),
		width: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width * AtcTheme.UI_SCALE, 44.0 * AtcTheme.UI_SCALE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(17))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_focus_color", AtcTheme.C_TEXT)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.border_color = Color(1, 1, 1, 0.12)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 16
	n.content_margin_right = 16
	n.content_margin_top = 9
	n.content_margin_bottom = 9
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.11)
	h.border_color = AtcTheme.C_ACCENT_DIM
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


func _build_toast() -> void:
	_toast_box = PanelContainer.new()
	# 放在顶栏中间的空位：进游戏后底部被通话条占着，提示压在通话上会看不清
	_toast_box.anchor_left = 0.26
	_toast_box.anchor_right = 0.74
	_toast_box.anchor_top = 0.012
	_toast_box.anchor_bottom = 0.056
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.031, 0.047, 0.055, 0.96)
	sb.border_color = AtcTheme.C_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_toast_box.add_theme_stylebox_override("panel", sb)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_override("font", AtcTheme.font(500))
	_toast.add_theme_font_size_override("font_size", AtcTheme.fs(17))
	_toast.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
	_toast_box.add_child(_toast)
	_root.add_child(_toast_box)


# ---------------------------------------------------------------- 对外

func open(p_session: GameSession, store: SaveStore) -> void:
	session = p_session
	_store_ref = store
	_root.visible = true
	_setup_seat_panel()
	_load_game_settings()
	# 难度/发布模式是开局后才套上的，套完要让席位面板重画一次，
	# 否则"预设一键"这类跟模式相关的控件不会出现
	if _seat_panel != null and _seat_panel.has_method("refresh"):
		_seat_panel.call("refresh")
	refresh()
	refresh_labels()


## 按当前席位挂上对应的操作面板；还没有面板的席位先用占位区。
func _setup_seat_panel() -> void:
	if _seat_panel != null:
		_seat_panel.queue_free()
		_seat_panel = null
	if _placeholder_box != null:
		_placeholder_box.visible = false

	if session == null:
		return

	# 换席位先清空顶栏标签，避免残留上一个席位的信息栏
	if _top_tabs_host != null:
		for c in _top_tabs_host.get_children():
			_top_tabs_host.remove_child(c)
			c.queue_free()

	if session.seat_id == "delivery" and session.delivery != null:
		var panel := DeliveryPanel.new()
		panel.name = "DeliveryPanel"
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_body_host.add_child(panel)
		panel.set_airport(session.airport)
		panel.open(session.delivery)
		_seat_panel = panel
		_placeholder_box.visible = false
		if _top_tabs_host != null and panel.has_method("mount_top_tabs"):
			panel.mount_top_tabs(_top_tabs_host)
	else:
		_placeholder_box.visible = true

	# 面板显隐跟着设置走：换席位、重开一局都沿用玩家上次的布局
	_apply_view(ViewState.load_settings())


## 把视图状态套到界面上。逻辑在 core/view_state.gd，这里只负责改 visible。
func _apply_view(d: Dictionary) -> void:
	if _seat_panel != null and _seat_panel.has_method("set_panel_visible"):
		for id in ["strip", "center", "editor", "radio"]:
			_seat_panel.call("set_panel_visible", String(id), bool(d.get(id, true)))
	var seat_on := bool(d.get("seat", true))
	if _mode_badge != null:
		_mode_badge.visible = seat_on
	if _seat_label != null:
		_seat_label.visible = seat_on
	if _clock != null:
		_clock.visible = bool(d.get("clock", true))
	# 标签栏只隐藏里面的标签条，挂载点本身留在顶栏里占位 ——
	# 否则整条顶栏会突然往左塌，时钟和按钮全跳位置。
	if _top_tabs_host != null:
		for c in _top_tabs_host.get_children():
			if c is Control:
				(c as Control).visible = bool(d.get("tabs", true))


## 换布局时把分栏宽度也恢复默认，否则"标准席位"会带着上一次拖窄的列宽
func _on_layout_reset() -> void:
	if _seat_panel != null and _seat_panel.has_method("reset_splits"):
		_seat_panel.call("reset_splits")


## 让顶栏中央的标签栏在整条顶栏里真正居中（而不是在左右两组的空隙里居中）。





func close() -> void:
	_save_screen.close()
	_load_screen.close()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func refresh() -> void:
	if session == null:
		return
	for c in _flight_box.get_children():
		c.queue_free()
	for f in session.state.flights:
		_flight_box.add_child(_flight_row(f))
	refresh_labels()


func refresh_labels() -> void:
	if session == null:
		return
	_mode_badge.text = session.mode_label()
	_mode_badge.add_theme_color_override("font_color",
		AtcTheme.C_WARM if session.mode == GameSession.MODE_TRAINING else AtcTheme.C_ACCENT)
	var head := "%s · %s" % [session.seat_label(), session.airport_id]
	var freq := AirportData.frequency(session.airport, session.seat_id)
	if freq != "":
		head += "   ·   " + freq
	_seat_label.text = head
	pass


func _flight_row(f: Dictionary) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	row.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	row.add_child(hb)

	_add_cell(hb, String(f.get("callsign", "----")), 200, AtcTheme.C_TEXT, 17, 500)
	_add_cell(hb, String(f.get("type", "")), 110, AtcTheme.C_TEXT_DIM, 15, 400)
	_add_cell(hb, _phase_text(String(f.get("phase", ""))), 160, AtcTheme.C_ACCENT_DIM, 15, 500)
	var extra := ""
	if f.has("alt"):
		extra = "%d ft" % int(f.get("alt", 0))
	elif f.has("stand"):
		extra = "机位 %s" % String(f.get("stand", ""))
	_add_cell(hb, extra, 160, AtcTheme.C_TEXT_DIM, 15, 400)
	return row


func _add_cell(parent: HBoxContainer, text: String, width: int, color: Color, size: int, weight: int) -> void:
	var lb := Label.new()
	lb.text = text
	lb.custom_minimum_size = Vector2(width, 0)
	lb.add_theme_font_override("font", AtcTheme.font(weight))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	lb.add_theme_color_override("font_color", color)
	parent.add_child(lb)


func _phase_text(phase: String) -> String:
	match phase:
		"delivery": return "放行中"
		"ground": return "地面滑行"
		"approach": return "进近中"
		"final": return "五边"
		"departure": return "离场"
		_: return phase


func show_toast(text: String, is_error: bool = false) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color",
		AtcTheme.C_DANGER if is_error else AtcTheme.C_ACCENT)
	_toast_box.modulate = Color(1, 1, 1, 1)
	_toast_box.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.55)
	_toast_tween.tween_callback(func() -> void: _toast_box.visible = false)


# ---------------------------------------------------------------- 帧更新

func _process(delta: float) -> void:
	if session == null or not _root.visible:
		return
	# 暂停、或任何对话框/选项面板打开时都不要推进时间，
	# 否则玩家在菜单里"瞎过时间"（暂停按钮原来只改标记不停表，这里一并修掉）
	if session.state.paused \
			or _save_screen.visible or _load_screen.visible or _confirm.visible \
			or (_options_layer != null and _options_layer.visible):
		return
	session.tick(delta)
	_clock.text = session.state.sim_time_text()

	# 席位面板自己推进（放行席要等机组复诵、自动来新航班）
	if _seat_panel != null and _seat_panel.has_method("tick"):
		_seat_panel.set("now", session.state.sim_time)
		_seat_panel.call("tick", session.state.sim_time)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			_confirm.close()
		elif _save_screen.visible:
			_save_screen.close()
		elif _load_screen.visible:
			_load_screen.close()
		else:
			exit_requested.emit()
		get_viewport().set_input_as_handled()


## 同一个确认框要服务两种场景（退出 / 载入），用这个记住当前是哪种。
var _confirm_kind := "exit"


## 弹出退出确认框。
func ask_exit_confirmation() -> void:
	_confirm_kind = "exit"
	var body := ""
	if session != null and session.save_slot == "":
		body = "本局还没有手动保存过。\n返回主菜单前要保存吗？"
	else:
		body = "上次保存之后又有新的进度。\n返回主菜单前要保存吗？"
	_confirm.open("退出当前会话", body, ["保存并退出", "不保存，直接退出", "取消"])


## 弹出载入确认框：载入会顶掉当前这局，有未保存进度时先问一句。
func ask_load_confirmation(target_label: String) -> void:
	_confirm_kind = "load"
	var body := "载入「%s」会结束当前这一局。\n当前进度还没有保存，要先把当前进度存起来吗？" % target_label
	_confirm.open("载入别的存档", body, ["保存当前进度并载入", "不保存，直接载入", "取消"])


func _on_confirm_choice(index: int) -> void:
	var save_first: bool = index == 0
	var is_cancel: bool = index >= 2
	if is_cancel:
		return
	if _confirm_kind == "exit":
		exit_decision.emit(save_first)
	else:
		load_decision.emit(save_first)


# ---------------------------------------------------------------- 内部动作

func _on_pause_pressed() -> void:
	if session == null:
		return
	session.state.paused = not session.state.paused
	refresh_labels()
	pause_toggled.emit(session.state.paused)


func _on_open_save() -> void:
	if session == null or _store_ref == null:
		return
	var default_name := session.label
	if default_name == "":
		default_name = "%s %s" % [session.mode_label(), session.seat_label()]
	_save_screen.open(_store_ref, session.save_slot, default_name)


## 供自动化验证直接打开保存对话框。
func open_save_dialog() -> void:
	_on_open_save()


func _on_open_load() -> void:
	if _store_ref == null:
		return
	_load_screen.open(_store_ref)


func _on_save_pressed(slot_id: String, label: String) -> void:
	if session == null or _store_ref == null:
		return
	session.label = label
	session.save_slot = slot_id
	var w := _store_ref.write(session.to_save(slot_id))
	if w.ok:
		session.mark_saved()
		AtcLog.info("手动保存 -> %s（%s）" % [slot_id, label])
		_save_screen.close()
		show_toast("已保存到 %s" % slot_id)
	else:
		show_toast("保存失败：%s" % w.error, true)
