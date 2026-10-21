## 「审查飞行计划」窗口（放行机制规范 §1）。
##
## 两级结构：左边是待审查的航班列表，右边是该航班的字段对照表
## （计划值 vs 当前有效值）+ 参考信息面板 + 三种处置按钮。
##
## 只负责显示与把点击转成 DeliveryDesk 的调用；判定规则全在 sim/plan_review.gd。
class_name PlanReviewWindow
extends Control

## 窗口关闭（调用方可能想刷新进程单）
signal closed
## 审查状态变化（处置/完成）
signal changed

var desk: DeliveryDesk

var _callsign := ""
var _card: PanelContainer
var _list_box: VBoxContainer
var _table: GridContainer
var _ref_box: VBoxContainer
var _title: Label
var _sub: Label
var _hint: Label
var _finish_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


## 「协调修改」是有延迟的，窗口开着时要自己刷新才能看到落地结果。
## 只用定时器刷右侧表格：**列表不重建**，否则点击正落在重建的那一帧会被吞掉
## （实际踩到过：点左侧航班没反应，因为那一下正好撞上重建）。
var _tick_acc := 0.0


func _process(delta: float) -> void:
	if not visible or desk == null:
		return
	_tick_acc += delta
	if _tick_acc < 0.4:
		return
	_tick_acc = 0.0
	_refresh_table()
	_refresh_ref()
	_refresh_footer()


# ---------------------------------------------------------------- 布局

func _build() -> void:
	# 遮罩：挡住下层并让背景变暗
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	# 宽度固定，高度跟着内容走 —— 写死高度会在内容少的时候留一大片空白
	_card.custom_minimum_size = Vector2(1360.0 * AtcTheme.UI_SCALE, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.050, 0.060, 0.995)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_card.add_child(root)

	# 标题行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	_title = _label("审查飞行计划", 22, 700, AtcTheme.C_TEXT)
	head.add_child(_title)
	_sub = _label("", 14, 400, AtcTheme.C_TEXT_DIM)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_btn := _button("关闭", AtcTheme.C_TEXT_DIM, 120.0)
	close_btn.pressed.connect(close_window)
	head.add_child(close_btn)

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.10)
	rule.custom_minimum_size = Vector2(0, 1)
	root.add_child(rule)

	# 主体：左列表 + 右对照
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280.0 * AtcTheme.UI_SCALE, 0)
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_label("待审查航班", 12, 700, AtcTheme.C_TEXT_FAINT))
	var lscroll := ScrollContainer.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.custom_minimum_size = Vector2(0, 340.0 * AtcTheme.UI_SCALE)
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lscroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 5)
	lscroll.add_child(_list_box)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)

	# 对照表
	var table_card := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(1, 1, 1, 0.028)
	tsb.border_color = Color(1, 1, 1, 0.07)
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(3)
	tsb.content_margin_left = 14
	tsb.content_margin_right = 14
	tsb.content_margin_top = 12
	tsb.content_margin_bottom = 12
	table_card.add_theme_stylebox_override("panel", tsb)
	right.add_child(table_card)

	_table = GridContainer.new()
	_table.columns = 5
	_table.add_theme_constant_override("h_separation", 14)
	_table.add_theme_constant_override("v_separation", 7)
	table_card.add_child(_table)

	# 参考信息
	var ref_card := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(1, 1, 1, 0.02)
	rsb.border_color = Color(1, 1, 1, 0.06)
	rsb.set_border_width_all(1)
	rsb.set_corner_radius_all(3)
	rsb.content_margin_left = 14
	rsb.content_margin_right = 14
	rsb.content_margin_top = 10
	rsb.content_margin_bottom = 10
	ref_card.add_theme_stylebox_override("panel", rsb)
	right.add_child(ref_card)

	_ref_box = VBoxContainer.new()
	_ref_box.add_theme_constant_override("separation", 4)
	ref_card.add_child(_ref_box)

	# 底部：提示 + 完成审查
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	root.add_child(foot)
	_hint = _label("", 13, 500, AtcTheme.C_TEXT_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_hint)
	_finish_btn = _button("完成审查", AtcTheme.C_ACCENT, 200.0)
	_finish_btn.pressed.connect(_on_finish)
	foot.add_child(_finish_btn)


# ---------------------------------------------------------------- 对外

func open(p_desk: DeliveryDesk, callsign: String = "") -> void:
	desk = p_desk
	if callsign != "":
		_callsign = callsign
	visible = true
	refresh()


func close_window() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if desk == null:
		return
	_refresh_list()
	if _callsign == "" or desk.get_flight(_callsign) == null:
		var pend := _reviewable()
		_callsign = (pend[0] as Flight).callsign if not pend.is_empty() else ""
	_refresh_table()
	_refresh_ref()
	_refresh_footer()


## 列表里放所有还在本席位流程里、尚未发放行许可的航班。
## 已经审查完的也留着（打上「计划已审查」），否则会出现
## "右边还显示这架、左边却已经不见了"的错位。
func _reviewable() -> Array:
	var out: Array = []
	for f in desk.flights:
		var fl := f as Flight
		if fl.state == Flight.State.PENDING:
			out.append(fl)
	return out


