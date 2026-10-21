## 放行席操作面板。
##
## 布局照着真实管制席的屏幕来：
##   左：进程单（待放行航班）
##   中：机场场面监视图（跑道/滑行道/机坪/停机位上的飞机/数据块）
##   右：许可编辑器 + 机组复诵复核
##   底：陆空通话记录
##
## 业务判断全部交给 DeliveryDesk；这里只负责显示与把玩家动作转成调用。
class_name DeliveryPanel
extends Control

var desk: DeliveryDesk
## 当前仿真时刻，由 SessionScreen 每帧写入
var now := 0.0

var _selected := ""
## 编辑器当前显示的航班，用来判断"要不要重新填表"
var _editor_for := ""

var _display: AirportDisplay
var _tabs: InfoTabs
var _pending_box: VBoxContainer
var _pending_count: Label
var _done_count: Label
var _detail_title: Label
var _detail_sub: Label
var _editor: PanelContainer
var _sid_opt: OptionButton
var _alt_opt: OptionButton
var _squawk_edit: LineEdit
var _qnh_value: Label
var _qnh_btn: Button
var _atis_state_label: Label
var _atis_lamp: Label
var _atis_update_btn: Button
var _atis_fix_row: HBoxContainer
var _atis_notify_btn: Button
var _atis_report_btn: Button
var _limit_label: Label
var _route_label: Label
var _preview: Label
var _atis_card: PanelContainer
var _atis_text: Label
var _atis_btn: Button
var _issue_btn: Button
var _hint: Label
var _readback_card: PanelContainer
var _readback_text: Label
var _readback_diff: Label
var _rb_grid: GridContainer
var _rb_timer: Label
var _handoff_card: PanelContainer
var _handoff_grid: GridContainer
var _tidy_btn: Button
var _cand_box: VBoxContainer
var _text_row: HBoxContainer
var _text_edit: LineEdit
var _text_btn: Button
var _dep_card: PanelContainer
var _dep_grid: GridContainer
var _accept_btn: Button
var _reissue_btn: Button
var _log_box: VBoxContainer
var _log_scroll: ScrollContainer
var _airport: Dictionary = {}
var _airport_box: VBoxContainer
## 审查飞行计划窗口（首次打开时才创建）
var _review_win: PlanReviewWindow


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


# ---------------------------------------------------------------- 布局

func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)

	# 左进程单 ┃ 中间场面图 ┃ 右许可编辑器，两侧可拖拽改变宽度
	_build_strips(main)
	main.add_child(_make_handle("left"))
	_build_display(main)
	main.add_child(_make_handle("right"))
	_build_editor(main)

	# 底部通话记录，上下可拖拽改变高度
	root.add_child(_make_handle("bottom"))
	_build_transcript(root)

	_apply_pane_visibility()



# ---------------------------------------------------------------- 可拖拽分栏

## 当前分栏尺寸（像素）。拖动时改这里，并同步到对应面板的最小尺寸上。
var _left_w := 286.0 * AtcTheme.UI_SCALE
var _right_w := 420.0 * AtcTheme.UI_SCALE
var _bottom_h := 132.0 * AtcTheme.UI_SCALE

var _left_pane: Control
var _center_pane: Control
var _right_pane: Control
var _bottom_pane: Control

## 面板显隐（由「视图」菜单驱动）。分栏尺寸不变，重新打开还是原来的宽度。
var _strip_visible := true
var _center_visible := true
var _editor_visible := true
var _radio_visible := true

## 正在拖的分隔条："" / "left" / "right" / "bottom"
var _drag_target := ""
var _drag_bar: ColorRect
var _drag_bar_normal := Color(1, 1, 1, 0.16)

## 拖动进程单调整放行顺序（规范 §2.3）
var _card_press := ""
var _card_press_pos := Vector2.ZERO
var _dragging_card := ""
## 与 ordered_pending() 同序的卡片节点，落位时用来算目标下标
var _card_nodes: Array = []

const LIM_LEFT := Vector2(190.0, 560.0)
const LIM_RIGHT := Vector2(300.0, 720.0)
const LIM_BOTTOM := Vector2(72.0, 460.0)


func _make_handle(kind: String) -> Control:
	var h := Control.new()
	h.name = "Split_" + kind
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var horizontal := kind == "bottom"
	if horizontal:
		h.custom_minimum_size = Vector2(0, 14)
		h.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	else:
		h.custom_minimum_size = Vector2(14, 0)
		h.mouse_default_cursor_shape = Control.CURSOR_HSIZE

	var bar := ColorRect.new()
	bar.color = _drag_bar_normal
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if horizontal:
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.5
		bar.anchor_bottom = 0.5
		bar.offset_top = -1.0
		bar.offset_bottom = 1.0
	else:
		bar.anchor_top = 0.0
		bar.anchor_bottom = 1.0
		bar.anchor_left = 0.5
		bar.anchor_right = 0.5
		bar.offset_left = -1.0
		bar.offset_right = 1.0
	h.add_child(bar)

	h.gui_input.connect(_on_handle_input.bind(kind, bar))
	h.mouse_entered.connect(func() -> void: bar.color = Color(0.37, 0.92, 0.83, 0.55))
	h.mouse_exited.connect(func() -> void:
		if _drag_target == "":
			bar.color = _drag_bar_normal)
	_handles[kind] = h
	return h


var _handles: Dictionary = {}


## 自己判定双击：按下事件被 accept_event() 消费后，Godot 的 double_click 标志
## 不会置位，直接依赖它会失效（实测双击无反应）。
var _last_press: Dictionary = {}
const DBL_MS := 400
const DBL_DIST := 8.0


func _on_handle_input(ev: InputEvent, kind: String, bar: ColorRect) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	# 右键点分隔条 = 恢复默认宽度（比双击可靠，不依赖系统双击间隔）
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_end_drag()
		_reset_split(kind)
		accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		var now_ms := Time.get_ticks_msec()
		var rec: Dictionary = _last_press.get(kind, {})
		var is_dbl := false
		if not rec.is_empty():
			is_dbl = (now_ms - int(rec.get("t", 0)) <= DBL_MS) \
				and (Vector2(rec.get("p", Vector2.ZERO)).distance_to(mb.position) <= DBL_DIST)
		_last_press[kind] = {"t": now_ms, "p": mb.position}
		if is_dbl:
			_last_press.erase(kind)
			_end_drag()
			_reset_split(kind)
			accept_event()
			return
		_drag_target = kind
		_drag_bar = bar
		bar.color = Color(0.37, 0.92, 0.83, 0.85)
	else:
		_end_drag()
	accept_event()


## 拖动期间的鼠标移动必须由面板整体接收：鼠标一旦离开分隔条本身，
## 分隔条就收不到 motion 事件了，这是拖拽最容易写坏的地方。
func _input(event: InputEvent) -> void:
	# 进程单拖动
	if _card_press != "":
		if event is InputEventMouseMotion:
			var gp := get_global_mouse_position()
			if _dragging_card == "" and gp.distance_to(_card_press_pos) > 14.0:
				_dragging_card = _card_press
				_hint.text = "拖动中…松开鼠标按当前位置落位"
				_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
			if _dragging_card != "":
				accept_event()
		elif event is InputEventMouseButton:
			var mb2 := event as InputEventMouseButton
			if mb2.button_index == MOUSE_BUTTON_LEFT and not mb2.pressed:
				var dragged := _dragging_card
				_card_press = ""
				_dragging_card = ""
				if dragged != "":
					_drop_card(dragged, get_global_mouse_position())
					accept_event()
		return

	if _drag_target == "":
		return
	if event is InputEventMouseMotion:
		_apply_drag(get_global_mouse_position())
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag()
			accept_event()


