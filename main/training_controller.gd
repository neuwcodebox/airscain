class_name TrainingController
extends Node

enum Step { NONE, CAMERA, RADAR, WEAPON, CONNECT, ACQUIRE, SELECT_TRACK, DOCTRINE, ENGAGE, SUPPORT, RESUPPLY, WAIT_RESUPPLY, REPAIR, WAIT_REPAIR, CITY_RESTORE, COMPLETE, RELOCATE, WAIT_RELOCATE }

signal selection_clear_requested

const LESSON_COUNT := 14

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
var c2_network: C2Network
var relocation_subject: DefenseUnit
var training_battery: MissileBattery

func configure(scenario_value: ScenarioDefinition, battlefield_value: Battlefield, objective_value: ProtectedObjective, defenses_value: Array[DefenseUnit], registry_value: ThreatRegistry, director_value: ThreatDirector, session_value: GameSession, hud_value: Hud, tactical_screen_overlay_value: Node, network_value: C2Network) -> void:
	scenario = scenario_value
	battlefield = battlefield_value
	objective = objective_value
	defenses = defenses_value
	registry = registry_value
	director = director_value
	session = session_value
	hud = hud_value
	tactical_screen_overlay = tactical_screen_overlay_value
	c2_network = network_value

func begin() -> void:
	session.start_defense()
	session.set_simulation_speed(0.0)
	_spawn_training_threat()
	tactical_screen_overlay.call("show_training_approach", objective.global_position, approach_position())
	_set_step(Step.CAMERA)

func _try_observe_approach() -> void:
	if step != Step.CONNECT:
		return
	var battery := _training_battery()
	relocation_subject = battery
	for unit: DefenseUnit in defenses:
		if unit.definition.id == &"search_radar" and not c2_network.has_command_path(unit, unit.runtime_id):
			relocation_subject = unit
		if unit.definition.id == &"search_radar" and c2_network.has_command_path(battery, unit.runtime_id):
			session.set_simulation_speed(1.0)
			hud.set_catalog_expanded(false)
			_set_step(Step.ACQUIRE)
			return

func defense_placed(unit: DefenseUnit) -> void:
	if step == Step.RADAR and unit.definition.id == &"search_radar":
		_set_step(Step.WEAPON)
	elif step == Step.WEAPON and unit is MissileBattery:
		training_battery = unit as MissileBattery
		unit.set_hold_fire(true)
		hud.refresh_selected_asset()
		_set_step(Step.CONNECT)
		_try_observe_approach()
	elif step == Step.SUPPORT and unit.service_range() > 0.0:
		var battery := _training_battery()
		if battery == null or not unit.supports_position(battery.global_position):
			hud.set_feedback("포대까지 녹색 지원선이 연결되는 범위 안에 지원기지를 배치하세요.")
			return
		selection_clear_requested.emit()
		_set_step(Step.RESUPPLY)

func tracks_refreshed(_selectable_hostile_count: int) -> void:
	_try_observe_approach()
	if step != Step.ACQUIRE:
		return
	var overlay := tactical_screen_overlay as TacticalScreenOverlay
	for track: PlayerTrack in overlay.player_knowledge.call("get_active_tracks"):
		if is_selectable_training_track(track):
			_set_step(Step.SELECT_TRACK)
			return
	_check_detection_obstruction()

func _check_detection_obstruction() -> void:
	for threat: ThreatUnit in registry.get_hostile_active():
		if threat.runtime_id != training_threat_runtime_id:
			continue
		for unit: DefenseUnit in defenses:
			if not unit is SearchRadar or not unit.active:
				continue
			var radar := unit as SearchRadar
			var definition := radar.definition as SearchRadarDefinition
			var origin := radar.global_position + Vector3.UP * 11.0
			if origin.distance_to(threat.get_aim_position()) > definition.detection_range * radar.operational_efficiency():
				continue
			if radar.altitude_in_envelope(threat.get_aim_position()) and not radar._has_line_of_sight(origin, threat.get_aim_position()):
				relocation_subject = radar
				_set_step(Step.RELOCATE)
				return

func is_selectable_training_track(track: PlayerTrack) -> bool:
	return track != null and track.state == PlayerTrack.State.CONFIRMED and track.affiliation == PlayerTrack.Affiliation.HOSTILE and track.affiliation_confidence >= 0.3

func track_selected(track: PlayerTrack) -> void:
	if step == Step.SELECT_TRACK and is_selectable_training_track(track):
		_set_step(Step.DOCTRINE)

