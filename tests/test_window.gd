## 窗口设置的存取与校验测试（无头可跑，不碰真实窗口）。
##
## 重点不是"能不能存"，而是**配置坏了也必须能起来**：
## 文件缺失、内容非法、数值越界，都要退回安全默认值。
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_window.gd
extends SceneTree

var _checks := 0
var _fails := 0

const TMP := "user://test_window_settings.cfg"


func _initialize() -> void:
	print("")
	print("════════ 窗口设置测试 ════════")
	_test_defaults()
	_test_roundtrip()
	_test_corrupt()
	_test_helpers()
	_test_screen()
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
	var d := WindowSettings.load_settings(TMP)
	_check(int(d.mode) == WindowSettings.MODE_WINDOWED, "默认窗口模式", str(d.mode))
	_check(int(d.w) == 1280 and int(d.h) == 720, "默认 1280x720", "%dx%d" % [d.w, d.h])
	_check(bool(d.always_on_top) == false, "默认不置顶")
	_check(int(d.screen) == WindowSettings.SCREEN_AUTO, "默认跟随系统显示器",
		str(d.screen))


func _test_roundtrip() -> void:
	_section("存取往返")

	var src := {"mode": WindowSettings.MODE_FULLSCREEN, "w": 1600, "h": 900,
		"always_on_top": true, "screen": 1}
	_check(WindowSettings.save_settings(src, TMP), "保存成功")

	var d := WindowSettings.load_settings(TMP)
	_check(int(d.mode) == WindowSettings.MODE_FULLSCREEN, "模式往返", str(d.mode))
	_check(int(d.w) == 1600 and int(d.h) == 900, "尺寸往返", "%dx%d" % [d.w, d.h])
	_check(bool(d.always_on_top), "置顶往返")
	_check(int(d.screen) == 1, "显示器往返", str(d.screen))

	# 覆盖写：第二次保存应该生效（不是追加）
	src = {"mode": WindowSettings.MODE_EXCLUSIVE, "w": 1920, "h": 1080,
		"always_on_top": false, "screen": -1}
	WindowSettings.save_settings(src, TMP)
	var d2 := WindowSettings.load_settings(TMP)
	_check(int(d2.mode) == WindowSettings.MODE_EXCLUSIVE, "覆盖写生效", str(d2.mode))
	_check(not bool(d2.always_on_top), "覆盖写清掉置顶")
	_check(int(d2.screen) == WindowSettings.SCREEN_AUTO, "覆盖写回到跟随系统")


func _test_corrupt() -> void:
	_section("配置坏掉时退回默认")

	# 1) 非法模式值
	var cfg := ConfigFile.new()
	cfg.set_value(WindowSettings.SECTION, "mode", 99)
	cfg.set_value(WindowSettings.SECTION, "width", 1280)
	cfg.set_value(WindowSettings.SECTION, "height", 720)
	cfg.save(TMP)
	var d := WindowSettings.load_settings(TMP)
	_check(int(d.mode) == WindowSettings.MODE_WINDOWED, "越界模式退回窗口模式", str(d.mode))

	# 2) 尺寸过小 / 过大都被夹住
	cfg = ConfigFile.new()
	cfg.set_value(WindowSettings.SECTION, "mode", 0)
	cfg.set_value(WindowSettings.SECTION, "width", 10)
	cfg.set_value(WindowSettings.SECTION, "height", 99999)
	cfg.save(TMP)
	var d2 := WindowSettings.load_settings(TMP)
	_check(int(d2.w) >= WindowSettings.MIN_W, "过小宽度被抬起", str(d2.w))
	_check(int(d2.h) <= WindowSettings.MAX_H, "过大高度被压下", str(d2.h))

	# 3) 完全不是配置文件
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("这不是配置文件\n随便写点什么\n")
	f.close()
	var d3 := WindowSettings.load_settings(TMP)
	_check(int(d3.mode) == WindowSettings.MODE_WINDOWED, "坏文件退回默认",
		str(d3.mode))
	_check(int(d3.w) == 1280, "坏文件尺寸用默认", str(d3.w))

	# 4) 文件不存在
	_cleanup()
	var d4 := WindowSettings.load_settings(TMP)
	_check(int(d4.mode) == WindowSettings.MODE_WINDOWED, "缺文件退回默认")