func _end_drag() -> void:
	_drag_target = ""
	if _drag_bar != null:
		_drag_bar.color = _drag_bar_normal
	_drag_bar = null


## 松开鼠标时按落点决定插到第几位（规范 §2.3）。
## 被拒绝（抢别人时隙）时卡片原地不动，只在提示区说明原因。
func _drop_card(callsign: String, pos: Vector2) -> void:
	var idx := 0
	for e in _card_nodes:
		var c: Variant = (e as Dictionary).get("ctrl")
		if c == null or not is_instance_valid(c):
			continue
		if pos.y > (c as Control).get_global_rect().get_center().y:
			idx += 1
	if desk == null:
		return
	var r := desk.move_flight(callsign, idx)
	refresh()
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
	else:
		_hint.text = "放行顺序已调整"
		_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)


func _apply_drag(pos: Vector2) -> void:
	var gp := get_global_rect().position
	var gs := get_global_rect().size
	if _drag_target == "left":
		_left_w = clampf(pos.x - gp.x, LIM_LEFT.x * AtcTheme.UI_SCALE, LIM_LEFT.y * AtcTheme.UI_SCALE)
		if _left_pane != null:
			_left_pane.custom_minimum_size.x = _left_w
	elif _drag_target == "right":
		_right_w = clampf(gp.x + gs.x - pos.x,
			LIM_RIGHT.x * AtcTheme.UI_SCALE, LIM_RIGHT.y * AtcTheme.UI_SCALE)
		if _right_pane != null:
			_right_pane.custom_minimum_size.x = _right_w
	elif _drag_target == "bottom":
		_bottom_h = clampf(gp.y + gs.y - pos.y,
			LIM_BOTTOM.x * AtcTheme.UI_SCALE, LIM_BOTTOM.y * AtcTheme.UI_SCALE)
		if _bottom_pane != null:
			_bottom_pane.custom_minimum_size.y = _bottom_h


func _reset_split(kind: String) -> void:
	if kind == "left":
		_left_w = 286.0 * AtcTheme.UI_SCALE
		if _left_pane != null:
			_left_pane.custom_minimum_size.x = _left_w
	elif kind == "right":
		_right_w = 420.0 * AtcTheme.UI_SCALE
		if _right_pane != null:
			_right_pane.custom_minimum_size.x = _right_w
	else:
		_bottom_h = 132.0 * AtcTheme.UI_SCALE
		if _bottom_pane != null:
			_bottom_pane.custom_minimum_size.y = _bottom_h


## 三处分隔条一起恢复默认（「视图 → 恢复默认布局」用）
func reset_splits() -> void:
	for k in ["left", "right", "bottom"]:
		_reset_split(String(k))


# ---------------------------------------------------------------- 面板显隐（视图菜单）

## 开关本席位内部的面板：strip 左进程单 / center 中间主视区 /
## editor 右许可编辑器 / radio 底部通话记录。
func set_panel_visible(id: String, on: bool) -> void:
	if id == "strip":
		_strip_visible = on
	elif id == "center":
		_center_visible = on
	elif id == "editor":
		_editor_visible = on
	elif id == "radio":
		_radio_visible = on
	else:
		return
	_apply_pane_visibility()


func _apply_pane_visibility() -> void:
	if _left_pane != null:
		_left_pane.visible = _strip_visible
	if _center_pane != null:
		_center_pane.visible = _center_visible
	if _right_pane != null:
		_right_pane.visible = _editor_visible
	if _bottom_pane != null:
		_bottom_pane.visible = _radio_visible

	# 分隔条只在"它两边都看得见"的时候才有意义
	_show_handle("left", _strip_visible and _center_visible)
	_show_handle("right", _editor_visible and _center_visible)
	_show_handle("bottom", _radio_visible
		and (_center_visible or _strip_visible or _editor_visible))

	# 宽度分配规则要确定：中间开着就中间吃满；中间关了就让右边吃满；
	# 右边也关了就让左边吃满。否则隐藏中间会留下一条空白。
	var center_on := _center_visible
	var right_on := _editor_visible
	if _center_pane != null:
		_center_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _right_pane != null:
		_right_pane.size_flags_horizontal = Control.SIZE_FILL if center_on \
			else Control.SIZE_EXPAND_FILL
	if _left_pane != null:
		_left_pane.size_flags_horizontal = Control.SIZE_FILL if (center_on or right_on) \
			else Control.SIZE_EXPAND_FILL


func _show_handle(kind: String, on: bool) -> void:
	var h: Variant = _handles.get(kind)
	if h != null and is_instance_valid(h):
		(h as Control).visible = on


