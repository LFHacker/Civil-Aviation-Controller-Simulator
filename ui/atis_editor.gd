## 通播编辑窗口（放行机制规范 §3.2）。
##
## 代号由系统按字母推进（玩家不能跳）；其余要素从"当前值 + 邻近值"里选 ——
## **允许选错**，选错就是"通播有误"，会一路传导到机组特情（§3.4）。
class_name AtisEditor
extends Control

signal published(alpha: String, has_error: bool)
signal closed

var desk: DeliveryDesk
## 仿真时钟，由放行面板每次写入
var now := 0.0

var _card: PanelContainer
var _title: Label
var _opts := {}
var _picks := {}
var _hazards := {}
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(760.0 * AtcTheme.UI_SCALE, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.050, 0.060, 0.995)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_card.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	_title = _label("编辑通播", 20, 700, AtcTheme.C_TEXT)
	head.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var cancel := _button("取消", AtcTheme.C_TEXT_DIM, 96.0)
	cancel.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(cancel)

	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.10)
	rule.custom_minimum_size = Vector2(0, 1)
	root.add_child(rule)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 8)
	root.add_child(_grid)

	_hint = _label("", 12, 500, AtcTheme.C_WARM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root.add_child(foot)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	_publish_btn = _button("发布通播", AtcTheme.C_ACCENT, 200.0)
	_publish_btn.pressed.connect(_on_publish)
	foot.add_child(_publish_btn)


var _grid: GridContainer
var _publish_btn: Button


func open(p_desk: DeliveryDesk, sim_time: float) -> void:
	desk = p_desk
	now = sim_time
	_opts = desk.atis_edit_options()
	_picks = {}
	_hazards = {}
	_rebuild()
	visible = true


func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_title.text = "编辑通播  %s → %s" % [desk.atis.alpha, String(_opts.alpha)]
	_publish_btn.text = "发布通播 %s" % String(_opts.alpha)

	_row_pick("runway", "使用跑道", _opts.runway, 0)
	_row_pick("transition_level", "过渡高度层", _opts.transition_level, 0)
	_row_pick("wind", "风向风速", _opts.wind, 0)
	_row_pick("visibility", "能见度", _opts.visibility, 0)
	_row_pick("qnh", "修正海压", _opts.qnh, 0)
	_row_pick("brake", "跑道刹车效应", _opts.brake, 0)

	_grid.add_child(_label("重要天气", 13, 500, AtcTheme.C_TEXT_DIM))
	var hz := HBoxContainer.new()
	hz.add_theme_constant_override("separation", 10)
	for h in _opts.hazards:
		var cb := CheckBox.new()
		cb.text = String(h)
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_override("font", AtcTheme.font(400))
		cb.add_theme_font_size_override("font_size", AtcTheme.fs(12))
		cb.add_theme_color_override("font_color", AtcTheme.C_TEXT_SOFT)
		cb.toggled.connect(func(on: bool) -> void: _hazards[String(h)] = on)
		hz.add_child(cb)
	_grid.add_child(hz)

	_hint.text = "代号由系统按字母推进，不能跳；其余要素从可选值里挑 —— 选错会变成「通播有误」，可能在机组那里出特情。"


## 一行"标签 + 下拉"。默认选第一项（= 当前实况值）。
func _row_pick(key: String, label: String, values: Array, default_index: int) -> void:
	_grid.add_child(_label(label, 13, 500, AtcTheme.C_TEXT_DIM))
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(360.0 * AtcTheme.UI_SCALE, 0)
	opt.add_theme_font_override("font", AtcTheme.font(400))
	opt.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	for v in values:
		opt.add_item(str(v))
	opt.selected = default_index
	_picks[key] = str(values[default_index])
	opt.item_selected.connect(func(i: int) -> void:
		_picks[key] = str(values[i]))
	_grid.add_child(opt)


func _on_publish() -> void:
	var opts := _picks.duplicate()
	var hz: Array = []
	for k in _hazards.keys():
		if bool(_hazards[k]):
			hz.append(k)
	opts["hazards"] = hz
	var r := desk.update_atis(opts, now)
	if not bool(r.ok):
		_hint.text = String(r.error)
		_hint.add_theme_color_override("font_color", AtcTheme.C_DANGER)
		return
	visible = false
	published.emit(String(r.get("alpha", "")), bool(r.get("has_error", false)))


func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", AtcTheme.font(weight))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	lb.add_theme_color_override("font_color", color)
	return lb


func _button(text: String, color: Color, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w * AtcTheme.UI_SCALE,
		38.0 * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_hover_color", color)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.06)
	n.border_color = Color(1, 1, 1, 0.16)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.13)
	h.border_color = color
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	return b