func _refresh_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var list := _reviewable()
	if list.is_empty():
		_list_box.add_child(_label("没有待审查的航班", 13, 400, AtcTheme.C_TEXT_FAINT))
		return
	for f in list:
		_list_box.add_child(_flight_tile(f as Flight))


func _flight_tile(f: Flight) -> Control:
	var card := PanelContainer.new()
	var sel := f.callsign == _callsign
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07) if sel else Color(1, 1, 1, 0.03)
	sb.border_color = AtcTheme.C_ACCENT if sel else Color(1, 1, 1, 0.07)
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
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_callsign = f.callsign
			refresh())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	# 子容器默认是 STOP，会把点击吞掉、卡片的 gui_input 永远收不到
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(_label(f.callsign, 16, 700, AtcTheme.C_TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(_label(f.state_text(), 11, 700, AtcTheme.C_ACCENT_DIM))

	var nbad := _bad_count(f.callsign)
	var tag := "已审查" if f.checked else ("全部一致" if nbad == 0 else ("%d 项不一致" % nbad))
	var tag_color := AtcTheme.C_ACCENT if f.checked else (
		AtcTheme.C_TEXT_FAINT if nbad == 0 else AtcTheme.C_DANGER)
	col.add_child(_label("%s · 至 %s · %s" % [f.type, f.destination, tag],
		11, 500, tag_color))
	# 卡片内部一律不接鼠标，否则点击会被里层容器吞掉、卡片收不到
	_passthrough(card)
	return card


static func _passthrough(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_passthrough(c)


func _bad_count(callsign: String) -> int:
	var n := 0
	for r in desk.review_rows(callsign):
		if int((r as Dictionary).get("state", PlanReview.OK)) == PlanReview.BAD:
			n += 1
	return n


func _refresh_table() -> void:
	for c in _table.get_children():
		c.queue_free()
	if _callsign == "":
		return
	var f := desk.get_flight(_callsign)
	if f == null:
		return

	# 表头
	for h in ["字段", "计划值", "当前有效值", "比对", "处置"]:
		_table.add_child(_label(h, 11, 700, AtcTheme.C_TEXT_FAINT))

	var hard := desk.difficulty == "hard"
	for rv in desk.review_rows(_callsign):
		var r: Dictionary = rv
		var state := int(r.get("state", PlanReview.OK))
		var key := String(r.get("key", ""))
		var bad := state == PlanReview.BAD

		var name_color := AtcTheme.C_TEXT_SOFT
		if bad: name_color = AtcTheme.C_DANGER
		elif state == PlanReview.WAIVED: name_color = AtcTheme.C_WARM
		_table.add_child(_label(String(r.get("label", "")), 14, 500, name_color))

		_table.add_child(_label(String(r.get("planned", "—")), 14, 400,
			AtcTheme.C_TEXT if not bad else AtcTheme.C_DANGER))
		_table.add_child(_label(String(r.get("current", "—")), 14, 400,
			AtcTheme.C_TEXT_DIM))

		# 标记列：高阶模式不给结论，玩家自己比
		var mark := "—"
		var mark_color := AtcTheme.C_TEXT_FAINT
		if state == PlanReview.INFO:
			mark = "—"
		elif hard and state == PlanReview.BAD:
			mark = "？"
			mark_color = AtcTheme.C_TEXT_DIM
		elif state == PlanReview.BAD:
			mark = "✕ 不一致"
			mark_color = AtcTheme.C_DANGER
		elif state == PlanReview.FIXED:
			mark = "✓ 已修正"
			mark_color = AtcTheme.C_ACCENT
		elif state == PlanReview.WAIVED:
			mark = "✓ 已审查"
			mark_color = AtcTheme.C_WARM
		else:
			mark = "✓ 一致"
			mark_color = AtcTheme.C_ACCENT_DIM
		_table.add_child(_label(mark, 13, 600, mark_color))

		# 处置列
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 4)
		_table.add_child(acts)
		var actionable := PlanReview.is_fixable(key) and (bad or hard) \
			and state != PlanReview.FIXED and state != PlanReview.WAIVED
		if actionable:
			if desk.review_coordinating(_callsign, key):
				acts.add_child(_label("协调中…", 12, 500, AtcTheme.C_WARM))
			else:
				var b1 := _mini("修正", AtcTheme.C_ACCENT)
				b1.pressed.connect(_on_fix.bind(key))
				acts.add_child(b1)
				if desk.difficulty != "easy":
					var b2 := _mini("协调", AtcTheme.C_TEXT_SOFT)
					b2.pressed.connect(_on_coordinate.bind(key))
					acts.add_child(b2)
					var b3 := _mini("保留", AtcTheme.C_WARM)
					b3.pressed.connect(_on_waive.bind(key))
					acts.add_child(b3)


func _refresh_ref() -> void:
	for c in _ref_box.get_children():
		c.queue_free()
	_ref_box.add_child(_label("参考信息  REFERENCE", 11, 700, AtcTheme.C_TEXT_FAINT))
	var ref: Dictionary = desk.review_ref
	_ref_box.add_child(_ref_row("当前天气", "%s  %s  修正海压 %d" % [
		str(desk.field.get("visibility", "--")),
		str(desk.field.get("wind", "--")),
		int(desk.field.get("qnh", 0))]))
	var routes: Dictionary = ref.get("routes", {})
	if not routes.is_empty():
		var parts := PackedStringArray()
		for k in routes.keys():
			parts.append("%s → %s" % [String(k), String(routes[k])])
		_ref_box.add_child(_ref_row("有效航路", "   ".join(parts)))
	var loa: Variant = ref.get("loa", [])
	if loa is Array and not (loa as Array).is_empty():
		var parts2 := PackedStringArray()
		for e in loa:
			if e is Dictionary:
				parts2.append("%s %d–%d 米" % [String(e.get("sid", "")),
					int(e.get("alt_min", 0)), int(e.get("alt_max", 0))])
		_ref_box.add_child(_ref_row("协议高度带", "   ".join(parts2)))
	var alts: Variant = ref.get("alternates", [])
	if alts is Array and not (alts as Array).is_empty():
		var parts3 := PackedStringArray()
		for a in alts:
			parts3.append(str(a))
		_ref_box.add_child(_ref_row("可用备降场", " / ".join(parts3)))


func _refresh_footer() -> void:
	if _callsign == "":
		_hint.text = "左侧选择一架待审查的航班"
		_hint.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
		_finish_btn.disabled = true
		return
	var f := desk.get_flight(_callsign)
	_title.text = "审查飞行计划"
	_sub.text = "%s · %s · 机位 %s · 至 %s" % [
		f.callsign, f.type, f.stand, f.destination]
	var nbad := _bad_count(_callsign)
	var hard := desk.difficulty == "hard"
	if f.checked:
		_hint.text = "该航班计划已审查完成，可以回去发放行许可了。"
		_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
		_finish_btn.disabled = true
	elif hard and nbad > 0:
		_finish_btn.disabled = false
		_hint.text = "高阶模式：系统不标出不一致项，请自己对照参考信息判断（漏检会计入评分）。"
		_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
	elif nbad > 0:
		_finish_btn.disabled = true
		_hint.text = "还有 %d 项不一致未处置，全部处置后才能完成审查。" % nbad
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
	else:
		_finish_btn.disabled = false
		_hint.text = "所有字段与当前有效数据一致，可以完成审查。"
		_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)


# ---------------------------------------------------------------- 动作

func _on_fix(key: String) -> void:
	_say(desk.fix_review_row(_callsign, key, _now()))
	refresh()
	changed.emit()


func _on_coordinate(key: String) -> void:
	var r := desk.coordinate_review_row(_callsign, key, _now())
	if bool(r.ok):
		_hint.text = "已提交协调，预计 %.0f 秒后返回结果。" % (
			float(r.get("ready_at", 0.0)) - _now())
		_hint.add_theme_color_override("font_color", AtcTheme.C_WARM)
	else:
		_say(r)
	refresh()


func _on_waive(key: String) -> void:
	_say(desk.waive_review_row(_callsign, key, _now()))
	refresh()
	changed.emit()


func _on_finish() -> void:
	var r := desk.finish_review(_callsign, _now())
	if not bool(r.ok):
		_say(r)
		return
	var missed := int(r.get("missed", 0))
	if missed > 0:
		_hint.text = "审查完成（有 %d 项未发现的不一致，已计入评分）。" % missed
	else:
		_hint.text = "审查完成，可以发放行许可了。"
	_hint.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
	refresh()
	changed.emit()


## 仿真时钟：会话每帧把当前时刻写进来（和 DeliveryPanel.now 同一口径）
var now := 0.0


func _now() -> float:
	return now


func _say(r: Dictionary) -> void:
	if bool(r.ok):
		return
	_hint.text = String(r.get("error", "操作失败"))
	_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)


# ---------------------------------------------------------------- 小工具

func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", AtcTheme.font(weight))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	lb.add_theme_color_override("font_color", color)
	return lb


func _ref_row(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var k := _label(key, 12, 400, AtcTheme.C_TEXT_FAINT)
	k.custom_minimum_size = Vector2(96.0 * AtcTheme.UI_SCALE, 0)
	row.add_child(k)
	var v := _label(value, 12, 500, AtcTheme.C_TEXT_SOFT)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	return row


func _mini(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(58.0 * AtcTheme.UI_SCALE, 26.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(12))
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.border_color = Color(1, 1, 1, 0.14)
	n.set_border_width_all(1)
	n.set_corner_radius_all(2)
	n.content_margin_left = 8
	n.content_margin_right = 8
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.12)
	h.border_color = color
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	return b


func _button(text: String, color: Color, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w * AtcTheme.UI_SCALE,
		38.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.55, 0.58, 0.5))
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
	b.add_theme_stylebox_override("disabled", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.13)
	h.border_color = color
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	return b
