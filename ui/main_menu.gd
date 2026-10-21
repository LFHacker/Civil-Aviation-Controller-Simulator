## 主菜单：窗框、标题、五项菜单、页脚、占位页。
## 键鼠都能操作：方向键上下移动焦点，回车确认，ESC 返回。
class_name MainMenu
extends CanvasLayer

signal quit_requested
signal load_requested(slot_id: String)
## 玩家选定席位、要开新局了。mode 取 "main" / "training"。
signal start_requested(mode: String, seat_id: String)

const ITEMS := [
	{"id": "new", "label": "新游戏"},
	{"id": "load", "label": "继续"},
	{"id": "train", "label": "训练"},
	{"id": "cfg", "label": "设置"},
	{"id": "quit", "label": "退出"},
]

## 由 main.gd 在 add_child 之前注入。为 null 时"继续"会给出提示而不是崩。
var save_store: SaveStore

var _root: Control
var _menu_box: VBoxContainer
var _buttons: Array[Button] = []
var _placeholder: PlaceholderScreen
var _load_screen: LoadScreen
var _seat_picker: SeatPicker
var _fade: ColorRect
var _toast_box: PanelContainer
var _toast: Label
var _window_menu: WindowMenu
var _toast_tween: Tween
var _idx := 0
var _leaving := false


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_frame()
	_build_scrim()
	_build_content()
	_build_footer()
	_build_toast()
	_build_placeholder()
	_build_load_screen()
	_build_seat_picker()
	_build_fade()

	if not _buttons.is_empty():
		_buttons[0].call_deferred("grab_focus")


# ---------------------------------------------------------------- 窗框

func _build_frame() -> void:
	_frame_rect(0.0, 0.0, 1.0, 0.079)
	_frame_rect(0.0, 0.924, 1.0, 1.0)
	_frame_rect(0.0, 0.0, 0.043, 1.0)
	_frame_rect(0.957, 0.0, 1.0, 1.0)
	# 塔台窗的竖向窗梃
	_frame_rect(0.665, 0.079, 0.672, 0.924)
	_frame_rect(0.795, 0.079, 0.802, 0.924)
	# 内侧细亮线，让"窗框"有金属包边感
	_hairline(0.079)
	_hairline(0.924)


## 左侧压暗，保证菜单文字在明亮天空前也能读清。
## 用一次 shader 画真正的渐变；TextureRect + GradientTexture2D 在这里会出现硬边。
func _build_scrim() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.012, 0.020, 0.026, 1.0);
uniform float edge_alpha = 0.90;
void fragment() {
	float t = smoothstep(0.0, 1.0, UV.x);
	COLOR = vec4(tint.rgb, mix(edge_alpha, 0.0, t));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("edge_alpha", 0.90)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.material = mat
	scrim.anchor_left = 0.043
	scrim.anchor_top = 0.079
	scrim.anchor_right = 0.56
	scrim.anchor_bottom = 0.924
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)


func _frame_rect(l: float, t: float, r: float, b: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = AtcTheme.C_FRAME
	rect.anchor_left = l
	rect.anchor_top = t
	rect.anchor_right = r
	rect.anchor_bottom = b
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


func _hairline(y_frac: float) -> void:
	var line := ColorRect.new()
	line.color = AtcTheme.C_FRAME_EDGE
	line.anchor_left = 0.043
	line.anchor_right = 0.957
	line.anchor_top = y_frac
	line.anchor_bottom = y_frac
	line.offset_bottom = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)


# ---------------------------------------------------------------- 标题 + 菜单

