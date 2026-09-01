# TECH.md

## 1. 문서 목적

이 문서는 `SPEC.md`를 구현하기 위한 **기술 설계**를 정의한다.

`SPEC.md`가 게임의 동작과 요구사항을 정의하고, 이 문서는 그 요구사항을 Godot 프로젝트에서 어떤 구조와 경계로 구현할지를 정의한다.

게임 규칙과 밸런스 값은 이 문서에서 다시 정의하지 않는다. 구현은 `SPEC.md`의 용어인 **보호 목표**, **방어 수단**, **위협**, **전장**, **시나리오**를 기술적 역할로 옮겨 사용한다.

AI 코딩 에이전트의 일반 작업 방식과 검증 습관은 `AGENTS.md`를 따른다.

---

## 2. 기술 스택

| 영역 | 선택 |
|---|---|
| 엔진 | Godot 4.7.2 stable |
| 언어 | typed GDScript |
| 렌더러 | Mobile |
| 주 실행 환경 | Windows 데스크톱 |
| CLI | `PATH`에 있는 `godot` |
| 장면 | 텍스트 `.tscn` |
| 데이터 | custom `Resource` + 텍스트 `.tres` |
| UI | Godot `Control` / `Container` / `Theme` |
| 3D | `MeshInstance3D`, primitive mesh, 절차적 `ArrayMesh` |
| VFX | `GPUParticles3D`, 기본 mesh와 material |
| 테스트 | GUT 9.7.1 |
| 버전 관리 | Git |

첫 버전에서는 C#, GDExtension, ECS 프레임워크, 외부 런타임 플러그인, 커스텀 셰이더, 멀티스레드 gameplay와 커스텀 에디터 플러그인을 사용하지 않는다.

필요가 실제로 생기기 전에는 기술을 추가하지 않는다.

---

## 3. Source of Truth

게임 실행에 필요한 영속 상태는 저장소의 텍스트 파일로 재현할 수 있어야 한다.

주요 Source of Truth:

```text
GDScript
.tscn
.tres
project.godot
```

원칙:

- main scene, input action, renderer와 필요한 프로젝트 설정을 저장소에 둔다.
- 필수 node, export 값과 signal 연결을 장면 또는 코드에 저장한다.
- 실행에 필요한 설정을 Godot 에디터에서 수동으로 만들어야 하는 상태로 남기지 않는다.
- `.uid` 파일은 관련 소스와 함께 버전 관리한다.
- `.godot/`, export 결과와 엔진 실행 파일은 버전 관리하지 않는다.
- 바이너리 `.scn`, `.res`는 사용하지 않는다.

Godot 실행 파일은 환경변수 래퍼 없이 `godot` 명령으로 호출할 수 있다고 가정한다.

---

## 4. 프로젝트 구조

`AGENTS.md`에서 정한 top-level 구조를 유지하고 관련 scene, script와 resource를 기능별로 가까이 둔다.

```text
main/
    main.tscn
    main.gd
    game_session.gd
    scenario_definition.gd

world/
    battlefield.gd
    world_generator.gd
    terrain/
    objective/
        protected_objective.gd
        city/

camera/
    camera_rig.tscn
    camera_rig.gd

defense/
    defense_unit.gd
    defense_definition.gd
    placement_profile.gd
    missile_battery/
        missile_battery.tscn
        missile_battery.gd
        missile_battery_definition.gd
        homing_interceptor.tscn
        homing_interceptor.gd

enemy/
    threat_unit.gd
    threat_definition.gd
    threat_registry.gd
    threat_director.gd
    threat_spawn_entry.gd
    attack_uav/
        attack_uav.tscn
        attack_uav.gd
        attack_uav_definition.gd

ui/
    hud.tscn
    hud.gd
    placement_controller.gd

effects/
    explosion/
    missile_trail/

tests/
    unit/
    integration/

tools/
```

새 top-level 디렉터리는 위 구조로 자연스럽게 표현할 수 없을 때만 추가한다.

