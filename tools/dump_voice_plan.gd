## 把 sim/voice.gd 算出的片段序列打印成 JSON，给 tools/gen_voice.py 的拼接试听用。
##
## 这个脚本存在的意义：证明"播什么"是**逻辑层**决定的，
## 试听用的音频序列与游戏里实际会播的序列是同一份输出，不是另写一套。
##
## 运行：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --script res://tools/dump_voice_plan.gd
extends SceneTree


func _initialize() -> void:
	var lines := {
		"pilot_readback": Voice.readback("CES5175", "SASAN5B", "ZSPD", 6900, "4215", 1013),
		"controller_clearance": Voice.clearance("CES5175", "SASAN5B", "ZSPD", 6900, "4215", 1013),
		"pilot_request": Voice.request("CCA1501", "215", "ZSPD", true),
		"handoff": Voice.handoff("CCA1501", "121.7"),
	}
	print("VOICE_PLAN_JSON:" + JSON.stringify(lines))
	quit(0)
