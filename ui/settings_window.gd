## 设置窗口：按"左边分类、右边设置项、底下按钮"的常规软件布局重排。
##
## 旧版是挂在「选项」按钮下面的一长条下拉菜单（十来行堆在一起），
## 项目一多就没人找得到东西。这里改成常规设置面板：
##   常规 / 对话 / 语音 / 关于 四个分类，右侧按分类放单选行与开关行。
##
## 只负责画与收集输入；真正的动作（存档、暂停、切难度…）通过信号交给会话界面，
## 因为那些要用到 session/存档系统，放这里会把界面和数据层搅在一起。
class_name SettingsWindow
extends Control

## 一次性动作：save / load / pause / exit / aux / demo / reset
signal action(id: String)
signal closed

const NAV := [
	{"id": "general", "label": "常规"},
	{"id": "dialog", "label": "对话"},
	{"id": "voice", "label": "语音"},
	{"id": "about", "label": "关于"},
]

const DIFF_NAMES := ["简易", "进阶", "高阶"]
const DIFF_KEYS := ["easy", "normal", "hard"]
const MODE_NAMES := ["预设一键", "填空式", "自由文本", "真实语音"]
const MODE_KEYS := ["preset", "form", "text", "voice"]

var desk: DeliveryDesk
## 暂停状态在 session 上，不在放行席上；由会话界面传进来
var paused := false
var category := "general"
var version_text := ""

var _nav_box: VBoxContainer
var _body: VBoxContainer
var _nav_buttons := {}
var _title: Label
var _player: VoicePlayer


## 试听：用当前片段库念一条标准放行许可（只出声，不发送）
func play_demo() -> void:
	if _player == null:
		_player = VoicePlayer.new()
		_player.name = "SettingsDemo"
		add_child(_player)
	_player.enabled = true
	_player.play(Voice.clearance("CCA1501", "RUMUK 8D", "ZBAA", 6000, "4215", 1013),
		"controller")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	closed.emit()


# ---------------------------------------------------------------- 构建

func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.66)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(820.0 * AtcTheme.UI_SCALE,
		640.0 * AtcTheme.UI_SCALE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.050, 0.060, 0.998)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var rootbox := VBoxContainer.new()
	rootbox.add_theme_constant_override("separation", 0)
	card.add_child(rootbox)

	# 标题栏
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.custom_minimum_size = Vector2(0, 54.0 * AtcTheme.UI_SCALE)
	rootbox.add_child(head)
	_title = _label("设置", 18, 700, AtcTheme.C_TEXT)
	_title.add_theme_constant_override("h_separation", 12)
	head.add_child(_pad(20))
	head.add_child(_title)

	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 0)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rootbox.add_child(body_row)

	# 左分类
	var nav_wrap := PanelContainer.new()
	nav_wrap.custom_minimum_size = Vector2(150.0 * AtcTheme.UI_SCALE, 0)
	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(1, 1, 1, 0.025)
	nb.border_color = Color(1, 1, 1, 0.07)
	nb.border_width_right = 1
	nb.set_corner_radius_all(0)
	nb.content_margin_left = 12
	nb.content_margin_right = 8
	nb.content_margin_top = 12
	nb.content_margin_bottom = 12
	nav_wrap.add_theme_stylebox_override("panel", nb)
	body_row.add_child(nav_wrap)
	_nav_box = VBoxContainer.new()
	_nav_box.add_theme_constant_override("separation", 2)
	nav_wrap.add_child(_nav_box)
	for item in NAV:
		var b := Button.new()
		b.text = String(item.label)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34.0 * AtcTheme.UI_SCALE)
		b.add_theme_font_override("font", AtcTheme.font(500))
		b.add_theme_font_size_override("font_size", AtcTheme.fs(14))
		b.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
		b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
		b.pressed.connect(_on_nav.bind(String(item.id)))
		_nav_box.add_child(b)
		_nav_buttons[String(item.id)] = b

	# 右侧内容
	var content_wrap := MarginContainer.new()
	content_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_wrap.add_theme_constant_override("margin_left", 18)
	content_wrap.add_theme_constant_override("margin_right", 18)
	content_wrap.add_theme_constant_override("margin_top", 14)
	content_wrap.add_theme_constant_override("margin_bottom", 10)
	body_row.add_child(content_wrap)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_wrap.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	# 底栏
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.custom_minimum_size = Vector2(0, 58.0 * AtcTheme.UI_SCALE)
	rootbox.add_child(foot)
	foot.add_child(_pad(18))
	var reset := UiKit.ghost("恢复默认设置")
	reset.pressed.connect(func() -> void: action.emit("reset"))
	foot.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var close_btn := UiKit.primary("关闭")
	close_btn.custom_minimum_size.x = 120.0 * AtcTheme.UI_SCALE
	close_btn.pressed.connect(close)
	foot.add_child(close_btn)
	foot.add_child(_pad(18))


