## 统一的按钮与排版构件（全游戏共用一套视觉层级）。
##
## 之前每个界面各写一套按钮样式：同一条右栏里十几个按钮全是 38 px 全宽同色，
## 主操作和"整理进程单"看起来一样重，找不着重点；不同界面之间高度、圆角、
## 间距也各不相同。这里把层级固定成四档，界面只负责选档，不再自己调像素。
##
##   主操作 primary   38 px  强调色底 + 强调色描边   —— 一个区域只放一个
##   次操作 secondary 32 px  浅底 + 灰描边          —— 与主操作同排或紧随其后
##   行内 ghost       26 px  无底，只在悬停时亮      —— 整理、切换、辅助
##   危险 danger      32 px  红系，用于"返回/放弃"
##
## 尺寸都用 AtcTheme.UI_SCALE 缩放，跟着全局界面缩走。
class_name UiKit
extends RefCounted

const H_PRIMARY := 38.0
const H_SECONDARY := 32.0
const H_GHOST := 26.0
const GAP_ROW := 8.0
const GAP_BLOCK := 14.0


# ---------------------------------------------------------------- 按钮

static func primary(text: String) -> Button:
	var b := _base(text, H_PRIMARY, 15, AtcTheme.C_ACCENT)
	_fill(b, AtcTheme.C_ACCENT, 0.20, 0.90, 2)
	return b


static func secondary(text: String) -> Button:
	var b := _base(text, H_SECONDARY, 14, AtcTheme.C_TEXT)
	_fill(b, Color(1, 1, 1, 1), 0.05, 0.16, 1)
	return b


## 暖色次操作：需要"请注意"的次要动作（重发、要求收听、通报变化…）
static func warm(text: String) -> Button:
	var b := _base(text, H_SECONDARY, 14, AtcTheme.C_WARM)
	_fill(b, AtcTheme.C_WARM, 0.12, 0.55, 1)
	return b


static func ghost(text: String) -> Button:
	var b := _base(text, H_GHOST, 13, AtcTheme.C_TEXT_DIM)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0)
	n.set_corner_radius_all(3)
	n.content_margin_left = 8
	n.content_margin_right = 8
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	return b


static func danger(text: String) -> Button:
	var b := _base(text, H_SECONDARY, 14, AtcTheme.C_DANGER)
	_fill(b, AtcTheme.C_DANGER, 0.14, 0.55, 1)
	return b


## 按语义色挑档：强调色→主操作，暖色→暖次操作，其余→次操作
static func by_color(text: String, color: Color) -> Button:
	if color == AtcTheme.C_ACCENT or color == AtcTheme.C_ACCENT_DIM:
		return primary(text)
	if color == AtcTheme.C_WARM:
		return warm(text)
	if color == AtcTheme.C_DANGER:
		return danger(text)
	return secondary(text)


# ---------------------------------------------------------------- 布局

## 一行等宽按钮：传几个按钮就把一行均分几份
static func equal_row(parent: Node, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP_ROW * AtcTheme.UI_SCALE))
	parent.add_child(row)
	for b in buttons:
		var btn: Control = b
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(btn)
	return row


static func vbox(gap: float = GAP_ROW) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", int(gap * AtcTheme.UI_SCALE))
	return c


static func hbox(gap: float = GAP_ROW) -> HBoxContainer:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", int(gap * AtcTheme.UI_SCALE))
	return c


static func spacer_h() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func expand(b: Control) -> Control:
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


static func fixed(b: Control, width: float) -> Control:
	b.custom_minimum_size = Vector2(width * AtcTheme.UI_SCALE,
		b.custom_minimum_size.y)
	return b


# ---------------------------------------------------------------- 内部

static func _base(text: String, height: float, font: int, hover: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height * AtcTheme.UI_SCALE)
	b.add_theme_font_override("font", AtcTheme.font(500))
	b.add_theme_font_size_override("font_size", AtcTheme.fs(font))
	b.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	b.add_theme_color_override("font_hover_color", hover)
	return b


static func _fill(b: Button, tint: Color, bg_a: float, border_a: float,
		border_px: int) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(tint.r, tint.g, tint.b, bg_a)
	n.border_color = Color(tint.r, tint.g, tint.b, border_a)
	n.set_border_width_all(border_px)
	n.set_corner_radius_all(3)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", n)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(tint.r, tint.g, tint.b, minf(bg_a + 0.10, 0.42))
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(tint.r, tint.g, tint.b, bg_a * 0.4)
	d.border_color = Color(tint.r, tint.g, tint.b, border_a * 0.4)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_disabled_color", AtcTheme.C_TEXT_FAINT)
