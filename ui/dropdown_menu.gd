## 「下拉菜单按钮」公共底座：一个按钮 + 一个贴着它的自绘浮层面板。
##
## 浮层、定位、点空白处关闭、按钮与行的样式都在这里；
## 子类只管实现 build_rows() / refresh_rows()，不重复写定位逻辑
## （定位有个坑：面板放在底部工具栏时会向下溢出，必须能向上翻）。
class_name DropdownMenu
extends Button

var _overlay: Control
var _panel: PanelContainer
var _col: VBoxContainer


## 按钮上的字，子类覆盖
func button_text() -> String:
	return "菜单"


## 往面板里加行，子类覆盖
func build_rows() -> void:
	pass


## 每次打开时刷新打勾状态，子类覆盖
func refresh_rows() -> void:
	pass


func _ready() -> void:
	text = button_text()
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

	pressed.connect(toggle_menu)
	# 用 item_rect_changed 而不是 resized：顶栏重新排布时按钮可能只**移动**、
	# 尺寸不变，resized 不会触发，面板就会停在老位置（实际踩到过）。
	item_rect_changed.connect(_reposition)


# ---------------------------------------------------------------- 面板

func _build_overlay() -> void:
	var host: Node = get_parent()
	while host != null and not (host is CanvasLayer):
		host = host.get_parent()
	if host == null:
		host = get_tree().root

	_overlay = Control.new()
	_overlay.name = "DropdownOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	host.add_child(_overlay)

	# 点面板外的任何地方都关掉（透明接收层，不能设成 IGNORE 否则点不到）
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

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 2)
	_panel.add_child(_col)

	build_rows()


## 分组小标题。上下各留一点空，否则会和上下两行黏在一起。
## parent 传了就往那个容器里加（用于"整组可隐藏"的分组），否则加到主列。
func add_section(title: String, parent: Control = null) -> Control:
	var host := _col if parent == null else parent
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var pad_top := Control.new()
	pad_top.custom_minimum_size = Vector2(0, 9.0 * AtcTheme.UI_SCALE)
	box.add_child(pad_top)
	var lb := Label.new()
	lb.text = title
	lb.add_theme_font_override("font", AtcTheme.font(700))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(11))
	lb.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.custom_minimum_size = Vector2(0, 20.0 * AtcTheme.UI_SCALE)
	box.add_child(lb)
	var pad_bottom := Control.new()
	pad_bottom.custom_minimum_size = Vector2(0, 4.0 * AtcTheme.UI_SCALE)
	box.add_child(pad_bottom)
	host.add_child(box)
	return box


func add_divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.10)
	line.custom_minimum_size = Vector2(0, 1)
	_col.add_child(line)
	return line


## 一行可点的菜单项，返回按钮让调用方接 pressed 并改文案（打勾/置灰）。
func add_row(text: String, parent: Control = null) -> Button:
	var host := _col if parent == null else parent
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
	host.add_child(b)
	return b


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func close_menu() -> void:
	if _overlay != null:
		_overlay.visible = false


func toggle_menu() -> void:
	if _overlay == null:
		_build_overlay()
	if _overlay.visible:
		_overlay.visible = false
		return
	_overlay.visible = true
	refresh_rows()
	_reposition()


## 面板贴着按钮，且绝不超出画面：下面放不下就往按钮上方翻
## （窗口底部的工具栏就是这种情况，向下开会把最后一项挤出画面）。
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
