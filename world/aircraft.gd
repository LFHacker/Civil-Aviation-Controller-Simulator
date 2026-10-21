## 低多边形飞机模型：全部由内置 PrimitiveMesh 拼装。
## 尺寸按真实客机量级（机身 ~40m，翼展 ~36m），方便直接摆进真实比例的机场。
## 以后换成 Blender 导出的 .glb 时，只需替换 _build() 里的拼装逻辑。
class_name AircraftModel
extends Node3D

var _body_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D


static func create(body_color: Color, stripe_color: Color) -> AircraftModel:
	var a := AircraftModel.new()
	a.name = "Aircraft"
	a._build(body_color, stripe_color)
	return a


func _build(body_color: Color, stripe_color: Color) -> void:
	_body_mat = _solid(body_color, 0.42)
	_stripe_mat = _solid(stripe_color, 0.38)
	_dark_mat = _solid(Color(0.075, 0.085, 0.095), 0.55)

	# 机身
	_add_cylinder(Vector3(1.92, 1.92, 0), 34.0, 10, Vector3(0, 0, 0), 0.0, _body_mat)
	# 机头锥（朝 -Z）
	_add_cone(Vector3(1.92, 0.0, 0), 4.6, 10, Vector3(0, 0, -19.3), 180.0, _body_mat)
	# 尾锥（朝 +Z）
	_add_cone(Vector3(1.92, 0.55, 0), 5.4, 10, Vector3(0, 0.28, 19.6), 0.0, _body_mat)

	# 主翼
	_add_box(Vector3(36.0, 0.55, 5.1), Vector3(0, -0.45, -2.2), Vector3.ZERO, _body_mat)
	# 平尾
	_add_box(Vector3(13.2, 0.42, 3.3), Vector3(0, 0.15, 13.4), Vector3.ZERO, _body_mat)
	# 垂尾
	_add_box(Vector3(0.45, 7.0, 5.6), Vector3(0, 3.6, 12.9), Vector3(deg_to_rad(-14.0), 0, 0), _body_mat)

	# 发动机短舱
	for side in [-1.0, 1.0]:
		_add_cylinder(Vector3(1.35, 1.15, 0), 5.2, 8,
			Vector3(side * 5.2, -1.75, -2.8), 0.0, _dark_mat)
		_add_cylinder(Vector3(1.42, 1.42, 0), 0.5, 8,
			Vector3(side * 5.2, -1.75, -5.35), 0.0, _stripe_mat)

	# 舷窗带
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.1, 0.42, 21.0), Vector3(side * 1.9, 0.62, -1.0), Vector3.ZERO, _dark_mat)

	# 涂装色带
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.12, 0.75, 26.0), Vector3(side * 1.92, -0.55, 0.0), Vector3.ZERO, _stripe_mat)

	# 航行灯：左红右绿尾白
	_add_box(Vector3(0.5, 0.5, 0.5), Vector3(-18.0, -0.35, -2.2), Vector3.ZERO, _emit(Color(1.0, 0.18, 0.18)))
	_add_box(Vector3(0.5, 0.5, 0.5), Vector3(18.0, -0.35, -2.2), Vector3.ZERO, _emit(Color(0.25, 1.0, 0.42)))
	_add_box(Vector3(0.4, 0.4, 0.4), Vector3(0, 6.9, 14.2), Vector3.ZERO, _emit(Color(1.0, 1.0, 0.9)))


# ---------------------------------------------------------------- 构件工具

func _solid(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	return m


func _emit(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 8.0
	return m


func _add_box(size: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	add_child(mi)


func _add_cylinder(radii: Vector3, height: float, seg: int, pos: Vector3, rot_y_deg: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radii.x
	cm.top_radius = radii.x
	cm.height = height
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = Vector3(90.0, rot_y_deg, 0.0)
	mi.material_override = mat
	add_child(mi)


func _add_cone(radii: Vector3, height: float, seg: int, pos: Vector3, tilt_deg: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radii.x
	cm.top_radius = radii.y
	cm.height = height
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = Vector3(90.0 + tilt_deg, 0.0, 0.0)
	mi.material_override = mat
	add_child(mi)
