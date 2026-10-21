## 席位顶部的数据标签栏：机场 / 天气 / 停机位 / 当日计划 / 滑行道 / 通波。
##
## 只读展示层：所有数字都来自机场数据或 DeliveryDesk，不在这里算业务结果。
## 「机场」页放的就是场面监视图本身，切走再切回来状态不丢。
class_name InfoTabs
extends VBoxContainer

const TABS := [
	{"id": "airport", "label": "机场"},
	{"id": "weather", "label": "天气"},
	{"id": "stand", "label": "停机位"},
	{"id": "plan", "label": "当日计划"},
	{"id": "taxiway", "label": "滑行道"},
	{"id": "atis", "label": "通波"},
]

const C_HEAD := Color(0.37, 0.92, 0.83, 1.0)
const C_ROW := Color(1, 1, 1, 0.045)
const C_ROW_ALT := Color(1, 1, 1, 0.018)

var desk: DeliveryDesk
var airport: Dictionary = {}
var now := 0.0

var _bar: HBoxContainer
var _frame: PanelContainer
var _stack: Control
var _buttons: Dictionary = {}
var _pages: Dictionary = {}
var _current := "airport"
var _clock_minute := -1


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build_stack()
	# 调试/截图用：--info-tab=weather 直接落在某一页
	var start := "airport"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--info-tab="):
			start = arg.substr(11)
	set_current(start)


## 标签栏由外部（会话顶部状态条的正中央）挂载，不再占中间显示面板的高度。
func attach_bar(host: Control) -> void:
	_build_bar(host)


# ---------------------------------------------------------------- 外框

func _build_bar(host: Control) -> void:
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 2)
	_bar.custom_minimum_size = Vector2(0, 34.0 * AtcTheme.UI_SCALE)
	host.add_child(_bar)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for t in TABS:
		var b := Button.new()
		b.text = String(t.label)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", AtcTheme.font(500))
		b.add_theme_font_size_override("font_size", AtcTheme.fs(14))
		b.custom_minimum_size = Vector2(72.0 * AtcTheme.UI_SCALE, 34.0 * AtcTheme.UI_SCALE)
		b.pressed.connect(_on_tab_pressed.bind(String(t.id)))
		_bar.add_child(b)
		_buttons[String(t.id)] = b
	_bar.add_child(spacer)


func _build_stack() -> void:
	_frame = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("070c10")
	sb.border_color = Color(0.37, 0.92, 0.83, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_frame)

	_stack = Control.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.clip_contents = true
	_frame.add_child(_stack)

	for t in TABS:
		var p := Control.new()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.visible = false
		_stack.add_child(p)
		_pages[String(t.id)] = p


## 把场面监视图放进「机场」页。
func attach_display(display: Control) -> void:
	var page: Control = _pages["airport"]
	page.add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_context(p_desk: DeliveryDesk, p_airport: Dictionary) -> void:
	desk = p_desk
	airport = p_airport
	refresh()


# ---------------------------------------------------------------- 切换

func current_page() -> String:
	return _current


func _on_tab_pressed(id: String) -> void:
	set_current(id)


func set_current(id: String) -> void:
	if not _pages.has(id):
		return
	_current = id
	for k in _pages.keys():
		(_pages[k] as Control).visible = (k == id)
	for k in _buttons.keys():
		_style_tab(_buttons[k] as Button, k == id)
	refresh()


func _style_tab(b: Button, active: bool) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.37, 0.92, 0.83, 0.10) if active else Color(1, 1, 1, 0.03)
	n.border_color = C_HEAD if active else Color(1, 1, 1, 0.07)
	n.border_width_bottom = 2 if active else 1
	n.border_width_top = 1 if active else 1
	n.border_width_left = 1
	n.border_width_right = 1
	n.set_corner_radius_all(2)
	n.content_margin_left = 10
	n.content_margin_right = 10
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", n)

	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.37, 0.92, 0.83, 0.16)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", C_HEAD if active else AtcTheme.C_TEXT_SOFT)


