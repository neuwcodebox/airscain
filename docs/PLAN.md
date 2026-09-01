# 구현 계획과 이력

`SPEC.md`의 완료 조건과 `TECH.md`의 기술 경계를 기준으로 한 고수준 작업 체크리스트다. 각 완료 항목은 실행 가능한 상태로 검증한 뒤 해당 변경과 함께 커밋한다.

- [x] 실행 가능한 첫 수직 플레이 루프 구성
  - Godot 4.7.2 Mobile 프로젝트와 영속 입력·메인 장면 설정
  - seed 기반 구릉 지형과 box 도시 생성, 지형과 공유하는 높이·경사 query
  - `ProtectedObjective`, `DefenseUnit`, `ThreatUnit` 역할과 Resource 기반 첫 시나리오
  - 예산 원자성을 갖는 미사일 포대 배치와 배치 preview/사거리/실패 사유
  - UAV 지속 생성·접근·강하, 포대 표적 선택, 실제 유도 요격미사일과 폭발 표현
  - 준비/진행/게임오버, 일시정지·1×·2×, HUD·최종 통계·동일/신규 seed 재시작
  - 검증: `godot --headless --path . --editor --quit`, `godot --headless --path . --quit-after 180`
- [ ] 규칙 단위 테스트와 전체 플레이 흐름 통합 테스트 추가
- [ ] 장기 고속 시뮬레이션으로 10분 이상 플레이 및 위협 상한 안정성 검증
- [ ] 실제 게임 창에서 카메라·배치·전투·UI 시각 검증과 보정
- [ ] SPEC/TECH 완료 조건별 최종 감사와 전체 CLI 검증
