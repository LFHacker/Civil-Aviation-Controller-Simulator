## 视图状态（面板显隐 + 布局预设）测试，无头可跑。
##
## 重点：**关掉最后一个主面板必须被拦住** —— 否则席位会变成一片空白，
## 而且这个 bug 在界面上表现为"点了没反应"，很难猜。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_view.gd
extends SceneTree

var _checks := 0
var _fails := 0

const TMP := "user://test_view_settings.cfg"


func _initialize() -> void:
	print("")
	print("════════ 视图状态测试 ════════")
	_test_defaults()
	_test_roundtrip()
	_test_corrupt()
	_test_last_main_panel()
	_test_presets()
	_test_helpers()
	_cleanup()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _cleanup() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _test_defaults() -> void:
	_section("默认值")
	_cleanup()
	var d := ViewState.load_settings(TMP)
	var all_on := true
	for id in ViewState.panel_ids():
		if not bool(d[String(id)]):
			all_on = false
	_check(all_on, "默认全部面板显示")
	_check(ViewState.hidden_count(d) == 0, "默认隐藏数为 0",
		str(ViewState.hidden_count(d)))
	_check(ViewState.defaults().size() == ViewState.PANELS.size(), "默认项数与面板表一致",
		"%d vs %d" % [ViewState.defaults().size(), ViewState.PANELS.size()])


func _test_roundtrip() -> void:
	_section("存取往返")
	var d := ViewState.defaults()
	d["radio"] = false
	d["seat"] = false
	_check(ViewState.save_settings(d, TMP), "保存成功")

	var back := ViewState.load_settings(TMP)
	_check(not bool(back["radio"]), "隐藏状态被记住（radio）")
	_check(not bool(back["seat"]), "隐藏状态被记住（seat）")
	_check(bool(back["center"]), "没动过的面板仍然是开")

	# 覆盖写
	var d2 := ViewState.defaults()
	d2["tabs"] = false
	ViewState.save_settings(d2, TMP)
	var back2 := ViewState.load_settings(TMP)
	_check(not bool(back2["tabs"]), "覆盖写生效（tabs 关）")
	_check(bool(back2["radio"]), "覆盖写清掉上一次的 radio=off")


func _test_corrupt() -> void:
	_section("配置坏掉时退回默认")

	# 1) 文件压根不存在
	_cleanup()
	var d := ViewState.load_settings(TMP)
	_check(bool(d["center"]) and bool(d["radio"]), "缺文件时全部显示")

	# 2) 不是配置文件
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("这里不是 ConfigFile\n")
	f.close()
	var d2 := ViewState.load_settings(TMP)
	_check(ViewState.hidden_count(d2) == 0, "坏文件退回全部显示")

	# 3) 有未知键：必须被忽略，不能把字典撑大
	var cfg := ConfigFile.new()
	cfg.set_value(ViewState.SECTION, "radio", false)
	cfg.set_value(ViewState.SECTION, "不存在的面板", false)
	cfg.save(TMP)
	var d3 := ViewState.load_settings(TMP)
	_check(not bool(d3["radio"]), "已知键正常读入")
	_check(not d3.has("不存在的面板"), "未知键被丢掉")
	_check(d3.size() == ViewState.PANELS.size(), "读入后项数不变", str(d3.size()))

	# 4) 存进去的值类型不对（字符串 "false"）：bool() 会当成 true，不能崩
	cfg = ConfigFile.new()
	cfg.set_value(ViewState.SECTION, "radio", "false")
	cfg.save(TMP)
	var d4 := ViewState.load_settings(TMP)
	_check(d4.size() == ViewState.PANELS.size(), "类型不对也不崩")


func _test_last_main_panel() -> void:
	_section("至少留一个主面板")

	# 逐个关掉三个主面板，最后一次必须被拦住
	var d := ViewState.defaults()
	d = ViewState.with_panel(d, "strip", false)
	d = ViewState.with_panel(d, "editor", false)
	_check(ViewState.with_panel(d, "center", true)["center"], "中间可以先开着")
	var refused := ViewState.with_panel(d, "center", false)
	_check(bool(refused["center"]), "关掉最后一个主面板会被拒绝", "center 应该仍是 true")

	# 反过来：先关中间，再关左边，最后右边被拦住
	var e := ViewState.defaults()
	e = ViewState.with_panel(e, "center", false)
	e = ViewState.with_panel(e, "strip", false)
	var e2 := ViewState.with_panel(e, "editor", false)
	_check(bool(e2["editor"]), "关掉最后一个主面板会被拒绝（另一种顺序）")

	# 非主面板可以全部关掉
	var f := ViewState.defaults()
	for id in ["radio", "tabs", "seat", "clock"]:
		f = ViewState.with_panel(f, String(id), false)
	_check(ViewState.hidden_count(f) == 4, "辅助面板可以全部关掉",
		str(ViewState.hidden_count(f)))

	# 未知 id 不改任何东西
	var g := ViewState.with_panel(ViewState.defaults(), "不存在", false)
	_check(ViewState.hidden_count(g) == 0, "未知面板 id 无副作用")


func _test_presets() -> void:
	_section("布局预设")

	var compact := ViewState.preset("compact")
	_check(not bool(compact["radio"]), "紧凑：收起通话记录")
	_check(not bool(compact["seat"]), "紧凑：收起席位徽章")
	_check(bool(compact["center"]) and bool(compact["editor"]), "紧凑：主面板都在")

	var full := ViewState.preset("fullmap")
	_check(bool(full["center"]), "全景：留场面监视")
	_check(not bool(full["strip"]) and not bool(full["editor"]), "全景：收起两侧")
	_check(not bool(full["radio"]) and not bool(full["tabs"]), "全景：收起通话与标签栏")
	_check(bool(full["center"]), "全景：仍有主面板（不会被 normalize 打回）")

	var std := ViewState.preset("standard")
	_check(ViewState.hidden_count(std) == 0, "标准席位：全部显示")

	_check(ViewState.matching_preset(std) == "standard", "能认出标准席位",
		ViewState.matching_preset(std))
	_check(ViewState.matching_preset(compact) == "compact", "能认出紧凑")
	_check(ViewState.matching_preset(full) == "fullmap", "能认出全景地图")

	var odd := ViewState.defaults()
	odd["radio"] = false
	_check(ViewState.matching_preset(odd) == "", "非预设组合返回空串",
		ViewState.matching_preset(odd))

	# 不认识的预设 id 退回全部显示
	_check(ViewState.hidden_count(ViewState.preset("胡写")) == 0, "未知预设退回全部显示")


func _test_helpers() -> void:
	_section("辅助函数")

	_check(ViewState.has_panel("center"), "认识 center")
	_check(not ViewState.has_panel("centerx"), "不认识 centerx")
	_check(ViewState.is_main("center"), "center 是主面板")
	_check(not ViewState.is_main("radio"), "radio 不是主面板")
	_check(ViewState.label_of("strip").begins_with("进程单"), "标签查得到",
		ViewState.label_of("strip"))
	_check(ViewState.label_of("不存在") == "不存在", "未知 id 原样返回")
	_check(ViewState.panel_ids().size() == 7, "面板共 7 块",
		str(ViewState.panel_ids().size()))

	# normalize 对空字典也要给出完整的开
	var n := ViewState.normalize({})
	_check(ViewState.hidden_count(n) == 0, "空字典 normalize 出全开")


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