파일 수를 늘리는 것이 목적은 아니다. 한 script가 한 가지 명확한 책임을 유지할 수 있다면 더 쪼개지 않는다.

---

## 5. 아키텍처 경계

코어 흐름은 구체 콘텐츠가 아니라 세 역할을 기준으로 동작한다.

```text
ProtectedObjective
DefenseUnit
ThreatUnit
```

첫 콘텐츠는 다음과 같이 대응한다.

```text
ProtectedObjective → CityObjective
DefenseUnit        → MissileBattery
ThreatUnit         → AttackUav
```

`GameSession`, 배치 UI, 카탈로그, 위협 생성과 공통 HUD는 `CityObjective`, `MissileBattery`, `AttackUav` 같은 구체 타입을 조건문으로 분기하지 않는다.

의존성은 다음 방향을 유지한다.

```text
Main / Session / UI / Director
             ↓
      공통 역할과 Definition
             ↑
       구체 콘텐츠 scene
```

구체 콘텐츠는 공통 흐름에 자신을 등록해 사용되며, 공통 흐름은 구체 콘텐츠 내부 행동을 알 필요가 없다.

---

## 6. 역할 구현

세 역할은 얕은 base script로 표현한다. base에는 공통 흐름에 실제로 필요한 상태와 API만 둔다.

### `ProtectedObjective`

공통 책임:

- runtime ID와 Definition 참조
- 현재/최대 상태 관리
- 피해 적용
- 소진 여부 제공
- 위협이 사용할 목표 위치 제공
- 배치 제외 영역 판정
- 상태 변화 signal 발행

구체 목표는 자신의 표현과 목표 지점 선택 방식을 구현한다.

### `DefenseUnit`

공통 책임:

- runtime ID와 Definition 참조
- 전장에 배치된 위치 관리
- 현재 활성 여부
- gameplay tick/update 진입점

표적 선택 방식, 사거리 판정과 공격 방식은 구체 방어 수단이 구현한다.

### `ThreatUnit`

공통 책임:

- runtime ID와 Definition 참조
- 활성/해결 상태
- 현재 위치와 피격 위치
- 피격 가능 여부
- 긴급도 제공
- 피해 수신
- 결과를 한 번만 확정하는 resolution 경계

이동, 임무 수행과 구체적인 결과 효과는 각 위협 구현이 소유한다.

### 얕은 추상화 원칙

첫 버전에는 다음 범용 계층을 만들지 않는다.

- `ActorBase`
- 범용 `WeaponBase`
- 범용 `ProjectileBase`
- Ability/Effect 시스템
- ECS abstraction
- service locator

`HomingInterceptor`는 `MissileBattery` 기능의 구체 구성요소다. 실제로 다른 방어 수단에서도 공유해야 하는 두 번째 발사체 사례가 생기기 전에는 공통 projectile 계층으로 올리지 않는다.

---

## 7. 데이터와 콘텐츠 등록

조정 가능한 콘텐츠 값과 시나리오 조합은 custom `Resource`로 정의하고 `.tres`로 저장한다.

공통 Definition은 콘텐츠를 선택하고 생성하는 데 필요한 최소 정보만 가진다.

### `ScenarioDefinition`

주요 참조:

```text
world_config
run_config
objectives
available_defenses
threat_entries
```

### `ObjectiveDefinition`

```text
id
name
scene
maximum_integrity
required_for_survival
```

### `DefenseDefinition`

```text
id
name
scene
price
placement_profile
preview_range
```

### `ThreatDefinition`

```text
id
name
scene
neutralization_reward
```

### `ThreatSpawnEntry`

```text
threat_definition
unlock_level
selection_weight
```

### 콘텐츠별 Definition

구체적인 행동 값은 해당 콘텐츠의 Definition에 둔다.

예:

```text
MissileBatteryDefinition extends DefenseDefinition
AttackUavDefinition extends ThreatDefinition
CityObjectiveDefinition extends ObjectiveDefinition
```