func _build_strips(parent: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	_left_pane = left
	left.custom_minimum_size = Vector2(_left_w, 0)
	left.add_theme_constant_override("separation", 6)
	parent.add_child(left)

	var head := HBoxContainer.new()
	left.add_child(head)
	head.add_child(_label("待放行", 15, 500, AtcTheme.C_TEXT_SOFT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_pending_count = _label("0", 15, 700, AtcTheme.C_ACCENT)
	head.add_child(_pending_count)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_pending_box = VBoxContainer.new()
	_pending_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_box.add_theme_constant_override("separation", 5)
	scroll.add_child(_pending_box)

	_done_count = _label("已放行 0 架", 12, 400, AtcTheme.C_TEXT_FAINT)
	left.add_child(_done_count)

	# 整理进程单（规范 §4.2）：一键按计划时刻重排，2 秒冷却
	_tidy_btn = _action_button("整理进程单", AtcTheme.C_TEXT_SOFT)
	_tidy_btn.custom_minimum_size = Vector2(0, 28.0 * AtcTheme.UI_SCALE)
	_tidy_btn.pressed.connect(_on_tidy)
	left.add_child(_tidy_btn)


func _build_display(parent: HBoxContainer) -> void:
	# 中间这块是"席位主窗口"：顶部数据标签栏 + 下方当前页
	var center := VBoxContainer.new()
	_center_pane = center
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(center)

	_tabs = InfoTabs.new()
	_tabs.name = "InfoTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_tabs)

	_display = AirportDisplay.new()
	_display.name = "AirportDisplay"
	_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_display.flight_clicked.connect(_on_map_flight_clicked)
	_tabs.attach_display(_display)


func _build_editor(parent: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	_right_pane = right
	right.custom_minimum_size = Vector2(_right_w, 0)
	right.add_theme_constant_override("separation", 8)
	parent.add_child(right)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	right.add_child(title_row)
	_detail_title = _label("未选择航班", 20, 700, AtcTheme.C_TEXT)
	title_row.add_child(_detail_title)
	_detail_sub = _label("", 13, 400, AtcTheme.C_TEXT_DIM)
	_detail_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(_detail_sub)

	_editor = PanelContainer.new()
	var esb := StyleBoxFlat.new()
	esb.bg_color = Color(1, 1, 1, 0.035)
	esb.border_color = Color(1, 1, 1, 0.09)
	esb.set_border_width_all(1)
	esb.set_corner_radius_all(3)
	esb.content_margin_left = 16
	esb.content_margin_right = 16
	esb.content_margin_top = 12
	esb.content_margin_bottom = 12
	_editor.add_theme_stylebox_override("panel", esb)
	right.add_child(_editor)

	var egrid := VBoxContainer.new()
	egrid.add_theme_constant_override("separation", 7)
	_editor.add_child(egrid)

	_sid_opt = OptionButton.new()
	_sid_opt.custom_minimum_size = Vector2(190.0 * AtcTheme.UI_SCALE, 0)
	for s in DeliveryDesk.SIDS:
		_sid_opt.add_item(s)
	_sid_opt.item_selected.connect(func(_i: int) -> void: _update_preview())
	egrid.add_child(_field_row("离场程序", _sid_opt))

	# 许可界限与航路来自飞行计划，管制员照读、不手填
	_limit_label = _readonly_value("—")
	egrid.add_child(_field_row("许可界限", _limit_label))
	_route_label = _readonly_value("—")
	egrid.add_child(_field_row("航路", _route_label))

	_alt_opt = OptionButton.new()
	_alt_opt.custom_minimum_size = Vector2(190.0 * AtcTheme.UI_SCALE, 0)
	for a in DeliveryDesk.ALT_OPTIONS:
		_alt_opt.add_item("%d 米" % a)
	_alt_opt.item_selected.connect(func(_i: int) -> void: _update_preview())
	egrid.add_child(_field_row("初始高度", _alt_opt))

	# 修正海压：机组抄收了 ATIS 也不能省 —— 必须由管制员在许可里确认
	# （《民用航空空中交通管理规则》第二百九十四条）
	_qnh_value = _label("—", 15, 700, AtcTheme.C_TEXT)
	_qnh_btn = _action_button("确认 QNH", AtcTheme.C_WARM)
	_qnh_btn.custom_minimum_size = Vector2(112.0 * AtcTheme.UI_SCALE,
		30.0 * AtcTheme.UI_SCALE)
	_qnh_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_qnh_btn.pressed.connect(_on_confirm_qnh)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 10)
	qh.add_child(_qnh_value)
	qh.add_child(_qnh_btn)
	egrid.add_child(_field_row("修正海压", qh))

	_squawk_edit = LineEdit.new()
	_squawk_edit.max_length = 4
	_squawk_edit.custom_minimum_size = Vector2(190.0 * AtcTheme.UI_SCALE, 0)
	_squawk_edit.add_theme_font_override("font", AtcTheme.font(700))
	_squawk_edit.add_theme_font_size_override("font_size", AtcTheme.fs(16))
	_squawk_edit.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(1, 1, 1, 0.06)
	lsb.border_color = Color(1, 1, 1, 0.16)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(3)
	lsb.content_margin_left = 10
	lsb.content_margin_right = 10
	lsb.content_margin_top = 5
	lsb.content_margin_bottom = 5
	_squawk_edit.add_theme_stylebox_override("normal", lsb)
	var lf := lsb.duplicate() as StyleBoxFlat
	lf.border_color = AtcTheme.C_ACCENT_DIM
	_squawk_edit.add_theme_stylebox_override("focus", lf)
	_squawk_edit.text_changed.connect(_on_squawk_changed)
	egrid.add_child(_field_row("应答机", _squawk_edit))

	# 将要发出的整条通话预览：许可七项 + 离场情报
	_preview = _label("", 12, 400, AtcTheme.C_TEXT_DIM)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(0, 0)
	egrid.add_child(_section_line("将要发出"))
	egrid.add_child(_preview)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	egrid.add_child(action_row)

	_issue_btn = _action_button("发放行许可", AtcTheme.C_ACCENT)
	_issue_btn.pressed.connect(_on_issue)
	action_row.add_child(_issue_btn)

	_hint = _label("", 13, 400, AtcTheme.C_TEXT_DIM)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_hint)

	# 预设一键模式（规范 §5.1 模式 A）：08 的简易对话就是"点一条候选"
	_cand_box = VBoxContainer.new()
	_cand_box.add_theme_constant_override("separation", 4)
	egrid.add_child(_cand_box)

	# 自由文本模式（规范 §5.1 模式 C）：语音识别出文本之后走的也是这条
	_text_row = HBoxContainer.new()
	_text_row.add_theme_constant_override("separation", 8)
	_text_edit = LineEdit.new()
	_text_edit.placeholder_text = "输入完整许可（呼号/界限/程序/高度/编码/修正海压）"
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.add_theme_font_override("font", AtcTheme.font(400))
	_text_edit.add_theme_font_size_override("font_size", AtcTheme.fs(13))
	_text_row.add_child(_text_edit)
	_text_btn = _action_button("按文本发布", AtcTheme.C_ACCENT)
	_text_btn.custom_minimum_size = Vector2(120.0 * AtcTheme.UI_SCALE,
		30.0 * AtcTheme.UI_SCALE)
	_text_btn.pressed.connect(_on_issue_text)
	_text_row.add_child(_text_btn)
	egrid.add_child(_text_row)

	# 机组漏报通播时的提示卡（第一百五十九条：建立联络应当表明已收到通播）
	_atis_card = PanelContainer.new()
	var asb := StyleBoxFlat.new()
	asb.bg_color = Color(0.72, 0.20, 0.16, 0.16)
	asb.border_color = AtcTheme.C_DANGER
	asb.set_border_width_all(1)
	asb.set_corner_radius_all(3)
	asb.content_margin_left = 14
	asb.content_margin_right = 14
	asb.content_margin_top = 10
	asb.content_margin_bottom = 10
	_atis_card.add_theme_stylebox_override("panel", asb)
	_atis_card.visible = false
	right.add_child(_atis_card)

	var acol := VBoxContainer.new()
	acol.add_theme_constant_override("separation", 6)
	_atis_card.add_child(acol)
	_atis_text = _label("", 13, 500, AtcTheme.C_TEXT)
	_atis_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acol.add_child(_atis_text)
	_atis_btn = _action_button("要求机组收听通播", AtcTheme.C_WARM)
	_atis_btn.pressed.connect(_on_require_atis)
	acol.add_child(_atis_btn)

	_readback_card = PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.border_color = AtcTheme.C_WARM
	rsb.set_border_width_all(1)
	rsb.set_corner_radius_all(3)
	rsb.content_margin_left = 14
	rsb.content_margin_right = 14
	rsb.content_margin_top = 10
	rsb.content_margin_bottom = 10
	_readback_card.add_theme_stylebox_override("panel", rsb)
	_readback_card.visible = false
	right.add_child(_readback_card)

	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 5)
	_readback_card.add_child(rcol)

	rcol.add_child(_label("机组复诵", 12, 700, AtcTheme.C_WARM))
	_readback_text = _label("", 14, 400, AtcTheme.C_TEXT)
	_readback_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_readback_text)

	# 逐项比对表（规范 §6.1）：字段 / 许可 / 复诵 / 判定
	_rb_timer = _label("", 11, 700, AtcTheme.C_WARM)
	rcol.add_child(_rb_timer)
	_rb_grid = GridContainer.new()
	_rb_grid.columns = 4
	_rb_grid.add_theme_constant_override("h_separation", 12)
	_rb_grid.add_theme_constant_override("v_separation", 4)
	rcol.add_child(_rb_grid)
	_readback_diff = _label("", 13, 700, AtcTheme.C_DANGER)
	_readback_diff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_readback_diff)

	var rb_actions := HBoxContainer.new()
	rb_actions.add_theme_constant_override("separation", 8)
	rcol.add_child(rb_actions)
	_accept_btn = _action_button("复诵正确", AtcTheme.C_ACCENT)
	_accept_btn.pressed.connect(_on_accept)
	rb_actions.add_child(_accept_btn)
	_reissue_btn = _action_button("重发许可", AtcTheme.C_WARM)
	_reissue_btn.pressed.connect(_on_reissue)
	rb_actions.add_child(_reissue_btn)

	# 移交地面检查清单（规范 §7.1）：五项全满足才让移交
	_handoff_card = PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(1, 1, 1, 0.03)
	hsb.border_color = AtcTheme.C_ACCENT_DIM
	hsb.set_border_width_all(1)
	hsb.set_corner_radius_all(3)
	hsb.content_margin_left = 14
	hsb.content_margin_right = 14
	hsb.content_margin_top = 10
	hsb.content_margin_bottom = 10
	_handoff_card.add_theme_stylebox_override("panel", hsb)
	_handoff_card.visible = false
	right.add_child(_handoff_card)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 5)
	_handoff_card.add_child(hcol)
	hcol.add_child(_label("移交地面检查", 12, 700, AtcTheme.C_ACCENT))
	_handoff_grid = GridContainer.new()
	_handoff_grid.columns = 2
	_handoff_grid.add_theme_constant_override("h_separation", 12)
	_handoff_grid.add_theme_constant_override("v_separation", 4)
	hcol.add_child(_handoff_grid)

	# 底部留白把机场信息卡顶到最下面，跟真实席位的固定信息区一样
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(filler)

	# 离场情报（规范 §5.2）：机组没抄 ATIS 时逐项通报
	_dep_card = PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(1, 1, 1, 0.03)
	dsb.border_color = Color(1, 1, 1, 0.08)
	dsb.set_border_width_all(1)
	dsb.set_corner_radius_all(3)
	dsb.content_margin_left = 14
	dsb.content_margin_right = 14
	dsb.content_margin_top = 10
	dsb.content_margin_bottom = 10
	_dep_card.add_theme_stylebox_override("panel", dsb)
	_dep_card.visible = false
	right.add_child(_dep_card)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 5)
	_dep_card.add_child(dcol)
	var dhead := HBoxContainer.new()
	dhead.add_theme_constant_override("separation", 8)
	dcol.add_child(dhead)
	dhead.add_child(_label("离场情报", 12, 700, AtcTheme.C_WARM))
	var dsp := Control.new()
	dsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dhead.add_child(dsp)
	var all_btn := _action_button("全部通报", AtcTheme.C_WARM)
	all_btn.custom_minimum_size = Vector2(96.0 * AtcTheme.UI_SCALE,
		26.0 * AtcTheme.UI_SCALE)
	all_btn.pressed.connect(_on_notify_all_dep)
	dhead.add_child(all_btn)
	_dep_grid = GridContainer.new()
	_dep_grid.columns = 2
	_dep_grid.add_theme_constant_override("h_separation", 10)
	_dep_grid.add_theme_constant_override("v_separation", 2)
	dcol.add_child(_dep_grid)

	# 通播卡（规范 §3）：状态、重大变化灯、更新与过期处置入口
	var atis_card := PanelContainer.new()
	var acsb := StyleBoxFlat.new()
	acsb.bg_color = Color(1, 1, 1, 0.03)
	acsb.border_color = Color(1, 1, 1, 0.08)
	acsb.set_border_width_all(1)
	acsb.set_corner_radius_all(3)
	acsb.content_margin_left = 14
	acsb.content_margin_right = 14
	acsb.content_margin_top = 10
	acsb.content_margin_bottom = 10
	atis_card.add_theme_stylebox_override("panel", acsb)
	right.add_child(atis_card)

	var atis_col := VBoxContainer.new()
	atis_col.add_theme_constant_override("separation", 6)
	atis_card.add_child(atis_col)
	atis_col.add_child(_label("通播  ATIS", 10, 700, AtcTheme.C_TEXT_FAINT))
	_atis_state_label = _label("—", 13, 600, AtcTheme.C_TEXT)
	atis_col.add_child(_atis_state_label)
	_atis_lamp = _label("", 11, 500, AtcTheme.C_WARM)
	atis_col.add_child(_atis_lamp)
	_atis_update_btn = _action_button("按实况更新通播", AtcTheme.C_ACCENT)
	_atis_update_btn.custom_minimum_size = Vector2(0, 30.0 * AtcTheme.UI_SCALE)
	_atis_update_btn.pressed.connect(_on_update_atis)
	atis_col.add_child(_atis_update_btn)

	_atis_fix_row = HBoxContainer.new()
	_atis_fix_row.add_theme_constant_override("separation", 8)
	atis_col.add_child(_atis_fix_row)
	_atis_notify_btn = _action_button("通知最新通播", AtcTheme.C_WARM)
	_atis_notify_btn.custom_minimum_size = Vector2(0, 30.0 * AtcTheme.UI_SCALE)
	_atis_notify_btn.pressed.connect(_on_notify_atis)
	_atis_fix_row.add_child(_atis_notify_btn)
	_atis_report_btn = _action_button("逐项通报变化", AtcTheme.C_TEXT_SOFT)
	_atis_report_btn.custom_minimum_size = Vector2(0, 30.0 * AtcTheme.UI_SCALE)
	_atis_report_btn.pressed.connect(_on_report_atis)
	_atis_fix_row.add_child(_atis_report_btn)

	var info := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(1, 1, 1, 0.02)
	isb.border_color = Color(1, 1, 1, 0.06)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(3)
	isb.content_margin_left = 14
	isb.content_margin_right = 14
	isb.content_margin_top = 10
	isb.content_margin_bottom = 10
	info.add_theme_stylebox_override("panel", isb)
	right.add_child(info)

	_airport_box = VBoxContainer.new()
	_airport_box.add_theme_constant_override("separation", 3)
	info.add_child(_airport_box)


