## 离线截图工具：把某个界面渲染出来存成 PNG，供开发时核对布局。
##
## 为什么需要它：桌面被别人占用时（MCP 返回 USER_CONTROL）截不到图，
## 只能靠猜布局——这一轮就是这么改错的。让 Godot 自己渲染、自己存图，
## 不依赖桌面控制，也能反复对比改动前后的效果。
##
## 运行（必须**窗口**模式，headless 没有渲染器）：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程> --script res://tools/shot.gd -- delivery
##   ... --script res://tools/shot.gd -- settings
##   ... --script res://tools/shot.gd -- seat
##
## 输出：user://shots/<scene>.png（同时打印绝对路径）
extends SceneTree

var _scene := "delivery"
var _frames := 0
var _panel: Control
var _desk: DeliveryDesk


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		_scene = String(argv[0])
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# 注意：在 _initialize 里 add_child 之后 _ready 还没跑（要等下一帧），
	# 所以界面放到 _process 的第一帧再建，否则 open() 会撞上未初始化的子控件。
	pass


func _build_placeholder(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(40, 40)
	root.add_child(l)


func _demo_desk() -> DeliveryDesk:
	var d := DeliveryDesk.new()
	d.setup(2718)
	d.field = {
		"runway": "18", "wind": "18005MPS", "visibility": "CAVOK", "qnh": 1013,
		"atis_alpha": "A", "dep_freq": "119.000", "ground_freq": "121.750",
		"clock_start": "0800", "airport_id": "ZDEM",
	}
	d.review_ref = {"types": {}, "alternates": [], "routes": {}, "loa": []}
	d.difficulty = "normal"
	d.issue_mode = "voice"
	# 与 GameSession.apply_airport 保持一致，否则截图里会少掉一半按钮
	d.enable_atis_check = true
	d.enable_strip_check = true
	d.enable_plan_review = true
	d.enable_qnh_gate = true
	d.enable_value_check = true
	d.enable_atis_lifecycle = true
	d.enable_handoff_check = true
	d.enable_dep_info = true
	d.pilot_check_enabled = true
	# 和真实开局一致：灌当日计划，按 07 §2.2 的时刻只放"已经到点"的航班
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/airports/demo.json"))
	if data is Dictionary:
		d.set_plan((data as Dictionary).get("schedule", []))
	d.seed_due(0.0)
	for f in d.flights:
		f.checked = true
		f.atis_ok = true
	return d


func _dump_tree(n: Node, depth: int) -> void:
	if depth > 5 or n == null:
		return
	var c := n as Control
	if c != null:
		print("%s%s[%s] vis=%s size=%s kids=%d" % ["  ".repeat(depth), n.name,
			n.get_class(), str(c.visible), str(c.size), n.get_child_count()])
	for ch in n.get_children():
		_dump_tree(ch, depth + 1)


func _mount_delivery_panel() -> void:
	_panel = DeliveryPanel.new()
	_panel.name = "DeliveryPanel"
	root.add_child(_panel)
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/airports/demo.json"))
	if data is Dictionary:
		_panel.call("set_airport", data)
	_panel.call("open", _desk)


func _build_delivery() -> void:
	_desk = _demo_desk()
	_mount_delivery_panel()


## 复诵待确认状态（07 §九的"复诵有误"按钮就在这张卡上）：
## 发一份许可、强制读错一项、把时钟推到复诵到达之后。
func _build_readback() -> void:
	_desk = _demo_desk()
	# 这两道闸门会拦住发放行（QNH 未确认 / 通播过期），截图只关心复诵卡片，先放开
	_desk.enable_qnh_gate = false
	_desk.enable_atis_lifecycle = false
	if not _desk.flights.is_empty():
		var f: Flight = _desk.flights[0]
		var r := _desk.issue_clearance(f.callsign, f.sid, f.initial_alt_m, f.squawk, 0.0)
		if not bool(r.ok):
			print("!! 发许可失败：" + String(r.error))
		_desk.force_error_next = true
		_desk.tick(f.readback_at + 0.1)
		print("!! state=" + str(f.state) + " items=" + str(f.readback_items.size()))
	_mount_delivery_panel()


func _build_settings() -> void:
	_desk = _demo_desk()
	var w := SettingsWindow.new()
	w.version_text = AtcVersion.display()
	w.desk = _desk
	w.category = "dialog"
	root.add_child(w)
	w.open()


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 1:
		match _scene:
			"delivery": _build_delivery()
			"readback": _build_readback()
			"settings": _build_settings()
			"seat": _build_placeholder("席位选择（未接入截图）")
			_: _build_delivery()
		return false
	if _frames == 13:
		_dump_tree(_panel, 0)
	if _frames < 14:
		return false
	var img := root.get_texture().get_image()
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(_scene + ".png")
	img.save_png(path)
	print("SHOT:" + ProjectSettings.globalize_path(path))
	quit(0)
	return true
