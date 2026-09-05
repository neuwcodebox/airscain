class_name TrainingController
extends Node

enum Step { NONE, CAMERA, RADAR, COMMAND, WEAPON, START, ACQUIRE, SELECT_TRACK, SELECT_ASSET, PRIORITY, DOCTRINE, ENGAGE, SUPPORT, RESUPPLY, WAIT_RESUPPLY, REPAIR, WAIT_REPAIR, CITY_RESTORE, OVERLAY, ALTITUDE, ENERGY, ENERGY_REVIEW, RELOCATE, WAIT_RELOCATE, OPERATIONS, COMPLETE }

signal selection_clear_requested

const APPROACH_DISTANCE_RATIO := 0.58
const LESSON_COUNT := 24

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
var energy_subject: DefenseUnit
var energy_reviewed: bool = false
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
	tactical_screen_overlay.call("show_training_approach", objective.global_position, approach_position())
	_set_step(Step.CAMERA)

func can_start_defense() -> bool:
	if step != Step.START:
		return false
	var battery := _training_battery()
	for unit: DefenseUnit in defenses:
		if unit.definition.id == &"search_radar" and c2_network.has_command_path(battery, unit.runtime_id):
			return true
	_lesson("C2 연결을 확인하세요", "레이더 → 지휘통제소 → 포대가 연결되어야 시작할 수 있습니다. 청색 연결선을 확인하고, 레이더와 포대 사이에 지휘통제소를 추가해 연결을 보완하세요.")
	return false

func defense_started() -> void:
	session.set_simulation_speed(1.0)
	hud.set_catalog_expanded(false)
	_set_step(Step.ACQUIRE)
	_spawn_training_threat()

func defense_placed(unit: DefenseUnit) -> void:
	if step == Step.RADAR and unit.definition.id == &"search_radar":
		_set_step(Step.COMMAND)
	elif step == Step.COMMAND and unit.definition.id == &"command_post":
		if c2_network.placement_preview(unit.definition, unit.global_position).ready:
			_set_step(Step.WEAPON)
		else:
			hud.set_feedback("지휘통제소가 센서와 연결되어 있지 않습니다. 청색 연결선이 생기는 위치를 선택하세요.")
	elif step == Step.WEAPON and unit is MissileBattery:
		training_battery = unit as MissileBattery
		unit.set_hold_fire(true)
		hud.refresh_selected_asset()
		_set_step(Step.START)
	elif step == Step.SUPPORT and unit.service_range() > 0.0:
		var battery := _training_battery()
		if battery == null or not unit.supports_position(battery.global_position):
			hud.set_feedback("포대까지 녹색 지원선이 연결되는 범위 안에 지원기지를 배치하세요.")
			return
		for munition_magazine: WeaponMagazine in battery.magazines.values():
			munition_magazine.reserve = 0
		selection_clear_requested.emit()
		_set_step(Step.RESUPPLY)
	elif step == Step.ALTITUDE and unit.definition.id == &"tracking_radar":
		relocation_subject = unit
		_set_step(Step.ENERGY)
	elif step == Step.ENERGY and unit.power_demand() > 0.0:
		energy_subject = unit
		selection_clear_requested.emit()
		_set_step(Step.ENERGY_REVIEW)

func tracks_refreshed(selectable_hostile_count: int) -> void:
	if step != Step.ACQUIRE or selectable_hostile_count <= 0:
		return
	session.set_simulation_speed(0.0)
	_set_step(Step.SELECT_TRACK)

func track_selected(track: PlayerTrack) -> void:
	if step == Step.SELECT_TRACK and track != null:
		_set_step(Step.SELECT_ASSET)

func asset_selected(unit: DefenseUnit) -> void:
	if step == Step.SELECT_ASSET and unit == _training_battery():
		_set_step(Step.PRIORITY)
	elif step == Step.ENERGY_REVIEW and unit == energy_subject:
		energy_reviewed = true
		_lesson("전력과 열 확인", "선택 패널에서 전체 수요/공급과 이 자산의 전력 수요, 충전과 열을 확인하세요. 전력은 전역 공급이고 보급·수리는 지역 지원입니다. 전체 수요가 공급보다 크면 일부 자산의 충전이 느려집니다.", true)

func priority_assigned(unit: DefenseUnit) -> void:
	if step == Step.PRIORITY and unit == _training_battery():
		_set_step(Step.DOCTRINE)

func hold_fire_changed(enabled: bool, unit: DefenseUnit) -> void:
	if step == Step.DOCTRINE and not enabled and unit == _training_battery():
		session.set_simulation_speed(1.0)
		_set_step(Step.ENGAGE)