func _test_helpers() -> void:
	_section("辅助函数")

	_check(WindowSettings.size_index(1600, 900) == 1, "1600x900 是第一档",
		str(WindowSettings.size_index(1600, 900)))
	_check(WindowSettings.size_index(1366, 768) == -1, "非预设尺寸返回 -1")

	_check(WindowSettings.mode_label(0) == "窗口", "模式标签 0")
	_check(WindowSettings.mode_label(2) == "独占全屏", "模式标签 2")
	_check(WindowSettings.mode_label(99) == "窗口", "非法模式标签兜底")

	var d := WindowSettings.defaults()
	d.mode = WindowSettings.MODE_FULLSCREEN
	var d2 := WindowSettings.set_mode(d, WindowSettings.MODE_WINDOWED)
	_check(int(d2.mode) == WindowSettings.MODE_WINDOWED, "set_mode 改模式")
	_check(int(d.mode) == WindowSettings.MODE_FULLSCREEN, "set_mode 不修改入参")

	var d3 := WindowSettings.set_mode(d, 999)
	_check(int(d3.mode) == WindowSettings.MODE_EXCLUSIVE, "set_mode 越界夹住",
		str(d3.mode))

	# 无头环境下 apply 必须安全空转，不能崩
	WindowSettings.apply(WindowSettings.defaults())
	_check(true, "headless 下 apply 不崩")

	# 无头环境下 minimize 也必须安全空转
	WindowSettings.minimize()
	_check(true, "headless 下 minimize 不崩")

	# 全屏/无头都不该让尺寸数组变形
	_check(WindowSettings.SIZES.size() == 3, "尺寸档位固定 3 档",
		str(WindowSettings.SIZES.size()))
	_check(WindowSettings.MODE_LABELS.size() == 3, "模式档位固定 3 档",
		str(WindowSettings.MODE_LABELS.size()))


func _test_screen() -> void:
	_section("显示器")

	_check(WindowSettings.screen_count() >= 1, "至少一个显示器",
		str(WindowSettings.screen_count()))
	_check(WindowSettings.screen_label(-1) == "跟随系统", "跟随系统标签")
	_check(WindowSettings.screen_label(0) == "显示器 1", "第一块屏标签")

	# 越界显示器号被夹住，不能存进一个不可能的值
	var cfg := ConfigFile.new()
	cfg.set_value(WindowSettings.SECTION, "mode", 0)
	cfg.set_value(WindowSettings.SECTION, "width", 1280)
	cfg.set_value(WindowSettings.SECTION, "height", 720)
	cfg.set_value(WindowSettings.SECTION, "screen", 999)
	cfg.save(TMP)
	var d := WindowSettings.load_settings(TMP)
	_check(int(d.screen) <= WindowSettings.MAX_SCREEN, "越界显示器号被压下",
		str(d.screen))

	cfg = ConfigFile.new()
	cfg.set_value(WindowSettings.SECTION, "mode", 0)
	cfg.set_value(WindowSettings.SECTION, "width", 1280)
	cfg.set_value(WindowSettings.SECTION, "height", 720)
	cfg.set_value(WindowSettings.SECTION, "screen", -99)
	cfg.save(TMP)
	var d2 := WindowSettings.load_settings(TMP)
	_check(int(d2.screen) == WindowSettings.SCREEN_AUTO, "过小显示器号回到跟随系统",
		str(d2.screen))

	# 尺寸超过 4K 的离谱值也要被夹进上下限
	cfg = ConfigFile.new()
	cfg.set_value(WindowSettings.SECTION, "mode", 0)
	cfg.set_value(WindowSettings.SECTION, "width", 999999)
	cfg.set_value(WindowSettings.SECTION, "height", 999999)
	cfg.save(TMP)
	var d3 := WindowSettings.load_settings(TMP)
	_check(int(d3.w) == WindowSettings.MAX_W, "宽度顶到上限", str(d3.w))
	_check(int(d3.h) == WindowSettings.MAX_H, "高度顶到上限", str(d3.h))


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
