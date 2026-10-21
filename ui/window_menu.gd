## 「窗口」按钮 + 下拉面板：显示模式 / 窗口尺寸 / 显示器 / 置顶 / 最小化 / 新开窗口 / 恢复默认。
##
## 用法：new() 之后 add_child 到任意位置，再放进工具栏即可。
## 面板挂在当前 CanvasLayer 上（和界面同一套缩放），保证坐标与字号一致。
class_name WindowMenu
extends Button

var _overlay: Control
var _panel: PanelContainer
var _col: VBoxContainer
var _mode_buttons: Array = []
var _size_buttons: Array = []
var _screen_buttons: Array = []
var _screen_box: VBoxContainer
var _screen_divider: ColorRect
var _top_btn: Button

const OPT_MODE := 0
const OPT_SIZE := 100


func _ready() -> void:
	text = "窗口"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(120.0 * AtcTheme.UI_SCALE, 44.0 * AtcTheme.UI_SCALE)
	add_theme_font_override("font", AtcTheme.font(500))
	add_theme_font_size_override("font_size", AtcTheme.fs(17))
	add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)

	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.border_color = Color(1, 1, 1, 0.12)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 16
	n.content_margin_right = 16
	n.content_margin_top = 9
	n.content_margin_bottom = 9
	add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.11)
	h.border_color = AtcTheme.C_ACCENT_DIM
	add_theme_stylebox_override("hover", h)
	add_theme_stylebox_override("focus", h)
	add_theme_stylebox_override("pressed", h)

	pressed.connect(_toggle)
	resized.connect(_reposition)


# ---------------------------------------------------------------- 面板

func _build_overlay() -> void:
	var host: Node = get_parent()
	while host != null and not (host is CanvasLayer):
		host = host.get_parent()
	if host == null:
		host = get_tree().root

	_overlay = Control.new()
	_overlay.name = "WindowMenuOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	host.add_child(_overlay)

	var catcher := ColorRect.new()
	catcher.color = Color(0, 0, 0, 0.001)
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_overlay.visible = false)
	_overlay.add_child(catcher)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.059, 0.070, 0.99)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	_overlay.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_panel.add_child(col)
	_col = col

	col.add_child(_section("显示模式"))
	for i in range(WindowSettings.MODE_LABELS.size()):
		var b := _item_button("", OPT_MODE)
		b.pressed.connect(_on_mode_pressed.bind(i))
		col.add_child(b)
		_mode_buttons.append(b)

	col.add_child(_divider())
	col.add_child(_section("窗口尺寸"))
	for i in range(WindowSettings.SIZES.size()):
		var b := _item_button("", OPT_SIZE)
		b.pressed.connect(_on_size_pressed.bind(i))
		col.add_child(b)
		_size_buttons.append(b)

	# 显示器一栏只在真的有多块屏时才有意义，单屏时整栏隐藏
	_screen_divider = _divider()
	col.add_child(_screen_divider)
	_screen_box = VBoxContainer.new()
	_screen_box.add_theme_constant_override("separation", 2)
	col.add_child(_screen_box)
	_screen_box.add_child(_section("显示器"))
	for i in range(WindowSettings.screen_count()):
		var b := _item_button("", OPT_SIZE)
		b.pressed.connect(_on_screen_pressed.bind(i))
		_screen_box.add_child(b)
		_screen_buttons.append(b)
	var b_auto := _item_button("", OPT_SIZE)
	b_auto.pressed.connect(_on_screen_pressed.bind(WindowSettings.SCREEN_AUTO))
	_screen_box.add_child(b_auto)
	_screen_buttons.append(b_auto)

	col.add_child(_divider())
	_top_btn = _item_button("置顶显示", OPT_SIZE)
	_top_btn.toggle_mode = true
	_top_btn.toggled.connect(_on_top_toggled)
	col.add_child(_top_btn)

	var min_btn := _item_button("最小化窗口", OPT_SIZE)
	min_btn.pressed.connect(func() -> void:
		_overlay.visible = false
		WindowSettings.minimize())
	col.add_child(min_btn)

	var new_btn := _item_button("新开一个窗口", OPT_SIZE)
	new_btn.pressed.connect(_on_new_window)
	col.add_child(new_btn)

	col.add_child(_divider())
	var reset_btn := _item_button("恢复默认", OPT_SIZE)
	reset_btn.pressed.connect(_on_reset)
	col.add_child(reset_btn)