# ---------------------------------------------------------------- 交互

func _on_nav(id: String) -> void:
	category = id
	_rebuild()


func _rebuild() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		c.queue_free()
	for id in _nav_buttons.keys():
		var b: Button = _nav_buttons[id]
		var on: bool = String(id) == category
		b.add_theme_color_override("font_color",
			AtcTheme.C_ACCENT if on else AtcTheme.C_TEXT_DIM)
		b.text = ("▸ " if on else "  ") + _nav_label(String(id))
	var titles := {"general": "常规", "dialog": "陆空对话", "voice": "语音", "about": "关于"}
	if _title != null:
		_title.text = String(titles.get(category, "设置"))
	match category:
		"general": _build_general()
		"dialog": _build_dialog()
		"voice": _build_voice()
		"about": _build_about()


func _build_general() -> void:
	_section("游戏进度")
	_action_row("保存游戏", "把当前进度存到存档槽", "save")
	_action_row("载入存档", "从存档槽恢复一局", "load")
	_action_row("继续游戏" if paused else "暂停游戏",
		"暂停时时钟与机组都不推进" if not paused else "当前已暂停",
		"pause")
	_section("离开")
	_action_row("返回主菜单", "当前进度会自动存档（有未存进度会先确认）", "exit")
	_section("窗口与显示")
	_hint("显示模式、窗口尺寸、显示器、置顶……在顶部「窗口」菜单里；"
		+ "面板布局与预设——也就是各块面板分别开关——在顶部「视图」菜单里。")


func _build_dialog() -> void:
	_section("陆空对话模式")
	_hint("决定你的通话怎么发出去。按 08 §6.2，模式在局中不可切换，"
		+ "这里改了只对下一局生效。")
	var cur := ""
	if desk != null:
		cur = desk.issue_mode
	for i in range(MODE_KEYS.size()):
		var key := String(MODE_KEYS[i])
		_radio_row(String(MODE_NAMES[i]), key == cur, "mode:" + key,
			"本局正在使用" if key == cur else "点一下改为下一局使用")
	_section("复诵核对难度")
	_hint("与对话模式互相独立：可以「说得简单、核对很严」。")
	var diff := "normal"
	if desk != null:
		diff = desk.difficulty
	for i in range(DIFF_KEYS.size()):
		var key2 := String(DIFF_KEYS[i])
		_radio_row(String(DIFF_NAMES[i]), key2 == diff, "diff:" + key2,
			"逐项核对" if key2 == "hard" else ("系统标出不一致项" if key2 == "easy" else "标准"))
	_section("练习辅助")
	_toggle_row("含错误候选", bool(desk != null and desk.candidate_error), "cand",
		"简易模式的候选里混入错误选项，练识别")


