## 低多边形机场几何的程序化生成。
## 全部使用 Godot 内置 PrimitiveMesh，不依赖任何外部模型文件，
## 后期可直接把这里替换成 .glb 导入的场景。
class_name TerrainBuilder
extends RefCounted

# ---- 跑道 / 滑行道几何（单位：米） ----
const RWY_X := 195.0          # 跑道中心线横向偏移
const RWY_HALF_W := 30.0      # 半宽（60m，4F 级）
const RWY_HEAD := -250.0      # 近端入口
const RWY_END := -3440.0      # 远端
const RWY_TOP := 0.35         # 跑道道面高度

const TXY_X := 62.0
const TXY_HALF_W := 11.5

const C_GRASS := Color(0.300, 0.352, 0.222)
const C_ASPHALT := Color(0.140, 0.147, 0.156)
const C_CONCRETE := Color(0.286, 0.294, 0.304)
const C_MARK := Color(0.880, 0.888, 0.860)
const C_WARM_MARK := Color(0.80, 0.63, 0.26)
const C_HILL := Color(0.165, 0.192, 0.224)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	root.add_child(_ground())
	root.add_child(_apron())
	root.add_child(_runway())
	root.add_child(_markings())
	root.add_child(_taxiway())
	root.add_child(_taxiway_lights())
	root.add_child(_runway_lights())
	root.add_child(_terminal())
	root.add_child(_hangars())
	root.add_child(_vehicles())
	root.add_child(_approach_lights())
	root.add_child(_hills())
	return root


# ---------------------------------------------------------------- 基础构件

static func _mat(color: Color, roughness: float = 0.96) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	return m


static func _emit(color: Color, energy: float = 5.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _box(name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	return mi


# ---------------------------------------------------------------- 场景内容

static func _ground() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Grass"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	mi.mesh = pm
	mi.position = Vector3(0, 0, -2400)

	# 色斑要"低对比"，否则整片草地会像泥地
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.013
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(0.80, 0.80, 0.80), Color(1.0, 1.0, 1.0)])
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp

	var m := StandardMaterial3D.new()
	m.albedo_color = C_GRASS
	m.albedo_texture = tex
	m.uv1_scale = Vector3(150, 150, 1)
	m.roughness = 1.0
	m.metallic = 0.0
	mi.material_override = m
	return mi


static func _runway() -> MeshInstance3D:
	var length: float = RWY_HEAD - RWY_END
	var mid_z: float = (RWY_HEAD + RWY_END) * 0.5
	return _box("Runway", Vector3(RWY_HALF_W * 2.0, 0.7, length),
		Vector3(RWY_X, RWY_TOP - 0.35, mid_z), _mat(C_ASPHALT, 0.82))


static func _taxiway() -> Node3D:
	var root := Node3D.new()
	root.name = "Taxiway"
	var tail_z: float = RWY_END + 260.0
	var length: float = (RWY_HEAD - 380.0) - tail_z
	var mid_z: float = ((RWY_HEAD - 380.0) + tail_z) * 0.5
	root.add_child(_box("Parallel", Vector3(TXY_HALF_W * 2.0, 0.5, length),
		Vector3(TXY_X, 0.0, mid_z), _mat(C_ASPHALT, 0.82)))

	var link_cx: float = (RWY_X - RWY_HALF_W + TXY_X + TXY_HALF_W) * 0.5
	var link_w: float = RWY_X - RWY_HALF_W - (TXY_X + TXY_HALF_W)
	for z in [-620.0, -1850.0, -3050.0]:
		root.add_child(_box("Link", Vector3(link_w, 0.5, 26.0),
			Vector3(link_cx, 0.0, z), _mat(C_ASPHALT, 0.82)))
		root.add_child(_box("LinkLine", Vector3(link_w - 14.0, 0.02, 0.9),
			Vector3(link_cx, 0.27, z), _mat(C_WARM_MARK, 0.8)))

	root.add_child(_box("CenterLine", Vector3(0.9, 0.02, length),
		Vector3(TXY_X, 0.27, mid_z), _mat(C_WARM_MARK, 0.8)))
	return root


static func _apron() -> MeshInstance3D:
	return _box("Apron", Vector3(380, 0.35, 700),
		Vector3(-205, 0.05, -640), _mat(C_CONCRETE, 0.92))


