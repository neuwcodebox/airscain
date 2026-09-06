class_name ThreatResolutionProfile
extends Resource
## Content-authored visuals, independent of sensor classification and mission AI.

@export var leave_wreck: bool = true
@export var explosion: bool = true
@export var wreck_color := Color(0.45, 0.16, 0.1)
@export var wreck_scale: float = 1.0
@export var wreck_smoke: bool = true
@export var landing_flash: bool = true

func validation_error() -> String:
	return "잔해 축척이 올바르지 않습니다" if not is_finite(wreck_scale) or wreck_scale <= 0.0 else ""
