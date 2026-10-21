## 气象观测解析与跑道风分量计算。
##
## 纯函数、无渲染依赖，可在无头环境下测试。
## 只处理确实存在于机场数据里的东西，不编造露点、云高等没有的字段。
class_name Meteo
extends RefCounted

## 解析风组。支持 "18005MPS"、"18005KT"、"18005G12KT"、"VRB03KT"。
## 返回 {ok, dir, variable, speed, gust, unit}；speed/gust 为原始单位数值。
static func parse_wind(raw: String) -> Dictionary:
	var s := raw.strip_edges().to_upper()
	if s == "" or s == "--":
		return {"ok": false}

	var i := 0
	var dir := 0
	var variable := false
	if s.begins_with("VRB"):
		variable = true
		i = 3
	else:
		var digits := ""
		while i < s.length() and s[i] >= "0" and s[i] <= "9" and digits.length() < 3:
			digits += s[i]
			i += 1
		if digits.length() != 3:
			return {"ok": false}
		dir = int(digits)

	var spd := ""
	while i < s.length() and s[i] >= "0" and s[i] <= "9" and spd.length() < 3:
		spd += s[i]
		i += 1
	# 风速固定两位（METAR 规范）。不足两位说明这串风组本身是坏的，
	# 宁可判定失败，也不要把 "1805MPS" 猜成 180 度 5 米/秒。
	if spd.length() != 2:
		return {"ok": false}
	var speed := int(spd)

	var gust := 0
	if i < s.length() and s[i] == "G":
		i += 1
		var g := ""
		while i < s.length() and s[i] >= "0" and s[i] <= "9" and g.length() < 3:
			g += s[i]
			i += 1
		gust = int(g) if g != "" else 0

	return {"ok": true, "dir": dir, "variable": variable,
		"speed": speed, "gust": gust, "unit": s.substr(i)}


## 原始单位换算成米/秒（KT -> MPS）；未知单位按 MPS 处理。
static func to_mps(value: float, unit: String) -> float:
	if unit.to_upper() == "KT" or unit.to_upper() == "KTS":
		return value * 0.5144
	return value


## 跑道风分量。返回 {headwind, crosswind}，单位米/秒。
## headwind 正值为顶风、负值为顺风；crosswind 正值为风从右侧来。
static func components(wind_dir: float, speed_mps: float, rwy_heading: float) -> Dictionary:
	var diff := deg_to_rad(wind_dir - rwy_heading)
	return {
		"headwind": speed_mps * cos(diff),
		"crosswind": speed_mps * sin(diff),
	}


## 把风组一步到位算成某个跑道的分量；风组无效时 ok=false。
static func runway_wind(raw: String, rwy_heading: float) -> Dictionary:
	var w := parse_wind(raw)
	if not bool(w.get("ok", false)):
		return {"ok": false}
	if bool(w.get("variable", false)):
		# 风向不定时只能给出风速范围，不硬算分量
		var v := to_mps(float(w.speed), String(w.unit))
		return {"ok": false, "variable": true, "speed_mps": v}
	var mps := to_mps(float(w.speed), String(w.unit))
	var c := components(float(w.dir), mps, rwy_heading)
	c["ok"] = true
	c["variable"] = false
	c["speed_mps"] = mps
	c["wind_dir"] = float(w.dir)
	return c


## 侧风是否超出常见机型限制（这里只给一个通用阈值，用于界面提示）。
static func is_crosswind_high(crosswind_mps: float, limit_mps: float = 15.0) -> bool:
	return absf(crosswind_mps) > limit_mps
