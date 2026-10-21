## 统一日志前缀，方便在启动输出里一眼捞出本项目的行。
class_name AtcLog
extends RefCounted

const PREFIX := "[ATC]"


static func info(msg: String) -> void:
	print("%s %s" % [PREFIX, msg])


static func warn(msg: String) -> void:
	push_warning("%s %s" % [PREFIX, msg])


static func error(msg: String) -> void:
	push_error("%s %s" % [PREFIX, msg])
