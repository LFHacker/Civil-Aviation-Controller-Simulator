## 窗口设置：显示模式 / 窗口尺寸 / 显示器 / 置顶，存取与套用。
##
## 纯数据 + 一个 apply()，不依赖具体界面，可以在无头环境测试存取与校验；
## 真正动窗口的 DisplayServer 调用在无头模式下会被跳过。
class_name WindowSettings
extends RefCounted

const PATH := "user://settings.cfg"
const SECTION := "window"

## 显示模式
const MODE_WINDOWED := 0
## 无边框全屏（推荐）：盖住整块屏幕，切回来不掉分辨率、不黑屏
const MODE_FULLSCREEN := 1
## 独占全屏：游戏独占显示输出，切窗口最容易被系统抢焦点
const MODE_EXCLUSIVE := 2
## 旧名字，等价于 MODE_EXCLUSIVE（早期存档里 2 表示的是这个）
const MODE_BORDERLESS := MODE_EXCLUSIVE

const MODE_LABELS := ["窗口", "全屏", "独占全屏"]

## 可选窗口尺寸（只在窗口模式下生效）
const SIZES := [
	{"label": "1280 × 720", "w": 1280, "h": 720},
	{"label": "1600 × 900", "w": 1600, "h": 900},
	{"label": "1920 × 1080", "w": 1920, "h": 1080},
]

## 尺寸下限/上限：防止把窗口写到看不见或者大到离谱
const MIN_W := 960
const MAX_W := 7680
const MIN_H := 600
const MAX_H := 4320

## screen = -1 表示"跟着系统走"，>=0 表示钉在某个显示器上
const SCREEN_AUTO := -1
const MAX_SCREEN := 15


static func defaults() -> Dictionary:
	return {
		"mode": MODE_WINDOWED,
		"w": 1280,
		"h": 720,
		"always_on_top": false,
		"screen": SCREEN_AUTO,
	}


## 读设置；文件不存在或内容非法都退回默认值（绝不因为配置坏了起不来）。
static func load_settings(path: String = PATH) -> Dictionary:
	var d := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return d

	var mode := int(cfg.get_value(SECTION, "mode", d.mode))
	if mode < MODE_WINDOWED or mode > MODE_EXCLUSIVE:
		mode = MODE_WINDOWED
	d.mode = mode

	d.w = clampi(int(cfg.get_value(SECTION, "width", d.w)), MIN_W, MAX_W)
	d.h = clampi(int(cfg.get_value(SECTION, "height", d.h)), MIN_H, MAX_H)
	d.always_on_top = bool(cfg.get_value(SECTION, "always_on_top", false))
	d.screen = clampi(int(cfg.get_value(SECTION, "screen", SCREEN_AUTO)),
		SCREEN_AUTO, MAX_SCREEN)
	return d


static func save_settings(d: Dictionary, path: String = PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "mode", int(d.get("mode", MODE_WINDOWED)))
	cfg.set_value(SECTION, "width", clampi(int(d.get("w", 1280)), MIN_W, MAX_W))
	cfg.set_value(SECTION, "height", clampi(int(d.get("h", 720)), MIN_H, MAX_H))
	cfg.set_value(SECTION, "always_on_top", bool(d.get("always_on_top", false)))
	cfg.set_value(SECTION, "screen", clampi(int(d.get("screen", SCREEN_AUTO)),
		SCREEN_AUTO, MAX_SCREEN))
	return cfg.save(path) == OK


## 无头模式（跑测试/截图流水线）下不能碰 DisplayServer。
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## 显示器个数；无头环境返回 1，界面据此决定要不要显示"显示器"一栏。
static func screen_count() -> int:
	if is_headless():
		return 1
	return maxi(1, DisplayServer.get_screen_count())


static func screen_label(index: int) -> String:
	if index < 0:
		return "跟随系统"
	return "显示器 %d" % (index + 1)


