## 保存界面：把当前会话写进某个手动槽位。
##
## 只负责"选槽位 + 取名字 + 二次确认覆盖"，真正的写盘交给调用方。
class_name SaveScreen
extends Control

signal close_requested
signal save_requested(slot_id: String, label: String)

var _store: SaveStore
var _list_box: VBoxContainer
var _name_edit: LineEdit
var _summary: Label
var _back: Button

## 当前会话已绑定的槽位，用来显示"当前"标记。
var _current_slot := ""
## 覆盖确认：第一次点变"确认覆盖？"
var _pending_overwrite := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.020, 0.026, 0.86)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.063, 0.075, 0.985)
	sb.border_color = AtcTheme.C_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 34
	sb.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(900, 0)
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title := Label.new()
	title.text = "保存游戏"
	title.add_theme_font_override("font", AtcTheme.font(700))
	title.add_theme_font_size_override("font_size", AtcTheme.fs(32))
	title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(title)

	var rule := ColorRect.new()
	rule.color = AtcTheme.C_ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)

	# 存档名
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	col.add_child(name_row)

	var name_lb := Label.new()
	name_lb.text = "存档名"
	name_lb.custom_minimum_size = Vector2(70, 0)
	name_lb.add_theme_font_override("font", AtcTheme.font(500))
	name_lb.add_theme_font_size_override("font_size", AtcTheme.fs(16))
	name_lb.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	name_row.add_child(name_lb)

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 48
	_name_edit.add_theme_font_override("font", AtcTheme.font(400))
	_name_edit.add_theme_font_size_override("font_size", AtcTheme.fs(17))
	_name_edit.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", AtcTheme.C_TEXT_FAINT)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(1, 1, 1, 0.06)
	nsb.border_color = Color(1, 1, 1, 0.14)
	nsb.set_border_width_all(1)
	nsb.set_corner_radius_all(3)
	nsb.content_margin_left = 12
	nsb.content_margin_right = 12
	nsb.content_margin_top = 8
	nsb.content_margin_bottom = 8
	_name_edit.add_theme_stylebox_override("normal", nsb)
	var nf := nsb.duplicate() as StyleBoxFlat
	nf.border_color = AtcTheme.C_ACCENT_DIM
	_name_edit.add_theme_stylebox_override("focus", nf)
	name_row.add_child(_name_edit)

	_summary = Label.new()
	_summary.add_theme_font_override("font", AtcTheme.font(400))
	_summary.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	_summary.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
	col.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	_back = Button.new()
	_back.text = "返回  (ESC)"
	_back.custom_minimum_size = Vector2(0, 42)
	_back.add_theme_font_override("font", AtcTheme.font(500))
	_back.add_theme_font_size_override("font_size", AtcTheme.fs(19))
	_back.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_back.add_theme_color_override("font_hover_color", AtcTheme.C_ACCENT)
	_back.add_theme_color_override("font_focus_color", AtcTheme.C_ACCENT)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1, 1, 1, 0.05)
	bs.border_color = AtcTheme.C_ACCENT_DIM
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(3)
	bs.content_margin_top = 9
	bs.content_margin_bottom = 9
	_back.add_theme_stylebox_override("normal", bs)
	_back.pressed.connect(func() -> void: close_requested.emit())
	col.add_child(_back)


## 打开保存界面。
## current_slot 为空表示还没存过；default_label 是预填的存档名。
func open(store: SaveStore, current_slot: String, default_label: String) -> void:
	_store = store
	_current_slot = current_slot
	_pending_overwrite = ""
	_name_edit.text = default_label
	visible = true
	refresh()
	_name_edit.grab_focus()
	_name_edit.select_all()


func close() -> void:
	visible = false


func refresh() -> void:
	for c in _list_box.get_children():
		c.queue_free()

	if _store == null:
		_summary.text = "存档系统未初始化"
		return

	var entries := _store.list()
	# 只数手动槽位：自动存档(auto_*)不占手动槽位的名额，
	# 否则摘要会显示成"已用 1 个"而玩家在下面看到的全是空槽位。
	var used := 0
	for e in entries:
		if e.ok and String(e.slot_id).begins_with("manual_"):
			used += 1
	_summary.text = "共 %d 个手动槽位，已用 %d 个      位置  %s" % [
		SaveFormat.MANUAL_SLOT_COUNT, used, _store.base_dir]

	for i in range(1, SaveFormat.MANUAL_SLOT_COUNT + 1):
		var slot_id := SaveFormat.manual_slot(i)
		var found: Dictionary = {}
		for e in entries:
			if String(e.slot_id) == slot_id:
				found = e
				break
		_list_box.add_child(_make_row(i, slot_id, found))


func _make_row(index: int, slot_id: String, entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	row.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hb.add_child(info)

	var head := Label.new()
	head.add_theme_font_override("font", AtcTheme.font(500))
	head.add_theme_font_size_override("font_size", AtcTheme.fs(18))

	var meta := Label.new()
	meta.add_theme_font_override("font", AtcTheme.font(400))
	meta.add_theme_font_size_override("font_size", AtcTheme.fs(13))

	var occupied: bool = not entry.is_empty() and bool(entry.get("ok", false))
	var is_current := slot_id == _current_slot

	if occupied:
		var save: SaveGame = entry.save
		head.text = "%02d   %s" % [index, save.label]
		if is_current:
			head.text += "   · 当前存档"
		head.add_theme_color_override("font_color",
			AtcTheme.C_ACCENT if is_current else AtcTheme.C_TEXT)
		meta.text = "%s · %s · 仿真 %s · 保存于 %s" % [
			("训练" if save.mode == GameSession.MODE_TRAINING else "主线"),
			SaveFormat.seat_label(save.state.seat_id),
			save.state.sim_time_text(),
			_format_time(save.updated_unix),
		]
		meta.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	elif not entry.is_empty():
		head.text = "%02d   槽位（损坏）" % index
		head.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		meta.text = String(entry.get("error", ""))
		meta.add_theme_color_override("font_color", Color(0.97, 0.60, 0.60))
	else:
		head.text = "%02d   空槽位" % index
		head.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
		meta.text = "点击右侧按钮保存到此处"
		meta.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)

	info.add_child(head)
	info.add_child(meta)

	var pending: bool = _pending_overwrite == slot_id
	var btn_text := "保存"
	if occupied:
		btn_text = "确认覆盖？" if pending else "覆盖"
	var btn := _small_button(btn_text,
		AtcTheme.C_DANGER if pending else AtcTheme.C_ACCENT)
	btn.pressed.connect(_on_slot_pressed.bind(slot_id, occupied))
	hb.add_child(btn)

	return row


func _on_slot_pressed(slot_id: String, occupied: bool) -> void:
	if occupied and _pending_overwrite != slot_id:
		# 第一次点：进入确认态，不覆盖
		_pending_overwrite = slot_id
		refresh()
		return
	_pending_overwrite = ""
	var name := _name_edit.text.strip_edges()
	if name == "":
		name = slot_id
	save_requested.emit(slot_id, name)


func _small_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 40)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(16))
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.border_color = Color(1, 1, 1, 0.12)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.12)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	return b


func _format_time(unix_sec: int) -> String:
	if unix_sec <= 0:
		return "--"
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix_sec + bias * 60)
	return "%02d-%02d %02d:%02d" % [
		int(d.get("month", 1)), int(d.get("day", 1)),
		int(d.get("hour", 0)), int(d.get("minute", 0)),
	]
