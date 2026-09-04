class_name TrainingController
extends Node

enum Step { NONE, CAMERA, RADAR, COMMAND, WEAPON, START, ACQUIRE, SELECT_TRACK, SELECT_ASSET, DOCTRINE, ENGAGE, SUPPORT, RESUPPLY, OVERLAY, COMPLETE }

signal selection_clear_requested

const APPROACH_DISTANCE_RATIO := 0.58

var step: Step = Step.NONE
var training_threat_runtime_id: int = 0
var scenario: ScenarioDefinition
var battlefield: Battlefield
var objective: ProtectedObjective
var defenses: Array[DefenseUnit]
var registry: ThreatRegistry
var director: ThreatDirector
var session: GameSession
var hud: Hud
var tactical_screen_overlay: Node

func configure(scenario_value: ScenarioDefinition, battlefield_value: Battlefield, objective_value: ProtectedObjective, defenses_value: Array[DefenseUnit], registry_value: ThreatRegistry, director_value: ThreatDirector, session_value: GameSession, hud_value: Hud, tactical_screen_overlay_value: Node) -> void:
	scenario = scenario_value
	battlefield = battlefield_value
	objective = objective_value
	defenses = defenses_value
	registry = registry_value
	director = director_value
	session = session_value
	hud = hud_value
	tactical_screen_overlay = tactical_screen_overlay_value

func begin() -> void:
	tactical_screen_overlay.call("show_training_approach", objective.global_position, approach_position())
	_set_step(Step.CAMERA)

func can_start_defense() -> bool:
	return step == Step.START

func defense_started() -> void:
	session.set_simulation_speed(1.0)
	hud.set_catalog_expanded(false)
	_set_step(Step.ACQUIRE)
	_spawn_training_threat()

func defense_placed(unit: DefenseUnit) -> void:
	if step == Step.RADAR and unit.definition.id == &"search_radar":
		_set_step(Step.COMMAND)
	elif step == Step.COMMAND and unit.definition.id == &"command_post":
		_set_step(Step.WEAPON)
	elif step == Step.WEAPON and unit is MissileBattery:
		unit.set_hold_fire(true)
		hud.refresh_selected_asset()
		_set_step(Step.START)
	elif step == Step.SUPPORT and unit.service_range() > 0.0:
		var battery := _training_battery()
		if battery != null:
			for munition_magazine: WeaponMagazine in battery.magazines.values():
				munition_magazine.reserve = 0
		selection_clear_requested.emit()
		_set_step(Step.RESUPPLY)

func tracks_refreshed(selectable_hostile_count: int) -> void:
	if step != Step.ACQUIRE or selectable_hostile_count <= 0:
		return
	session.set_simulation_speed(0.0)
	tactical_screen_overlay.call("hide_training_approach")
	_set_step(Step.SELECT_TRACK)

func track_selected(track: PlayerTrack) -> void:
	if step == Step.SELECT_TRACK and track != null:
		_set_step(Step.SELECT_ASSET)

func asset_selected(unit: DefenseUnit) -> void:
	if step == Step.SELECT_ASSET and unit is MissileBattery:
		_set_step(Step.DOCTRINE)

func hold_fire_changed(enabled: bool) -> void:
	if step == Step.DOCTRINE and not enabled:
		session.set_simulation_speed(1.0)
		_set_step(Step.ENGAGE)

func threat_resolved(threat: ThreatUnit) -> void:
	if threat.runtime_id != training_threat_runtime_id or step != Step.ENGAGE:
		return
	session.set_simulation_speed(0.0)
	_set_step(Step.SUPPORT)

func resupply_requested(succeeded: bool) -> void:
	if succeeded and step == Step.RESUPPLY:
		_set_step(Step.OVERLAY)

func overlay_selected(mode: StringName) -> void:
	if step == Step.OVERLAY and mode != &"none":
		_set_step(Step.COMPLETE)

func next_requested() -> void:
	if step == Step.CAMERA:
		_set_step(Step.RADAR)

func approach_position() -> Vector3:
	var position := objective.global_position + Vector3.RIGHT * scenario.battlefield_size * APPROACH_DISTANCE_RATIO
	position.y = battlefield.flight_surface_height(position.x, position.z) + 80.0
	return position