## 把设置真正套到窗口上。headless 下直接返回，方便测试。
static func apply(d: Dictionary) -> void:
	if is_headless():
		return
	var mode := int(d.get("mode", MODE_WINDOWED))
	var on_top := bool(d.get("always_on_top", false))
	var screen := clampi(int(d.get("screen", SCREEN_AUTO)), SCREEN_AUTO, MAX_SCREEN)
	var size := Vector2i(
		clampi(int(d.get("w", 1280)), MIN_W, MAX_W),
		clampi(int(d.get("h", 720)), MIN_H, MAX_H))

	# 先把窗口放回窗口模式，再把尺寸定死，最后才切模式 ——
	# 反过来的话从全屏切回窗口时，Godot 会把窗口写成"全屏那一瞬的尺寸"。
	if mode == MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# 尺寸超过显示器可用区域时先夹住，否则窗口会有一半在屏幕外面
		size = _fit_to_screen(size, screen)
		DisplayServer.window_set_size(size)
		if screen >= 0 and screen < screen_count():
			DisplayServer.window_set_current_screen(screen)
		_center_on_screen(size, screen)
	elif mode == MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		if screen >= 0 and screen < screen_count():
			DisplayServer.window_set_current_screen(screen)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if screen >= 0 and screen < screen_count():
			DisplayServer.window_set_current_screen(screen)

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, on_top)


## 把尺寸夹进目标显示器的可用区域，避免"选了 1920×1080 但屏幕只有 1366×768"。
static func _fit_to_screen(size: Vector2i, screen: int) -> Vector2i:
	if screen < 0 or screen >= screen_count():
		screen = maxi(0, DisplayServer.window_get_current_screen())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return size
	return Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))


static func _center_on_screen(size: Vector2i, screen: int) -> void:
	if screen < 0 or screen >= screen_count():
		screen = maxi(0, DisplayServer.window_get_current_screen())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var pos := usable.position + (usable.size - size) / 2
	DisplayServer.window_set_position(pos)


static func minimize() -> void:
	if is_headless():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


## 只切换模式（不改尺寸），切回窗口模式时沿用当前保存的尺寸。
static func set_mode(d: Dictionary, mode: int) -> Dictionary:
	var out := d.duplicate()
	out.mode = clampi(mode, MODE_WINDOWED, MODE_EXCLUSIVE)
	return out


## 找尺寸在 SIZES 里的下标；找不到返回 -1（界面上用来打勾）。
static func size_index(w: int, h: int) -> int:
	for i in range(SIZES.size()):
		if int(SIZES[i].w) == w and int(SIZES[i].h) == h:
			return i
	return -1


static func mode_label(mode: int) -> String:
	if mode < 0 or mode >= MODE_LABELS.size():
		return MODE_LABELS[MODE_WINDOWED]
	return MODE_LABELS[mode]


# ---------------------------------------------------------------- 新开窗口

## 再开一个本程序的窗口（多席位 / 多显示器时很有用：一块屏放放行席，一块屏放地面席）。
## 返回新进程 pid，失败返回 -1。
static func spawn_new_instance() -> int:
	var exe := OS.get_executable_path()
	if exe == "":
		return -1
	# 从编辑器 / 命令行跑的时候，可执行文件是 Godot 本体，必须带 --path 才知道开哪个工程；
	# 导出成发行版之后可执行文件就是本程序，不能再塞 --path（否则会被当成未知参数）。
	var probe := exe.get_file().to_lower()
	var args: Array = []
	if probe.begins_with("godot"):
		args = ["--path", ProjectSettings.globalize_path("res://")]
	# 优先启动不带控制台的那个 exe（console 版会多弹一个黑框）
	if probe.ends_with("_console.exe"):
		var plain := exe.substr(0, exe.length() - "_console.exe".length()) + ".exe"
		if FileAccess.file_exists(plain):
			exe = plain
	return OS.create_process(exe, args)
