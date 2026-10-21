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

	# 信息标签栏的挂载点：CenterContainer 自动把子控件放在顶栏正中央，
	# 不用手动算宽度（手动算踩过坑：首次布局最小宽度还是 0）。
	# 直接把标签栏容器交给 CenterContainer：它会按子控件的最小尺寸居中，
	# 所以挂载点本身必须是个 Container（普通 Control 不会向上传递最小尺寸）。
	_top_tabs_host = CenterContainer.new()
	_top_tabs_host.name = "TopTabsCenter"
	_top_tabs_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top_tabs_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_top_tabs_host)

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

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	_clock = Label.new()
	_clock.add_theme_font_override("font", AtcTheme.font(700))
	_clock.add_theme_font_size_override("font_size", AtcTheme.fs(26))
	_clock.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_clock)

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
const OPT_SAVE := 0
const OPT_LOAD := 1
const OPT_PAUSE := 2
const OPT_EXIT := 3

var _options_layer: Control
var _options_panel: PanelContainer
var _opt_pause_btn: Button


func _build_options_menu() -> void:
	_options_layer = Control.new()
	_options_layer.name = "OptionsLayer"
	_options_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_layer.visible = false
	# 整层放在最上面，否则会被信息面板盖住
	_root.add_child(_options_layer)

	# 点空白处关闭
	var catcher := ColorRect.new()
	catcher.color = Color(0, 0, 0, 0.001)
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_options_layer.visible = false)
	_options_layer.add_child(catcher)

	_options_panel = PanelContainer.new()
	_options_panel.name = "OptionsPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.059, 0.070, 0.99)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_options_panel.add_theme_stylebox_override("panel", sb)
	_options_layer.add_child(_options_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_options_panel.add_child(col)

	col.add_child(_option_button("保存游戏", OPT_SAVE))
	col.add_child(_option_button("载入存档", OPT_LOAD))
	col.add_child(_option_divider())
	_opt_pause_btn = _option_button("暂停游戏", OPT_PAUSE)
	col.add_child(_opt_pause_btn)
	col.add_child(_option_divider())
	col.add_child(_option_button("返回主菜单    ESC", OPT_EXIT))


func _option_button(text: String, id: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(196.0 * AtcTheme.UI_SCALE, 36.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_disabled_color", AtcTheme.C_TEXT_FAINT)

	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.set_corner_radius_all(2)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.37, 0.92, 0.83, 0.16)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("disabled", d)

	b.pressed.connect(func() -> void:
		_options_layer.visible = false
		_on_option_selected(id))
	return b


func _option_divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.10)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _on_options_pressed() -> void:
	if _options_layer == null:
		return
	if _options_layer.visible:
		_options_layer.visible = false
		return
	_refresh_option_texts()
	_options_layer.visible = true
	# 贴在「选项」按钮正下方、右对齐
	var r := _options_btn.get_global_rect()
	var sz := _options_panel.get_combined_minimum_size()
	_options_panel.size = sz
	_options_panel.position = Vector2(
		r.end.x - sz.x, r.end.y + 6.0 * AtcTheme.UI_SCALE)


func _refresh_option_texts() -> void:
	var paused := session != null and session.state.paused
	_opt_pause_btn.text = "继续游戏" if paused else "暂停游戏"


func _on_option_selected(id: int) -> void:
	if id == OPT_SAVE:
		_on_open_save()
	elif id == OPT_LOAD:
		_on_open_load()
	elif id == OPT_PAUSE:
		_on_pause_pressed()
	elif id == OPT_EXIT:
		exit_requested.emit()


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