func threat_resolved(threat: ThreatUnit) -> void:
	if threat.runtime_id != training_threat_runtime_id or step != Step.ENGAGE:
		return
	session.set_simulation_speed(0.0)
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
		_set_step(Step.OVERLAY)

func overlay_selected(mode: StringName) -> void:
	if step == Step.OVERLAY and mode == &"c2":
		session.update_pressure(3)
		hud.set_pressure(3)
		_set_step(Step.ALTITUDE)

func relocation_started(unit: DefenseUnit) -> void:
	if step == Step.RELOCATE and unit == relocation_subject:
		session.set_simulation_speed(1.0)
		_set_step(Step.WAIT_RELOCATE)

func relocation_completed(unit: DefenseUnit) -> void:
	if step == Step.WAIT_RELOCATE and unit == relocation_subject:
		session.set_simulation_speed(0.0)
		_set_step(Step.OPERATIONS)
	elif step == Step.COMMAND:
		for defense: DefenseUnit in defenses:
			if defense.definition.id == &"command_post" and c2_network.placement_preview(defense.definition, defense.global_position).ready:
				_set_step(Step.WEAPON)
				break
	elif step == Step.SUPPORT and unit.service_range() > 0.0:
		defense_placed(unit)

func next_requested() -> void:
	if step == Step.CAMERA:
		_set_step(Step.RADAR)
	elif step == Step.ENERGY_REVIEW and energy_reviewed:
		_set_step(Step.RELOCATE)
	elif step == Step.OPERATIONS:
		_set_step(Step.COMPLETE)

func approach_position() -> Vector3:
	var position := objective.global_position + Vector3.RIGHT * scenario.battlefield_size * APPROACH_DISTANCE_RATIO
	position.y = battlefield.flight_surface_height(position.x, position.z) + 80.0
	return position

