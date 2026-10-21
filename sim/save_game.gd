## 一份存档 = 元信息 + 仿真状态。
##
## payload 的结构一旦发布就不要随意改：改就升 SaveFormat.VERSION，
## 并在 migrate() 里补一条从旧版到新版的转换分支。
class_name SaveGame
extends RefCounted

var slot_id := ""
var label := ""
## "main"（主线）或 "training"（训练）。缺省 "main"，兼容早期没有该字段的存档。
var mode := "main"
var created_unix := 0
var updated_unix := 0
var app_version := ""
var state: SimState


func _init() -> void:
	state = SimState.new()


## 组装成可写入磁盘的完整文档（含 magic / 版本 / 校验和）。
func to_payload() -> Dictionary:
	var body := {
		"slot_id": slot_id,
		"label": label,
		"mode": mode,
		"created_unix": created_unix,
		"updated_unix": updated_unix,
		"app_version": app_version,
		"state": state.to_dict(),
	}
	return {
		"magic": SaveFormat.MAGIC,
		"format_version": SaveFormat.VERSION,
		"payload": body,
		"checksum": _checksum(body),
	}


## 校验完整文档，返回 {ok, error}。不修改任何东西。
static func validate(doc: Dictionary) -> Dictionary:
	if str(doc.get("magic", "")) != SaveFormat.MAGIC:
		return _fail("不是本游戏的存档（magic 不匹配）")

	var ver := int(doc.get("format_version", 0))
	if ver <= 0:
		return _fail("存档缺少有效的版本号")
	if ver > SaveFormat.VERSION:
		return _fail("存档版本 %d 高于本程序支持的 %d，请升级游戏后再载入" % [ver, SaveFormat.VERSION])

	var raw: Variant = doc.get("payload", null)
	if not (raw is Dictionary):
		return _fail("存档内容缺失或结构不对")
	var body: Dictionary = raw

	if str(doc.get("checksum", "")) != _checksum(body):
		return _fail("存档校验失败（文件可能已损坏，或被手动改过）")

	return {"ok": true, "error": ""}


## 从完整文档还原成 SaveGame，返回 {ok, error, save}。
static func from_payload(doc: Dictionary) -> Dictionary:
	var v := validate(doc)
	if not v.ok:
		return {"ok": false, "error": v.error, "save": null}

	var body: Dictionary = doc.get("payload", {})
	var g := SaveGame.new()
	g.slot_id = str(body.get("slot_id", ""))
	g.label = str(body.get("label", ""))
	g.mode = str(body.get("mode", "main"))
	g.created_unix = int(body.get("created_unix", 0))
	g.updated_unix = int(body.get("updated_unix", 0))
	g.app_version = str(body.get("app_version", ""))

	var st: Variant = body.get("state", {})
	g.state = SimState.from_dict(st if st is Dictionary else {})

	# 兜底：槽位 id 缺失或不合法时，用文件名补不了，只能报错
	if not SaveFormat.is_valid_slot_id(g.slot_id):
		return _fail3("存档内的槽位 id 不合法：'%s'" % g.slot_id)
	if g.label == "":
		g.label = g.slot_id

	return {"ok": true, "error": "", "save": g}


## 旧版本迁移入口。目前只有 v1，所以没有可迁移的内容。
## 将来加 v2 时，在这里按 from_version 逐级向上转换 body，再走 validate。
static func migrate(body: Dictionary, from_version: int) -> Dictionary:
	if from_version == SaveFormat.VERSION:
		return {"ok": true, "body": body, "error": ""}
	return _fail("不支持的存档版本迁移：%d -> %d" % [from_version, SaveFormat.VERSION])


# ---------------------------------------------------------------- 内部工具

## 规范化 JSON 后取 SHA256。sort_keys + full_precision 保证同一份数据
## 在任何机器上都能得到同一个字符串。
##
## 但只靠 stringify 还不够：Godot 的 JSON.parse_string 会把**所有数字都读成 float**，
## 于是写入时是 int 的 1760000000，读回变成 1760000000.0，
## stringify 出来一个是 "1760000000"、另一个是 "1760000000.0"，校验和必然对不上。
## 所以先跑一遍 _normalize，把"没有小数部分的浮点"压回 int，两侧就一致了。
static func _checksum(body: Dictionary) -> String:
	return JSON.stringify(_normalize(body), "", true, true).sha256_text()


## 递归归一化数值类型。只处理有限的整值浮点，真正的浮点（如 0.5）原样保留。
static func _normalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floor(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var d := {}
			for k in value.keys():
				d[k] = _normalize(value[k])
			return d
		TYPE_ARRAY:
			var a := []
			for v in value:
				a.append(_normalize(v))
			return a
		_:
			return value


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func _fail3(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "save": null}