func _build_transcript(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	_bottom_pane = panel
	panel.custom_minimum_size = Vector2(0, _bottom_h)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.025)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	col.add_child(_label("陆空通话  RADIO", 11, 700, AtcTheme.C_TEXT_FAINT))

	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_log_scroll)

	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_box)


func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", AtcTheme.font(weight))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	lb.add_theme_color_override("font_color", color)
	return lb


func _field_row(caption: String, field: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var lb := _label(caption, 14, 500, AtcTheme.C_TEXT_DIM)
	lb.custom_minimum_size = Vector2(74.0 * AtcTheme.UI_SCALE, 0)
	r.add_child(lb)
	r.add_child(field)
	return r


## 只读字段：来自飞行计划，管制员照读不手填。
func _readonly_value(text: String) -> Label:
	var lb := _label(text, 15, 600, AtcTheme.C_TEXT)
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lb


func _section_line(title: String) -> Label:
	return _label(title, 11, 700, AtcTheme.C_TEXT_FAINT)


## 把当前编辑器里的选择拼成本次将要发出的完整通话。
## 与机组复诵用同一个格式化函数，避免"发的一套、比的一套"。
func _update_preview() -> void:
	if desk == null or _selected == "" or _preview == null:
		return
	var f := desk.get_flight(_selected)
	if f == null:
		return
	var sid_sel: String = DeliveryDesk.SIDS[_sid_opt.selected]
	var alt_sel: int = DeliveryDesk.ALT_OPTIONS[_alt_opt.selected]
	var route_sel := String(DeliveryDesk.SID_ROUTES.get(sid_sel, ""))
	var limit := f.clearance_limit if f.clearance_limit != "" else f.destination
	_limit_label.text = limit
	_route_label.text = route_sel if route_sel != "" else "—"
	var body := DeliveryDesk.readback_text_of(f.callsign, limit, sid_sel, route_sel,
		alt_sel, _squawk_edit.text)
	var info := desk.departure_info_text(f)
	_preview.text = body + ((" " + info + "。") if info != "" else "")


func _action_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38.0 * AtcTheme.UI_SCALE)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_color_override("font_focus_color", color)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.06)
	n.border_color = Color(1, 1, 1, 0.16)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.13)
	h.border_color = color
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	return b


# ---------------------------------------------------------------- 对外