static func _markings() -> Node3D:
	var root := Node3D.new()
	root.name = "Markings"
	var white := _mat(C_MARK, 0.8)
	var length: float = RWY_HEAD - RWY_END
	var mid_z: float = (RWY_HEAD + RWY_END) * 0.5
	var y: float = RWY_TOP + 0.02

	for side in [-1.0, 1.0]:
		root.add_child(_box("Edge", Vector3(1.0, 0.02, length),
			Vector3(RWY_X + side * (RWY_HALF_W - 1.6), y, mid_z), white))

	var dash := 30.0
	var gap := 50.0
	var z: float = RWY_HEAD - 60.0
	while z > RWY_END + 60.0:
		root.add_child(_box("Dash", Vector3(1.1, 0.02, dash),
			Vector3(RWY_X, y, z - dash * 0.5), white))
		z -= dash + gap

	for head in [RWY_HEAD, RWY_END]:
		var dir: float = -1.0 if head == RWY_HEAD else 1.0
		for i in range(8):
			var offx: float = (i - 3.5) * 3.8
			root.add_child(_box("Threshold", Vector3(2.0, 0.02, 32.0),
				Vector3(RWY_X + offx, y, head + dir * 24.0), white))
		for side in [-1.0, 1.0]:
			root.add_child(_box("Aiming", Vector3(8.0, 0.02, 26.0),
				Vector3(RWY_X + side * 12.0, y, head + dir * 340.0), white))
	return root


# ---------------------------------------------------------------- 灯光

static func _runway_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "RunwayLights"
	var white := _emit(Color(1.0, 0.96, 0.90), 9.0)
	var z: float = RWY_HEAD
	while z > RWY_END:
		for side in [-1.0, 1.0]:
			root.add_child(_box("RL", Vector3(1.0, 1.0, 1.0),
				Vector3(RWY_X + side * (RWY_HALF_W + 1.4), 0.9, z), white))
		z -= 100.0
	# 入口绿灯 / 末端红灯
	var green := _emit(Color(0.30, 1.0, 0.48), 8.0)
	var red := _emit(Color(1.0, 0.24, 0.22), 8.0)
	for i in range(7):
		var offx: float = (i - 3.0) * 8.0
		root.add_child(_box("THR", Vector3(1.2, 1.2, 1.2),
			Vector3(RWY_X + offx, 0.9, RWY_HEAD + 2.0), green))
		root.add_child(_box("END", Vector3(1.2, 1.2, 1.2),
			Vector3(RWY_X + offx, 0.9, RWY_END - 2.0), red))
	return root


static func _taxiway_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "TaxiwayLights"
	var blue := _emit(Color(0.32, 0.55, 1.0), 7.0)
	var z: float = RWY_HEAD - 380.0
	while z > RWY_END + 260.0:
		for side in [-1.0, 1.0]:
			root.add_child(_box("TL", Vector3(0.9, 0.9, 0.9),
				Vector3(TXY_X + side * (TXY_HALF_W + 1.4), 0.8, z), blue))
		z -= 120.0
	return root


static func _approach_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "ApproachLights"
	var light := _emit(Color(1.0, 0.93, 0.80), 7.0)
	var z: float = RWY_HEAD - 30.0
	while z > RWY_HEAD - 940.0:
		root.add_child(_box("AL", Vector3(0.8, 0.8, 0.8), Vector3(RWY_X, 0.6, z), light))
		z -= 30.0
	var cross := _emit(Color(1.0, 0.95, 0.85), 6.0)
	for k in range(5):
		root.add_child(_box("Cross", Vector3(26.0, 0.4, 0.4),
			Vector3(RWY_X, 0.6, RWY_HEAD - 300.0 - k * 240.0), cross))
	return root


# ---------------------------------------------------------------- 建筑