func _set_step(next_step: Step) -> void:
	step = next_step
	match step:
		Step.CAMERA:
			hud.set_training_lesson(1, 13, "전장 살펴보기", "WASD로 이동하고 Q/E 또는 우클릭 드래그로 회전하며, 주황색 훈련 표적 진입 표시를 찾아보세요.", true)
		Step.RADAR:
			hud.set_training_lesson(2, 13, "탐색 센서", "상단의 방공 자산을 열어 탐색 레이더를 고르세요. 표적은 주황색 진입 표시 너머 먼 해상에서 오므로 도시와 진입 표시 사이의 평탄한 지형에 배치하세요.")
		Step.COMMAND:
			hud.set_training_lesson(3, 13, "지휘통제 연결", "방공 자산을 다시 열어 지휘통제소를 고르고, 레이더와 연결될 거리 안에 배치해 항적 공유 경로를 만드세요.")
		Step.WEAPON:
			hud.set_training_lesson(4, 13, "요격 계층", "방공 자산에서 미사일 포대를 골라 도시와 주황색 진입 표시 사이, 지휘통제망 안에 배치하세요. 포대는 사격중지 상태로 준비됩니다.")
		Step.START:
			hud.set_training_lesson(5, 13, "방어 시작", "오른쪽 아래의 방어 시작을 누르세요. 표적 탐지까지 훈련이 자동 재생됩니다.")
		Step.ACQUIRE:
			hud.set_training_lesson(6, 13, "탐지와 항적 · 자동 재생", "진입 표시 너머 먼 해상에서 접근하는 표적을 레이더가 확인할 때까지 관찰하세요. 확인 즉시 자동 일시정지됩니다.")
		Step.SELECT_TRACK:
			hud.set_training_lesson(7, 13, "항적 선택 · 일시정지", "지도에 나타난 적성 항적 표식을 클릭해 분류·소속·추적 품질을 확인하세요.")
		Step.SELECT_ASSET:
			hud.set_training_lesson(8, 13, "방어자산 선택 · 일시정지", "배치한 미사일 포대를 클릭해 탄약, C2 연결과 교전규칙을 확인하세요.")
		Step.DOCTRINE:
			hud.set_training_lesson(9, 13, "자동교전 허용 · 일시정지", "선택 패널에서 체크된 사격중지를 해제하세요. 해제하면 자동 재생됩니다.")
		Step.ENGAGE:
			hud.set_training_lesson(10, 13, "자동교전 관찰 · 자동 재생", "포대가 선회·조준하고 표적을 요격하는 과정을 관찰하세요. 교전 종료 후 자동 일시정지됩니다.")
		Step.SUPPORT:
			hud.set_catalog_expanded(true)
			hud.set_training_lesson(11, 13, "통합 지원", "열린 방공 자산에서 통합 지원기지를 골라 배치하세요. 배치 후 포대의 예비탄을 훈련용으로 소진시킵니다.")
		Step.RESUPPLY:
			hud.set_training_lesson(12, 13, "재보급 작업 · 일시정지", "미사일 포대를 다시 선택하세요. 활성화된 재보급 요청을 눌러 지원 대기열에 작업을 넣으세요.")
		Step.OVERLAY:
			hud.set_training_lesson(13, 13, "전술 오버레이 · 일시정지", "상단의 범위 없음 버튼을 눌러 센서·교전·지원 또는 C2 오버레이를 확인하세요.")
		Step.COMPLETE:
			session.set_simulation_speed(1.0)
			hud.set_training_lesson(13, 13, "훈련 완료 · 재생", "핵심 운용을 완료했습니다. 자유롭게 연습하거나 Esc로 메인 메뉴에 돌아가세요.")

func _spawn_training_threat() -> void:
	if _training_battery() == null or not _has_search_radar():
		return
	var threat := director._spawn_entry(scenario.threat_entries[0], 0.0, 0.0)
	if threat == null:
		return
	training_threat_runtime_id = threat.runtime_id
	threat.global_position = approach_position()
	if threat is AttackUav:
		(threat as AttackUav).speed_multiplier = 0.65
	tactical_screen_overlay.call("show_training_approach", objective.global_position, threat.global_position)

func _has_search_radar() -> bool:
	for defense: DefenseUnit in defenses:
		if defense.definition.id == &"search_radar":
			return true
	return false

func _training_battery() -> MissileBattery:
	for defense: DefenseUnit in defenses:
		if defense is MissileBattery:
			return defense as MissileBattery
	return null
