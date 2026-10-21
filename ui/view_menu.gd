## 「视图」菜单：开关界面面板 + 三套布局预设（对应 PyCharm 的 视图→工具窗口 / 外观）。
##
## 只管面板显隐，不管分辨率；分辨率在「窗口」菜单里。
## 状态存 core/view_state.gd，这里只负责显示与把点击变成 state_changed。
class_name ViewMenu
extends DropdownMenu

## 面板显隐变了（参数是完整的新状态字典）
signal state_changed(state: Dictionary)
## 换布局了：顺带把分栏宽度也恢复默认
signal layout_reset

var _rows: Dictionary = {}
var _preset_rows: Dictionary = {}


func button_text() -> String:
	return "视图"


func build_rows() -> void:
	add_section("面板")
	for p in ViewState.PANELS:
		var id := String(p.id)
		var b := add_row("")
		b.pressed.connect(_on_panel_pressed.bind(id))
		_rows[id] = b

	add_divider()
	add_section("布局")
	for p in ViewState.PRESETS:
		var id := String(p.id)
		var b := add_row("")
		b.pressed.connect(_on_preset_pressed.bind(id))
		_preset_rows[id] = b

	add_divider()
	var reset := add_row("恢复默认布局")
	reset.pressed.connect(_on_reset_layout)


func refresh_rows() -> void:
	var d := ViewState.load_settings()
	for p in ViewState.PANELS:
		var id := String(p.id)
		var b: Button = _rows.get(id)
		if b == null:
			continue
		var on := bool(d[id])
		b.text = ("☑ " if on else "☐ ") + String(p.label)
		# 最后一个主面板不能关，置灰提示"至少留一个"
		b.disabled = on and ViewState.is_main(id) and _main_open_count(d) <= 1
	var cur := ViewState.matching_preset(d)
	for p in ViewState.PRESETS:
		var id := String(p.id)
		var b: Button = _preset_rows.get(id)
		if b == null:
			continue
		var mark := "● " if id == cur else "○ "
		b.text = mark + String(p.label)
		b.tooltip_text = String(p.hint)
	_reposition()


func _main_open_count(d: Dictionary) -> int:
	var n := 0
	for p in ViewState.PANELS:
		if bool(p.main) and bool(d[String(p.id)]):
			n += 1
	return n


func _commit(d: Dictionary) -> void:
	ViewState.save_settings(d)
	refresh_rows()
	state_changed.emit(d)


func _on_panel_pressed(id: String) -> void:
	var d := ViewState.load_settings()
	_commit(ViewState.with_panel(d, id, not bool(d[id])))


func _on_preset_pressed(id: String) -> void:
	_commit(ViewState.preset(id))
	layout_reset.emit()


func _on_reset_layout() -> void:
	_commit(ViewState.defaults())
	layout_reset.emit()
