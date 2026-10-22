## 通用三选一确认框。
##
## 只负责"摆出选项并回传序号"，不关心选项含义；
## 这样退出确认、覆盖确认之类的地方都能复用同一套外观与键盘行为。
class_name ConfirmDialog
extends Control

## 选中某项时发出，index 与 open() 时传入的 options 下标一致。
signal choice(index: int)

var _title: Label
var _body: Label
var _btn_row: HBoxContainer
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.008, 0.014, 0.018, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.078, 0.090, 0.99)
	sb.border_color = AtcTheme.C_WARM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 30
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(620, 0)
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_override("font", AtcTheme.font(700))
	_title.add_theme_font_size_override("font_size", AtcTheme.fs(26))
	_title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(_title)

	var rule := ColorRect.new()
	rule.color = AtcTheme.C_WARM
	rule.custom_minimum_size = Vector2(48, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_override("font", AtcTheme.font(400))
	_body.add_theme_font_size_override("font_size", AtcTheme.fs(17))
	_body.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	col.add_child(_body)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)

	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 10)
	_btn_row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_btn_row)


## 打开确认框。options 是按钮文字，第一个是默认焦点（通常放"安全"的那项）。
func open(title: String, body: String, options: Array) -> void:
	_title.text = title
	_body.text = body

	for b in _buttons:
		b.queue_free()
	_buttons.clear()

	for i in range(options.size()):
		var idx := i
		var btn := _make_button(String(options[i]))
		btn.pressed.connect(func() -> void:
			close()
			choice.emit(idx))
		_btn_row.add_child(btn)
		_buttons.append(btn)

	visible = true
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func close() -> void:
	visible = false


func _make_button(text: String) -> Button:
	# 对话框按钮统一走 UiKit：确认=主操作、取消=次操作、删除/放弃=危险
	var low := text
	var b: Button
	if low.contains("删除") or low.contains("放弃") or low.contains("退出"):
		b = UiKit.danger(text)
	elif low.contains("取消") or low.contains("关闭") or low == "否":
		b = UiKit.secondary(text)
	else:
		b = UiKit.primary(text)
	b.custom_minimum_size.x = 150.0 * AtcTheme.UI_SCALE
	return b