func asset_selected(unit: DefenseUnit) -> void:
	if step == Step.DOCTRINE and unit == _training_battery():
		_lesson("사격 허용", "선택 패널에서 사격중지를 해제하세요. 포대가 탐지된 적을 자동으로 조준하고 발사합니다.")

func hold_fire_changed(enabled: bool, unit: DefenseUnit) -> void:
	if step == Step.DOCTRINE and not enabled and unit == _training_battery():
		session.set_simulation_speed(1.0)
		_set_step(Step.ENGAGE)

func threat_resolved(threat: ThreatUnit) -> void:
	if threat.runtime_id != training_threat_runtime_id or step != Step.ENGAGE:
		return
	session.set_simulation_speed(0.0)
	var battery := _training_battery()
	if battery != null:
		for magazine: WeaponMagazine in battery.magazines.values():
			magazine.reserve = 0
		hud.refresh_selected_asset()
	_set_step(Step.SUPPORT)

func support_requested(kind: StringName, unit: DefenseUnit) -> void:
	if unit != _training_battery():
		return
	if kind == &"resupply" and step == Step.RESUPPLY:
		session.set_simulation_speed(1.0)
		_set_step(Step.WAIT_RESUPPLY)
	elif kind == &"repair" and step == Step.REPAIR:
		session.set_simulation_speed(1.0)
		_set_step(Step.WAIT_REPAIR)

func support_completed(kind: StringName, unit: DefenseUnit) -> void:
	if unit != _training_battery():
		return
	if step == Step.WAIT_RESUPPLY and kind == &"resupply":
		session.set_simulation_speed(0.0)
		unit.receive_damage(unit.definition.maximum_integrity * 0.25)
		hud.refresh_selected_asset()
		_set_step(Step.REPAIR)
	elif step == Step.WAIT_REPAIR and kind == &"repair":
		session.set_simulation_speed(0.0)
		if objective.current_integrity > objective.definition.maximum_integrity - objective.definition.restoration_amount:
			objective.apply_mission_damage(objective.definition.restoration_amount)
		_set_step(Step.CITY_RESTORE)

func city_restored() -> void:
	if step == Step.CITY_RESTORE:
		_set_step(Step.COMPLETE)

func relocation_started(unit: DefenseUnit) -> void:
	if step in [Step.CONNECT, Step.RELOCATE] and unit == relocation_subject:
		_set_step(Step.WAIT_RELOCATE)

func relocation_completed(unit: DefenseUnit) -> void:
	if step == Step.WAIT_RELOCATE and unit == relocation_subject:
		_set_step(Step.CONNECT)
		_try_observe_approach()
	elif step == Step.SUPPORT and unit.service_range() > 0.0:
		defense_placed(unit)

func next_requested() -> void:
	if step == Step.CAMERA:
		_set_step(Step.RADAR)

func approach_position() -> Vector3:
	var position := objective.global_position + Vector3.RIGHT * scenario.battlefield_size * scenario.threat_entries[0].threat_definition.spawn_radius_multiplier()
	position.y = battlefield.flight_surface_height(position.x, position.z) + 80.0
	return position