func _build_content() -> void:
	var box := VBoxContainer.new()
	box.name = "Content"
	box.anchor_left = 0.075
	box.anchor_top = 0.155
	box.anchor_right = 0.520
	box.anchor_bottom = 0.885
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	var title := Label.new()
	title.text = "管制模拟器"
	title.add_theme_font_override("font", AtcTheme.font(700))
	title.add_theme_font_size_override("font_size", AtcTheme.fs(76))
	title.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "AIR  TRAFFIC  CONTROL  SIMULATOR"
	sub.add_theme_font_override("font", AtcTheme.font(500))
	sub.add_theme_font_size_override("font_size", AtcTheme.fs(16))
	sub.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	sub.add_theme_constant_override("shadow_offset_x", 0)
	sub.add_theme_constant_override("shadow_offset_y", 1)
	box.add_child(sub)

	box.add_child(_spacer(20))

	var rule := ColorRect.new()
	rule.color = AtcTheme.C_ACCENT
	rule.custom_minimum_size = Vector2(96, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	box.add_child(_spacer(34))

	_menu_box = VBoxContainer.new()
	_menu_box.name = "Menu"
	_menu_box.add_theme_constant_override("separation", 2)
	_menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_menu_box)

	for i in range(ITEMS.size()):
		var btn := _make_item(ITEMS[i], i)
		_menu_box.add_child(btn)
		_buttons.append(btn)


