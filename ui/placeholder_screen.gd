## 占位页：主菜单各入口点进去不报错，也不假装有功能。
class_name PlaceholderScreen
extends Control

signal back_requested

var _title_label: Label
var _body_label: Label
var _back_button: Button


func _ready() -> void:
	# 注意：set_anchors_preset() 会保留原尺寸（offset 被反算成负值，宽度仍是 0），
	# 必须用 set_anchors_and_offsets_preset() 才能真正铺满父级。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.020, 0.026, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.047, 0.070, 0.082, 0.98)
	sb.border_color = AtcTheme.C_ACCENT_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 56
	sb.content_margin_right = 56
	sb.content_margin_top = 44
	sb.content_margin_bottom = 44
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(620, 0)
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	_title_label = Label.new()
	_title_label.add_theme_font_override("font", AtcTheme.font(700))
	_title_label.add_theme_font_size_override("font_size", AtcTheme.fs(34))
	_title_label.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(_title_label)

	var rule := ColorRect.new()
	rule.color = AtcTheme.C_ACCENT
	rule.custom_minimum_size = Vector2(64, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_override("font", AtcTheme.font(400))
	_body_label.add_theme_font_size_override("font_size", AtcTheme.fs(19))
	_body_label.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	col.add_child(_body_label)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap)

	_back_button = Button.new()
	_back_button.text = "返回  (ESC)"
	_back_button.custom_minimum_size = Vector2(0, 48)
	_back_button.add_theme_font_override("font", AtcTheme.font(500))
	_back_button.add_theme_font_size_override("font_size", AtcTheme.fs(20))
	_back_button.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	_back_button.add_theme_color_override("font_hover_color", AtcTheme.C_ACCENT)
	_back_button.add_theme_color_override("font_focus_color", AtcTheme.C_ACCENT)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1, 1, 1, 0.05)
	bs.border_color = AtcTheme.C_ACCENT_DIM
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(3)
	bs.content_margin_top = 10
	bs.content_margin_bottom = 10
	_back_button.add_theme_stylebox_override("normal", bs)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	col.add_child(_back_button)


func show_for(title: String, body: String) -> void:
	_title_label.text = title
	_body_label.text = body
	visible = true
	_back_button.grab_focus()


func close() -> void:
	visible = false