func _set_step(next_step: Step) -> void:
	step = next_step
	var playing := step in [Step.ACQUIRE, Step.ENGAGE, Step.WAIT_RESUPPLY, Step.WAIT_REPAIR, Step.WAIT_RELOCATE, Step.COMPLETE]
	session.set_simulation_speed(1.0 if playing else 0.0)
	match step:
		Step.CAMERA:
			_lesson("진입 방향 확인", "작전은 이미 시작됐으며 안내와 배치를 위해 자동 일시정지했습니다. 실전에서는 우측 상단 일시정지를 직접 사용할 수 있습니다.\n\n주황색 훈련 표적 진입 표시를 찾아보세요.\nWASD: 이동\n가운데 버튼 드래그: 수평, 수직 회전\n휠: 확대, 축소\nBackspace: 시점 초기화\n\n방향을 확인했으면 계속을 누르세요.", true)
		Step.RADAR:
			_lesson("접근로 감시", "방공 자산을 열어 저·중고도 레이더를 선택하세요. 도시와 주황색 진입 표시 사이의 추천 위치에 배치해 접근로를 감시하세요.")
		Step.WEAPON:
			_lesson("요격 포대 배치", "방공 자산에서 미사일 포대를 선택하세요. 레이더 근처의 추천 위치에 놓고 청색 연결선을 확인하세요. 도시의 지휘통제소가 레이더 정보를 포대로 전달합니다.")
		Step.CONNECT:
			_lesson("끊긴 연결 복구", "청색 연결선이 이어지지 않았습니다. 강조된 자산을 선택하고 재배치를 눌러 추천 위치로 옮기세요.")
		Step.ACQUIRE:
			tactical_screen_overlay.call("hide_training_approach")
			hud.set_catalog_expanded(false)
			_lesson("접근 감시", "레이더와 포대가 연결됐습니다. 주황색으로 표시했던 방향에서 표적이 접근 중입니다. 레이더가 항적을 만드는 모습을 관찰하세요.")
		Step.SELECT_TRACK:
			_lesson("탐지된 표적 확인", "적성 항적이 확인됐습니다. 강조된 항적 표식을 클릭해 표적 정보를 열어보세요.")
		Step.DOCTRINE:
			_lesson("사격 허용", "표적을 확인했습니다. 이제 강조된 미사일 포대를 선택하고 사격중지를 해제하세요.")
		Step.ENGAGE:
			_lesson("요격 관찰", "사격을 허용했습니다. 표적이 사거리 안에 들어오면 포대가 자동으로 발사합니다. 발사된 미사일과 표적의 움직임을 관찰하세요.")
		Step.SUPPORT:
			_lesson("전투 후 탄약 확보", "첫 교전이 끝났습니다. 보급 실습을 위해 포대의 예비탄을 소진 상태로 설정했습니다.\n\n방공 자산을 열어 통합 지원기지를 포대 근처에 배치하세요. 포대까지 녹색 지원선이 연결되는 위치를 고르세요.")
		Step.RESUPPLY:
			hud.set_catalog_expanded(false)
			_lesson("재보급 요청", "지원기지가 연결됐습니다. 포대를 선택하고 재보급 요청을 누르세요. 요청 비용은 버튼에서 확인할 수 있습니다.")
		Step.WAIT_RESUPPLY:
			_lesson("탄약 보충 확인", "보급이 진행 중입니다. 포대 선택 패널의 작업 진행도와 예비탄 수량을 확인하세요. 완료되면 예비탄이 채워집니다.")
		Step.REPAIR:
			_lesson("손상된 포대 수리", "보급이 완료됐습니다. 다음 정비 실습을 위해 포대에 경미한 손상을 적용했습니다.\n\n포대를 선택해 내구도를 확인하고 수리 요청을 누르세요.")
		Step.WAIT_REPAIR:
			_lesson("수리 결과 확인", "지원기지가 포대를 수리하고 있습니다. 선택 패널에서 내구도가 회복되는지 확인하세요.")
		Step.CITY_RESTORE:
			_lesson("도시 피해 복구", "포대 수리가 완료됐습니다. 마지막으로 도시 복구 실습용 피해를 적용했습니다.\n\n상단 도시 관리를 열고 피해 복구를 누르세요. 예산을 사용해 도시 내구도를 즉시 회복합니다.")
		Step.COMPLETE:
			_lesson("훈련 완료", "도시 복구까지 마쳤습니다. 레이더와 포대를 연결해 요격하고, 소모된 탄약과 피해를 복구했습니다.\n\nEsc 메뉴에서 메인 메뉴로 돌아가 새 게임을 시작하세요.")
		Step.RELOCATE:
			_lesson("탐지 사각 해결", "표적이 탐지거리 안에 들어왔지만 지형에 가려져 있습니다. 강조된 레이더를 선택하고 재배치를 누른 뒤, 접근로가 트인 추천 위치로 옮기세요.")
		Step.WAIT_RELOCATE:
			_lesson("자산 재설치", "자산을 옮기고 있습니다. 재설치가 끝나면 연결과 탐지 상태를 다시 확인합니다.")

func _lesson(title: String, body: String, next_visible: bool = false) -> void:
	hud.set_training_lesson(5 if step in [Step.RELOCATE, Step.WAIT_RELOCATE] else mini(int(step), LESSON_COUNT), LESSON_COUNT, title, body, next_visible)

func _spawn_training_threat() -> void:
	var threat := director._spawn_entry(scenario.threat_entries[0], 0.0, 0.0)
	if threat == null:
		return
	training_threat_runtime_id = threat.runtime_id

func _training_battery() -> MissileBattery:
	return training_battery if is_instance_valid(training_battery) else null
