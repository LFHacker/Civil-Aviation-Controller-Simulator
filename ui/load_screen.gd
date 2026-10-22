## 载入存档界面：列出所有槽位，可载入、可删除。
##
## 表现层只负责"显示 SaveStore 读出来的东西"，不自己做任何文件判断。
## 损坏的存档也会照实列出来并标红 —— 让玩家知道这个档坏了，
## 比让它在列表里悄悄消失要好得多。
class_name LoadScreen
extends Control

signal close_requested
signal load_requested(slot_id: String)
signal delete_requested(slot_id: String)

var _store: SaveStore
var _list_box: VBoxContainer
var _summary: Label
var _empty: Label
var _scroll: ScrollContainer
var _back_button: Button

## 删除确认：第一次点变"确认删除"，再点才真删。key 是 slot_id。
var _pending_delete := ""


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
	sb.content_margin_top = 36
	sb.content_margin_bottom = 36
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(920, 0)
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := Label.new()
	title.text = "载入存档"
	title.add_theme_font_override("font", AtcTheme.font(700))
	title.add_theme_font_size_override("font_size", AtcTheme.fs(32))
	title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(title)

	var rule := ColorRect.new()
	rule.color = AtcTheme.C_ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)

	_summary = Label.new()
	_summary.add_theme_font_override("font", AtcTheme.font(400))
	_summary.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	_summary.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	col.add_child(_summary)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 360)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list_box)

	_empty = Label.new()
	_empty.text = "暂无存档。\n\n开始一场新游戏后，系统会自动写入存档；\n调试时按 F9 可以生成一份演示存档。"
	_empty.add_theme_font_override("font", AtcTheme.font(400))
	_empty.add_theme_font_size_override("font_size", AtcTheme.fs(18))
	_empty.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.visible = false
	col.add_child(_empty)

	_back_button = Button.new()
	_back_button.text = "返回  (ESC)"
	_back_button.custom_minimum_size = Vector2(0, 40.0 * AtcTheme.UI_SCALE)
	_back_button.add_theme_font_override("font", AtcTheme.font(500))
	_back_button.add_theme_font_size_override("font_size", AtcTheme.fs(19))
	_back_button.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_back_button.add_theme_color_override("font_hover_color", AtcTheme.C_ACCENT)
	_back_button.add_theme_color_override("font_focus_color", AtcTheme.C_ACCENT)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1, 1, 1, 0.05)
	bs.border_color = AtcTheme.C_ACCENT_DIM
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(3)
	bs.content_margin_top = 9
	bs.content_margin_bottom = 9
	_back_button.add_theme_stylebox_override("normal", bs)
	_back_button.pressed.connect(func() -> void: close_requested.emit())
	col.add_child(_back_button)


## 打开界面并刷新列表。
func open(store: SaveStore) -> void:
	_store = store
	_pending_delete = ""
	visible = true
	refresh()
	_back_button.grab_focus()


func close() -> void:
	visible = false


func refresh() -> void:
	for c in _list_box.get_children():
		c.queue_free()

	var entries := _store.list() if _store != null else []
	var valid := 0
	for e in entries:
		if e.ok:
			valid += 1

	_summary.text = "共 %d 个槽位，%d 个可用      位置  %s" % [
		entries.size(), valid, _store.base_dir]

	_empty.visible = entries.is_empty()
	_scroll.visible = not entries.is_empty()

	if entries.is_empty():
		return

	for e in entries:
		_list_box.add_child(_make_row(e))


# ---------------------------------------------------------------- 行

func _make_row(entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var broken: bool = not entry.ok
	sb.bg_color = Color(0.30, 0.10, 0.10, 0.22) if broken else Color(1, 1, 1, 0.045)
	sb.border_color = Color(0.97, 0.44, 0.44, 0.45) if broken else Color(1, 1, 1, 0.09)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	row.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	row.add_child(hb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	hb.add_child(info)

	var name_label := Label.new()
	name_label.add_theme_font_override("font", AtcTheme.font(500))
	name_label.add_theme_font_size_override("font_size", AtcTheme.fs(21))

	var meta := Label.new()
	meta.add_theme_font_override("font", AtcTheme.font(400))
	meta.add_theme_font_size_override("font_size", AtcTheme.fs(14))

	if entry.ok:
		var save: SaveGame = entry.save
		name_label.text = save.label
		name_label.add_theme_color_override("font_color", AtcTheme.C_TEXT)
		var mode_text := "训练" if save.mode == GameSession.MODE_TRAINING else "主线"
		meta.text = "%s · %s · %s · 仿真 %s · 保存于 %s" % [
			mode_text,
			SaveFormat.seat_label(save.state.seat_id),
			save.state.airport_id,
			save.state.sim_time_text(),
			_format_time(save.updated_unix),
		]
		meta.add_theme_color_override("font_color",
			AtcTheme.C_WARM if save.mode == GameSession.MODE_TRAINING else AtcTheme.C_TEXT_DIM)
	else:
		name_label.text = "%s（损坏）" % entry.slot_id
		name_label.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		meta.text = str(entry.error)
		meta.add_theme_color_override("font_color", Color(0.97, 0.60, 0.60))

	info.add_child(name_label)
	info.add_child(meta)

	if entry.ok:
		var btn_load := _small_button("载入", AtcTheme.C_ACCENT)
		btn_load.pressed.connect(func() -> void: load_requested.emit(str(entry.slot_id)))
		hb.add_child(btn_load)

	var pending: bool = _pending_delete == str(entry.slot_id)
	var btn_del := _small_button("确认删除？" if pending else "删除",
		AtcTheme.C_DANGER if pending else AtcTheme.C_TEXT_DIM)
	btn_del.pressed.connect(_on_delete_pressed.bind(str(entry.slot_id)))
	hb.add_child(btn_del)

	return row


func _small_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110.0 * AtcTheme.UI_SCALE, 40.0 * AtcTheme.UI_SCALE)
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


func _on_delete_pressed(slot_id: String) -> void:
	if _pending_delete != slot_id:
		# 第一次点击：进入确认态，不真删。
		# 注意：refresh() 绝不能清 _pending_delete，否则这里刚设上就被抹掉，
		# 二次确认永远进不去（这个 bug 实际发生过）。
		_pending_delete = slot_id
		refresh()
		return
	_pending_delete = ""
	delete_requested.emit(slot_id)


# ---------------------------------------------------------------- 工具

## unix 秒 → 本地 "MM-DD HH:MM"
func _format_time(unix_sec: int) -> String:
	if unix_sec <= 0:
		return "--"
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix_sec + bias * 60)
	return "%02d-%02d %02d:%02d" % [
		int(d.get("month", 1)), int(d.get("day", 1)),
		int(d.get("hour", 0)), int(d.get("minute", 0)),
	]
