## 塔台窗景：相机、天空、光照、地形、飞机，以及镜头呼吸。
## 纯表现层 —— 这里任何一个数字都不影响仿真逻辑。
class_name TowerView
extends Node3D

const CAM_HEIGHT := 42.0
const CAM_PITCH := -7.0
const CAM_FOV := 62.0

# 进近飞机：沿跑道中线下降
const APCH_Z0 := -820.0
const APCH_Z1 := -235.0
const APCH_Y0 := 88.0
const APCH_Y1 := 16.0
const APCH_PERIOD := 24.0

var _camera: Camera3D
var _plane_final: AircraftModel
var _plane_taxi: AircraftModel
var _t := 0.0


func _ready() -> void:
	name = "TowerView"
	_build_environment()
	_build_lights()
	_build_camera()
	add_child(TerrainBuilder.build())
	_build_aircraft()


func _process(delta: float) -> void:
	_t += delta
	_drift_camera()
	_animate_aircraft()


# ---------------------------------------------------------------- 环境

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "Environment"

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.118, 0.180, 0.365)
	sky_mat.sky_horizon_color = Color(0.965, 0.678, 0.435)
	sky_mat.sky_curve = 0.22
	sky_mat.sky_energy_multiplier = 0.95
	sky_mat.ground_horizon_color = Color(0.529, 0.412, 0.353)
	sky_mat.ground_bottom_color = Color(0.055, 0.059, 0.067)
	sky_mat.ground_curve = 0.10
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.05

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 0.78
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.678, 0.612, 0.573)
	env.fog_light_energy = 0.55
	env.fog_density = 0.00007
	env.fog_sky_affect = 0.22
	env.fog_aerial_perspective = 0.18

	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1

	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# 太阳放在左前方偏后：侧顺光，跑道有长投影，低多边形棱面才立得起来
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.784, 0.573)
	sun.light_energy = 2.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.045
	sun.directional_shadow_max_distance = 3400.0
	sun.rotation_degrees = Vector3(-23.0, -112.0, 0.0)
	add_child(sun)

	# 冷色补光，压住阴影里的死黑
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.478, 0.620, 0.827)
	fill.light_energy = 0.38
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, 56.0, 0.0)
	add_child(fill)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "TowerCam"
	_camera.position = Vector3(0.0, CAM_HEIGHT, 0.0)
	_camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)
	_camera.fov = CAM_FOV
	_camera.near = 0.1
	_camera.far = 12000.0
	add_child(_camera)


# ---------------------------------------------------------------- 飞机

func _build_aircraft() -> void:
	_plane_final = AircraftModel.create(Color(0.914, 0.918, 0.925), Color(0.129, 0.404, 0.639))
	_plane_final.name = "FinalApproach"
	add_child(_plane_final)

	_plane_taxi = AircraftModel.create(Color(0.851, 0.867, 0.882), Color(0.729, 0.239, 0.239))
	_plane_taxi.name = "Taxiing"
	_plane_taxi.scale = Vector3(0.94, 0.94, 0.94)
	add_child(_plane_taxi)


func _animate_aircraft() -> void:
	# 五边进近：p 从 0→1 循环，高度二次下降（近地慢）
	var p: float = fmod(_t / APCH_PERIOD, 1.0)
	var z: float = lerpf(APCH_Z0, APCH_Z1, p)
	var y: float = lerpf(APCH_Y0, APCH_Y1, p * p)
	_plane_final.position = Vector3(TerrainBuilder.RWY_X, y, z)
	_plane_final.rotation_degrees = Vector3(-2.4, 0.0, sin(_t * 0.55) * 1.2)

	# 地面滑行：沿滑行道缓慢前推
	var q: float = fmod(_t / 52.0, 1.0)
	var tz: float = lerpf(-1050.0, -330.0, q)
	_plane_taxi.position = Vector3(TerrainBuilder.TXY_X, 0.3, tz)
	_plane_taxi.rotation_degrees = Vector3.ZERO


# ---------------------------------------------------------------- 镜头呼吸

func _drift_camera() -> void:
	if _camera == null:
		return
	_camera.rotation_degrees.y = sin(_t * 0.043) * 1.7
	_camera.rotation_degrees.x = CAM_PITCH + sin(_t * 0.061 + 1.1) * 0.34
	_camera.rotation_degrees.z = sin(_t * 0.037) * 0.15
