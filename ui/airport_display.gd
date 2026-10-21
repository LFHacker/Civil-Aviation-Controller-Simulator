## 机场场面监视显示。
##
## 底图 = Blender 正射渲染的真实机场俯视图（assets/textures/airport_top.png），
## 矢量层 = 航空器符号、呼号标牌、机位占用高亮、数据块、比例尺。
##
## 底图与矢量层严格共用同一套「世界米制坐标 → 地图坐标」变换：
##   世界 X[-2132, 468]  世界 Y[-866, 866]（北为正）
##   地图 1200 x 800，X 向东、Y 向南
## 于是 Blender 里画出来的机位、滑行道、跑道与游戏里的机位编号一一对应。
##
## 支持滚轮缩放、拖拽平移、双击复位；点击航空器回传呼号。
class_name AirportDisplay
extends Control

signal flight_clicked(callsign: String)

const TEX_PATH := "res://assets/textures/airport_top.png"

const MAP_W := 1200.0
const MAP_H := 800.0

## 底图覆盖的世界范围（米），必须与 assets/blender/build_airport.py 中的
## MAP_X0/X1/Y0/Y1 完全一致。
const W_X0 := -2132.0
const W_X1 := 468.0
const W_Y0 := -866.0
const W_Y1 := 866.0

## 每个地图单位代表多少米（2600 m / 1200 单位）
const M_PER_UNIT := (W_X1 - W_X0) / MAP_W

const MIN_ZOOM := 0.7
const MAX_ZOOM := 4.0
const DRAG_THRESHOLD := 4.0

const C_VOID := Color(0.055, 0.068, 0.052)
const C_TINT := Color(0.055, 0.098, 0.086, 0.55)
const C_STAND_OCC := Color(0.37, 0.92, 0.83, 0.30)
const C_STAND_SEL := Color(1.0, 0.86, 0.42, 0.85)
const C_LABEL_BG := Color(0.016, 0.035, 0.045, 0.82)

var desk: DeliveryDesk
var selected := ""

var _tex: Texture2D
var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _moved := false
var _press_pos := Vector2.ZERO
var _press_pan := Vector2.ZERO

var _hit: Array = []
var _stand_occupancy: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex = load_map_texture()
	# 调试/截图用：--map-zoom=2.5 指定初始缩放
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-zoom="):
			_zoom = clampf(float(arg.substr(11)), MIN_ZOOM, MAX_ZOOM)


## 自定义 _draw 不会因为控件尺寸变化自动重画——分栏拖拽改变了地图控件大小，
## 不主动重绘就会留下旧尺寸的画面。
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## 运行时解码 PNG，不走 Godot 导入管线：
## 底图尺寸大（4608x3072），需要可控的 mipmap 才能在缩放时不出摩尔纹。
static func load_map_texture() -> Texture2D:
	if not FileAccess.file_exists(TEX_PATH):
		return null
	var bytes := FileAccess.get_file_as_bytes(TEX_PATH)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func set_desk(p_desk: DeliveryDesk) -> void:
	desk = p_desk
	queue_redraw()


func set_selected(callsign: String) -> void:
	if selected != callsign:
		selected = callsign
		queue_redraw()


func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()


# ---------------------------------------------------------------- 世界坐标

## 世界米制坐标 -> 地图坐标
func wmap(wx: float, wy: float) -> Vector2:
	return Vector2(
		(wx - W_X0) / (W_X1 - W_X0) * MAP_W,
		(W_Y1 - wy) / (W_Y1 - W_Y0) * MAP_H)


func wrect(wx0: float, wy0: float, wx1: float, wy1: float) -> Rect2:
	var a := wmap(minf(wx0, wx1), maxf(wy0, wy1))
	var b := wmap(maxf(wx0, wx1), minf(wy0, wy1))
	return Rect2(a, b - a)


# ---------------------------------------------------------------- 机位定义

