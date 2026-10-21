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
		"alt": 6900, "squawk": "4215", "qnh": 1013,
	}
	var xml := VoiceGrammar.build(param)
	var path := out_dir.path_join("readback.srgs")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("GRAMMAR_FAIL: 写不了 " + path)
		quit(1)
		return
	f.store_string(xml)
	f.close()
	var lines := VoiceGrammar.variant_lines(param)
	var tags: Array = []
	for v in lines:
		tags.append(String(v.tag))
	print("GRAMMAR_WRITTEN:" + ProjectSettings.globalize_path(path))
	print("GRAMMAR_TAGS:" + ",".join(PackedStringArray(tags)))
	print("GRAMMAR_ITEMS:%d" % lines.size())
	quit(0)