미사일 포대의 발사 간격이나 UAV의 속도 같은 값은 공통 Definition에 넣지 않는다.

공통 데이터에 미래 기능용 빈 필드나 거대한 option 집합을 추가하지 않는다.

모든 exported field와 collection 원소는 가능한 한 구체적인 타입을 사용한다. 실행 시작 전에 필수 참조와 값 범위를 검증하며, runtime 상태를 공유 Resource에 기록하지 않는다.

---

## 8. 런타임 조합

`main/main.tscn`은 한 판을 구성하는 상위 node를 연결한다.

권장 구조:

```text
Main
├─ Battlefield
├─ GameSession
├─ ThreatDirector
├─ CameraRig
├─ WorldObjects
└─ UI
```

`Main`은 시나리오를 읽고 필요한 상위 객체를 연결한다. 구체 콘텐츠의 세부 행동은 scene 자체에 맡긴다.

### 상태 소유권

- `GameSession`: 게임 진행 단계, 예산, 생존시간, 통계, game over
- `Battlefield`: 전장 크기와 지형 데이터, 배치 query
- `ProtectedObjective`: 자신의 상태
- `DefenseUnit`: 자신의 교전 상태와 cooldown
- `ThreatUnit`: 자신의 이동, 피해와 resolution 상태
- `ThreatDirector`: 공격 압력과 spawn timing
- `ThreatRegistry`: 현재 활성 위협 목록
- `PlacementController`: 플레이어의 현재 배치 입력 상태

하나의 상태를 여러 객체가 직접 수정하지 않는다.

전역 mutable Autoload singleton은 사용하지 않는다. 필요한 참조는 상위 조합 시점에 명시적으로 전달한다.

---

## 9. 위협 Registry와 방어 교전

활성 위협은 `ThreatRegistry`에서 관리한다.

구체 방어 수단은 registry에서 공통 `ThreatUnit` 목록을 받아 자신의 조건으로 후보를 평가한다.

공통 시스템이 위협의 이동 모델이나 클래스 이름을 확인해서는 안 된다.

첫 `MissileBattery`는 다음 정보만 사용하면 된다.

- 현재 위협 위치
- 피격 가능 여부
- 긴급도
- runtime ID

배터리는 자신의 사거리와 cooldown을 적용해 표적을 결정하고 `HomingInterceptor`를 생성한다.

`HomingInterceptor`는 표적 `ThreatUnit` 참조를 사용해 추적한다. 명중 판정은 빠른 탄체가 frame 사이를 통과하지 않도록 직전 위치와 현재 위치 사이의 구간을 사용한다.

위협이 이미 해결되면 추가 피해, 보상과 임무 완료 처리를 발생시키지 않는다.

---

## 10. 전장 생성

`WorldGenerator`는 하나의 seed로 다음 데이터를 생성한다.

- height field
- terrain mesh
- terrain collision
- 도시 영역
- 도시 건물 transform

지형 외곽은 같은 height field에서 해수면 아래로 낮추고, gameplay collision이 없는 넓은 primitive 평면으로 바다를 표현한다. 별도 수면 simulation은 두지 않는다.

지형의 논리 높이 데이터는 하나만 생성하고 렌더링과 배치 판정이 이를 공유한다.

첫 전장은 규칙적인 grid height field를 사용한다.

권장 구현:

- `FastNoiseLite`로 저주파 높이 생성
- 중앙 도시 영역과 외곽 여유 구간을 부드럽게 평탄화
- `ArrayMesh` 또는 `SurfaceTool`로 low-poly terrain 생성
- 같은 vertex/triangle 데이터에서 terrain collision 생성
- 전장 크기가 달라져도 비슷한 지형 표본 간격을 유지하도록 grid 해상도 조정

도시 건물은 primitive box mesh를 절차적으로 배치한다. 첫 버전에서는 건물이 gameplay collision이나 LOS에 참여하지 않으므로 시각 node로만 유지한다.

