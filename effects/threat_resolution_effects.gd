class_name ThreatResolutionEffects
extends Node
## Consumes final threat state; never owns damage, rewards, or registry membership.

const WRECK_SCENE := preload("res://effects/falling_wreck/falling_wreck.tscn")
var battlefield: Battlefield
var effects_parent: Node3D
var audio: CombatAudio

func configure(world: Battlefield, parent: Node3D, combat_audio: CombatAudio) -> void:
	battlefield = world
	effects_parent = parent
	audio = combat_audio

func present(threat: ThreatUnit, neutralized: bool) -> void:
	var profile := threat.definition.resolution_profile
	if neutralized and profile != null and profile.leave_wreck:
		spawn_wreck(threat)
	if not threat.definition.has_resolution_explosion():
		return
	if neutralized or not threat.impact_uses_objective_audio():
		audio.play_event(CombatAudio.EXPLOSION, 0.8 if neutralized else 1.0)
	ExplosionEffect.spawn(effects_parent, threat.global_position, Color("ff8c35") if neutralized else Color("ff3b24"), 10.0 if neutralized else 15.0)

func spawn_wreck(threat: ThreatUnit) -> void:
	var profile := threat.definition.resolution_profile
	if profile == null:
		return
	var effect := WRECK_SCENE.instantiate() as FallingWreckEffect
	effect.battlefield = battlefield
	effects_parent.add_child(effect)
	effect.global_position = threat.global_position
	var ground := battlefield.terrain_height(threat.global_position.x, threat.global_position.z)
	effect.setup(threat.definition.wreck_tint(), threat.presentation_velocity(), ground, profile.wreck_scale, profile.wreck_smoke, profile.landing_flash)
	effect.use_airframe(threat)