## 24 个机位（世界米制，垂直机位停放点）：
##   A01–A09 北指廊（机头朝北，靠廊桥）
##   A10–A18 南指廊（机头朝南，靠廊桥）
##   A19–A24 远机坪（机头朝北，无廊桥）
const STAND_X0 := -1361.0
const STAND_PITCH := 78.0
const STAND_Y_N := 210.0
const STAND_Y_S := -210.0
const REMOTE_X0 := -1360.0
const REMOTE_PITCH := 110.0
const REMOTE_Y := 770.0


func stand_world(index: int) -> Vector2:
	if index < 9:
		return Vector2(STAND_X0 + index * STAND_PITCH, STAND_Y_N)
	if index < 18:
		return Vector2(STAND_X0 + (index - 9) * STAND_PITCH, STAND_Y_S)
	return Vector2(REMOTE_X0 + (index - 18) * REMOTE_PITCH, REMOTE_Y)


## facing：-1 机头朝北，+1 机头朝南
func stand_def(index: int) -> Dictionary:
	var w := stand_world(index)
	return {
		"pos": wmap(w.x, w.y),
		"world": w,
		"facing": -1 if index < 9 or index >= 18 else 1,
		"bridge": index < 18,
	}


## 机位停放框（世界米制），用于占用高亮
func stand_box(index: int) -> Rect2:
	var w := stand_world(index)
	if index < 9:
		return wrect(w.x - 30.0, 140.0, w.x + 30.0, 250.0)
	if index < 18:
		return wrect(w.x - 30.0, -250.0, w.x + 30.0, -140.0)
	return wrect(w.x - 40.0, 700.0, w.x + 40.0, 800.0)


# ---------------------------------------------------------------- 交互

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.15, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click:
					reset_view()
					accept_event()
					return
				_dragging = true
				_moved = false
				_press_pos = mb.position
				_press_pan = _pan
				grab_focus()
			else:
				if _dragging and not _moved:
					_click_at(mb.position)
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if not _moved and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_moved = true
		if _moved:
			_pan = _press_pan + (mm.position - _press_pos)
			_clamp_pan()
			queue_redraw()
		accept_event()


func _click_at(p: Vector2) -> void:
	for h in _hit:
		if (h.rect as Rect2).has_point(p):
			flight_clicked.emit(String(h.callsign))
			return


func _zoom_at(factor: float, pivot: Vector2) -> void:
	var old := _fit()
	var map_pt: Vector2 = (pivot - old.o) / old.s
	var z := clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(z, _zoom):
		return
	_zoom = z
	var nw := _fit()
	_pan += pivot - (nw.o + map_pt * nw.s)
	_clamp_pan()
	queue_redraw()


func _clamp_pan() -> void:
	var lim := size * 1.2 * _zoom
	_pan.x = clampf(_pan.x, -lim.x, lim.x)
	_pan.y = clampf(_pan.y, -lim.y, lim.y)


# ---------------------------------------------------------------- 坐标换算

func _base_scale() -> float:
	var margin := 6.0
	return minf((size.x - margin * 2.0) / MAP_W, (size.y - margin * 2.0) / MAP_H)


func _fit() -> Dictionary:
	var s: float = _base_scale() * _zoom
	var center := size * 0.5 + _pan
	var o := center - Vector2(MAP_W, MAP_H) * 0.5 * s
	return {"s": s, "o": o}


func _p(x: float, y: float, fit: Dictionary) -> Vector2:
	var s: float = fit.s
	var o: Vector2 = fit.o
	return o + Vector2(x, y) * s


func _v(pt: Vector2, fit: Dictionary) -> Vector2:
	return _p(pt.x, pt.y, fit)


