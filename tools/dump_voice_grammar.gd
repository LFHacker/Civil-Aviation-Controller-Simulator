## 把复诵语法生成出来并写盘，供 tools/atc-listen/AtcListen.exe 实测。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> \
##       --script res://tools/dump_voice_grammar.gd -- <输出目录>
extends SceneTree


func _initialize() -> void:
	var out_dir := "user://"
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		out_dir = String(argv[0])
	var param := {
		"callsign": "CES5175", "limit": "ZSPD", "sid": "SASAN 5B",
		"alt": 6000, "squawk": "4215", "qnh": 1013,
		"ground_freq": "121.750",
	}
	# 三种通话各写一份语法（08 §7.1：复诵 / 复诵确认 / 移交地面）
	for mode in ["readback", "confirm", "handoff"]:
		if not _write(out_dir, param, mode):
			quit(1)
			return
	print("GRAMMAR_OK")
	quit(0)


func _write(out_dir: String, param: Dictionary, mode: String) -> bool:
	var path := out_dir.path_join(mode + ".srgs")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("GRAMMAR_FAIL: 写不了 " + path)
		return false
	f.store_string(VoiceGrammar.build(param, mode))
	f.close()
	var tags: Array = []
	for v in VoiceGrammar.lines_for(param, mode):
		tags.append(String(v.tag))
	var tag_line := ",".join(PackedStringArray(tags))
	if mode == "readback":
		# 老脚本按这两个键读，保持兼容
		print("GRAMMAR_WRITTEN:" + ProjectSettings.globalize_path(path))
		print("GRAMMAR_TAGS:" + tag_line)
		print("GRAMMAR_ITEMS:%d" % tags.size())
	print("GRAMMAR_%s:%s" % [mode.to_upper(), tag_line])
	return true
