## 通播（ATIS）文本生成与仿真时钟。
##
## 通播内容全部由机场数据里的真实字段拼出：跑道、风、能见度、温度、修正海压。
## 没有的字段（露点、云高）一律不写，不编造观测值。
class_name Atis
extends RefCounted


## 从机场的 clock_start（"HHMM"，本地时间）起算，返回 "HHMM" 时刻。
static func clock_text(start_hhmm: String, elapsed_s: float) -> String:
	var m := minutes_since(start_hhmm, elapsed_s)
	return "%02d%02d" % [(m / 60) % 24, m % 60]


## 从 clock_start 起算的"当前分钟数"（可用于与计划时刻比较）。
static func minutes_since(start_hhmm: String, elapsed_s: float) -> int:
	var base := _parse_hhmm(start_hhmm)
	return base + int(elapsed_s / 60.0)


## 把 "HHMM" 解析成一天内的分钟数；非法输入回落到 08:00。
static func _parse_hhmm(text: String) -> int:
	var s := text.strip_edges()
	if s.length() < 4:
		return 8 * 60
	for i in range(4):
		if s[i] < "0" or s[i] > "9":
			return 8 * 60
	return int(s.substr(0, 2)) * 60 + int(s.substr(2, 2))


## 机场数据的通播字母（默认 A）。
static func alpha_of(airport: Dictionary) -> String:
	var a := str(airport.get("atis_alpha", "A")).strip_edges()
	return a if a != "" else "A"


## 拼出通播全文。返回多行字符串。
static func compose(airport: Dictionary, elapsed_s: float) -> String:
	if airport.is_empty():
		return "通播数据不可用"

	var icao := str(airport.get("icao", "----"))
	var alpha := alpha_of(airport)
	var clock := clock_text(str(airport.get("clock_start", "0000")), elapsed_s)

	var rwy := AirportData.primary_runway(airport)
	var wx: Variant = airport.get("weather", {})
	var w: Dictionary = wx if wx is Dictionary else {}

	var lines := PackedStringArray()
	lines.append("%s 通播 %s  %s" % [icao, alpha, clock])
	lines.append("")
	lines.append("使用跑道 %s。" % rwy)

	var wind := str(w.get("wind", ""))
	var pw := Meteo.parse_wind(wind)
	if bool(pw.get("ok", false)):
		var unit := String(pw.unit).to_upper()
		var unit_text := "米每秒" if unit == "MPS" else ("节" if unit == "KT" else unit)
		if bool(pw.get("variable", false)):
			lines.append("风向不定，风速 %d %s。" % [int(pw.speed), unit_text])
		else:
			var gust := int(pw.get("gust", 0))
			if gust > 0:
				lines.append("地面风 %d 度 %d 阵风 %d %s。" % [int(pw.dir), int(pw.speed), gust, unit_text])
			else:
				lines.append("地面风 %d 度 %d %s。" % [int(pw.dir), int(pw.speed), unit_text])
	else:
		lines.append("地面风资料暂缺。")

	lines.append("能见度 %s。" % str(w.get("visibility", "--")))
	lines.append("温度 %s 摄氏度。" % str(w.get("temperature_c", "--")))
	lines.append("修正海压 %s 百帕。" % str(w.get("qnh_hpa", "--")))
	lines.append("")
	lines.append("首次与本席位联络时，报告已收到通播 %s。" % alpha)
	return "\n".join(lines)
