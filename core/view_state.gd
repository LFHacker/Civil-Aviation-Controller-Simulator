## 视图状态：哪些界面面板显示 / 隐藏，以及三套布局预设。
##
## 和 window_settings.gd 一样是**纯数据层**：只做存取、校验、预设，
## 不碰任何 Control。真正把 visible 改掉的是 ui/view_menu.gd + 各界面。
## 这样"关掉最后一个主面板"这类规则可以在无头环境里测。
class_name ViewState
extends RefCounted

const PATH := "user://view.cfg"
const SECTION := "panels"

## 面板清单。main=true 的是席位主面板，至少要留一个，否则席位就一片空白。
const PANELS := [
	{"id": "strip", "label": "进程单 · 待放行", "main": true},
	{"id": "center", "label": "场面监视 / 信息面板", "main": true},
	{"id": "editor", "label": "许可编辑器", "main": true},
	{"id": "radio", "label": "陆空通话记录", "main": false},
	{"id": "tabs", "label": "顶部信息标签栏", "main": false},
	{"id": "seat", "label": "席位与频率", "main": false},
	{"id": "clock", "label": "仿真时钟", "main": false},
]

## 布局预设（对应 PyCharm「外观」里的演示模式/紧凑模式那种东西）
const PRESETS := [
	{"id": "standard", "label": "标准席位",
		"hint": "左进程单 + 中场面 + 右许可 + 底部通话"},
	{"id": "compact", "label": "紧凑",
		"hint": "收起通话记录与席位徽章，多留出地图高度"},
	{"id": "fullmap", "label": "全景地图",
		"hint": "只留场面监视，其余全部收起"},
]


static func has_panel(id: String) -> bool:
	for p in PANELS:
		if String(p.id) == id:
			return true
	return false


static func is_main(id: String) -> bool:
	for p in PANELS:
		if String(p.id) == id:
			return bool(p.main)
	return false


static func label_of(id: String) -> String:
	for p in PANELS:
		if String(p.id) == id:
			return String(p.label)
	return id


static func panel_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in PANELS:
		out.append(String(p.id))
	return out


## 全部显示
static func defaults() -> Dictionary:
	var d := {}
	for p in PANELS:
		d[String(p.id)] = true
	return d


## 把配置里读到的值变成 bool。
## ⚠️ GDScript 的 bool() 不能从 String 构造（跑起来直接报
## "Nonexistent 'bool' constructor"），所以必须自己判类型。
## 认不出来的一律当 fallback —— 面板显隐里 fallback 取 true（宁可多显示，不要莫名少一块）。
static func coerce_bool(v: Variant, fallback: bool) -> bool:
	if v is bool:
		return v
	if v is int:
		return int(v) != 0
	if v is float:
		return float(v) != 0.0
	if v is String:
		var s := String(v).strip_edges().to_lower()
		if s == "true" or s == "1" or s == "yes" or s == "on":
			return true
		if s == "false" or s == "0" or s == "no" or s == "off":
			return false
	return fallback


## 补齐缺失项（默认显示）、丢掉不认识的键，并保证至少有一个主面板是开的。
static func normalize(d: Dictionary) -> Dictionary:
	var out := {}
	for p in PANELS:
		var k := String(p.id)
		out[k] = coerce_bool(d.get(k, true), true)

	var any_main := false
	for p in PANELS:
		if bool(p.main) and bool(out[String(p.id)]):
			any_main = true
	if not any_main:
		# 全关了就把中间主视区放回来 —— 比"空白席位"有用
		out["center"] = true
	return out


static func load_settings(path: String = PATH) -> Dictionary:
	var raw := {}
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for p in PANELS:
			var k := String(p.id)
			if cfg.has_section_key(SECTION, k):
				raw[k] = coerce_bool(cfg.get_value(SECTION, k), true)
	return normalize(raw)


static func save_settings(d: Dictionary, path: String = PATH) -> bool:
	var cfg := ConfigFile.new()
	var n := normalize(d)
	for p in PANELS:
		cfg.set_value(SECTION, String(p.id), bool(n[String(p.id)]))
	return cfg.save(path) == OK


## 切一个面板的开/关。
## 想关掉最后一个主面板会被**整体拒绝**（原样返回），而不是偷偷把中间又打开 ——
## 后者表现为"我明明关的是编辑器，中间却自己弹出来了"，比没反应更让人困惑。
static func with_panel(d: Dictionary, id: String, on: bool) -> Dictionary:
	var cur := normalize(d)
	if not has_panel(id):
		return cur
	if bool(cur[id]) == on:
		return cur
	var out := cur.duplicate()
	out[id] = on
	# 关掉之后还剩主面板吗？没有就整条请求作废
	if not on:
		var still := false
		for p in PANELS:
			if bool(p.main) and bool(out[String(p.id)]):
				still = true
		if not still:
			return cur
	return normalize(out)


static func hidden_count(d: Dictionary) -> int:
	var n := normalize(d)
	var c := 0
	for p in PANELS:
		if not bool(n[String(p.id)]):
			c += 1
	return c


## 预设；不认识的 id 退回全部显示
static func preset(id: String) -> Dictionary:
	var d := {}
	for p in PANELS:
		d[String(p.id)] = true
	if id == "compact":
		d["radio"] = false
		d["seat"] = false
	elif id == "fullmap":
		d["strip"] = false
		d["editor"] = false
		d["radio"] = false
		d["tabs"] = false
		d["seat"] = false
	return normalize(d)


## 当前状态对应哪套预设；都不是就返回 ""
static func matching_preset(d: Dictionary) -> String:
	var n := normalize(d)
	for p in PRESETS:
		var want := preset(String(p.id))
		var same := true
		for k in n.keys():
			if bool(n[k]) != bool(want[k]):
				same = false
				break
		if same:
			return String(p.id)
	return ""