func _rect(r: Rect2, fit: Dictionary) -> Rect2:
	return Rect2(_v(r.position, fit), r.size * float(fit.s))


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_hit.clear()
	_stand_occupancy.clear()

	var fit := _fit()

	draw_rect(Rect2(Vector2.ZERO, size), C_VOID, true)

	if _tex != null:
		draw_texture_rect(_tex, _rect(Rect2(0, 0, MAP_W, MAP_H), fit), false)
	else:
		draw_rect(_rect(Rect2(0, 0, MAP_W, MAP_H), fit), Color(0.28, 0.28, 0.26), true)
		draw_string(AtcTheme.font(500), size * 0.5 - Vector2(120, 0),
			"底图缺失：res://assets/textures/airport_top.png",
			HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(13), Color(1, 0.4, 0.4))

	# 地图外区域压暗，让画面边界明确
	draw_rect(_rect(Rect2(0, 0, MAP_W, MAP_H), fit), C_TINT, false, 1.0)

	_draw_aircraft(fit)
	_draw_chrome(fit)


func _draw_aircraft(fit: Dictionary) -> void:
	if desk == null:
		return
	for flight in desk.pending():
		var idx := _stand_index(String(flight.stand))
		var def := stand_def(idx)
		var sp := _v(def.pos, fit)
		var facing := int(def.facing)

		var is_sel: bool = flight.callsign == selected
		var occupied_key := str(idx)
		var n: int = int(_stand_occupancy.get(occupied_key, 0))
		_stand_occupancy[occupied_key] = n + 1
		if n == 0:
			_draw_stand_box(idx, fit, is_sel)

		sp += Vector2(0, n * 13.0)

		var color := AtcTheme.C_WARM
		if flight.state == Flight.State.SENT:
			color = AtcTheme.C_TEXT_SOFT
		elif flight.state == Flight.State.READBACK:
			color = AtcTheme.C_ACCENT
		elif flight.state == Flight.State.CLEARED:
			color = AtcTheme.C_ACCENT_DIM

		if is_sel:
			draw_circle(sp, 16.0, Color(0.37, 0.92, 0.83, 0.18))
			draw_arc(sp, 16.0, 0.0, TAU, 28, AtcTheme.C_ACCENT, 1.6)

		var poly := _aircraft_poly(sp, facing, 9.5)
		draw_colored_polygon(poly, Color(0.02, 0.04, 0.05, 0.85))
		var inner := _aircraft_poly(sp, facing, 7.6)
		draw_colored_polygon(inner, color)
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, Color(0.02, 0.04, 0.05, 0.55), 1.2)

		var label: String = String(flight.callsign)
		var fsmall := AtcTheme.font(500)
		var lfs := AtcTheme.fs(10)
		var lh := float(lfs) + 6.0
		var lw := fsmall.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_rect(Rect2(sp + Vector2(12, -8), Vector2(lw + 9, lh)), C_LABEL_BG, true)
		draw_rect(Rect2(sp + Vector2(12, -8), Vector2(2, lh)), color, true)
		draw_string(fsmall, sp + Vector2(17, 4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, color)

		_hit.append({
			"callsign": flight.callsign,
			"rect": Rect2(sp - Vector2(14, 12), Vector2(34 + lw, 24)),
		})

		if is_sel:
			_draw_data_block(flight, sp)


func _draw_stand_box(idx: int, fit: Dictionary, is_sel: bool) -> void:
	var r := _rect(stand_box(idx), fit)
	if is_sel:
		draw_rect(r, Color(1.0, 0.86, 0.42, 0.16), true)
		draw_rect(r, C_STAND_SEL, false, 1.6)
	else:
		draw_rect(r, C_STAND_OCC, false, 1.2)


func _aircraft_poly(sp: Vector2, facing: int, r: float) -> PackedVector2Array:
	var dir := Vector2(0, -1)
	if facing > 0:
		dir = Vector2(0, 1)
	var side := Vector2(-dir.y, dir.x)
	# 机头 → 右翼尖 → 右尾 → 尾中点 → 左尾 → 左翼尖（单环，可直接三角化）
	return PackedVector2Array([
		sp + dir * r,
		sp - dir * r * 0.35 + side * r * 0.85,
		sp - dir * r * 0.85 + side * r * 0.35,
		sp - dir * r * 1.00,
		sp - dir * r * 0.85 - side * r * 0.35,
		sp - dir * r * 0.35 - side * r * 0.85,
	])


func _draw_data_block(flight: Flight, sp: Vector2) -> void:
	var f := AtcTheme.font(700)
	var fsmall := AtcTheme.font(500)
	var w := 156.0 * AtcTheme.UI_SCALE
	var h := 54.0 * AtcTheme.UI_SCALE
	var org := sp + Vector2(18, -h - 18)
	if org.x + w > size.x - 8:
		org.x = sp.x - w - 18
	if org.y < 8:
		org.y = sp.y + 20

	var rect := Rect2(org, Vector2(w, h))
	draw_rect(rect, Color(0.016, 0.035, 0.045, 0.96), true)
	draw_rect(rect, AtcTheme.C_ACCENT, false, 1.0)
	draw_line(sp, Vector2(org.x, org.y + h), AtcTheme.C_ACCENT, 1.0)

	draw_string(f, org + Vector2(8, 17 * AtcTheme.UI_SCALE), flight.callsign,
		HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(13), AtcTheme.C_TEXT)
	draw_string(fsmall, org + Vector2(8, 34 * AtcTheme.UI_SCALE), "%s  %s" % [flight.type, flight.stand],
		HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(11), AtcTheme.C_TEXT_DIM)
	draw_string(fsmall, org + Vector2(8, 50 * AtcTheme.UI_SCALE), "%s  SQK %s" % [flight.destination, flight.squawk],
		HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(11), AtcTheme.C_ACCENT)


func _draw_chrome(fit: Dictionary) -> void:
	var f := AtcTheme.font(500)

	var hint := "场面监视 SURFACE  ·  滚轮缩放 · 拖拽平移 · 双击复位"
	var hfs := AtcTheme.fs(11)
	var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
	draw_rect(Rect2(8, 6, hw + 14, float(hfs) + 8.0), C_LABEL_BG, true)
	draw_string(f, Vector2(15, 6 + float(hfs) + 1.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(11), Color(0.37, 0.92, 0.83, 0.85))

	# 比例尺：按真实米数画，长度取整百/整千米
	var s: float = fit.s
	var meters_per_px: float = M_PER_UNIT / s
	for cand in [2000.0, 1000.0, 500.0, 200.0, 100.0, 50.0]:
		var px: float = cand / meters_per_px
		if px <= 150.0:
			var bx := size.x - px - 18.0
			var by := size.y - 16.0
			draw_rect(Rect2(bx - 8, by - 24, px + 16, 32), C_LABEL_BG, true)
			draw_line(Vector2(bx, by), Vector2(bx + px, by), Color(1, 1, 1, 0.55), 1.5)
			draw_line(Vector2(bx, by - 4), Vector2(bx, by + 4), Color(1, 1, 1, 0.55), 1.0)
			draw_line(Vector2(bx + px, by - 4), Vector2(bx + px, by + 4), Color(1, 1, 1, 0.55), 1.0)
			draw_string(f, Vector2(bx, by - 8), "%d m" % int(cand),
				HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(10), Color(1, 1, 1, 0.72))
			break

	draw_string(f, Vector2(size.x - 66, 20), "x%.2f" % _zoom,
		HORIZONTAL_ALIGNMENT_LEFT, -1, AtcTheme.fs(11), Color(0.37, 0.92, 0.83, 0.70))


func _stand_index(stand: String) -> int:
	var digits := ""
	for i in range(stand.length()):
		var c := stand[i]
		if c >= "0" and c <= "9":
			digits += c
	if digits == "":
		return 0
	return clampi(int(digits) - 1, 0, 23)