전장 생성 결과를 개별 scene 파일로 굽지 않는다. seed와 설정에서 runtime에 생성한다.

---

## 11. 배치 시스템

배치 입력과 배치 가능 여부 판정은 구분한다.

### `PlacementController`

책임:

- UI에서 선택한 `DefenseDefinition` 유지
- camera ray로 후보 지점 획득
- preview 표시
- 유효/무효 상태 표시
- 확정 또는 취소 입력 처리

### `Battlefield` 배치 query

배치 판정에 필요한 순수 query를 제공한다.

- 지도 안쪽인지
- 지형 높이
- footprint 범위의 경사
- 보호 목표 제외 영역과 겹치는지
- 기존 방어 수단 footprint와 겹치는지

배치 가능 여부를 UI node가 직접 계산하지 않는다.

구매와 배치는 `GameSession`을 통한 하나의 원자적 요청으로 확정한다.

```text
검증 성공
→ 예산 차감
→ DefenseUnit 생성
→ 점유 등록
```

어느 단계에서든 검증이 실패하면 예산과 전장 상태를 바꾸지 않는다.

---

## 12. 위협 생성과 난수

전장 생성 RNG와 위협 생성 RNG를 분리한다.

```text
world seed
├─ world RNG
└─ threat RNG
```

새 콘텐츠가 위협 내부에서 난수를 더 사용하더라도 전체 spawn 순서가 불필요하게 바뀌지 않도록, 필요하면 생성 시 각 위협에 별도 seed를 전달한다.

`ThreatDirector`는 공통적으로 다음만 결정한다.

- 다음 spawn 시점
- 한 번에 생성할 수
- 현재 unlock된 `ThreatSpawnEntry`
- 가중치에 따른 콘텐츠 선택
- 활성 위협 상한

구체 위협의 속도, 이동 패턴과 임무 효과는 director가 직접 수정하지 않는다. 공격 압력 단계에 따른 콘텐츠별 변화가 필요하면 구체 위협 Definition 또는 생성 context가 해석한다.

---

## 13. UI 구조

제품 UI는 Godot `Control` 계층으로 구현한다.

권장 구성:

```text
HUD
├─ StatusBar
├─ DefenseCatalog
├─ PlacementFeedback
├─ RunControls
└─ GameOverPanel
```

UI는 authoritative gameplay state를 직접 소유하지 않는다.

- 버튼은 명령을 요청한다.
- HUD는 `GameSession`과 역할 객체가 제공하는 상태를 표시한다.
- 배치 preview는 `PlacementController`가 관리한다.
- 게임오버 판정은 UI가 아니라 `GameSession`이 수행한다.

위협을 종류별로 읽어 별도 UI 분기를 만드는 대신 첫 버전에 필요한 공통 상태만 표시한다.

---

## 14. 3D 표현과 VFX

첫 제품의 mesh는 primitive와 절차적 geometry로 구성한다.

- 지형: `ArrayMesh`
- 건물: `BoxMesh`
- 포대: `BoxMesh`, `CylinderMesh` 조합
- UAV: 소수 primitive 또는 작은 procedural mesh
- 요격미사일: cylinder 계열 primitive

반복되는 단순 material은 공유하고 색과 크기만 필요한 범위에서 조정한다.

첫 버전에서는 custom shader를 만들지 않는다.

VFX는 다음 Godot 기본 기능을 우선한다.

- `GPUParticles3D`: 폭발, 연기, 발사 섬광
- 짧은-lived mesh/particle: spark와 impact
- missile trail: 간단한 particle emitter

VFX callback이 gameplay 피해나 보상을 발생시키지 않는다. gameplay event가 먼저 확정되고 표현 계층이 이를 소비한다.

---

## 15. Signal과 객체 통신

Signal은 상태 변화의 통지에 사용한다.

예:

- 보호 목표 상태 변경
- 위협 resolution
- 예산 변경
- 게임 진행 단계 변경
- 방어 수단 배치 완료

