## 存档系统无头测试。
##
## 运行方式：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_save.gd
##
## 全部在 user:// 下的临时目录里跑，跑完自动清理，绝不碰真实存档。
extends SceneTree

const TEST_ROOT := "user://test_saves"

var _checks := 0
var _fails := 0
var _store: SaveStore
var _stamp := 0


func _initialize() -> void:
	_stamp = int(Time.get_unix_time_from_system())
	Cleanup()

	print("")
	print("════════ 存档系统测试 ════════")
	_store = SaveStore.new(TEST_ROOT)
	_run()

	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])

	Cleanup()
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	_section("目录与空库")
	_check(_store.ensure_dir(), "能创建存档目录")
	_check(DirAccess.dir_exists_absolute(TEST_ROOT), "目录确实存在")
	_check(_store.list().is_empty(), "空库 list() 为空")
	_check(_store.has("manual_1") == false, "空库 has() 为 false")

	_section("写入与读回")
	var g := _make_save("manual_1", "测试存档 A")
	var w := _store.write(g)
	_check(w.ok, "写入成功", str(w))
	_check(_store.has("manual_1"), "写入后 has() 为 true")
	_check(not FileAccess.file_exists(_store.slot_path("manual_1") + SaveFormat.TMP_SUFFIX),
		"提交后不残留 .tmp")

	var r := _store.read("manual_1")
	_check(r.ok, "读取成功", str(r))
	var back: SaveGame = r.save
	_check(back.label == "测试存档 A", "label 往返一致", back.label)
	_check(absf(back.state.sim_time - 3723.0) < 0.001, "sim_time 往返一致", str(back.state.sim_time))
	_check(back.state.seat_id == "tower", "seat_id 往返一致", back.state.seat_id)
	_check(back.state.flights.size() == 2, "flights 数量一致", str(back.state.flights.size()))
	_check(back.state.extra.get("rb", "") == "跑道 18", "extra 往返一致", str(back.state.extra))

	_section("覆盖写与备份")
	var g2 := _make_save("manual_1", "测试存档 A2")
	g2.updated_unix = _stamp + 100
	var w2 := _store.write(g2)
	_check(w2.ok, "覆盖写入成功", str(w2))
	_check(FileAccess.file_exists(_store.slot_path("manual_1") + SaveFormat.BAK_SUFFIX),
		"覆盖时生成 .bak 备份")
	var r2 := _store.read("manual_1")
	_check(r2.ok and r2.save.label == "测试存档 A2", "覆盖后读到新内容")

	_section("列表与排序")
	var g3 := _make_save("manual_2", "测试存档 B")
	g3.updated_unix = _stamp + 200
	_store.write(g3)
	var lst := _store.list()
	_check(lst.size() == 2, "list() 返回 2 项", str(lst.size()))
	_check(lst[0].save.slot_id == "manual_2", "按更新时间倒序（新的在前）", lst[0].save.slot_id)
	_check(_store.list_valid().size() == 2, "list_valid() 返回 2 项")

	_section("异常：损坏的存档")
	var bad_path := _store.slot_path("manual_3")
	_write_raw(bad_path, "{ 这不是 JSON ///")
	var rb := _store.read("manual_3")
	_check(not rb.ok, "损坏存档被拒绝")
	_check(rb.error.length() > 0, "损坏存档给出可读错误", rb.error)
	_check(_store.list().size() == 3, "损坏存档仍出现在列表里（不静默消失）")
	var bad_entry: Dictionary = {}
	for e in _store.list():
		if e.slot_id == "manual_3":
			bad_entry = e
	_check(bad_entry.is_empty() == false and bad_entry.ok == false, "列表把损坏项标为 ok=false")

	_section("异常：版本过新")
	var future := {
		"magic": SaveFormat.MAGIC,
		"format_version": SaveFormat.VERSION + 99,
		"payload": {},
		"checksum": "",
	}
	_write_raw(_store.slot_path("manual_4"), JSON.stringify(future))
	var rf := _store.read("manual_4")
	_check(not rf.ok, "未来版本被拒绝")
	_check(rf.error.find("高于") >= 0, "错误信息说明版本过新", rf.error)

	_section("异常：校验和篡改")
	var tamper_path := _store.slot_path("manual_5")
	var tg := _make_save("manual_5", "原始标签")
	_store.write(tg)
	var raw_text := FileAccess.get_file_as_string(tamper_path)
	_write_raw(tamper_path, raw_text.replace("原始标签", "被改过的标签"))
	var rt := _store.read("manual_5")
	_check(not rt.ok, "校验和被篡改的存档被拒绝")
	_check(rt.error.find("校验失败") >= 0, "错误信息说明校验失败", rt.error)

	_section("异常：非法槽位 id（路径穿越）")
	_check(SaveFormat.is_valid_slot_id("manual_1"), "合法 id 通过校验")
	_check(not SaveFormat.is_valid_slot_id("../../etc/passwd"), "带 ../ 的 id 被拒绝")
	_check(not SaveFormat.is_valid_slot_id("a/b"), "带斜杠的 id 被拒绝")
	_check(not SaveFormat.is_valid_slot_id(""), "空 id 被拒绝")
	_check(not SaveFormat.is_valid_slot_id("有中文"), "非 ASCII 的 id 被拒绝")
	var evil := _make_save("../evil", "穿越测试")
	var we := _store.write(evil)
	_check(not we.ok, "非法 id 写入被拒绝", str(we))
	_check(_store.read("../evil").ok == false, "非法 id 读取被拒绝")

	_section("删除")
	var d1 := _store.erase("manual_2")
	_check(d1.ok, "删除存在的存档成功", str(d1))
	_check(not _store.has("manual_2"), "删除后 has() 为 false")
	var d2 := _store.erase("manual_2")
	_check(not d2.ok, "重复删除返回失败而不是崩溃")
	_check(d2.error.length() > 0, "重复删除给出错误说明", d2.error)
	var wv := _store.write(g3)  # 重新写回，验证删除后可复用槽位
	_check(wv.ok, "删除后槽位可再次写入")

	_section("中文与长内容")
	var cn := _make_save("manual_6", "北京首都－夜间高峰（含特殊字符 <>&\"'）")
	var wc := _store.write(cn)
	_check(wc.ok, "中文/特殊字符标签写入成功", str(wc))
	var rc := _store.read("manual_6")
	_check(rc.ok and rc.save.label == cn.label, "中文/特殊字符往返一致", rc.save.label if rc.ok else rc.error)

	var big := _make_save("manual_7", "两百架航班")
	big.state.flights = []
	for i in range(200):
		big.state.flights.append({
			"callsign": "CES%03d" % i,
			"type": "A320",
			"alt": 1000.0 + i,
			"hdg": float(i % 360),
			"spd": 220 + (i % 40),
		})
	var wb := _store.write(big)
	_check(wb.ok, "大批量写入成功", str(wb))
	var rb2 := _store.read("manual_7")
	_check(rb2.ok and rb2.save.state.flights.size() == 200, "200 架航班往返数量一致",
		str(rb2.save.state.flights.size()) if rb2.ok else rb2.error)
	var size_kb := FileAccess.get_file_as_string(_store.slot_path("manual_7")).length() / 1024.0
	_check(size_kb > 1.0 and size_kb < 512.0, "文件体积在合理范围（%.1f KB）" % size_kb, "%.1f KB" % size_kb)

	_section("空槽位查找")
	_check(_store.next_free_manual_slot() != "", "能返回可用手动槽位")
	for i in range(1, SaveFormat.MANUAL_SLOT_COUNT + 1):
		var s := _make_save(SaveFormat.manual_slot(i), "填满 %d" % i)
		_store.write(s)
	_check(_store.next_free_manual_slot() == "", "槽位全满时返回空串")

	_section("时间格式化")
	_check(SimState.format_duration(0.0) == "00:00:00", "0 秒")
	_check(SimState.format_duration(3723.0) == "01:02:03", "3723 秒 -> 01:02:03",
		SimState.format_duration(3723.0))
	_check(SimState.format_duration(-5.0) == "00:00:00", "负数回落到 00:00:00")


# ---------------------------------------------------------------- 工具

func _make_save(slot: String, label: String) -> SaveGame:
	var g := SaveGame.new()
	g.slot_id = slot
	g.label = label
	g.created_unix = _stamp
	g.updated_unix = _stamp
	g.app_version = AtcVersion.text()
	g.state.sim_time = 3723.0
	g.state.play_time = 120.0
	g.state.seat_id = "tower"
	g.state.airport_id = "DEMO"
	g.state.flights = [
		{"callsign": "CCA1501", "type": "B738"},
		{"callsign": "CES2302", "type": "A320"},
	]
	g.state.extra = {"rb": "跑道 18", "wx": "CAVOK"}
	return g


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


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


func Cleanup() -> void:
	_rm_rf(TEST_ROOT)


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
