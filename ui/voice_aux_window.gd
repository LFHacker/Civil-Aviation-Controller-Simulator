## 语音辅助设置窗口（08 §4.4 / §4.5）。
##
## 五项辅助功能都可开关，外加一个无障碍兜底（语音失败时允许文本输入）。
## 文档要求的是"帮助玩家组织和发音，**不替玩家填写内容**"，所以这里只有开关，
## 没有任何自动填入的东西。
class_name VoiceAuxWindow
extends Control

signal changed
signal closed

var desk: DeliveryDesk

var _rows := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func open(p_desk: DeliveryDesk) -> void:
	desk = p_desk
	_sync()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560.0 * AtcTheme.UI_SCALE, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.050, 0.060, 0.995)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	col.add_child(_label("语音辅助", 17, 700, AtcTheme.C_TEXT))
	col.add_child(_label(
		"这些只帮你听懂和发音，不替你填写任何内容。", 12, 400, AtcTheme.C_TEXT_DIM))
	col.add_child(_divider())

	_add_toggle(col, "transcript", "转录文本显示",
		"说话时实时显示识别出的文字，发送前可以核对")
	_add_toggle(col, "phrase_hint", "标准用语提示",
		"显示通话结构（不给具体数值）")
	_add_toggle(col, "reference", "参考面板",
		"保留天气与飞行计划卡片，方便自己查")
	_add_toggle(col, "read_numbers", "数值朗读辅助",
		"点击参考面板里的数值，读一遍标准读法（幺两洞洞）")
	_add_toggle(col, "read_template", "通话模板朗读",
		"可以点「听示例」听一条标准通话，只示范、不发送")

	col.add_child(_divider())
	_add_toggle(col, "text_fallback", "语音失败时允许文本输入",
		"无障碍选项。默认关闭：高级模式要求必须用语音说完", true)

	col.add_child(_divider())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(120.0 * AtcTheme.UI_SCALE,
		34.0 * AtcTheme.UI_SCALE)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	foot.add_child(close_btn)
	var note := _label("设置会随档保存，下一局沿用", 11, 400, AtcTheme.C_TEXT_FAINT)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(note)


func _add_toggle(col: VBoxContainer, key: String, title: String,
		desc: String, is_fallback: bool = false) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 32.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
	b.add_theme_color_override("font_hover_color", AtcTheme.C_TEXT)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.03)
	n.border_color = Color(1, 1, 1, 0.08)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 12
	n.content_margin_right = 12
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("hover", h)
	b.pressed.connect(_on_toggle.bind(key, is_fallback))
	col.add_child(b)
	col.add_child(_label(desc, 11, 400, AtcTheme.C_TEXT_FAINT))
	_rows[key] = b


func _on_toggle(key: String, is_fallback: bool) -> void:
	if desk == null:
		return
	if is_fallback:
		desk.allow_text_fallback = not desk.allow_text_fallback
	else:
		var cur := VoiceMode.aux_enabled(desk.voice_aux, key)
		desk.voice_aux[key] = not cur
	_sync()
	changed.emit()


## 按钮文字跟着当前值走：☑/☐ + 标题
func _sync() -> void:
	if desk == null:
		return
	var titles := {
		"transcript": "转录文本显示",
		"phrase_hint": "标准用语提示",
		"reference": "参考面板",
		"read_numbers": "数值朗读辅助",
		"read_template": "通话模板朗读",
	}
	for key in titles.keys():
		if not _rows.has(key):
			continue
		var on := VoiceMode.aux_enabled(desk.voice_aux, key)
		_rows[key].text = ("☑ " if on else "☐ ") + String(titles[key])
	if _rows.has("text_fallback"):
		_rows["text_fallback"].text = \
			("☑ " if desk.allow_text_fallback else "☐ ") + "语音失败时允许文本输入"


func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", AtcTheme.font(weight))
	l.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	l.add_theme_color_override("font_color", color)
	return l


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.10)
	d.custom_minimum_size = Vector2(0, 1)
	return d
