## 机场数据加载器的无头测试。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_airport.gd
##
## 坏数据全部写在 user:// 的临时目录里，绝不污染工程的 data/airports/。
extends SceneTree

const TMP_DIR := "user://test_airport"

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("")
	print("════════ 机场数据测试 ════════")
	AirportData.clear_cache()
	_mkdir(TMP_DIR)
	_run()
	_rm_rf(TMP_DIR)
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	_section("载入演示机场（真实数据）")
	var r := AirportData.load_airport("DEMO")
	_check(r.ok, "能载入 res://data/airports/demo.json", str(r.get("error", "")))
	if not r.ok:
		return

	var d: Dictionary = r.data
	_check(str(d.id) == "DEMO", "id 正确", str(d.get("id", "")))
	_check(str(d.name) == "演示机场", "name 正确", str(d.get("name", "")))

	_section("跑道")
	var rwys: Array = d.get("runways", [])
	_check(rwys.size() == 2, "两条跑道", str(rwys.size()))
	_check(AirportData.primary_runway(d) == "18", "主跑道是 18",
		AirportData.primary_runway(d))
	var r0: Dictionary = rwys[0]
	_check(float(r0.length_m) == 3200.0, "跑道长度 3200m", str(r0.get("length_m", 0)))
	_check(bool(r0.ils) == true, "跑道 18 有 ILS")

	_section("席位频率")
	for seat in ["delivery", "ground", "tower", "approach", "center"]:
		var f := AirportData.frequency(d, seat)
		_check(f.length() > 0, "%s 有频率" % seat, f)
	_check(AirportData.frequency(d, "tower") == "118.100", "塔台 118.100",
		AirportData.frequency(d, "tower"))
	_check(AirportData.frequency(d, "unknown") == "", "未知席位返回空串")

	_section("缓存")
	var r2 := AirportData.load_airport("DEMO")
	_check(r2.ok and r2.data == d, "第二次读取命中缓存且内容一致")
	var r3 := AirportData.load_airport("demo")
	_check(r3.ok, "机场 id 大小写不敏感")

	_section("异常：不存在的机场")
	var miss := AirportData.load_airport("nope")
	_check(not miss.ok, "不存在的机场返回失败")
	_check(String(miss.error).find("找不到") >= 0, "错误信息说明文件缺失", String(miss.error))
	var empty := AirportData.load_airport("")
	_check(not empty.ok, "空 id 返回失败")
	_check(String(empty.error).find("为空") >= 0, "空 id 的错误信息可读", String(empty.error))

	_section("异常：结构不完整的机场（临时目录）")
	_write(TMP_DIR, "bad_empty", "{}")
	var b1 := AirportData.load_airport("bad_empty", TMP_DIR)
	_check(not b1.ok, "空对象被拒绝", String(b1.error))

	_write(TMP_DIR, "bad_norwy",
		'{"id":"X","name":"无跑道","runways":[],"frequencies":{"delivery":"1","ground":"1","tower":"1","approach":"1","center":"1"}}')
	var b2 := AirportData.load_airport("bad_norwy", TMP_DIR)
	_check(not b2.ok, "没有跑道被拒绝", String(b2.error))
	_check(String(b2.error).find("runways") >= 0, "错误信息点名 runways", String(b2.error))

	_write(TMP_DIR, "bad_nofreq",
		'{"id":"X","name":"缺频率","runways":[{"id":"01","length_m":1000}],"frequencies":{"tower":"118"}}')
	var b3 := AirportData.load_airport("bad_nofreq", TMP_DIR)
	_check(not b3.ok, "缺席位频率被拒绝", String(b3.error))
	_check(String(b3.error).find("频率") >= 0, "错误信息点名频率", String(b3.error))

	_write(TMP_DIR, "bad_json", "{ 这不是 JSON")
	var b4 := AirportData.load_airport("bad_json", TMP_DIR)
	_check(not b4.ok, "非法 JSON 被拒绝")
	_check(String(b4.error).find("合法 JSON") >= 0, "错误信息说明 JSON 非法", String(b4.error))

	_write(TMP_DIR, "bad_len",
		'{"id":"X","name":"跑道长度非法","runways":[{"id":"01","length_m":0}],"frequencies":{"delivery":"1","ground":"1","tower":"1","approach":"1","center":"1"}}')
	var b5 := AirportData.load_airport("bad_len", TMP_DIR)
	_check(not b5.ok, "跑道长度 0 被拒绝", String(b5.error))

	_section("好数据依旧能通过同一目录参数")
	_write(TMP_DIR, "ok_one",
		'{"id":"OK1","name":"测试机场","runways":[{"id":"09","length_m":1800}],"frequencies":{"delivery":"1","ground":"2","tower":"3","approach":"4","center":"5"}}')
	var good := AirportData.load_airport("ok_one", TMP_DIR)
	_check(good.ok, "结构完整的数据能载入", String(good.error))
	_check(String(good.data.get("name", "")) == "测试机场", "name 读对",
		str(good.data.get("name", "")))


# ---------------------------------------------------------------- 工具

func _write(dir: String, id: String, text: String) -> void:
	var f := FileAccess.open("%s/%s.json" % [dir, id], FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _mkdir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			_rm_rf(path.path_join(n))
		else:
			DirAccess.remove_absolute(path.path_join(n))
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


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
