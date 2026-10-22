## 设置窗口测试（无头）：导航、分类内容、单选与开关发出的动作。
##
## 这个窗口取代了原来的长条下拉菜单，所以至少要有测试守着
## 「四个分类都在」「点单选能发出对应动作」「改完能重画」这几件事。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_settings_window.gd
extends SceneTree

var _checks := 0
var _fails := 0
var _step := 0
var _win: SettingsWindow
var _desk: DeliveryDesk
var _got: Array = []


func _process(_dt: float) -> bool:
	_step += 1
	match _step:
		2: _setup()
		4: _check_nav()
		6: _check_rows()
		8: _check_actions()
		10: _finish()
	return false


func _setup() -> void:
	print("")
	print("════════ 设置窗口测试 ════════")
	_desk = DeliveryDesk.new()
	_desk.setup(2718)
	_desk.difficulty = "normal"
	_desk.issue_mode = "form"
	_win = SettingsWindow.new()
	root.add_child(_win)
	_win.desk = _desk
	_win.version_text = "v0.0.0 test"
	_win.action.connect(func(id: String) -> void: _got.append(id))
	_win.open()


func _check_nav() -> void:
	_section("分类导航")
	_check(_win.visible, "窗口能打开")
	_check(_win._nav_buttons.size() == 4, "四个分类（常规/对话/语音/关于）",
		str(_win._nav_buttons.size()))
	for id in ["general", "dialog", "voice", "about"]:
		_check(_win._nav_buttons.has(id), "有分类 %s" % id)
	_check(_win.category == "general", "默认停在常规")
	# 切到每个分类都要能重建出内容，不能空白
	for cat in ["dialog", "voice", "about", "general"]:
		_win._on_nav(cat)
		_check(_win._body.get_child_count() > 0, "%s 分类有内容" % cat,
			str(_win._body.get_child_count()))


func _check_rows() -> void:
	_section("分类内容")
	_win._on_nav("dialog")
	var texts := _row_texts()
	var has_mode := false
	for t in texts:
		if t.contains("真实语音"):
			has_mode = true
	_check(has_mode, "对话页列出四种模式", str(texts.size()))
	var has_diff := false
	for t2 in texts:
		if t2.contains("高阶"):
			has_diff = true
	_check(has_diff, "对话页列出复诵难度")
	_check(texts.size() >= 7, "对话页行数足够（4 模式 + 3 难度）", str(texts.size()))

	_win._on_nav("voice")
	var vtexts := _row_texts()
	var has_speak := false
	var has_aux := false
	var has_demo := false
	for t3 in vtexts:
		if t3.contains("语音播报"):
			has_speak = true
		if t3.contains("语音辅助"):
			has_aux = true
		if t3.contains("试听"):
			has_demo = true
	_check(has_speak, "语音页有播报开关")
	_check(has_aux, "语音页有语音辅助入口")
	_check(has_demo, "语音页有试听")

	_win._on_nav("about")
	var atexts := _row_texts()
	_check(atexts.size() >= 2, "关于页有内容", str(atexts.size()))


func _check_actions() -> void:
	_section("点击发出的动作")
	_got.clear()
	_win._on_nav("dialog")
	_check(_press_row("真实语音"), "点得到「真实语音」这一行")
	_check(_got.has("pick:mode:voice"), "发出 pick:mode:voice", str(_got))
	_got.clear()
	_check(_press_row("高阶"), "点得到「高阶」")
	_check(_got.has("pick:diff:hard"), "发出 pick:diff:hard", str(_got))
	_win._on_nav("voice")
	_got.clear()
	_check(_press_row("语音播报"), "点得到「语音播报」")
	_check(_got.has("toggle:speak"), "发出 toggle:speak", str(_got))
	_got.clear()
	_check(_press_row("试听"), "点得到「试听」")
	_check(_got.has("demo"), "发出 demo", str(_got))
	_got.clear()
	_check(_press_row("语音辅助"), "点得到「语音辅助」")
	_check(_got.has("aux"), "发出 aux", str(_got))
	_win._on_nav("general")
	_got.clear()
	_check(_press_row("保存游戏"), "点得到「保存游戏」")
	_check(_got.has("save"), "发出 save", str(_got))


## 右侧内容里所有可点行的文字
func _row_texts() -> Array:
	var out: Array = []
	for c in _win._body.get_children():
		if c is Button:
			out.append(String((c as Button).text))
	return out


## 按文字找行并点它
func _press_row(needle: String) -> bool:
	for c in _win._body.get_children():
		if c is Button and String((c as Button).text).contains(needle):
			(c as Button).pressed.emit()
			return true
	return false


func _finish() -> void:
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	if _win != null and is_instance_valid(_win):
		_win.free()
	quit(0 if _fails == 0 else 1)


func _section(title: String) -> void:
	print("")
	print("· " + title)


func _check(cond: bool, name: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("    PASS  " + name)
	else:
		_fails += 1
		if detail == "":
			print("    FAIL  " + name)
		else:
			print("    FAIL  %s  -> %s" % [name, detail])