func _build_voice() -> void:
	_section("朗读与识别")
	var lib := VoiceLibrary.new()
	var ready := bool(lib.ready_for("controller") and lib.ready_for("pilot"))
	_toggle_row("语音播报（机组与管制发声）",
		desk != null and desk.speak_enabled, "speak",
		"打开后发许可会读出来、复诵到点也会读" if ready
			else "未生成片段库：先跑 tools/gen_voice.py")
	_action_row("试听音色", "按当前音色念一条放行许可", "demo")
	_action_row("语音辅助…", "转录显示、数值朗读、示例朗读、无障碍文本兜底", "aux")
	_section("识别引擎")
	var exe := VoiceAsr.exe_path()
	_hint(("识别助手已就绪：离线中文识别，闭集语法。") if FileAccess.file_exists(exe)
		else "未找到识别助手（tools/atc-listen/AtcListen.exe），真实语音模式用不了。")
	_hint("当前模式：" + (_mode_label() if desk != null else "—"))


func _build_about() -> void:
	_section("版本")
	_hint("管制模拟器 %s" % version_text)
	_section("这一版实现到哪")
	_hint("放行席完整可玩：进程单、计划审查、ATIS、放行许可三种发法（含真实语音）、"
		+ "复诵核对、离场情报、移交地面、运行品质评分。")
	_hint("AI 驾驶舱：定时申请、完整性质疑、错误注入、九态可见状态。")
	_hint("语音：闭集语法识别 + 片段拼装播报，全部离线。")
	_section("快捷键")
	_hint("Esc 打开/关闭设置　·　F1 教学提示　·　顶部菜单：视图 / 窗口")


# ---------------------------------------------------------------- 行构件

func _section(title: String) -> void:
	var l := _label(title, 12, 700, AtcTheme.C_TEXT_FAINT)
	l.custom_minimum_size = Vector2(0, 26.0 * AtcTheme.UI_SCALE)
	_body.add_child(l)


func _hint(text: String) -> void:
	var l := _label(text, 12, 400, AtcTheme.C_TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	_body.add_child(l)
	_body.add_child(_gap(4))


func _radio_row(text: String, on: bool, id: String, desc: String) -> void:
	var b := _row_button(("● " if on else "○ ") + text, on)
	b.pressed.connect(func() -> void: action.emit("pick:" + id))
	_body.add_child(b)
	if desc != "":
		_body.add_child(_sub(desc))


func _toggle_row(text: String, on: bool, id: String, desc: String) -> void:
	var b := _row_button(("☑ " if on else "☐ ") + text, on)
	b.pressed.connect(func() -> void: action.emit("toggle:" + id))
	_body.add_child(b)
	if desc != "":
		_body.add_child(_sub(desc))


func _action_row(text: String, desc: String, id: String) -> void:
	var b := _row_button(text, false)
	b.pressed.connect(func() -> void: action.emit(id))
	_body.add_child(b)
	if desc != "":
		_body.add_child(_sub(desc))


func _row_button(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	b.add_theme_color_override("font_color",
		AtcTheme.C_ACCENT if on else AtcTheme.C_TEXT_SOFT)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.03)
	n.border_color = Color(1, 1, 1, 0.07)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 12
	n.content_margin_right = 12
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("hover", h)
	return b


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150.0 * AtcTheme.UI_SCALE,
		32.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.05)
	n.border_color = Color(1, 1, 1, 0.12)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.10)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	return b


func _sub(text: String) -> Control:
	var l := _label(text, 11, 400, AtcTheme.C_TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 22)
	m.add_theme_constant_override("margin_bottom", 6)
	m.add_child(l)
	return m


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h * AtcTheme.UI_SCALE)
	return c


func _pad(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w * AtcTheme.UI_SCALE, 0)
	return c


func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", AtcTheme.font(weight))
	l.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	l.add_theme_color_override("font_color", color)
	return l


func _nav_label(id: String) -> String:
	for item in NAV:
		if String(item.id) == id:
			return String(item.label)
	return id


func _mode_label() -> String:
	var i := MODE_KEYS.find(String(desk.issue_mode))
	return String(MODE_NAMES[i]) if i >= 0 else String(desk.issue_mode)