func _section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	# 小标题上下各留一点空，否则会和上一条目、下一条目黏在一起
	var pad_top := Control.new()
	pad_top.custom_minimum_size = Vector2(0, 9.0 * AtcTheme.UI_SCALE)
	box.add_child(pad_top)
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", AtcTheme.font(700))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(11))
	lb.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.custom_minimum_size = Vector2(0, 20.0 * AtcTheme.UI_SCALE)
	box.add_child(lb)
	var pad_bottom := Control.new()
	pad_bottom.custom_minimum_size = Vector2(0, 4.0 * AtcTheme.UI_SCALE)
	box.add_child(pad_bottom)
	return box


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.10)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _item_button(text: String, _kind: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(228.0 * AtcTheme.UI_SCALE, 34.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.62, 0.55))

	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.set_corner_radius_all(2)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.content_margin_top = 7
	n.content_margin_bottom = 7
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("disabled", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.37, 0.92, 0.83, 0.16)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(0.37, 0.92, 0.83, 0.10)
	b.add_theme_stylebox_override("pressed", p)
	return b


# ---------------------------------------------------------------- 交互

func _toggle() -> void:
	if _overlay == null:
		_build_overlay()
	if _overlay.visible:
		_overlay.visible = false
		return
	_overlay.visible = true
	_refresh()
	_reposition()


## 面板贴着按钮，且绝不超出画面：上面放不下就往按钮上方翻（底部工具栏就是这种情况）。
func _reposition() -> void:
	if _panel == null or _overlay == null or not _overlay.visible:
		return
	var r := get_global_rect()
	var sz := _panel.get_combined_minimum_size()
	_panel.size = sz
	var margin := 8.0 * AtcTheme.UI_SCALE
	var gap := 6.0 * AtcTheme.UI_SCALE
	var vp := _overlay.size
	var x := minf(r.end.x - sz.x, vp.x - sz.x - margin)
	x = maxf(x, margin)
	var y := r.end.y + gap
	if y + sz.y > vp.y - margin:
		var above := r.position.y - sz.y - gap
		# 上面能完整放下就翻上去；上下都放不下就贴着上边，至少标题不会被切掉
		y = above if above >= margin else maxf(margin, vp.y - sz.y - margin)
	_panel.position = Vector2(x, y)


func _refresh() -> void:
	var d := WindowSettings.load_settings()
	for i in range(_mode_buttons.size()):
		var mark := "● " if i == int(d.mode) else "○ "
		_mode_buttons[i].text = mark + String(WindowSettings.MODE_LABELS[i])
		_mode_buttons[i].disabled = false
	var idx := WindowSettings.size_index(int(d.w), int(d.h))
	for i in range(_size_buttons.size()):
		var mark := "● " if i == idx else "○ "
		_size_buttons[i].text = mark + String(WindowSettings.SIZES[i].label)
		# 全屏时尺寸没意义，置灰
		_size_buttons[i].disabled = int(d.mode) != WindowSettings.MODE_WINDOWED
	# 显示器：单屏就没必要显示这一栏
	var multi := WindowSettings.screen_count() > 1
	_screen_box.visible = multi
	_screen_divider.visible = multi
	if multi:
		var cur := int(d.screen)
		var auto_btn: Button = _screen_buttons[_screen_buttons.size() - 1]
		for i in range(_screen_buttons.size() - 1):
			var b: Button = _screen_buttons[i]
			b.text = ("● " if i == cur else "○ ") + WindowSettings.screen_label(i)
		auto_btn.text = ("● " if cur < 0 else "○ ") + WindowSettings.screen_label(-1)
	_top_btn.set_pressed_no_signal(bool(d.always_on_top))
	_top_btn.text = ("☑ " if bool(d.always_on_top) else "☐ ") + "置顶显示"
	_reposition()


func _on_mode_pressed(mode: int) -> void:
	var d := WindowSettings.load_settings()
	d = WindowSettings.set_mode(d, mode)
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	_refresh()


func _on_size_pressed(index: int) -> void:
	if index < 0 or index >= WindowSettings.SIZES.size():
		return
	var d := WindowSettings.load_settings()
	d.mode = WindowSettings.MODE_WINDOWED
	d.w = int(WindowSettings.SIZES[index].w)
	d.h = int(WindowSettings.SIZES[index].h)
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	_refresh()


func _on_screen_pressed(index: int) -> void:
	var d := WindowSettings.load_settings()
	d.screen = index
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	_refresh()


func _on_top_toggled(on: bool) -> void:
	var d := WindowSettings.load_settings()
	d.always_on_top = on
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	_refresh()


func _on_new_window() -> void:
	_overlay.visible = false
	var pid := WindowSettings.spawn_new_instance()
	if pid <= 0:
		push_warning("新开窗口失败：拿不到可执行文件路径")


func _on_reset() -> void:
	var d := WindowSettings.defaults()
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	_refresh()