static func _terminal() -> Node3D:
	var root := Node3D.new()
	root.name = "Terminal"
	var body := _mat(Color(0.376, 0.392, 0.408), 0.85)
	var glass := _mat(Color(0.110, 0.156, 0.184), 0.22)
	var win := _emit(Color(1.0, 0.85, 0.58), 2.2)
	root.add_child(_box("Hall", Vector3(120, 26, 300), Vector3(-250, 13, -620), body))
	root.add_child(_box("Glass", Vector3(121.5, 9, 301.5), Vector3(-250, 15, -620), glass))
	root.add_child(_box("Pier", Vector3(26, 16, 250), Vector3(-150, 8, -640), body))
	root.add_child(_box("Roof", Vector3(142, 1.4, 322), Vector3(-250, 26.7, -620),
		_mat(Color(0.216, 0.227, 0.239))))
	# 候机楼窗光
	for i in range(10):
		root.add_child(_box("Win", Vector3(2.2, 5.0, 18.0),
			Vector3(-189.0, 14.0, -480 - i * 30.0), win))
	# 机位泛光灯杆
	var lamp := _emit(Color(1.0, 0.88, 0.62), 5.0)
	for i in range(7):
		root.add_child(_box("Pole", Vector3(0.7, 26.0, 0.7),
			Vector3(-118, 13.0, -470 - i * 46.0), _mat(Color(0.25, 0.26, 0.27))))
		root.add_child(_box("LampHead", Vector3(3.0, 1.0, 1.0),
			Vector3(-118, 26.0, -470 - i * 46.0), lamp))
	return root


static func _hangars() -> Node3D:
	var root := Node3D.new()
	root.name = "Hangars"
	var wall := _mat(Color(0.318, 0.333, 0.345), 0.9)
	var roof := _mat(Color(0.216, 0.227, 0.239), 0.9)
	for i in range(3):
		var z: float = -1000.0 - i * 130.0
		root.add_child(_box("Hangar", Vector3(95, 22, 85), Vector3(-390, 11, z), wall))
		root.add_child(_box("Roof", Vector3(99, 1.4, 89), Vector3(-390, 22.7, z), roof))
	return root


# ---------------------------------------------------------------- 地面车辆

## 机坪上的地勤车辆，给静止画面一点"活着的机场"的感觉。
static func _vehicles() -> Node3D:
	var root := Node3D.new()
	root.name = "Vehicles"
	var white := _mat(Color(0.855, 0.867, 0.878), 0.7)
	var orange := _mat(Color(0.902, 0.478, 0.129), 0.7)
	var yellow := _mat(Color(0.902, 0.776, 0.180), 0.7)
	var beacon := _emit(Color(1.0, 0.72, 0.18), 6.0)

	var spots := [
		[Vector3(-118.0, 0.9, -486.0), white, Vector3(6.0, 2.4, 2.6)],
		[Vector3(-100.0, 0.9, -560.0), orange, Vector3(4.2, 2.0, 2.2)],
		[Vector3(-88.0, 0.9, -644.0), yellow, Vector3(9.0, 2.8, 2.8)],
		[Vector3(-112.0, 0.9, -716.0), white, Vector3(3.6, 1.8, 2.0)],
		[Vector3(-96.0, 0.9, -808.0), orange, Vector3(5.0, 2.2, 2.4)],
		[Vector3(-130.0, 0.9, -872.0), white, Vector3(6.4, 2.4, 2.6)],
	]
	for s in spots:
		var pos: Vector3 = s[0]
		var mat: Material = s[1]
		var size: Vector3 = s[2]
		root.add_child(_box("Vehicle", size, pos, mat))
		root.add_child(_box("Beacon", Vector3(0.5, 0.5, 0.5),
			pos + Vector3(0, size.y * 0.5 + 0.3, 0), beacon))
	return root


# ---------------------------------------------------------------- 远山

static func _hills() -> Node3D:
	var root := Node3D.new()
	root.name = "Hills"
	var mat := _mat(C_HILL, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for i in range(18):
		# θ 从 -Z 轴量起，铺在塔台正前方 ±52° 的扇面上
		var theta: float = deg_to_rad(lerp(-52.0, 52.0, float(i) / 17.0))
		var dist: float = rng.randf_range(2800.0, 5200.0)
		var h: float = rng.randf_range(180.0, 520.0)
		var r: float = rng.randf_range(450.0, 1150.0)
		var mi := MeshInstance3D.new()
		mi.name = "Hill"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 5
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		mi.position = Vector3(sin(theta) * dist, h * 0.5 - 30.0, -cos(theta) * dist)
		mi.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(mi)
	return root
