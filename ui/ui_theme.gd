## 全局视觉常量：配色、字体、按钮样式。
## 所有 UI 脚本只从这里取色，改一处即全局生效。
class_name AtcTheme
extends RefCounted

# ---- 配色（黄昏塔台：暖光 + 冷阴影，青色作强调） ----
const C_TEXT       := Color("eef2f4")
const C_TEXT_SOFT  := Color("c8d2d7")
const C_TEXT_DIM   := Color("8d9aa1")
const C_TEXT_FAINT := Color("5a686f")
const C_ACCENT     := Color("5eead4")
const C_ACCENT_DIM := Color("2b7f74")
const C_WARM       := Color("f6c177")
const C_DANGER     := Color("f87171")
const C_FRAME      := Color(0.016, 0.024, 0.031, 0.94)
const C_FRAME_EDGE := Color(0.37, 0.92, 0.83, 0.20)

# ---- 字体：走系统字体，避免打包 CJK 字库 ----
const FONT_NAMES := [
	"Microsoft YaHei",
	"微软雅黑",
	"Microsoft YaHei UI",
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"PingFang SC",
	"SimHei",
]

static var _font_cache: Dictionary = {}

## 全局字号缩放。
##
## 界面里所有字号都写成"设计值"，实际像素一律过 fs()。
## 这样调一处就能整体放大/缩小，不用去几十个标签里改数字。
## 1.0 = 原始设计（正文 11–13px，偏小）；中文正文在这个尺寸下看不清，
## 所以默认放到 1.35 —— 正文 13 → 18px，小字 10 → 14px。
const UI_SCALE := 1.35


## 设计字号 → 实际字号（至少 10px，保证中文不糊）
static func fs(base: int) -> int:
	return maxi(10, int(round(float(base) * UI_SCALE)))


## 取一个中文字体实例。weight 取 400 / 500 / 700。
static func font(weight: int = 400) -> SystemFont:
	if _font_cache.has(weight):
		return _font_cache[weight]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_NAMES)
	f.font_weight = weight
	_font_cache[weight] = f
	return f


## 菜单项按钮的样式表。active=true 时显示左侧青色竖条。
static func menu_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.055) if active else Color(0, 0, 0, 0)
	sb.border_width_left = 4
	sb.border_color = C_ACCENT if active else Color(0, 0, 0, 0)
	sb.content_margin_left = 30
	sb.content_margin_right = 18
	sb.content_margin_top = 11
	sb.content_margin_bottom = 11
	return sb
