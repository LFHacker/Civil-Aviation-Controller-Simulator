## 进入游戏的加载页。
##
## 纯表现层：自己不含任何进度造假逻辑——进度由 main.gd 按真实步骤喂进来。
## 每步之间会有一小段停顿（仅仅是让进度条可读），真实工作在 step 回调里完成。
class_name LoadingScreen
extends CanvasLayer

const TIPS := [
	"管制许可的顺序是有讲究的：先跑道，后高度，最后是应答机。",
	"复诵不完整就是许可没给到——让对方重述。",
	"五边上的飞机最需要你；它没有第二次机会。",
	"跑道占用期间，任何穿越许可都要先问一句「确认跑道已空」。",
	"速度控制在进近末段比航向更管用。",
	"冲突往往是两架飞机都在做「对的事」。",
]

var _root: Control
var _mode_label: Label
var _seat_label: Label
var _airport_label: Label
var _bar: ProgressBar
var _step_label: Label
var _tip_label: Label
var _radar: RadarSweep

var _tip_index := 0
var _tip_timer := 0.0
var _ratio := 0.0


func _ready() -> void:
	layer = 30
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color("0a0e11")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	_build_left()
	_build_radar()

	_root.visible = false


func _build_left() -> void:
	var col := VBoxContainer.new()
	col.anchor_left = 0.072
	col.anchor_top = 0.30
	col.anchor_right = 0.56
	col.anchor_bottom = 0.62
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)

	var tag := Label.new()
	tag.text = "AIR  TRAFFIC  CONTROL  SIMULATOR"
	tag.add_theme_font_override("font", AtcTheme.font(500))
	tag.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	tag.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
	col.add_child(tag)

	col.add_child(_spacer(16))

	_mode_label = Label.new()
	_mode_label.add_theme_font_override("font", AtcTheme.font(700))
	_mode_label.add_theme_font_size_override("font_size", AtcTheme.fs(18))
	_mode_label.add_theme_color_override("font_color", AtcTheme.C_ACCENT)
	col.add_child(_mode_label)

	_seat_label = Label.new()
	_seat_label.add_theme_font_override("font", AtcTheme.font(700))
	_seat_label.add_theme_font_size_override("font_size", AtcTheme.fs(62))
	_seat_label.add_theme_color_override("font_color", AtcTheme.C_TEXT)
	col.add_child(_seat_label)

	col.add_child(_spacer(10))

	_airport_label = Label.new()
	_airport_label.add_theme_font_override("font", AtcTheme.font(400))
	_airport_label.add_theme_font_size_override("font_size", AtcTheme.fs(16))
	_airport_label.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	col.add_child(_airport_label)

	# 进度条
	var bar_wrap := VBoxContainer.new()
	bar_wrap.anchor_left = 0.072
	bar_wrap.anchor_top = 0.685
	bar_wrap.anchor_right = 0.56
	bar_wrap.anchor_bottom = 0.80
	bar_wrap.add_theme_constant_override("separation", 10)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar_wrap)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.show_percentage = false
	_bar.value = 0.0

	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.10)
	track.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = AtcTheme.C_ACCENT
	fill.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("fill", fill)
	bar_wrap.add_child(_bar)

	_step_label = Label.new()
	_step_label.text = "准备中…"
	_step_label.add_theme_font_override("font", AtcTheme.font(400))
	_step_label.add_theme_font_size_override("font_size", AtcTheme.fs(15))
	_step_label.add_theme_color_override("font_color", AtcTheme.C_TEXT_DIM)
	bar_wrap.add_child(_step_label)

	# 底部小贴士
	_tip_label = Label.new()
	_tip_label.anchor_left = 0.072
	_tip_label.anchor_right = 0.78
	_tip_label.anchor_top = 0.895
	_tip_label.anchor_bottom = 0.935
	_tip_label.add_theme_font_override("font", AtcTheme.font(400))
	_tip_label.add_theme_font_size_override("font_size", AtcTheme.fs(14))
	_tip_label.add_theme_color_override("font_color", AtcTheme.C_TEXT_FAINT)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tip_label)


func _build_radar() -> void:
	_radar = RadarSweep.new()
	_radar.name = "Radar"
	_radar.anchor_left = 0.67
	_radar.anchor_right = 0.94
	_radar.anchor_top = 0.24
	_radar.anchor_bottom = 0.76
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_radar)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ---------------------------------------------------------------- 对外

## 显示加载页。
func begin(mode_text: String, seat_text: String, airport_line: String) -> void:
	_mode_label.text = mode_text
	_mode_label.add_theme_color_override("font_color",
		AtcTheme.C_WARM if mode_text == "训练" else AtcTheme.C_ACCENT)
	_seat_label.text = seat_text
	_airport_label.text = airport_line
	_bar.value = 0.0
	_step_label.text = "准备中…"
	_tip_index = 0
	_tip_timer = 0.0
	_tip_label.text = TIPS[0]
	_root.modulate = Color(1, 1, 1, 1)
	_root.visible = true


## 推进到某一步。ratio 取 0..1。
func set_step(text: String, ratio: float) -> void:
	_step_label.text = text
	_ratio = clampf(ratio, 0.0, 1.0)
	var tw := create_tween()
	tw.tween_property(_bar, "value", _ratio * 100.0, 0.18)


## 机场数据载入后补上更详细的副标题（一开始只知道机场代码）。
func set_airport_line(text: String) -> void:
	_airport_label.text = text


## 收起加载页（淡出）。调用方 await 它，切场才连贯。
func finish() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.34)
	await tw.finished
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_tip_timer += delta
	if _tip_timer >= 2.4 and TIPS.size() > 1:
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip_label.text = TIPS[_tip_index]


# ---------------------------------------------------------------- 雷达

## 一个纯粹为了气氛的扫描雷达：同心圆 + 旋转扫掠 + 几个固定目标点。
class RadarSweep extends Control:
	var _angle := 0.0
	var _blips: Array = []

	func _ready() -> void:
		# 用固定角度摆放几个"目标"，避免每帧随机闪烁
		_blips = [
			[0.4, 0.62], [1.9, 0.34], [3.4, 0.78], [4.7, 0.48], [5.6, 0.26],
		]

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_angle = fmod(_angle + delta * 0.9, TAU)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 6.0
		if r <= 4.0:
			return

		for i in range(3):
			draw_arc(c, r * (0.36 + i * 0.32), 0.0, TAU, 72,
				Color(0.37, 0.92, 0.83, 0.11), 1.0)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.06), 1.0)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(1, 1, 1, 0.06), 1.0)

		# 扫掠尾迹
		for k in range(20):
			var a: float = _angle - k * 0.05
			var alpha: float = 0.32 * (1.0 - float(k) / 20.0)
			draw_line(c, c + Vector2(cos(a), sin(a)) * r,
				Color(0.37, 0.92, 0.83, alpha), 1.6)

		# 目标点：扫过时才亮
		for b in _blips:
			var ang: float = float(b[0])
			var rr: float = r * float(b[1])
			var delta_a: float = absf(wrapf(_angle - ang, -PI, PI))
			var bright: float = clampf(1.0 - delta_a / 1.2, 0.18, 1.0)
			var p := c + Vector2(cos(ang), sin(ang)) * rr
			draw_circle(p, 2.6, Color(0.37, 0.92, 0.83, 0.35 + bright * 0.6))