# ---------------------------------------------------------------- 刷新

func tick(sim_time: float) -> void:
	now = sim_time
	# 通播/天气里有时间码，跨分钟才重画，别每帧重建控件
	var minute := Atis.minutes_since(str(airport.get("clock_start", "0000")), sim_time)
	if minute != _clock_minute:
		_clock_minute = minute
		if _current == "weather" or _current == "atis":
			refresh()


func refresh() -> void:
	if _current == "airport":
		return
	var page: Control = _pages[_current]
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	if _current == "weather":
		_build_weather(col)
	elif _current == "stand":
		_build_stands(col)
	elif _current == "plan":
		_build_plan(col)
	elif _current == "taxiway":
		_build_taxiways(col)
	elif _current == "atis":
		_build_atis(col)


# ---------------------------------------------------------------- 天气

func _build_weather(col: VBoxContainer) -> void:
	var wx: Variant = airport.get("weather", {})
	var w: Dictionary = wx if wx is Dictionary else {}
	var clock := Atis.clock_text(str(airport.get("clock_start", "0000")), now)

	col.add_child(_section("地面观测  SURFACE OBSERVATION"))
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", 6)
	col.add_child(kv)
	_kv(kv, "观测时刻", clock)
	_kv(kv, "风向风速", str(w.get("wind", "--")))
	_kv(kv, "能见度", str(w.get("visibility", "--")))
	_kv(kv, "温度", "%s °C" % str(w.get("temperature_c", "--")))
	_kv(kv, "修正海压", "%s hPa" % str(w.get("qnh_hpa", "--")))

	col.add_child(_gap(6))
	col.add_child(_section("跑道风分量  RUNWAY WIND"))
	var wind_raw := str(w.get("wind", ""))
	var rows: Array = []
	var runways: Variant = airport.get("runways", [])
	if runways is Array:
		for r in runways:
			if not (r is Dictionary):
				continue
			var head := float((r as Dictionary).get("heading_deg", 0))
			var c := Meteo.runway_wind(wind_raw, head)
			var head_text := "--"
			var cross_text := "--"
			if bool(c.get("ok", false)):
				var hw := float(c.get("headwind", 0.0))
				var xw := float(c.get("crosswind", 0.0))
				head_text = ("顶风 %.1f" % hw) if hw >= 0.0 else ("顺风 %.1f" % absf(hw))
				cross_text = ("右 %.1f" % xw) if xw >= 0.0 else ("左 %.1f" % absf(xw))
			elif bool(c.get("variable", false)):
				head_text = "风向不定"
			rows.append(["跑道 " + str((r as Dictionary).get("id", "?")), head_text, cross_text])
	col.add_child(_table(["跑道", "顶风/顺风", "侧风"], [210, 210, 160], rows))
	col.add_child(_note("单位 m/s。侧风「右/左」指风从跑道右侧或左侧来。"))

	if rows.is_empty():
		col.add_child(_note("机场数据里没有跑道信息。"))


# ---------------------------------------------------------------- 停机位

func _build_stands(col: VBoxContainer) -> void:
	var occupancy := _stand_occupancy()
	var near_total := 18
	var far_total := 6
	var near_used := 0
	var far_used := 0
	for i in range(1, 25):
		if occupancy.has("A%02d" % i):
			if i <= 18:
				near_used += 1
			else:
				far_used += 1

	col.add_child(_section("机位占用  STAND OCCUPANCY"))
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 26)
	col.add_child(summary)
	summary.add_child(_stat("近机位", "%d / %d" % [near_used, near_total], " A01–A18"))
	summary.add_child(_stat("远机位", "%d / %d" % [far_used, far_total], " A19–A24"))
	summary.add_child(_stat("机位总数", "%d" % (near_total + far_total), ""))

	col.add_child(_gap(4))
	var rows: Array = []
	for i in range(1, 25):
		var id := "A%02d" % i
		var cls := "近机位" if i <= 18 else "远机位"
		var occ := String(occupancy.get(id, ""))
		var state := "占用" if occ != "" else "空闲"
		rows.append([id, cls, state, occ if occ != "" else "—"])
	col.add_child(_table(["机位", "类别", "状态", "占用航班"], [130, 150, 130, 200], rows,
		func(r: Array, idx: int) -> Color:
			return AtcTheme.C_WARM if String(r[2]) == "占用" else AtcTheme.C_TEXT_SOFT))
	col.add_child(_note("机位在航班级只能看到一个占用者；地面席位接入后会显示机型/占用时长。"))


