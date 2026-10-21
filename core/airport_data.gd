## 机场数据加载器。
##
## 机场定义放在 data/airports/<id>.json，加载后做一遍结构校验。
## 校验失败绝不"尽力而为"地用半份数据——宁可报错让人看见，
## 也不要在后面的席位逻辑里因为少一个频率字段而莫名其妙地空着。
##
## 注意：导出 exe 时要把 *.json 加进包含过滤器，否则资源不会被打包。
class_name AirportData
extends RefCounted

const DIR := "res://data/airports"

## 必需的席位频率键
const REQUIRED_FREQ := ["delivery", "ground", "tower", "approach", "center"]

static var _cache: Dictionary = {}


## 读取机场。返回 {ok, error, data}。
## dir 可覆盖数据目录，测试用临时目录，避免往工程里写脏文件。
static func load_airport(id: String, dir: String = DIR) -> Dictionary:
	var key := id.strip_edges().to_lower()
	if key == "":
		return _fail("机场 id 为空")

	var cache_key := "%s|%s" % [dir, key]
	if _cache.has(cache_key):
		return {"ok": true, "error": "", "data": _cache[cache_key]}

	var path := "%s/%s.json" % [dir, key]
	if not FileAccess.file_exists(path):
		return _fail("找不到机场数据文件：%s" % path)

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail("机场数据文件为空：%s" % path)

	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("机场数据不是合法 JSON（%s 第 %d 行）：%s" % [
			key, json.get_error_line(), json.get_error_message()])

	var raw: Variant = json.data
	if not (raw is Dictionary):
		return _fail("机场数据根节点不是对象：%s" % key)

	var data: Dictionary = raw
	var v := _validate(data)
	if not v.ok:
		return _fail("机场 %s 数据校验失败：%s" % [key, v.error])

	_cache[cache_key] = data
	return {"ok": true, "error": "", "data": data}


static func _validate(d: Dictionary) -> Dictionary:
	if str(d.get("id", "")) == "":
		return _err("缺少 id")
	if str(d.get("name", "")) == "":
		return _err("缺少 name")

	var runways: Variant = d.get("runways", null)
	if not (runways is Array) or (runways as Array).is_empty():
		return _err("runways 必须是非空数组")
	for r in (runways as Array):
		if not (r is Dictionary):
			return _err("runways 内元素必须是对象")
		if str(r.get("id", "")) == "":
			return _err("跑道缺少 id")
		if float(r.get("length_m", 0.0)) <= 0.0:
			return _err("跑道 %s 的 length_m 非法" % str(r.get("id", "?")))

	var freqs: Variant = d.get("frequencies", null)
	if not (freqs is Dictionary):
		return _err("frequencies 必须是对象")
	for k in REQUIRED_FREQ:
		if not (freqs as Dictionary).has(k):
			return _err("缺少席位频率：%s" % k)

	return {"ok": true, "error": ""}


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "data": {}}


## 给界面用的取频率快捷方法。
static func frequency(airport: Dictionary, seat_id: String) -> String:
	var f: Variant = airport.get("frequencies", {})
	if f is Dictionary:
		return str((f as Dictionary).get(seat_id, ""))
	return ""


## 主跑道 id（第一条）。
static func primary_runway(airport: Dictionary) -> String:
	var rs: Variant = airport.get("runways", [])
	if rs is Array and not (rs as Array).is_empty():
		var r: Variant = (rs as Array)[0]
		if r is Dictionary:
			return str((r as Dictionary).get("id", ""))
	return ""


## 清缓存，供测试使用。
static func clear_cache() -> void:
	_cache.clear()
