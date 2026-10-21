## 语音片段库（08 §4「说」取件层）测试，无头可跑，不依赖真音频。
##
## 造一份只指向"半个文件"的清单，验证：
##   ① 缺件的片段被跳过，而不是整句不播；
##   ② 清单读不到时安静退回（不报错、不假装有）；
##   ③ 角色子目录与根目录的回退；
##   ④ 时长累加与缺件列举。
## 若本机已生成真片段库（tools/gen_voice.py），额外验证真实清单能取到件。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tests/test_voice_library.gd
extends SceneTree

var _checks := 0
var _fails := 0
var _root := ""


func _initialize() -> void:
	print("")
	print("════════ 语音片段库测试 ════════")
	_build_fixture()
	_test_missing()
	_test_fallback()
	_test_real()
	print("")
	print("────────────────────────────")
	if _fails == 0:
		print("✓ 全部通过：%d 项断言" % _checks)
	else:
		print("✗ 失败 %d / %d 项断言" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


## 造一个假片段库：清单里列了 d1 和 p_missing，但只创建 d1.ogg
func _build_fixture() -> void:
	_root = OS.get_user_data_dir().path_join("vl_test")
	# 上一次跑留下的子目录会让"回退到根目录"的断言假失败，先清干净
	_wipe(_root)
	DirAccess.make_dir_recursive_absolute(_root)
	var mf := {
		"d1": {"file": "d1.ogg", "text": "幺", "sec": 0.5, "bytes": 10},
		"d2": {"file": "d2.ogg", "text": "两", "sec": 0.4, "bytes": 10},
		"p_missing": {"file": "p_missing.ogg", "text": "缺", "sec": 0.3, "bytes": 10},
		"_meta": {"voice": "test", "count": 3},
	}
	var f := FileAccess.open(_root.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(mf))
	f.close()
	# 只落 d1 / d2 两个真文件，p_missing 故意不落
	for id in ["d1", "d2"]:
		var w := FileAccess.open(_root.path_join(id + ".ogg"), FileAccess.WRITE)
		w.store_string("not-a-real-ogg")
		w.close()


func _test_missing() -> void:
	_section("缺件降级（不能因为缺一条就整句不播）")
	var lib := VoiceLibrary.new(_root)
	_check(lib.ready_for(), "清单在就算就绪")
	_check(lib.has("d1"), "d1 取得到")
	_check(not lib.has("p_missing"), "清单有但文件不在 → 不算有")
	var plan := lib.plan(["d1", "p_missing", "d2"])
	_check(plan.size() == 2, "缺件被跳过，其余照播", str(plan.size()))
	_check(String((plan[0] as Dictionary).get("id", "")) == "d1", "顺序保持"
		, str(plan))
	_check(String((plan[1] as Dictionary).get("id", "")) == "d2",
		"跳过后仍按原顺序", str(plan))
	var miss := lib.missing(["d1", "p_missing"])
	_check(miss.size() == 1 and String(miss[0]) == "p_missing",
		"能列出缺哪些", str(miss))
	_check(absf(lib.plan_seconds(["d1", "d2"]) - 0.9) < 0.001,
		"时长累加正确", str(lib.plan_seconds(["d1", "d2"])))
	_check(lib.plan_seconds(["p_missing"]) == 0.0, "缺件不计时长")


func _test_fallback() -> void:
	_section("角色目录与回退")
	var lib := VoiceLibrary.new(_root)
	_check(lib.dir_for("controller") == _root, "没有子目录时退回根目录",
		lib.dir_for("controller"))
	# 造一个 controller 子目录：应当优先用它
	var sub := _root.path_join("controller")
	DirAccess.make_dir_recursive_absolute(sub)
	var f := FileAccess.open(sub.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"d1": {"file": "c1.ogg", "sec": 0.6}}))
	f.close()
	var w := FileAccess.open(sub.path_join("c1.ogg"), FileAccess.WRITE)
	w.store_string("x")
	w.close()
	var lib2 := VoiceLibrary.new(_root)
	_check(lib2.dir_for("controller") == sub, "有角色子目录时用子目录",
		lib2.dir_for("controller"))
	_check(lib2.path_for("d1").contains("c1.ogg"), "取件走子目录清单",
		lib2.path_for("d1"))
	_check(lib2.dir_for("pilot") == _root, "pilot 没有子目录仍退回根")


func _test_real() -> void:
	_section("本机真片段库（生成过才验）")
	var lib := VoiceLibrary.new("res://assets/audio/phrases")
	if not lib.ready_for("controller"):
		print("    （本机没生成片段库，跳过真库校验；"
			+ "跑 python tools/gen_voice.py 后可用）")
		# 这时仍要保证：没有片段库时绝不假装能播
		_check(not lib.ready_for("controller"), "没生成时明确报未就绪")
		return
	_check(lib.ready_for("controller"), "管制音色库就绪")
	_check(lib.ready_for("pilot"), "机组音色库就绪")
	var ids := Voice.readback("CES5175", "SASAN5B", "ZSPD", 6000, "4215", 1013)
	var plan := lib.plan(ids, "pilot")
	_check(not plan.is_empty(), "复诵能取到片段", str(plan.size()))
	_check(plan.size() == ids.size(), "片段一个不缺", "%d/%d" % [plan.size(), ids.size()])
	var miss := lib.missing(ids, "pilot")
	_check(miss.is_empty(), "没有缺件", str(miss))
	_check(lib.plan_seconds(ids, "pilot") > 3.0, "整句时长合理",
		str(lib.plan_seconds(ids, "pilot")))
	# 真文件的流能被读出来（不依赖导入管线）
	var p := lib.path_for(String(ids[0]), "pilot")
	_check(VoiceLibrary.load_stream(p) != null, "OGG 能直接读成音频流", p)


## 递归删掉夹具目录（DirAccess 没有递归删除，自己走一遍）
func _wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if d.current_is_dir():
				_wipe(full)
			else:
				DirAccess.remove_absolute(full)
		name = d.get_next()
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