func _set_step(next_step: Step) -> void:
	step = next_step
	match step:
		Step.CAMERA:
			_lesson("전장 살펴보기", "WASD 또는 휠 클릭 드래그로 이동하고 Q/E 또는 우클릭 드래그로 회전하세요. 휠로 확대·축소하며 주황색 훈련 표적 진입 표시를 찾아보세요.", true)
		Step.RADAR:
			_lesson("탐색 센서", "상단의 방공 자산을 열어 탐색 레이더를 고르세요. 도시와 주황색 진입 표시 사이의 평탄한 지형에 배치하세요. 산 뒤에는 저고도 탐지 사각이 생깁니다.")
		Step.COMMAND:
			_lesson("지휘통제 연결", "방공 자산에서 지휘통제소를 골라 레이더에 청색 연결선이 이어지는 위치에 배치하세요. 센서만으로는 포대에 항적이 공유되지 않습니다.")
		Step.WEAPON:
			_lesson("요격 계층", "미사일 포대를 도시와 주황색 진입 표시 사이, 지휘통제망 안에 배치하세요. 포대는 사격중지 상태로 준비됩니다. 배치 모드는 우클릭이나 Esc로 종료합니다.")
		Step.START:
			_lesson("방어 시작", "화면 하단 중앙의 방어 시작을 누르세요. 레이더·지휘통제소·포대의 연결을 확인한 뒤 통제된 표적 하나가 접근합니다.")
		Step.ACQUIRE:
			tactical_screen_overlay.call("hide_training_approach")
			_lesson("탐지 관찰 · 자동 재생", "실제 물체가 보여도 방공망이 탐지하기 전에는 교전할 수 없습니다. 잠정 항적이 확인 항적으로 바뀌면 자동 일시정지됩니다.")
		Step.SELECT_TRACK:
			_lesson("항적 선택 · 일시정지", "적성 항적 표식을 클릭하세요. 화면 밖 가장자리 표식도 선택할 수 있습니다. 추적 품질과 분류 확신도는 서로 다른 정보입니다.")
		Step.SELECT_ASSET:
			_lesson("방어자산 선택", "배치한 미사일 포대를 클릭하세요. 선택 패널에서 탄약과 C2 연결, 사격중지 상태를 확인할 수 있습니다.")
		Step.PRIORITY:
			_lesson("우선표적 지정", "포대를 선택한 상태에서 적성 항적을 다시 클릭하세요. 교전 검토 패널의 우선표적 지정을 누르면 이 포대가 해당 항적을 우선 평가합니다.")
		Step.DOCTRINE:
			_lesson("자동교전 허용", "미사일 포대를 다시 클릭하고 사격중지를 해제하세요. 해제하면 자동 재생됩니다. 미확인 교전은 분류가 불충분한 물체까지 허용하므로 신중하게 사용하세요.")
		Step.ENGAGE:
			_lesson("자동교전 · 자동 재생", "포대의 선회, 발사관 사출과 요격을 관찰하세요. 표적이 요격되거나 임무를 마치면 자동 일시정지됩니다.")
		Step.SUPPORT:
			_lesson("통합 지원기지", "방공 자산을 열어 통합 지원기지를 배치하세요. 포대에 녹색 지원선이 연결되어야 합니다. 지역 보급·수리는 260m 안에서만 가능하며 예비탄 소진을 훈련합니다.")
		Step.RESUPPLY:
			hud.set_catalog_expanded(false)
			_lesson("재보급 요청", "포대를 다시 선택하고 재보급 요청을 누르세요. 요청은 예산을 사용해 지원 대기열에 작업을 넣습니다. 완료까지 시간이 필요합니다.")
		Step.WAIT_RESUPPLY:
			_lesson("보급 완료 관찰 · 재생", "선택 패널의 보급 작업과 탄약을 관찰하세요. 2×·4×로 대기를 줄일 수 있습니다. 보급 완료 후 정지하고 수리 실습용으로 포대에 경미한 손상을 적용합니다.")
		Step.REPAIR:
			_lesson("시설 수리 · 일시정지", "손상은 가동 효율을 낮춥니다. 포대를 선택해 수리 요청을 누르세요. 수리도 같은 지역 지원기지의 작업 용량을 사용합니다.")
		Step.WAIT_REPAIR:
			_lesson("수리 완료 관찰 · 재생", "지원기지가 포대를 수리하고 있습니다. 가동 상태가 회복되면 자동 정지하고, 다음 도시 복구 실습을 위한 경미한 도시 피해를 적용합니다.")
		Step.CITY_RESTORE:
			_lesson("도시 기능 복구", "상단 도시 상태를 열고 피해 복구를 누르세요. 도시 복구는 예산을 지불하면 즉시 적용됩니다. 포대 수리와는 별개이며 전투 중에도 사용할 수 있습니다.")
		Step.OVERLAY:
			_lesson("방공망 점검", "우측 상단 범위 버튼을 반복해서 눌러 C2까지 전환하세요. 센서·교전·지원 범위와 실제 C2 연결을 번갈아 확인할 수 있습니다.")
		Step.ALTITUDE:
			_lesson("고도별 탐지 계층", "고급 장비를 훈련용으로 해금했습니다. 고고도 추적 레이더를 배치하세요. 120–1500m를 감시하며 기본 탐색 레이더와 역할이 다릅니다. 오른쪽 고도 프로파일로 탐지 높이를 확인하세요.")
		Step.ENERGY:
			_lesson("전력 기반 방어", "고출력 레이저를 배치하세요. 커서 옆 전력 수요·공급과 배치 후 수치를 확인하세요. 통합 지원기지의 전력은 거리 제한 없는 전역 공급입니다.")
		Step.ENERGY_REVIEW:
			hud.set_catalog_expanded(false)
			_lesson("충전과 열 확인", "방금 배치한 에너지 무기를 선택하세요. 충전·열·전체 수요/공급을 확인하면 다음 단계로 진행할 수 있습니다.")
		Step.RELOCATE:
			_lesson("센서 재배치", "배치한 고고도 추적 레이더를 선택하고 재배치 위치 지정을 누른 뒤 다른 빈 지점을 클릭하세요. 이동 중에는 센서가 가동하지 않습니다. 새 위치에서도 C2 연결을 유지하세요.")
		Step.WAIT_RELOCATE:
			_lesson("재배치 완료 관찰 · 재생", "철수와 재설치가 진행 중입니다. 시간이 끝나면 센서가 새 위치에서 다시 가동하고 훈련이 일시정지됩니다.")
		Step.OPERATIONS:
			_lesson("다음 작전 준비", "장거리는 고가 탄약과 탄종, 근거리는 기관포·레이저로 역할을 나누세요. 지속 작전은 Esc에서 저장하고 메뉴에서 이어갈 수 있습니다. 샌드박스는 위협을 직접 투입해 조합을 시험합니다.", true)
		Step.COMPLETE:
			session.set_simulation_speed(1.0)
			_lesson("훈련 완료", "탐지·C2·우선표적·자동교전, 보급·수리·도시 복구, 고도 계층·전력·재배치를 마쳤습니다. 자유롭게 연습하거나 Esc로 돌아가 지속 작전을 시작하세요.")

func _lesson(title: String, body: String, next_visible: bool = false) -> void:
	hud.set_training_lesson(mini(int(step), LESSON_COUNT), LESSON_COUNT, title, body, next_visible)
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

func _has_search_radar() -> bool:
	for defense: DefenseUnit in defenses:
		if defense.definition.id == &"search_radar":
			return true
	return false

func _training_battery() -> MissileBattery:
	return training_battery if is_instance_valid(training_battery) else null
