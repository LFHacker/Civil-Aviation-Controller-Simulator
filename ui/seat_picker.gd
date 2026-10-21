## 开局前的席位选择。
##
## 新游戏和训练共用这个界面，只是标题与后续流程不同 —— 席位本身完全一样。
class_name SeatPicker
extends Control

signal close_requested
signal seat_chosen(seat_id: String)

const SEAT_DESC := {
	"delivery": "发放行许可、离场程序、推出开车",
	"apron": "机坪动线、机位分配、地面服务协调",
	"ground": "滑行路线、跑道穿越、地面冲突",
	"tower": "起降许可、跑道占用、目视间隔",
	"approach": "进近排序、高度与速度调配",
	"center": "航路移交、扇区流量、航路间隔",
}

var _title: Label
var _sub: Label
var _back: Button
var _mode := "main"


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
	sb.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(900, 0)
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_override("font", AtcTheme.font(700))
	_title.add_theme_font_size_override("font_size", AtcTheme.fs(32))
	_title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(_title)

	var rule := ColorRect.new()
	rule.color = AtcTheme.C_ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)

	_sub = Label.new()
	_sub.add_theme_font_override("font", AtcTheme.font(400))
	_sub.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	_sub.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	_sub.text = "每个席位练习各自的管制职责，进度可以分别存档。"
	col.add_child(_sub)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)

	for seat in SaveFormat.SEATS:
		grid.add_child(_make_seat_card(String(seat.id), String(seat.label)))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)

	_back = Button.new()
	_back.text = "返回  (ESC)"
	_back.custom_minimum_size = Vector2(0, 44)
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


func _make_seat_card(seat_id: String, seat_name: String) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(438, 86)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.045)
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("normal", sb)

	var h := sb.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.10)
	h.border_color = AtcTheme.C_ACCENT_DIM
	card.add_theme_stylebox_override("hover", h)
	card.add_theme_stylebox_override("focus", h)

	# 卡片内部自己排两行：席位名 + 职责说明
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20
	v.offset_top = 10
	v.offset_right = -20
	v.offset_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)

	var name_lb := Label.new()
	name_lb.text = seat_name
	name_lb.add_theme_font_override("font", AtcTheme.font(500))
	name_lb.add_theme_font_size_override("font_size", AtcTheme.fs(21))
	name_lb.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	name_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lb)

	var desc := Label.new()
	desc.text = String(SEAT_DESC.get(seat_id, ""))
	desc.add_theme_font_override("font", AtcTheme.font(400))
	desc.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	desc.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)

	card.add_child(v)
	card.pressed.connect(func() -> void: seat_chosen.emit(seat_id))
	return card


## 打开选择界面。mode 取 "main" / "training"。
func open(mode: String) -> void:
	_mode = mode
	var is_train := mode == GameSession.MODE_TRAINING
	_title.text = ("训练 · 选择席位" if is_train else "新游戏 · 选择席位")
	_sub.text = ("训练不写入主线进度，但同样会自动存档。" if is_train
		else "选择你要值守的席位，开局后会自动存档。")
	visible = true
	_back.grab_focus()


func close() -> void:
	visible = false


func current_mode() -> String:
	return _mode