func open(p_desk: DeliveryDesk) -> void:
	desk = p_desk
	_selected = ""
	_editor_for = ""
	_display.set_desk(desk)
	# 默认选中第一架待放行航班：管制员开工时也是从最上面一张进程单开始
	var pend := desk.pending()
	if not pend.is_empty():
		_selected = (pend[0] as Flight).callsign
	_sync_tabs()
	refresh()


## 机场静态信息（跑道/天气/ATIS），显示在右下角信息卡里。
func set_airport(data: Dictionary) -> void:
	_airport = data
	_refresh_airport()
	_sync_tabs()


## 把信息标签栏（机场/天气/停机位/当日计划/滑行道/通波）挂到会话顶栏正中央。
## 这样中间「信息显示面板」不再被标签条占掉一整行高度。
func mount_top_tabs(host: Control) -> void:
	if _tabs != null:
		_tabs.attach_bar(host)


func _sync_tabs() -> void:
	if _tabs != null and desk != null:
		_tabs.set_context(desk, _airport)


func _refresh_airport() -> void:
	if _airport_box == null:
		return
	for c in _airport_box.get_children():
		c.queue_free()

	if _airport.is_empty():
		_airport_box.add_child(_label("机场信息不可用", 12, 400, AtcTheme.C_TEXT_FAINT))
		return

	_airport_box.add_child(_label("机场信息  AERODROME", 10, 700, AtcTheme.C_TEXT_FAINT))

	var rwy := AirportData.primary_runway(_airport)
	_info_row("使用跑道", rwy)

	var wx: Variant = _airport.get("weather", {})
	if wx is Dictionary:
		var w: Dictionary = wx
		var wind := str(w.get("wind", "--"))
		var vis := str(w.get("visibility", "--"))
		_info_row("天气", "%s  %s" % [vis, wind])
		_info_row("修正海压", "%s hPa" % str(w.get("qnh_hpa", "--")))

	_info_row("ATIS", str(_airport.get("atis", "--")))
	var f: Variant = _airport.get("frequencies", {})
	if f is Dictionary:
		_info_row("本席位", "%s MHz" % AirportData.frequency(_airport, "delivery"))


func _info_row(key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := _label(key, 12, 400, AtcTheme.C_TEXT_FAINT)
	k.custom_minimum_size = Vector2(74.0 * AtcTheme.UI_SCALE, 0)
	row.add_child(k)
	row.add_child(_label(value, 12, 500, AtcTheme.C_TEXT_SOFT))
	_airport_box.add_child(row)


## 每帧由会话界面调用：推进放行席，必要时重建界面。
func tick(sim_time: float) -> void:
	if desk == null:
		return
	var before := _signature()
	if _review_win != null:
		_review_win.now = sim_time
	desk.maybe_spawn(sim_time)
	desk.tick(sim_time)
	if _tabs != null:
		_tabs.tick(sim_time)
	if _signature() != before:
		refresh()
	# 复诵核对倒计时不需要整面板重建，单独刷这一行
	if _readback_card != null and _readback_card.visible and _selected != "":
		var f := desk.get_flight(_selected)
		if f != null and f.state == Flight.State.READBACK:
			_refresh_rb_timer(f)


func _signature() -> String:
	var parts := PackedStringArray()
	for f in desk.flights:
		parts.append("%s:%d" % [f.callsign, int(f.state)])
	parts.append("t%d" % desk.transcript.size())
	return "|".join(parts)


# ---------------------------------------------------------------- 选择

func _select(callsign: String) -> void:
	_selected = callsign
	_display.set_selected(callsign)
	refresh()


func _on_map_flight_clicked(callsign: String) -> void:
	_select(callsign)


# ---------------------------------------------------------------- 刷新

func refresh() -> void:
	if desk == null:
		return
	_refresh_list()
	_refresh_detail()
	_refresh_log()
	_refresh_atis()
	_display.set_selected(_selected)
	_display.queue_redraw()
	if _tabs != null:
		_tabs.now = now
		_tabs.refresh()


func _refresh_list() -> void:
	for c in _pending_box.get_children():
		c.queue_free()
	_card_nodes.clear()

	# 按计划起飞时刻排（第二百九十二条），而不是按来的先后
	var pend := desk.ordered_pending()
	# 已放行但还没移交地面的进程单继续留在板上——
	# 真实席位在完成移交给地面之前不会把进程单撤走。
	var waiting: Array = []
	for f in desk.done_flights():
		if not (f as Flight).handed_off:
			waiting.append(f)

	_pending_count.text = str(pend.size())
	var rep := desk.score_report()
	_done_count.text = "已放行 %d 架 · 已移交 %d 架 · 评分 %d (%s)" % [
		desk.cleared_count, desk.handed_off_count(), int(rep.total),
		String(rep.grade)]

	if pend.is_empty() and waiting.is_empty():
		var empty := _label("暂无待放行航班", 13, 400, AtcTheme.C_TEXT_FAINT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pending_box.add_child(empty)
		return

	for f in pend:
		var card := _flight_card(f)
		_pending_box.add_child(card)
		_card_nodes.append({"callsign": (f as Flight).callsign, "ctrl": card})

	if not waiting.is_empty():
		_pending_box.add_child(_label("待移交地面  %d" % waiting.size(),
			11, 700, AtcTheme.C_ACCENT_DIM))
		for f in waiting:
			_pending_box.add_child(_flight_card(f))


## 一张飞行进程单。
## 要素对齐《飞行进程单》(MH4011)：呼号/机型/机位/目的地/航路/程序/高度/应答机/时刻，
## 并按第一百三十四条记入各节点时间戳。
func _flight_card(f: Flight) -> Control:
	var card := PanelContainer.new()
	var sel: bool = f.callsign == _selected
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07) if sel else Color(1, 1, 1, 0.035)
	sb.border_color = AtcTheme.C_ACCENT if sel else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(f.callsign)
			# 记下按下点：移动超过阈值才算拖动，否则只当点击选中
			_card_press = f.callsign
			_card_press_pos = get_global_mouse_position()
			_dragging_card = "")

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	# 子容器默认 STOP 会吞掉点击，卡片本身的 gui_input 就收不到（选不中航班）
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	head.add_child(_label(f.callsign, 16, 700, AtcTheme.C_TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label(f.state_text(), 11, 700, _state_color(f.state)))

	col.add_child(_label("%s · %s → %s" % [f.type, f.stand, f.destination],
		12, 500, AtcTheme.C_TEXT_DIM))
	col.add_child(_label("%s · %s" % [f.sid, f.route if f.route != "" else "—"],
		11, 400, AtcTheme.C_TEXT_FAINT))
	col.add_child(_label("%d m · SQK %s" % [f.initial_alt_m, f.squawk],
		11, 400, AtcTheme.C_TEXT_FAINT))

	var stamps := _stamp_text(f)
	if stamps != "":
		col.add_child(_label(stamps, 10, 400, AtcTheme.C_TEXT_FAINT))

	# 计划时刻与延误（第二百九十三条：延误超 30 分钟必须通知机组）
	if f.planned_std != "":
		var dly := desk.delay_minutes(f, now)
		var dly_color := AtcTheme.C_TEXT_FAINT
		var dly_text := "计划 %s" % f.planned_std
		if dly > 30:
			dly_color = AtcTheme.C_DANGER
			dly_text += "  延误 %d 分" % dly
		elif dly > 0:
			dly_color = AtcTheme.C_WARM
			dly_text += "  延误 %d 分" % dly
		col.add_child(_label(dly_text, 10, 500, dly_color))

	# AI 驾驶舱状态（07 文档）：质疑过几次、机组是否已经不再呼叫
	if f.pilot_queries > 0 or f.pilot_waiting or f.request_count > 1:
		var ai_txt := ""
		if f.pilot_waiting:
			ai_txt = "机组等待中（已呼叫 %d 次）" % f.request_count
		elif f.pilot_queries > 0:
			ai_txt = "机组质疑 %d 次 · 已呼叫 %d 次" % [
				f.pilot_queries, f.request_count]
		else:
			ai_txt = "已呼叫 %d 次" % f.request_count
		col.add_child(_label(ai_txt, 10, 700,
			AtcTheme.C_DANGER if f.pilot_waiting else AtcTheme.C_WARM))

	# CDM 时隙（规范 §2.2）：四个时间只读显示，CTOT 单独标色
	if f.eobt_min >= 0:
		var tline := "EOBT %s · TOBT %s" % [
			DeliveryDesk.slot_hhmm(f.eobt_min), DeliveryDesk.slot_hhmm(f.tobt_min)]
		col.add_child(_label(tline, 10, 400, AtcTheme.C_TEXT_FAINT))
		if f.ctot_restricted and f.ctot_min >= 0:
			col.add_child(_label("CTOT %s · COBT %s" % [
				DeliveryDesk.slot_hhmm(f.ctot_min),
				DeliveryDesk.slot_hhmm(f.cobt_min)], 10, 700, AtcTheme.C_WARM))
		if f.slot_eval != "":
			var ec := AtcTheme.C_ACCENT
			if f.slot_eval == "提前":
				ec = AtcTheme.C_WARM
			elif f.slot_eval == "延误":
				ec = AtcTheme.C_DANGER
			col.add_child(_label("放行 %s" % f.slot_eval, 10, 700, ec))

	# 未核对计划时，进程单上直接给出核对入口
	if desk != null and desk.enable_strip_check and not f.checked \
			and f.state == Flight.State.PENDING:
		var btn := Button.new()
		btn.text = "审查飞行计划" if desk.enable_plan_review else "核对计划"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 24)
		btn.add_theme_font_override("font", AtcTheme.font(500))
		btn.add_theme_font_size_override("font_size", AtcTheme.fs(12))
		btn.add_theme_color_override("font_color", AtcTheme.C_WARM)
		btn.pressed.connect(func() -> void: _on_check_plan(f.callsign))
		col.add_child(btn)
	return card