## 机位 → 呼号
func _stand_occupancy() -> Dictionary:
	var out := {}
	if desk == null:
		return out
	for f in desk.flights:
		if (f as Flight).is_done():
			continue
		out[(f as Flight).stand] = (f as Flight).callsign
	return out


# ---------------------------------------------------------------- 当日计划

func _build_plan(col: VBoxContainer) -> void:
	var clock := Atis.clock_text(str(airport.get("clock_start", "0000")), now)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var t := _label("当日飞行计划  DAY PLAN", 15, 700, C_HEAD)
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("当前时刻 %s" % clock, 13, 500, AtcTheme.C_TEXT_DIM))

	if desk == null or desk.plan.is_empty():
		col.add_child(_note("机场数据里没有当日计划（data/airports/*.json 的 schedule）。"))
		return

	var status := {}
	for f in desk.flights:
		var fl := f as Flight
		status[fl.callsign] = fl

	var rows: Array = []
	for e in desk.plan:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var cs := str(d.get("callsign", ""))
		var st := "计划"
		var color := AtcTheme.C_TEXT_FAINT
		if status.has(cs):
			var fl: Flight = status[cs]
			st = fl.state_text()
			color = AtcTheme.C_ACCENT if fl.state == Flight.State.CLEARED else AtcTheme.C_WARM
		rows.append([str(d.get("std", "--")), cs, str(d.get("type", "")),
			str(d.get("dest", "")), str(d.get("stand", "")), str(d.get("sid", "")), st])
	col.add_child(_table(["计划", "呼号", "机型", "目的地", "机位", "离场程序", "状态"],
		[80, 140, 90, 110, 80, 150, 110], rows,
		func(r: Array, idx: int) -> Color:
			var v := String(r[6])
			if v == "已放行":
				return AtcTheme.C_ACCENT
			if v == "计划":
				return AtcTheme.C_TEXT_FAINT
			return AtcTheme.C_WARM))

	var remain := desk.plan.size() - desk.plan_index
	col.add_child(_note("共 %d 条计划，已进入放行流程 %d 条，余 %d 条。计划用完后来机按随机生成。" % [
		desk.plan.size(), desk.plan_index, maxi(0, remain)]))


# ---------------------------------------------------------------- 滑行道

func _build_taxiways(col: VBoxContainer) -> void:
	var rwy := AirportData.primary_runway(airport)

	col.add_child(_section("跑道运行  RUNWAY"))
	var rkv := VBoxContainer.new()
	rkv.add_theme_constant_override("separation", 6)
	col.add_child(rkv)
	_kv(rkv, "使用跑道", rwy)
	var runways: Variant = airport.get("runways", [])
	if runways is Array:
		for r in runways:
			if not (r is Dictionary):
				continue
			var d: Dictionary = r
			var ils := "有 ILS" if bool(d.get("ils", false)) else "无 ILS"
			_kv(rkv, "跑道 %s" % str(d.get("id", "?")),
				"%d × %d m  %s" % [int(d.get("length_m", 0)), int(d.get("width_m", 0)), ils])

	col.add_child(_gap(6))
	col.add_child(_section("滑行道状态  TAXIWAY STATUS"))
	var txy: Variant = airport.get("taxiways", [])
	if not (txy is Array) or (txy as Array).is_empty():
		col.add_child(_note("机场数据里没有滑行道清单。"))
		return
	var rows: Array = []
	for e in txy:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var w := int(d.get("width_m", 0))
		rows.append([str(d.get("id", "")), str(d.get("name", "")),
			("%d m" % w) if w > 0 else "—",
			str(d.get("status", "—")), str(d.get("remark", ""))])
	col.add_child(_table(["编号", "名称", "宽度", "状态", "备注"],
		[80, 190, 90, 90, 340], rows,
		func(r: Array, idx: int) -> Color:
			return AtcTheme.C_ACCENT_DIM if String(r[3]) == "开放" else AtcTheme.C_DANGER))


