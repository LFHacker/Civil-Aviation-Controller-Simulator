## 存档存储层：只负责"把一份存档安全地落到磁盘 / 从磁盘读回来"。
##
## 三条硬规则：
## 1. **原子写**：先写 .tmp，校验长度，再把旧的改名成 .bak，最后 rename 提交。
##    任何一步失败都回滚，绝不留下半截存档。
## 2. **只读不崩**：读到的任何异常都变成 {ok:false, error:"人话"}，不抛异常。
## 3. **路径安全**：槽位 id 必须过 SaveFormat.is_valid_slot_id，杜绝 ../ 穿越。
class_name SaveStore
extends RefCounted

var base_dir: String


func _init(dir_path: String = "") -> void:
	base_dir = dir_path if dir_path != "" else SaveFormat.DIR_DEFAULT


# ---------------------------------------------------------------- 路径

func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(base_dir):
		return true
	return DirAccess.make_dir_recursive_absolute(base_dir) == OK


func slot_path(slot_id: String) -> String:
	return base_dir.path_join(SaveFormat.SLOT_PREFIX + slot_id + SaveFormat.SLOT_EXT)


func has(slot_id: String) -> bool:
	if not SaveFormat.is_valid_slot_id(slot_id):
		return false
	return FileAccess.file_exists(slot_path(slot_id))


# ---------------------------------------------------------------- 写

## 写入一份存档。返回 {ok, error}。
func write(save: SaveGame) -> Dictionary:
	if not SaveFormat.is_valid_slot_id(save.slot_id):
		return _fail("槽位 id 不合法：'%s'" % save.slot_id)
	if not ensure_dir():
		return _fail("无法创建存档目录：%s" % base_dir)

	var path := slot_path(save.slot_id)
	var tmp := path + SaveFormat.TMP_SUFFIX
	var bak := path + SaveFormat.BAK_SUFFIX
	var text := JSON.stringify(save.to_payload(), "\t", true, true)

	# 1) 写临时文件
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("无法创建临时文件：%s（错误码 %d）" % [tmp, FileAccess.get_open_error()])
	f.store_string(text)
	f.close()

	# 2) 确认真的写全了（磁盘满 / 掉电 / 权限问题都要在这里拦住）
	if not FileAccess.file_exists(tmp):
		return _fail("临时文件没有生成：%s" % tmp)
	var written := FileAccess.get_file_as_string(tmp)
	if written.length() != text.length():
		DirAccess.remove_absolute(tmp)
		return _fail("存档写入不完整（期望 %d 字符，实际 %d），已丢弃" % [text.length(), written.length()])

	# 3) 旧存档留一份备份，方便人工回滚
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)

	# 4) 提交
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		# 提交失败就把备份换回来，别让玩家丢掉原存档
		if FileAccess.file_exists(bak) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(bak, path)
		DirAccess.remove_absolute(tmp)
		return _fail("提交存档失败（错误码 %d），已回滚到上一版" % err)

	return {"ok": true, "error": ""}


# ---------------------------------------------------------------- 读

## 读一份存档。返回 {ok, error, save}。
func read(slot_id: String) -> Dictionary:
	if not SaveFormat.is_valid_slot_id(slot_id):
		return _fail3("槽位 id 不合法：'%s'" % slot_id)

	var path := slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return _fail3("存档不存在：%s" % slot_id)

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail3("存档文件为空（%s）" % path)

	# 用 JSON 实例而不是 JSON.parse_string：能拿到出错行号与原因，
	# 给玩家的报错才有用（"不是合法 JSON" 这种话没法排查）。
	var json := JSON.new()
	var jerr := json.parse(text)
	if jerr != OK:
		var where := ""
		if json.get_error_line() > 0:
			where = "（第 %d 行）" % json.get_error_line()
		return _fail3("存档不是合法的 JSON%s：%s" % [where, json.get_error_message()])
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return _fail3("存档根节点不是对象（%s）" % path)

	return SaveGame.from_payload(parsed)


## 列出所有槽位。返回数组，每项 {slot_id, ok, save, error}。
## 损坏的存档也会列出来（ok=false），因为"告诉玩家这个档坏了"比"悄悄消失"好得多。
func list() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(base_dir):
		return out

	var files := DirAccess.get_files_at(base_dir)
	for name in files:
		if not name.begins_with(SaveFormat.SLOT_PREFIX):
			continue
		if not name.ends_with(SaveFormat.SLOT_EXT):
			continue
		var inner_start := SaveFormat.SLOT_PREFIX.length()
		var inner_len := name.length() - inner_start - SaveFormat.SLOT_EXT.length()
		if inner_len <= 0:
			continue
		var slot_id := name.substr(inner_start, inner_len)

		var res := read(slot_id)
		if res.ok:
			out.append({"slot_id": slot_id, "ok": true, "save": res.save, "error": ""})
		else:
			out.append({"slot_id": slot_id, "ok": false, "save": null, "error": res.error})

	# 有效的排前面，同一档按更新时间倒序
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.ok != b.ok:
			return a.ok
		if not a.ok:
			return a.slot_id < b.slot_id
		return a.save.updated_unix > b.save.updated_unix)
	return out


## 只返回可用的存档，供"继续游戏"直接使用。
func list_valid() -> Array:
	var out: Array = []
	for e in list():
		if e.ok:
			out.append(e.save)
	return out


# ---------------------------------------------------------------- 删

## 删除一份存档（连同 .bak）。返回 {ok, error}。
func erase(slot_id: String) -> Dictionary:
	if not SaveFormat.is_valid_slot_id(slot_id):
		return _fail("槽位 id 不合法：'%s'" % slot_id)
	var path := slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return _fail("存档不存在：%s" % slot_id)

	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return _fail("删除存档失败（错误码 %d）" % err)

	var bak := path + SaveFormat.BAK_SUFFIX
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	return {"ok": true, "error": ""}


## 找第一个空的手动槽位；全满时返回空串。
func next_free_manual_slot() -> String:
	for i in range(1, SaveFormat.MANUAL_SLOT_COUNT + 1):
		var id := SaveFormat.manual_slot(i)
		if not has(id):
			return id
	return ""


# ---------------------------------------------------------------- 内部

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


func _fail3(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "save": null}