## 进程单时间戳：只显示已经发生的节点。
func _stamp_text(f: Flight) -> String:
	var parts := PackedStringArray()
	var clock_start := str(_airport.get("clock_start", "0000"))
	if f.t_check >= 0.0:
		parts.append("核 %s" % Atis.clock_text(clock_start, f.t_check))
	if f.t_sent >= 0.0:
		parts.append("发 %s" % Atis.clock_text(clock_start, f.t_sent))
	if f.t_readback >= 0.0:
		parts.append("复 %s" % Atis.clock_text(clock_start, f.t_readback))
	if f.t_cleared >= 0.0:
		parts.append("放 %s" % Atis.clock_text(clock_start, f.t_cleared))
	if f.t_handoff >= 0.0:
		parts.append("移 %s" % Atis.clock_text(clock_start, f.t_handoff))
	return " · ".join(parts)


func _on_check_plan(callsign: String) -> void:
	# 开启完整审查流程时，这里是"打开审查窗口"；关闭时保持原来的一键核对。
	if desk != null and desk.enable_plan_review:
		_open_review(callsign)
		return
	var r := desk.check_plan(callsign, now)
	if not r.ok:
		refresh()
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()


## 审查飞行计划窗口：挂在最近的 CanvasLayer 上（和下拉菜单同一套做法），
## 这样它能盖住顶栏，看起来才像"新开了一个窗口"。
func _open_review(callsign: String) -> void:
	if _review_win == null:
		var host: Node = get_parent()
		while host != null and not (host is CanvasLayer):
			host = host.get_parent()
		if host == null:
			host = get_tree().root
		_review_win = PlanReviewWindow.new()
		_review_win.name = "PlanReviewWindow"
		_review_win.changed.connect(func() -> void: refresh())
		host.add_child(_review_win)
	_review_win.now = now
	_review_win.open(desk, callsign)


## 用 if 而不是 match：GDScript 对 match 分支的"返回值完整性"检查很保守。
func _state_color(state: int) -> Color:
	if state == Flight.State.PENDING:
		return AtcTheme.C_WARM
	if state == Flight.State.SENT:
		return AtcTheme.C_TEXT_DIM
	if state == Flight.State.READBACK:
		return AtcTheme.C_ACCENT
	return AtcTheme.C_ACCENT_DIM


func _refresh_detail() -> void:
	var f := desk.get_flight(_selected) if _selected != "" else null

	if f == null:
		_detail_title.text = "未选择航班"
		_detail_title.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
		_detail_sub.text = ""
		_editor.modulate = Color(1, 1, 1, 0.45)
		_issue_btn.disabled = true
		_readback_card.visible = false
		_atis_card.visible = false
		_preview.text = ""
		_limit_label.text = "—"
		_route_label.text = "—"
		_hint.text = "在左列表或场面图上点一架航班"
		_hint.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
		_editor_for = ""
		return

	_detail_title.text = f.callsign
	_detail_title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_detail_sub.text = "%s · 机位 %s · 至 %s" % [f.type, f.stand, f.destination]
	_editor.modulate = Color(1, 1, 1, 1)

	# 只有换了航班才重新填表，避免玩家正在输入时被覆盖
	if _editor_for != f.callsign:
		_editor_for = f.callsign
		_select_item(_sid_opt, DeliveryDesk.SIDS.find(f.sid))
		_select_item(_alt_opt, DeliveryDesk.ALT_OPTIONS.find(f.initial_alt_m))
		_squawk_edit.text = f.squawk

	var can_issue: bool = f.state == Flight.State.PENDING
	var need_check: bool = desk.enable_strip_check and not f.checked
	var need_qnh: bool = desk.enable_qnh_gate and not f.qnh_confirmed
	var qnh_v := int(desk.field.get("qnh", 0))
	_qnh_value.text = "%d hPa" % qnh_v if qnh_v > 0 else "—"
	_qnh_btn.visible = desk.enable_qnh_gate
	_qnh_btn.disabled = f.qnh_confirmed or not can_issue
	_qnh_btn.text = "已确认" if f.qnh_confirmed else "确认 QNH"
	_sid_opt.disabled = not can_issue
	_alt_opt.disabled = not can_issue
	_squawk_edit.editable = can_issue

	if can_issue:
		_issue_btn.text = "发放行许可"
		_issue_btn.disabled = need_check or need_qnh
	elif f.state == Flight.State.CLEARED and not f.handed_off:
		_issue_btn.text = "移交给地面席"
		_issue_btn.disabled = not desk.handoff_ready(f)
	elif f.state == Flight.State.CLEARED and f.handed_off:
		_issue_btn.text = "已移交地面"
		_issue_btn.disabled = true
	else:
		_issue_btn.text = f.state_text()
		_issue_btn.disabled = true

	if f.state == Flight.State.PENDING:
		if need_check:
			_hint.text = "先在进程单上核对飞行计划"
			_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
		elif need_qnh:
			_hint.text = "先确认修正海压 QNH 才能发许可"
			_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
		else:
			_hint.text = "计划已核对，可以发放行许可"
			_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
	elif f.state == Flight.State.SENT:
		_hint.text = "许可已发出，等待机组复诵…"
		_hint.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	elif f.state == Flight.State.READBACK:
		_hint.text = "收到复诵，请核对"
		_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
	elif f.handed_off:
		_hint.text = "已移交给地面席"
		_hint.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
	else:
		_hint.text = "放行完成，等机组转频地面"
		_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)

	var show_rb: bool = f.state == Flight.State.READBACK
	_readback_card.visible = show_rb
	if show_rb:
		_readback_text.text = f.readback_text
		_refresh_readback_table(f)
		_accept_btn.disabled = desk.readback_hard and desk.readback_unmarked(f) > 0
		if desk.readback_hard:
			# 高阶模式不告诉玩家对错，这是这一档的核心压力
			_readback_diff.text = ""
		elif f.readback_ok:
			_readback_diff.text = "与许可要素一致"
			_readback_diff.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
		else:
			_readback_diff.text = "不一致：" + f.readback_diff
			_readback_diff.add_theme_color_override("font_color", AtcTheme.C_DANGER)

	# 机组首次呼叫没报通播：先要求收听，再发放行
	_atis_card.visible = (not f.atis_ok) and f.state == Flight.State.PENDING
	if _atis_card.visible:
		_atis_text.text = "机组未报告收到通播 %s。按规则应先要求机组收听，再发放行许可。" % \
			str(desk.field.get("atis_alpha", "A"))

	_update_preview()
	_refresh_handoff(f)
	_refresh_dep_info(f)
	# 三种发布模式（规范 §5.1）：只有当前模式对应的控件可见
	_cand_box.visible = desk.issue_mode == "preset" and can_issue
	_text_row.visible = desk.issue_mode == "text" and can_issue
	if _cand_box.visible:
		_refresh_candidates()