# ---------------------------------------------------------------- 通波

func _build_atis(col: VBoxContainer) -> void:
	var alpha := Atis.alpha_of(airport)
	col.add_child(_section("当前通播  ATIS %s" % alpha))
	col.add_child(_note("通播内容由机场实时气象生成，与「天气」页同源。"))

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.border_color = Color(0.37, 0.92, 0.83, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)
	col.add_child(card)

	var text := _label(Atis.compose(airport, now), 16, 400, AtcTheme.C_TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(text)

	col.add_child(_note("本席位 121.950 MHz。机组首次联络时若未报告已收到通播，应要求其先收听。"))


# ---------------------------------------------------------------- 控件工具

func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", AtcTheme.font(weight))
	lb.add_theme_font_size_override("font_size", AtcTheme.fs(size))
	lb.add_theme_color_override("font_color", color)
	return lb


func _section(title: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lb := _label(title, 12, 700, C_HEAD)
	row.add_child(lb)
	var line := ColorRect.new()
	line.color = Color(0.37, 0.92, 0.83, 0.22)
	line.custom_minimum_size = Vector2(0, 1)
	row.add_child(line)
	return row


func _kv(parent: VBoxContainer, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var k := _label(key, 14, 400, AtcTheme.C_TEXT_FAINT)
	k.custom_minimum_size = Vector2(110.0 * AtcTheme.UI_SCALE, 0)
	row.add_child(k)
	row.add_child(_label(value, 15, 600, AtcTheme.C_TEXT))
	parent.add_child(row)


func _stat(name: String, value: String, suffix: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label(name, 13, 400, AtcTheme.C_TEXT_FAINT))
	row.add_child(_label(value, 22, 700, C_HEAD))
	if suffix != "":
		row.add_child(_label(suffix, 12, 400, AtcTheme.C_TEXT_FAINT))
	return row


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _note(text: String) -> Label:
	var lb := _label(text, 12, 400, AtcTheme.C_TEXT_FAINT)
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lb


## 表格：表头 + 数据行；行可以点，用来把航班选回机场页。
func _table(headers: Array, widths: Array, rows: Array, color_of: Callable = Callable()) -> Control:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 0)

	for i in range(headers.size()):
		var h := _cell_header(String(headers[i]), int(widths[i]))
		grid.add_child(h)

	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(headers.size()):
			var text: String = String(row[c]) if c < row.size() else ""
			var color := AtcTheme.C_TEXT_SOFT
			if color_of.is_valid():
				var res: Variant = color_of.call(row, r)
				if res is Color:
					color = res
			grid.add_child(_cell_body(text, int(widths[c]), color, r % 2 == 1))

	return grid


func _cell_header(text: String, width: int) -> Control:
	var lb := _label(text, 12, 700, AtcTheme.C_TEXT_FAINT)
	lb.custom_minimum_size = Vector2(width, 26)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lb


func _cell_body(text: String, width: int, color: Color, alt: bool) -> Control:
	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ROW_ALT if alt else C_ROW
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	cell.add_theme_stylebox_override("panel", sb)
	cell.custom_minimum_size = Vector2(width, 0)

	var lb := _label(text, 14, 500, color)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.clip_text = true
	cell.add_child(lb)
	return cell
