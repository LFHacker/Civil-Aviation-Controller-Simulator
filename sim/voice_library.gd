## 语音片段库（08 §4「说」的取件层）。
##
## 片段是 tools/gen_voice.py 离线生成的一次性产物，游戏运行时只是**按 id 取文件播放**。
## 这一层负责：清单、缺件降级、按角色选库（管制 / 机组两套音色）。
##
## 关键取舍：**不依赖 Godot 的导入管线**。
## 片段是玩家机器上后生成的，没有 .import 文件，`load()` 会失败；
## 所以用 AudioStreamOggVorbis.load_from_file() 直接读字节建流。
class_name VoiceLibrary
extends RefCounted

const DEFAULT_DIR := "res://assets/audio/phrases"
const MANIFEST := "manifest.json"

## 角色 → 子目录（没有子目录就退回根目录，方便只生成一套时也能用）
const ROLES := {
	"controller": "controller",
	"pilot": "pilot",
}

var root := DEFAULT_DIR
var _cache := {}


func _init(p_root: String = DEFAULT_DIR) -> void:
	root = p_root


## 某个角色实际用的目录
func dir_for(role: String) -> String:
	var sub := String(ROLES.get(role, role))
	var cand := root.path_join(sub)
	if FileAccess.file_exists(cand.path_join(MANIFEST)):
		return cand
	return root


## 有没有生成过片段库（没有就让界面静默退回纯文字，不要报错）
func ready_for(role: String = "controller") -> bool:
	return FileAccess.file_exists(dir_for(role).path_join(MANIFEST))


## 清单 {id: {file, text, sec, bytes}}；读不到返回空字典
func manifest(role: String = "controller") -> Dictionary:
	var dir := dir_for(role)
	if _cache.has(dir):
		return _cache[dir]
	var path := dir.path_join(MANIFEST)
	var out := {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				out = parsed as Dictionary
	_cache[dir] = out
	return out


func has(id: String, role: String = "controller") -> bool:
	var m := manifest(role)
	return m.has(id) and FileAccess.file_exists(path_for(id, role))


func path_for(id: String, role: String = "controller") -> String:
	var m := manifest(role)
	if not m.has(id):
		return ""
	var row: Variant = m[id]
	if not (row is Dictionary):
		return ""
	var file := String((row as Dictionary).get("file", id + ".ogg"))
	return dir_for(role).path_join(file)


## 把一个片段 id 序列变成可播放计划：缺的跳过，绝不因为缺一条就整句不播。
## 返回 [{id, path}]。
func plan(ids: Array, role: String = "controller") -> Array:
	var out: Array = []
	var m := manifest(role)
	for it in ids:
		var id := String(it)
		if not m.has(id):
			continue
		var p := path_for(id, role)
		if p == "" or not FileAccess.file_exists(p):
			continue
		out.append({"id": id, "path": p})
	return out


## 缺了哪些片段（生成脚本与自检用）
func missing(ids: Array, role: String = "controller") -> Array:
	var out: Array = []
	var m := manifest(role)
	for it in ids:
		var id := String(it)
		if not m.has(id) or not FileAccess.file_exists(path_for(id, role)):
			out.append(id)
	return out


## 计划总时长（秒）。只算**真能播**的片段，与 plan() 口径一致 ——
## 否则界面会显示"还要说 8 秒"但其实一条都播不出来。
func plan_seconds(ids: Array, role: String = "controller") -> float:
	var m := manifest(role)
	var total := 0.0
	for it in ids:
		var id := String(it)
		var row: Variant = m.get(id, null)
		if not (row is Dictionary):
			continue
		if not FileAccess.file_exists(path_for(id, role)):
			continue
		total += float((row as Dictionary).get("sec", 0.0))
	return total


## 读成音频流。读不到返回 null（调用方跳过这一片，不当作成功）。
static func load_stream(path: String) -> AudioStream:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return AudioStreamOggVorbis.load_from_file(path)
