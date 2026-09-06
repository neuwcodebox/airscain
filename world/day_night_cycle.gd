class_name DayNightCycle
extends Node
## Presentation derived from the saved simulation clock, never a sensor modifier.

const CYCLE_SECONDS: float = 720.0
const START_HOUR: float = 9.0
var hour: float = START_HOUR
var night_amount: float = 0.0
var _sun: DirectionalLight3D
var _environment: Environment
var _battlefield: Battlefield
var _sky_material: ShaderMaterial
var _ocean_material: ShaderMaterial
var _moon: DirectionalLight3D
var _last_elapsed: float = -INF
var _last_motion_elapsed: float = -INF

func configure(sun: DirectionalLight3D, world_environment: WorldEnvironment, battlefield: Battlefield) -> void:
	_sun = sun
	_sun.shadow_enabled = true
	_environment = world_environment.environment.duplicate() as Environment
	world_environment.environment = _environment
	_battlefield = battlefield
	_battlefield.configure_smoke_shadows(sun)
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("res://world/living_sky.gdshader")
	_sky_material.set_shader_parameter("cloud_noise", preload("res://world/sky_noise.tres"))
	if battlefield.ocean != null:
		_ocean_material = battlefield.ocean.mesh.surface_get_material(0) as ShaderMaterial
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.sky_material = _sky_material
	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# Compatibility glow uses an LDR bright pass; avoid washing out the whole scene.
	_environment.glow_bloom = 0.0
	_environment.glow_hdr_scale = 1.4
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("839ac0")
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	apply_time(0.0)

static func hour_at(elapsed: float) -> float:
	return fposmod(START_HOUR + elapsed * 24.0 / CYCLE_SECONDS, 24.0)

static func orbit_rotation(time_hour: float) -> Vector3:
	var elevation := sin((time_hour - 6.0) / 24.0 * TAU)
	return Vector3(-rad_to_deg(asin(elevation)) * 0.72, -38.0 + (time_hour - 9.0) * 15.0, 0.0)

func apply_time(elapsed: float, force: bool = false) -> void:
	if not force and elapsed == _last_motion_elapsed:
		return
	_last_motion_elapsed = elapsed
	hour = hour_at(elapsed)
	var orbit := (hour - 6.0) / 24.0 * TAU
	# Small celestial discs must move every simulation frame, not in 10 Hz steps.
	_sun.rotation_degrees = orbit_rotation(hour)
	_moon.rotation_degrees = orbit_rotation(fposmod(hour + 12.0, 24.0))
	_sky_material.set_shader_parameter("moon_direction", _moon.basis.z.normalized())
	_sky_material.set_shader_parameter("sky_clock", elapsed)
	_sky_material.set_shader_parameter("star_rotation", orbit)
	for material: ShaderMaterial in [_sky_material, _ocean_material]:
		if material != null:
			material.set_shader_parameter("sun_direction", _sun.basis.z.normalized())
	if not force and absf(elapsed - _last_elapsed) < 0.1:
		return
	_last_elapsed = elapsed
	var elevation := sin(orbit)
	var daylight := smoothstep(-0.10, 0.32, elevation)
	night_amount = 1.0 - smoothstep(-0.12, 0.16, elevation)
	var warmth := 1.0 - smoothstep(0.0, 0.55, elevation)
	_sun.light_color = Color(1.0, 0.91, 0.76).lerp(Color(1.0, 0.43, 0.19), warmth)
	_sun.light_energy = 1.2 * daylight
	# A zero-energy sun contributes no light, but still submits shadow passes.
	# Only retire it after the existing twilight light and shadow fades finish.
	_sun.visible = _sun.light_energy > 0.0
	# Fade long horizon shadows before twilight; never switch a visible shadow off.
	_sun.shadow_opacity = smoothstep(0.02, 0.20, elevation)
	_environment.ambient_light_color = Color("60769e").lerp(Color(0.62, 0.73, 0.82), daylight)
	_environment.ambient_light_energy = lerpf(0.22, 0.55, daylight)
	_moon.light_energy = 0.16 * night_amount
	_environment.glow_hdr_threshold = lerpf(0.9, 0.22, night_amount)
	_environment.glow_intensity = lerpf(0.65, 1.15, night_amount)
	var twilight := (1.0 - smoothstep(0.02, 0.45, absf(elevation))) * smoothstep(-0.3, -0.02, elevation)
	var zenith := Color("030815").lerp(Color("32699b"), daylight)
	var horizon := Color("142139").lerp(Color("b9d3dc"), daylight).lerp(Color("ac7886"), twilight * 0.5)
	for material: ShaderMaterial in [_sky_material, _ocean_material]:
		if material == null:
			continue
		material.set_shader_parameter("zenith_color", zenith)
		material.set_shader_parameter("horizon_color", horizon)
		material.set_shader_parameter("daylight", daylight)
		material.set_shader_parameter("twilight", twilight)
	_sky_material.set_shader_parameter("night_amount", night_amount)
	_battlefield.set_night_amount(night_amount)