func _select_item(opt: OptionButton, index: int) -> void:
	if index >= 0 and index < opt.item_count:
		opt.selected = index


# ---------------------------------------------------------------- 移交地面（规范 §7）

func _refresh_handoff(f: Flight) -> void:
	if _handoff_card == null:
		return
	var show := desk.enable_handoff_check \
		and f.state == Flight.State.CLEARED and not f.handed_off
	_handoff_card.visible = show
	if not show:
		return
	for c in _handoff_grid.get_children():
		c.queue_free()
	for it in desk.handoff_checklist(f):
		var d: Dictionary = it
		var ok := bool(d.ok)
		var key := String(d.key)
		_handoff_grid.add_child(_label(String(d.label), 12, 500,
			AtcTheme.C_TEXT_SOFT if ok else AtcTheme.C_DANGER))
		if desk.handoff_hard:
			var confirmed: bool = f.handoff_confirmed.has(key)
			var b := Button.new()
			b.text = "已确认" if confirmed else ("确认" if ok else "不满足")
			b.disabled = confirmed or not ok
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(76.0 * AtcTheme.UI_SCALE,
				24.0 * AtcTheme.UI_SCALE)
			b.add_theme_font_override("font", AtcTheme.font(600))
			b.add_theme_font_size_override("font_size", AtcTheme.fs(12))
			b.add_theme_color_override("font_color",
				AtcTheme.C_ACCENT if confirmed else AtcTheme.C_TEXT_SOFT)
			b.add_theme_color_override("font_disabled_color",
				Color(0.55, 0.60, 0.62, 0.5))
			var n := StyleBoxFlat.new()
			n.bg_color = Color(1, 1, 1, 0.05)
			n.border_color = Color(1, 1, 1, 0.14)
			n.set_border_width_all(1)
			n.set_corner_radius_all(2)
			b.add_theme_stylebox_override("normal", n)
			b.add_theme_stylebox_override("disabled", n)
			var h := n.duplicate() as StyleBoxFlat
			h.bg_color = Color(1, 1, 1, 0.12)
			b.add_theme_stylebox_override("hover", h)
			b.pressed.connect(_on_confirm_handoff.bind(key))
			_handoff_grid.add_child(b)
		else:
			_handoff_grid.add_child(_label("✓" if ok else "✕", 12, 700,
				AtcTheme.C_ACCENT if ok else AtcTheme.C_DANGER))


func _on_confirm_handoff(key: String) -> void:
	if desk == null or _selected == "":
		return
	var r := desk.confirm_handoff_item(_selected, key)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()


func _on_tidy() -> void:
	if desk == null:
		return
	var r := desk.tidy_strips(now)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
		return
	refresh()
	_hint.text = "进程单已按计划时刻整理"
	_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)


# ---------------------------------------------------------------- 复诵核对（规范 §6）
## 逐项比对表：简易模式直接给结论，高阶模式只给"未核对"，让玩家自己判。
func _refresh_readback_table(f: Flight) -> void:
	if _rb_grid == null:
		return
	for c in _rb_grid.get_children():
		c.queue_free()
	for h in ["项目", "许可", "复诵", "判定"]:
		_rb_grid.add_child(_label(h, 10, 700, AtcTheme.C_TEXT_FAINT))
	var hard := desk.readback_hard
	for it in f.readback_items:
		var d: Dictionary = it
		var same := bool(d.get("same", true))
		_rb_grid.add_child(_label(String(d.get("label", "")), 12, 500,
			AtcTheme.C_TEXT_SOFT))
		_rb_grid.add_child(_label(String(d.get("expected", "")), 12, 400,
			AtcTheme.C_TEXT_DIM))
		_rb_grid.add_child(_label(String(d.get("actual", "")), 12, 400,
			AtcTheme.C_TEXT if (hard or same) else AtcTheme.C_DANGER))
		if hard:
			_rb_grid.add_child(_mark_button(f, String(d.get("key", ""))))
		else:
			_rb_grid.add_child(_label("✓ 一致" if same else "✕ 不一致", 11, 700,
				AtcTheme.C_ACCENT_DIM if same else AtcTheme.C_DANGER))
	_refresh_rb_timer(f)


func _mark_button(f: Flight, key: String) -> Button:
	var marked: bool = f.readback_marks.has(key)
	var ok_mark := bool(f.readback_marks.get(key, true))
	var txt := "未核对"
	var col := AtcTheme.C_TEXT_FAINT
	if marked:
		txt = "一致" if ok_mark else "不一致"
		col = AtcTheme.C_ACCENT if ok_mark else AtcTheme.C_DANGER
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(76.0 * AtcTheme.UI_SCALE, 24.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(600))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(12))
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.border_color = Color(1, 1, 1, 0.14)
	n.set_border_width_all(1)
	n.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.12)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.pressed.connect(_on_mark_readback.bind(key))
	return b


func _on_mark_readback(key: String) -> void:
	if desk == null or _selected == "":
		return
	var f := desk.get_flight(_selected)
	if f == null:
		return
	# 未核对 → 一致 → 不一致 → 一致 ……
	var next := true
	if f.readback_marks.has(key):
		next = not bool(f.readback_marks[key])
	desk.mark_readback_item(_selected, key, next, now)
	refresh()


func _refresh_rb_timer(f: Flight) -> void:
	if _rb_timer == null:
		return
	if desk.readback_hard and f.readback_deadline > 0.0:
		var left := maxf(0.0, f.readback_deadline - now)
		_rb_timer.text = "剩余 %.0f 秒（超时退回，需要重新发布）" % left
		_rb_timer.add_theme_color_override("font_color", AtcTheme.C_WARM)
	else:
		_rb_timer.text = ""


# ---------------------------------------------------------------- 通播（规范 §3）
func _refresh_atis() -> void:
	if _atis_state_label == null or desk == null:
		return
	_atis_state_label.text = desk.atis_status_text(now)
	var major := desk.atis_major
	if desk.enable_atis_lifecycle and major != "":
		_atis_lamp.text = "⚠ 重大变化：%s" % major
		_atis_lamp.add_theme_color_override("font_color", AtcTheme.C_WARM)
	elif desk.atis.has_error:
		_atis_lamp.text = "⚠ 本次通播的要素与实况不符"
		_atis_lamp.add_theme_color_override("font_color", AtcTheme.C_DANGER)
	else:
		_atis_lamp.text = ""
	_atis_update_btn.visible = desk.enable_atis_lifecycle
	# 过期时才需要处置；已经在提示区说明过就隐藏
	var need_fix := desk.enable_atis_lifecycle and desk.atis_expired \
		and _selected != ""
	_atis_fix_row.visible = need_fix
	if need_fix:
		var f := desk.get_flight(_selected)
		if f != null and f.atis_notified:
			_atis_fix_row.visible = false


