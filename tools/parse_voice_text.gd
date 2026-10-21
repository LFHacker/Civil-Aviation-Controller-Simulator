## 把一段（识别出来的）通话文本喂给逻辑层，打印解析结果。
## 供 tools/test-listen.ps1 验证"识别出的文本能不能被逻辑层解析"这个接缝。
##
## 运行：
##   Godot ... --script res://tools/parse_voice_text.gd -- "<文本>"
extends SceneTree


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("PARSE_FAIL: 没给文本")
		quit(2)
		return
	var raw := String(argv[0])
	var norm := VoiceMode.normalize(raw)
	var parsed := VoiceMode.parse(norm)
	parsed["normalized"] = norm
	parsed["kind"] = VoiceMode.kind_of(norm)
	print("PARSE_JSON:" + JSON.stringify(parsed))
	quit(0)
