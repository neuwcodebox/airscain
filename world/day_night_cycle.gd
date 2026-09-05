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
var _sky_material: ProceduralSkyMaterial
var _moon: DirectionalLight3D
var _last_elapsed: float = -INF

func configure(sun: DirectionalLight3D, world_environment: WorldEnvironment, battlefield: Battlefield) -> void:
	_sun = sun
	_environment = world_environment.environment.duplicate() as Environment
	world_environment.environment = _environment
	_battlefield = battlefield
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_curve = 0.18
	_sky_material.sun_angle_max = 2.0
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.sky_material = _sky_material
	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Compatibility glow uses an LDR bright pass; avoid washing out the whole scene.
	_environment.glow_bloom = 0.0
	_environment.glow_hdr_scale = 1.4
	_moon = DirectionalLight3D.new()
	_moon.rotation_degrees = Vector3(-48, 115, 0)
	_moon.light_color = Color("839ac0")
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	apply_time(0.0)

static func hour_at(elapsed: float) -> float:
	return fposmod(START_HOUR + elapsed * 24.0 / CYCLE_SECONDS, 24.0)

func apply_time(elapsed: float, force: bool = false) -> void:
	if not force and absf(elapsed - _last_elapsed) < 0.1:
		return
	_last_elapsed = elapsed
	hour = hour_at(elapsed)
	var orbit := (hour - 6.0) / 24.0 * TAU
	var elevation := sin(orbit)
	var daylight := smoothstep(-0.10, 0.32, elevation)
	night_amount = 1.0 - smoothstep(-0.12, 0.16, elevation)
	var warmth := 1.0 - smoothstep(0.0, 0.55, elevation)
	_sun.rotation_degrees = Vector3(-rad_to_deg(asin(elevation)) * 0.72, -38.0 + (hour - 9.0) * 15.0, 0.0)
	_sun.light_color = Color(1.0, 0.91, 0.76).lerp(Color(1.0, 0.43, 0.19), warmth)
	_sun.light_energy = 1.2 * daylight
	_sun.shadow_enabled = elevation > 0.04
	_environment.ambient_light_color = Color("60769e").lerp(Color(0.62, 0.73, 0.82), daylight)
	_environment.ambient_light_energy = lerpf(0.22, 0.55, daylight)
	_moon.light_energy = 0.16 * night_amount
	_environment.glow_hdr_threshold = lerpf(0.9, 0.22, night_amount)
	_environment.glow_intensity = lerpf(0.65, 1.15, night_amount)
	_sky_material.sky_top_color = Color("010207").lerp(Color("294960"), daylight)
	_sky_material.sky_horizon_color = Color("03050b").lerp(Color("9f6451").lerp(Color("8196a1"), daylight), smoothstep(-0.25, 0.15, elevation))
	_sky_material.ground_horizon_color = _sky_material.sky_horizon_color
	_sky_material.ground_bottom_color = _sky_material.sky_top_color
	_battlefield.set_night_amount(night_amount)
