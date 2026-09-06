# 대규모 교전 성능 측정

## 조건

2026-09-06, Godot 4.7.2 Compatibility, WSL/Mesa D3D12 RTX 3060. 실제 창 캡처는 1920×1080이며 오디오는 Dummy 및 진단기 재생 비활성화다. 브라우저/WebGL 수치는 아니다.

`profile_check --large`는 seed 73129, 자산 종류별 4세트(기본 지휘시설 포함 45개), 적 종류별 20기로 구성한다. 50ms 작전 진행을 400회 실행하며 게임의 하위 시뮬레이션 단계를 유지한다. 최대 적 371개·항적 322개·기관포 비행탄 185발을 기록했다. 순차 격자 배치는 부하 재현용이며 실제 플레이의 대표 전술이나 밸런스 검사가 아니다.

CPU 측정은 수동 시뮬레이션 호출 시간을, `--render`는 실제 창의 프레임 완료 대기까지 측정한다. `--render-probe`는 마지막 전장을 정지한 후 계열별 표현을 일시적으로 숨겨 비용을 비교한다. 제외 옵션은 진단에만 사용하며 제품의 품질을 낮추지 않는다. VFX의 나이는 실제 프레임 시간을 따르므로 독립 실행의 입자 상태·발사체 부모 아래 잔류 효과 개수는 완전히 같지 않다. 아래 수치는 동일 seed/옵션의 실행 비교이며 다중 실행 통계나 GPU timestamp 측정이 아니다.

## 전후 비교

| 측정 | 기준선 | 개선 후 |
| --- | ---: | ---: |
| CPU 평균 / 50ms 작전 진행 | 61.281ms | 53.370ms |
| CPU p95 / 50ms 작전 진행 | 163.052ms | 137.887ms |
| 실제 창 전투 평균 프레임 | 446.636ms | 402.051ms |
| 실제 창 전투 p95 프레임 | 766.275ms | 723.342ms |
| 정지 전장 평균 프레임 | 223.437ms | 180.213ms |
| 정지 전장 드로 콜 | 2,734 | 2,223 |

CPU 평균 약 13%, p95 약 15%, 정지 전장 프레임 약 19%, 실제 진행 프레임 약 10% 감소다. CPU 수치는 FPS로 환산하지 않는다. CPU 재현의 최대 발사체 부모 child 수는 전후 모두 136이며, 렌더 재현은 잔류 효과 수명 차이로 78/77이다. 실제 창 종료 화면의 도시 기능 8,532와 적성 항적 119는 일치했다.

## 적용 범위

- 항적 연관: 현재 최선보다 먼 후보를 제곱 거리로 먼저 제외한다. 분류·동일 센서 중복·시간 기반 게이트와 동률 순서는 유지한다.
- 미사일: 사거리 밖 후보에 탄종 평가를 수행하지 않고 선택한 탄종의 적합도를 재사용한다.
- 기관포: 현재 선택보다 낮은 순위의 비우선 후보에 불필요한 사선 검사를 생략한다. 가림 여부는 첫 건물 교차에서 반환하고 실제 탄착점 검사는 기존 최근접 표면 경로를 사용한다.
- 정적 자산: 레이더·지휘시설·지원시설·HPM 장식의 동일 재질 부품을 결합하고 같은 장비끼리 메시를 공유한다. 형상·삼각형·재질·그림자·안테나 회전·부착점을 유지한다.

무장 검색 공간 인덱스는 실험에서 전체 CPU 개선이 뚜렷하지 않아 채택하지 않았다. 일반화된 캐시나 낮은 갱신 빈도로 전투의 신선도를 바꾸지 않는다.

## 남은 큰 비용

개선 후 정지 전장에서 파티클 제외 시 180.2→147.5ms, 적 메시 제외 시 180.2→129.1ms, 도시 제외 시 180.2→152.8ms였다. 각 차이는 별도 실험이며 더해서 총 비용으로 간주하지 않는다. 다음 렌더 조사 대상은 다수 기체·파티클 제출/합성 비용이다. 입자 수·수명·그림자·광원을 줄이는 품질 절충은 적용하지 않았다.

단독 기준선에서 기관포 12문·표적 60개는 평균 1.264ms, 연기 24줄·19,200개 CPU 갱신은 0.771ms였다. 작은 단독 부하 결과만으로 복합 교전이나 투명 입자 렌더 비용을 판단하지 않는다. 웹 배포의 실제 프레임과 낮/밤·다른 배치·여러 seed의 분포는 추가 측정 대상이다.

## 재현

```bash
godot --headless --audio-driver Dummy --path . --script res://tools/profile_check.gd -- --breakdown --large
godot --audio-driver Dummy --path . --script res://tools/profile_check.gd -- --breakdown --large --render --render-probe
godot --headless --audio-driver Dummy --path . --script res://tools/combat_perf_check.gd
godot --audio-driver Dummy --path . --script res://tools/visual_capture.gd -- --capture-static-details-only
```

로컬 원본 로그: `/tmp/airscain_large_before_cpu.log`, `/tmp/airscain_large_occlusion_cpu.log`, `/tmp/airscain_large_before_render.log`, `/tmp/airscain_large_after_render.log`. 캡처는 `/tmp/airscain_profile_combat.png` 및 `/tmp/airscain_batched_search_radar.png`, `/tmp/airscain_batched_tracking_radar.png`, `/tmp/airscain_batched_support_facility.png`에 저장한다. `/tmp` 파일은 영구 산출물이 아니다.
