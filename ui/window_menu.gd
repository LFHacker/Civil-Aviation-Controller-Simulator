## 「窗口」菜单：显示模式 / 窗口尺寸 / 显示器 / 置顶 / 最小化 / 新开窗口 / 恢复默认。
##
## 只管"程序窗口"本身；面板显隐是 ui/view_menu.gd（「视图」）的事。
class_name WindowMenu
extends DropdownMenu

var _mode_buttons: Array = []
var _size_buttons: Array = []
var _screen_buttons: Array = []
var _screen_box: VBoxContainer
var _screen_divider: ColorRect
var _top_btn: Button


func button_text() -> String:
	return "窗口"


func build_rows() -> void:
	add_section("显示模式")
	for i in range(WindowSettings.MODE_LABELS.size()):
		var b := add_row("")
		b.pressed.connect(_on_mode_pressed.bind(i))
		_mode_buttons.append(b)

	add_divider()
	add_section("窗口尺寸")
	for i in range(WindowSettings.SIZES.size()):
		var b := add_row("")
		b.pressed.connect(_on_size_pressed.bind(i))
		_size_buttons.append(b)

	# 显示器一栏只在真的有多块屏时才有意义，单屏时整栏隐藏
	# ⚠️ 标题必须和按钮放进同一个容器，否则隐藏按钮时标题还留在外面
	# （这个错实际发生过：单屏时菜单里只剩一个光秃秃的「显示器」）。
	_screen_divider = add_divider()
	_screen_box = VBoxContainer.new()
	_screen_box.add_theme_constant_override("separation", 2)
	_col.add_child(_screen_box)
	add_section("显示器", _screen_box)
	for i in range(WindowSettings.screen_count()):
		var b := add_row("", _screen_box)
		b.pressed.connect(_on_screen_pressed.bind(i))
		_screen_buttons.append(b)
	var b_auto := add_row("", _screen_box)
	b_auto.pressed.connect(_on_screen_pressed.bind(WindowSettings.SCREEN_AUTO))
	_screen_buttons.append(b_auto)

	add_divider()
	_top_btn = add_row("置顶显示")
	_top_btn.toggle_mode = true
	_top_btn.toggled.connect(_on_top_toggled)

	var min_btn := add_row("最小化窗口")
	min_btn.pressed.connect(func() -> void:
		close_menu()
		WindowSettings.minimize())

	var new_btn := add_row("新开一个窗口")
	new_btn.pressed.connect(_on_new_window)

	add_divider()
	var reset_btn := add_row("恢复默认")
	reset_btn.pressed.connect(_on_reset)


func refresh_rows() -> void:
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
	refresh_rows()


func _on_size_pressed(index: int) -> void:
	if index < 0 or index >= WindowSettings.SIZES.size():
		return
	var d := WindowSettings.load_settings()
	d.mode = WindowSettings.MODE_WINDOWED
	d.w = int(WindowSettings.SIZES[index].w)
	d.h = int(WindowSettings.SIZES[index].h)
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	refresh_rows()


func _on_screen_pressed(index: int) -> void:
	var d := WindowSettings.load_settings()
	d.screen = index
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	refresh_rows()


func _on_top_toggled(on: bool) -> void:
	var d := WindowSettings.load_settings()
	d.always_on_top = on
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	refresh_rows()


func _on_new_window() -> void:
	close_menu()
	var pid := WindowSettings.spawn_new_instance()
	if pid <= 0:
		push_warning("新开窗口失败：拿不到可执行文件路径")


func _on_reset() -> void:
	var d := WindowSettings.defaults()
	WindowSettings.save_settings(d)
	WindowSettings.apply(d)
	refresh_rows()