func _make_item(item: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.name = "Item_%s" % item.id
	btn.text = "%02d    %s" % [index + 1, item.label]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(0, 54)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	btn.add_theme_font_override("font", AtcTheme.font(500))
	btn.add_theme_font_size_override("font_size", AtcTheme.fs(29))
	btn.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	btn.add_theme_color_override("font_focus_color", AtcTheme.C_TEXT)
	btn.add_theme_color_override("font_pressed_color", AtcTheme.C_ACCENT)

	btn.add_theme_stylebox_override("normal", AtcTheme.menu_style(false))
	btn.add_theme_stylebox_override("hover", AtcTheme.menu_style(true))
	btn.add_theme_stylebox_override("pressed", AtcTheme.menu_style(true))
	btn.add_theme_stylebox_override("focus", AtcTheme.menu_style(true))
	btn.add_theme_stylebox_override("disabled", AtcTheme.menu_style(false))

	btn.pressed.connect(_on_item_pressed.bind(str(item.id)))
	btn.mouse_entered.connect(func() -> void: btn.grab_focus())
	btn.focus_entered.connect(func() -> void: _idx = index)
	return btn


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ---------------------------------------------------------------- 页脚

func _build_footer() -> void:
	var bar := Control.new()
	bar.name = "Footer"
	bar.anchor_left = 0.055
	bar.anchor_top = 0.924
	bar.anchor_right = 0.945
	bar.anchor_bottom = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	bar.add_child(_footer_label("v%s  %s" % [AtcVersion.text(), AtcVersion.CODENAME],
		0.0, 0.5, HORIZONTAL_ALIGNMENT_LEFT, AtcTheme.C_TEXT_FAINT))
	bar.add_child(_footer_label("● 系统待机",
		0.34, 0.66, HORIZONTAL_ALIGNMENT_CENTER, AtcTheme.C_ACCENT_DIM))
	bar.add_child(_footer_label("GODOT 4.7.2  ·  FORWARD+",
		0.5, 0.87, HORIZONTAL_ALIGNMENT_RIGHT, AtcTheme.C_TEXT_FAINT))

	# 窗口按钮：主菜单里也能改显示模式 / 尺寸（和游戏内共用同一份设置）
	_window_menu = WindowMenu.new()
	_window_menu.name = "WindowMenu"
	_window_menu.anchor_left = 1.0
	_window_menu.anchor_right = 1.0
	_window_menu.anchor_top = 0.0
	_window_menu.anchor_bottom = 1.0
	_window_menu.offset_left = -126.0 * AtcTheme.UI_SCALE
	_window_menu.offset_right = 0.0
	_window_menu.offset_top = 2.0
	_window_menu.offset_bottom = -2.0
	bar.add_child(_window_menu)


func _footer_label(text: String, l: float, r: float, align: int, color: Color) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.anchor_left = l
	lb.anchor_right = r
	lb.anchor_top = 0.0
	lb.anchor_bottom = 1.0
	lb.horizontal_alignment = align
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_override("font", AtcTheme.font(400))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	lb.add_theme_color_override("font_color", color)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


# ---------------------------------------------------------------- 占位页 / 淡出

func _build_placeholder() -> void:
	# 必须挂在全屏的 _root 下：直接挂 CanvasLayer 时锚点不参与布局，会缩到左上角。
	_placeholder = PlaceholderScreen.new()
	_placeholder.name = "Placeholder"
	_root.add_child(_placeholder)
	_placeholder.back_requested.connect(_on_placeholder_back)


func _build_load_screen() -> void:
	_load_screen = LoadScreen.new()
	_load_screen.name = "LoadScreen"
	_root.add_child(_load_screen)
	_load_screen.close_requested.connect(_on_load_close)
	_load_screen.load_requested.connect(_on_load_requested)
	_load_screen.delete_requested.connect(_on_delete_requested)


func _build_seat_picker() -> void:
	_seat_picker = SeatPicker.new()
	_seat_picker.name = "SeatPicker"
	_root.add_child(_seat_picker)
	_seat_picker.close_requested.connect(func() -> void:
		_seat_picker.close()
		_restore_menu_focus())
	_seat_picker.seat_chosen.connect(_on_seat_chosen)


## 底部居中的提示条，用于"已载入 / 已删除 / 删除失败"这类反馈。
func _build_toast() -> void:
	_toast_box = PanelContainer.new()
	_toast_box.name = "Toast"
	_toast_box.anchor_left = 0.30
	_toast_box.anchor_right = 0.70
	_toast_box.anchor_top = 0.828
	_toast_box.anchor_bottom = 0.884
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


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


# ---------------------------------------------------------------- 交互

## 供调试/自动化使用：按 id 直接触发某个菜单项。
func open_item(id: String) -> void:
	_on_item_pressed(id)


func _on_item_pressed(id: String) -> void:
	match id:
		"new":
			_seat_picker.open(GameSession.MODE_MAIN)
		"load":
			if save_store == null:
				_placeholder.show_for("继续", "存档系统未初始化，无法读取存档。")
			else:
				_load_screen.open(save_store)
		"train":
			_seat_picker.open(GameSession.MODE_TRAINING)
		"cfg":
			_placeholder.show_for("设置",
				"分辨率、音量、按键映射与语言设置正在开发中。\n\n当前版本使用 1280×720 窗口与系统默认字体。")
		"quit":
			_do_quit()


func _on_placeholder_back() -> void:
	_placeholder.close()
	_restore_menu_focus()


func _on_load_close() -> void:
	_load_screen.close()
	_restore_menu_focus()


func _on_load_requested(slot_id: String) -> void:
	load_requested.emit(slot_id)


func _on_delete_requested(slot_id: String) -> void:
	if save_store == null:
		return
	var r := save_store.erase(slot_id)
	if r.ok:
		show_toast("已删除存档 %s" % slot_id)
	else:
		show_toast("删除失败：%s" % r.error, true)
	_load_screen.refresh()


func _on_seat_chosen(seat_id: String) -> void:
	var mode := _seat_picker.current_mode()
	_seat_picker.close()
	start_requested.emit(mode, seat_id)


## 开始一局后整个菜单让位给会话界面。
func set_ui_visible(v: bool) -> void:
	_root.visible = v
	if v:
		_restore_menu_focus()


func _restore_menu_focus() -> void:
	if _idx >= 0 and _idx < _buttons.size():
		_buttons[_idx].grab_focus()


## 存档文件在外部发生变化时（例如按 F9 生成了演示存档），刷新已打开的列表。
func refresh_load_screen() -> void:
	if _load_screen != null and _load_screen.visible:
		_load_screen.refresh()


func _do_quit() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color", Color(0, 0, 0, 1), 0.32)
	tw.tween_callback(func() -> void:
		quit_requested.emit()
		get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _seat_picker.visible:
		_seat_picker.close()
		_restore_menu_focus()
		get_viewport().set_input_as_handled()
	elif _load_screen.visible:
		_on_load_close()
		get_viewport().set_input_as_handled()
	elif _placeholder.visible:
		_on_placeholder_back()
		get_viewport().set_input_as_handled()
