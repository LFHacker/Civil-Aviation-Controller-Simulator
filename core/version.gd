## 版本号常量。构建脚本与主菜单共用同一来源。
class_name AtcVersion
extends RefCounted

const MAJOR := 0
const MINOR := 1
const PATCH := 5

const CODENAME := "radar"


## 形如 "0.0.1"
static func text() -> String:
	return "%d.%d.%d" % [MAJOR, MINOR, PATCH]


## 形如 "v0.0.1 skyline"
static func display() -> String:
	return "v%s %s" % [text(), CODENAME]