func _on_update_atis() -> void:
	var r := desk.update_atis({}, now)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()
	_hint.text = "通播 %s 已发布%s" % [
		str(r.get("alpha", "")),
		"（要素与实况不符，注意）" if bool(r.get("has_error", false)) else ""]
	_hint.add_theme_color_override("font_color",
		AtcTheme.C_DANGER if bool(r.get("has_error", false)) else AtcTheme.C_ACCENT)


func _on_notify_atis() -> void:
	if _selected == "":
		return
	var r := desk.notify_latest_atis(_selected, now)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()


func _on_report_atis() -> void:
	if _selected == "":
		return
	var r := desk.report_atis_changes(_selected, now)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()


func _refresh_log() -> void:
	for c in _log_box.get_children():
		c.queue_free()

	for e in desk.recent(40):
		var side := String(e.side)
		var color := AtcTheme.C_TEXT_DIM
		var prefix := "· "
		if side == "pilot":
			color = AtcTheme.C_WARM
			prefix = "▸ 机组  "
		elif side == "atc":
			color = AtcTheme.C_ACCENT
			prefix = "◂ 管制  "
		var lb := _label("%s%s" % [prefix, String(e.text)], 13, 400, color)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_log_box.add_child(lb)

	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


# ---------------------------------------------------------------- 动作

func _on_squawk_changed(t: String) -> void:
	var clean := ""
	for i in range(t.length()):
		var c := t[i]
		if c >= "0" and c <= "7":
			clean += c
		if clean.length() == 4:
			break
	if clean != t:
		_squawk_edit.text = clean
		_squawk_edit.caret_column = clean.length()


func _on_confirm_qnh() -> void:
	if desk == null or _selected == "":
		return
	var r := desk.confirm_qnh(_selected)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()


## 离场情报（规范 §5.2）：机组没抄 ATIS 时逐项勾选通报。
## 抄了 ATIS 的项由系统自动算已覆盖（QNH 除外，它必须单独确认）。
func _refresh_dep_info(f: Flight) -> void:
	if _dep_card == null:
		return
	var show := desk.enable_dep_info and not f.atis_ok \
		and f.state == Flight.State.PENDING
	_dep_card.visible = show
	if not show:
		return
	for c in _dep_grid.get_children():
		c.queue_free()
	for it in desk.departure_info_items(f):
		var d: Dictionary = it
		var key := String(d.key)
		var cb := CheckBox.new()
		var val := String(d.value)
		cb.text = String(d.label) + ("" if val == "" else " " + val)
		var covered := bool(d.covered)
		var required := bool(d.required)
		cb.button_pressed = bool(d.notified) or covered or required
		cb.disabled = covered or required
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_override("font", AtcTheme.font(400))
		cb.add_theme_font_size_override("font_size", AtcTheme.fs(12))
		cb.add_theme_color_override("font_color",
			AtcTheme.C_TEXT_FAINT if cb.disabled else AtcTheme.C_TEXT_SOFT)
		if not cb.disabled:
			cb.toggled.connect(func(_on: bool) -> void: _on_toggle_dep(key))
		_dep_grid.add_child(cb)


## 简易对话模式（08 §2）：把当前适用的候选通话列出来，点哪条发哪条。
func _refresh_candidates() -> void:
	if _cand_box == null:
		return
	for c in _cand_box.get_children():
		c.queue_free()
	if desk == null or _selected == "":
		return
	for cand in desk.radio_candidates(_selected):
		var d: Dictionary = cand
		var b := Button.new()
		b.text = String(d.text)
		b.tooltip_text = String(d.hint)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32.0 * AtcTheme.UI_SCALE)
		b.add_theme_font_override("font", AtcTheme.font(400))
		b.add_theme_font_size_override("font_size", AtcTheme.fs(13))
		var good := bool(d.get("correct", true))
		b.add_theme_color_override("font_color",
			AtcTheme.C_TEXT_SOFT if good else AtcTheme.C_WARM)
		b.add_theme_color_override("font_hover_color",
			AtcTheme.C_ACCENT if good else AtcTheme.C_DANGER)
		var n := StyleBoxFlat.new()
		n.bg_color = Color(1, 1, 1, 0.04)
		n.border_color = Color(1, 1, 1, 0.10)
		n.set_border_width_all(1)
		n.set_corner_radius_all(3)
		n.content_margin_left = 10
		n.content_margin_right = 10
		n.content_margin_top = 6
		n.content_margin_bottom = 6
		b.add_theme_stylebox_override("normal", n)
		var h := n.duplicate() as StyleBoxFlat
		h.bg_color = Color(1, 1, 1, 0.10)
		b.add_theme_stylebox_override("hover", h)
		b.pressed.connect(_on_send_candidate.bind(String(d.id)))
		_cand_box.add_child(b)


func _on_send_candidate(cand_id: String) -> void:
	if desk == null or _selected == "":
		return
	_handle_issue_result(desk.send_candidate(_selected, cand_id, now))


## 发出许可后的统一处理：被机组质疑要显眼地提示，而不是当成成功
func _handle_issue_result(r: Dictionary) -> void:
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()
	if bool(r.get("queried", false)):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)


func _on_issue_preset() -> void:
	if desk == null or _selected == "":
		return
	_handle_issue_result(desk.issue_preset(_selected, now))


func _on_issue_text() -> void:
	if desk == null or _selected == "":
		return
	var r := desk.issue_free_text(_selected, _text_edit.text, now)
	if bool(r.ok):
		_text_edit.text = ""
	_handle_issue_result(r)


func _on_notify_all_dep() -> void:
	if desk == null or _selected == "":
		return
	desk.notify_all_dep_info(_selected)
	refresh()


func _on_toggle_dep(key: String) -> void:
	if desk == null or _selected == "":
		return
	desk.toggle_dep_info(_selected, key)
	refresh()


func _on_issue() -> void:
	var f := desk.get_flight(_selected)
	if f == null:
		return
	# 已放行的航班，这个按钮变成"移交地面"
	if f.state == Flight.State.CLEARED:
		var hr := desk.handoff_ground(_selected, now)
		if not hr.ok:
			_hint.text = String(hr.error)
			_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
			return
		refresh()
		return
	var sid: String = DeliveryDesk.SIDS[_sid_opt.selected]
	var alt: int = DeliveryDesk.ALT_OPTIONS[_alt_opt.selected]
	var sq := _squawk_edit.text
	var r := desk.issue_clearance(_selected, sid, alt, sq, now)
	_handle_issue_result(r)


func _on_accept() -> void:
	var r := desk.accept_readback(_selected, now)
	if not r.ok:
		# 必须先 refresh 再写提示：refresh 会用状态文案覆盖 _hint，
		# 顺序反了玩家就什么反馈都看不到（这个 bug 实际发生过）。
		refresh()
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	# 复核通过后保持选中：紧接着就是"联系地面"，按钮在这里变成移交地面
	refresh()


func _on_reissue() -> void:
	var r := desk.reissue(_selected, now)
	if not r.ok:
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()


func _on_require_atis() -> void:
	if desk == null or _selected == "":
		return
	var r := desk.require_atis(_selected, now)
	if not r.ok:
		refresh()
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	refresh()
