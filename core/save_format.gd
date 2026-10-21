## 存档格式契约：所有字段名、版本号、槽位规则集中在这里。
## 逻辑层与表现层都只从本文件取常量，避免魔法字符串散落各处。
class_name SaveFormat
extends RefCounted

## 存档文件里的"魔数"，防止把别的 JSON 当存档读进来。
const MAGIC := "atc.save"

## 当前格式版本。改动 payload 结构时必须 +1，并在 SaveGame 里补迁移分支。
const VERSION := 1

const DIR_DEFAULT := "user://saves"
const SLOT_PREFIX := "slot_"
const SLOT_EXT := ".json"

## 写入过程产生的临时文件与上一版备份
const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"

const MANUAL_SLOT_COUNT := 8
const AUTO_SLOT_COUNT := 3

## 席位 id → 中文名。与将来的仿真模块一一对应。
const SEATS := [
	{"id": "delivery", "label": "放行席"},
	{"id": "apron", "label": "机坪席"},
	{"id": "ground", "label": "地面席"},
	{"id": "tower", "label": "塔台席"},
	{"id": "approach", "label": "进近席"},
	{"id": "center", "label": "区域管制"},
]


static func seat_label(id: String) -> String:
	for s in SEATS:
		if s.id == id:
			return s.label
	return "未知席位"


## 槽位 id 只允许字母、数字、下划线和短横，长度 1..48。
## 这是安全边界：槽位 id 会直接拼进文件路径，绝不能带 .. 或斜杠。
static func is_valid_slot_id(id: String) -> bool:
	if id.length() < 1 or id.length() > 48:
		return false
	for i in range(id.length()):
		var ch := id[i]
		var ok := (ch >= "a" and ch <= "z") \
			or (ch >= "A" and ch <= "Z") \
			or (ch >= "0" and ch <= "9") \
			or ch == "_" or ch == "-"
		if not ok:
			return false
	return true


## 手动槽位 id：manual_1 .. manual_N
static func manual_slot(index: int) -> String:
	return "manual_%d" % index


## 自动槽位 id：auto_1 .. auto_N
static func auto_slot(index: int) -> String:
	return "auto_%d" % index
