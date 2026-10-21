## 会话与存档联动的无头测试。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_session.gd
extends SceneTree

const TEST_ROOT := "user://test_session"

var _checks := 0
var _fails := 0
var _store: SaveStore
var _stamp := 0


func _initialize() -> void:
	_stamp = int(Time.get_unix_time_from_system())
	_rm_rf(TEST_ROOT)

	print("")
	print("════════ 会话 / 存档联动测试 ════════")
	_store = SaveStore.new(TEST_ROOT)
	_store.ensure_dir()
	_run()

	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	_rm_rf(TEST_ROOT)
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	_section("新建会话")
	var s := GameSession.create(GameSession.MODE_MAIN, "tower", "主线 塔台席")
	_check(s.mode == GameSession.MODE_MAIN, "mode 正确")
	_check(s.seat_id == "tower", "seat_id 正确")
	_check(s.state.seat_id == "tower", "state.seat_id 同步")
	_check(s.state.flights.size() == 3, "带三架起步航班", str(s.state.flights.size()))
	_check(s.save_slot == "", "新会话还没有绑定槽位")

	_section("时钟推进")
	s.tick(1.5)
	s.tick(2.5)
	_check(absf(s.state.sim_time - 4.0) < 0.0001, "非暂停时 sim_time 累加", str(s.state.sim_time))
	_check(absf(s.state.play_time - 4.0) < 0.0001, "play_time 同步累加")
	s.state.paused = true
	s.tick(100.0)
	_check(absf(s.state.sim_time - 4.0) < 0.0001, "暂停后 sim_time 不再增长", str(s.state.sim_time))
	s.state.paused = false

	_section("保存 -> 读回 -> 复原会话")
	s.state.sim_time = 1234.0
	var g := s.to_save("manual_1")
	_check(g.mode == GameSession.MODE_MAIN, "存档带上 mode")
	_check(g.slot_id == "manual_1", "存档槽位正确")
	var w := _store.write(g)
	_check(w.ok, "写入成功", str(w))

	var r := _store.read("manual_1")
	_check(r.ok, "读回成功", str(r))
	var back: GameSession = GameSession.from_save(r.save)
	_check(back.mode == GameSession.MODE_MAIN, "mode 往返一致", back.mode)
	_check(back.seat_id == "tower", "seat_id 往返一致", back.seat_id)
	_check(absf(back.state.sim_time - 1234.0) < 0.0001, "sim_time 往返一致", str(back.state.sim_time))
	_check(back.state.flights.size() == 3, "flights 往返一致", str(back.state.flights.size()))
	_check(back.save_slot == "manual_1", "复原后绑定到读取的槽位", back.save_slot)
	_check(back.label == "主线 塔台席", "label 往返一致", back.label)

	_section("训练模式存档")
	var t := GameSession.create(GameSession.MODE_TRAINING, "approach", "训练 进近席")
	t.state.sim_time = 60.0
	var tg := t.to_save("manual_2")
	_check(tg.mode == GameSession.MODE_TRAINING, "训练存档 mode=training")
	_store.write(tg)
	var tr := _store.read("manual_2")
	_check(tr.ok, "训练存档可读回")
	_check(tr.save.mode == GameSession.MODE_TRAINING, "训练标记往返一致", tr.save.mode)
	_check(GameSession.from_save(tr.save).mode_label() == "训练", "mode_label 输出中文")

	_section("旧存档兼容（缺 mode 字段）")
	# 手工构造一份没有 mode 的 payload，模拟旧版本写出的存档
	var legacy_body := {
		"slot_id": "manual_3",
		"label": "旧存档",
		"created_unix": _stamp,
		"updated_unix": _stamp,
		"app_version": "0.0.1",
		"state": {"sim_time": 10.0, "play_time": 1.0, "seat_id": "ground",
			"airport_id": "DEMO", "paused": false, "flights": [], "events": [], "extra": {}},
	}
	var legacy_doc := {
		"magic": SaveFormat.MAGIC,
		"format_version": SaveFormat.VERSION,
		"payload": legacy_body,
		"checksum": JSON.stringify(SaveGame._normalize(legacy_body), "", true, true).sha256_text(),
	}
	var lf := FileAccess.open(_store.slot_path("manual_3"), FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy_doc, "\t", true, true))
	lf.close()
	var lr := _store.read("manual_3")
	_check(lr.ok, "缺 mode 的旧存档仍可载入", str(lr))
	_check(lr.ok and lr.save.mode == "main", "缺 mode 时回落为 main",
		lr.save.mode if lr.ok else lr.error)

	_section("自动槽位选择")
	_check(_pick_auto(_store) == "auto_1", "自动槽全空时选 auto_1")
	var a1 := GameSession.create(GameSession.MODE_MAIN, "tower", "a1")
	a1.state.sim_time = 1.0
	_store.write(a1.to_save("auto_1"))
	_check(_pick_auto(_store) == "auto_2", "auto_1 被占后选 auto_2")
	var a2 := GameSession.create(GameSession.MODE_MAIN, "tower", "a2")
	_store.write(a2.to_save("auto_2"))
	var a3 := GameSession.create(GameSession.MODE_MAIN, "tower", "a3")
	_store.write(a3.to_save("auto_3"))
	_check(_pick_auto(_store) == "auto_1", "三个都占满时回到最旧的槽位（按时间轮换）")

	_section("未保存进度标记")
	var d0 := GameSession.create(GameSession.MODE_MAIN, "ground", "未保存测试")
	_check(d0.dirty == false, "新会话初始不算脏")
	_check(d0.has_unsaved_progress() == false, "新会话不弹退出确认")
	d0.tick(0.3)
	_check(d0.dirty == true, "推进后标记为脏")
	_check(d0.has_unsaved_progress() == false, "只过 0.3 秒不弹确认（噪音阈值）")
	d0.tick(2.0)
	_check(d0.has_unsaved_progress() == true, "过 2 秒后应当提示未保存",
		"sim=%s saved=%s" % [str(d0.state.sim_time), str(d0._saved_sim)])
	d0.mark_saved()
	_check(d0.dirty == false, "存档后清除脏标记")
	_check(d0.has_unsaved_progress() == false, "存档后不再提示")
	d0.state.paused = true
	d0.tick(10.0)
	_check(d0.dirty == false, "暂停期间推进不置脏")

	_section("会话摘要")
	var summ := s.summary()
	_check(summ.find("主线") >= 0, "摘要含模式", summ)
	_check(summ.find("塔台席") >= 0, "摘要含席位", summ)


# ---------------------------------------------------------------- 工具

## 与 main.gd 里 _pick_auto_slot 相同的策略，这里独立实现一份用于断言。
func _pick_auto(store: SaveStore) -> String:
	var best := SaveFormat.auto_slot(1)
	var best_ts := 0x7FFFFFFF
	for i in range(1, SaveFormat.AUTO_SLOT_COUNT + 1):
		var id := SaveFormat.auto_slot(i)
		var r := store.read(id)
		if not r.ok:
			return id
		var ts: int = r.save.updated_unix
		if ts < best_ts:
			best_ts = ts
			best = id
	return best


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