Signal을 전역 메시지 버스처럼 사용하지 않는다.

명확한 요청/응답이 필요한 동작은 typed method 호출을 사용하고, 여러 consumer에게 변화 사실을 알릴 때 signal을 사용한다.

node 이름 검색이나 광범위한 group query를 runtime 의존성 주입 수단으로 사용하지 않는다.

---

## 16. 테스트 설계

테스트는 `tests/unit/`과 `tests/integration/`으로 나눈다.

### Unit test 대상

- 배치 가능 여부 판정
- 예산 원자성
- 보호 목표 상태 감소와 소진
- 위협 resolution이 한 번만 발생하는지
- threat priority 비교
- 공격 압력 계산
- seed 기반 세계 생성의 주요 결과

### Integration test 대상

- 시나리오 로딩 후 정상적인 한 판 시작
- 방어 수단 구매·배치
- 위협 spawn → 교전 → neutralization → 보상
- 위협 mission completion → 보호 목표 피해
- game over
- restart

### 역할 경계 검증

테스트 전용 최소 구현을 사용해 공통 흐름이 첫 콘텐츠에 결합되지 않았는지 검증한다.

예:

```text
TestObjective
TestDefense
TestThreat
```

이 테스트 구현은 제품 기능을 흉내 내기 위한 거대한 mock이 아니라, 공통 계약만 만족하는 가장 작은 대역이어야 한다.

---

## 17. 확장 규칙

새 방어 수단을 추가할 때 기본 경로는 다음과 같다.

```text
DefenseUnit 구현 scene
+ DefenseDefinition subtype/resource
+ 시나리오 등록
```

새 위협:

```text
ThreatUnit 구현 scene
+ ThreatDefinition subtype/resource
+ ThreatSpawnEntry
+ 시나리오 등록
```

새 보호 목표:

```text
ProtectedObjective 구현 scene
+ ObjectiveDefinition subtype/resource
+ 시나리오 등록
```

이 과정에서 `GameSession`, 카탈로그, 배치 흐름, `ThreatDirector`, `ThreatRegistry`와 공통 HUD를 수정해야 한다면 먼저 역할 경계가 잘못된 것은 아닌지 확인한다.

반대로 모든 미래 콘텐츠를 미리 수용하려고 거대한 공통 타입을 만들지 않는다.

실제 두 번째 사례에서 중복이 생겼을 때만 가장 작은 공통 helper, component 또는 base API를 추출한다.

---

## 18. 성능 원칙

첫 버전은 구조적 단순성과 빠른 반복을 우선한다.

처음부터 다음 최적화를 도입하지 않는다.

- object pool
- custom spatial index
- MultiMesh 기반 gameplay 구조
- 멀티스레드 simulation
- GDExtension 최적화
- custom rendering pipeline

Godot profiler에서 실제 병목이 확인된 뒤 필요한 부분만 최적화한다.

단, 활성 위협 상한처럼 gameplay 차원에서 명확한 안전장치는 유지한다.

---

## 19. 기술적 완료 기준

구현은 다음 조건을 만족해야 한다.

- `SPEC.md`의 첫 시나리오를 실행할 수 있다.
- 공통 시스템이 `CityObjective`, `MissileBattery`, `AttackUav`에 대한 타입 분기를 갖지 않는다.
- gameplay 설정과 scene wiring이 저장소에 존재한다.
- 모든 GDScript는 typed code를 기본으로 한다.
- runtime 상태를 `.tres` Definition에 기록하지 않는다.
- 배치와 위협 resolution 같은 중요한 전이는 부분 적용되지 않는다.
- gameplay 결과와 VFX가 분리되어 있다.
- 역할별 테스트 대역으로 공통 흐름을 실행할 수 있다.
- parse error, 처리되지 않은 runtime error와 필수 경로의 placeholder가 없다.
- 시각 변경은 실제 Godot 게임 창에서도 확인 가능한 구조다.
