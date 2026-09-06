# 대규모 교전 성능 측정

## 시간대별 하늘 비용 진단

`godot --audio-driver Dummy --path . --script res://tools/day_night_capture.gd -- --sky-benchmark`로 비교한다. 1920×1080 WSL Compatibility, seed 73129의 준비 완료된 정지 전장에서 UI/오디오를 끄고 전술/하늘 점검 각도를 측정한다. 야간 구름·달·별을 포함한 실제 하늘과 기본 ProceduralSkyMaterial의 별도 Sky를 참조→실제→실제→참조 순서로 교차한다. 구간마다 30프레임을 버리고 180프레임의 중앙값/p95를 기록한다. 매 프레임 작전 시계를 진행하며 같은 바다/도시/조명 코드를 실행한다. 참조는 기존 버전 전체가 아닌 하늘 표현만의 비용 비교다. GPU timestamp나 대규모 교전·웹 성능을 뜻하지 않는다.

하늘 본체는 공유 512px 노이즈 텍스처를 재사용하고 배경이 보이는 픽셀에서 구름/천체를 계산한다. 32px 실시간 반사맵은 대기색만 계산한다. 화면에 보이지 않는 구름 노드나 레이마칭·매 프레임 텍스처 생성은 없다. `--sky`는 시간대별 전술/하늘 캡처, `--sky-menu`는 메뉴 시간대 검증을 제공한다.

최종 교차 측정(각 셀은 두 구간의 값, ms):

| 시점 | 참조 중앙값 | 실제 중앙값 | 참조 p95 | 실제 p95 |
| --- | --- | --- | --- | --- |
| 전술 | 31.084 / 33.531 | 32.916 / 33.446 | 43.360 / 36.330 | 43.831 / 36.282 |
| 하늘 점검 | 8.923 / 9.969 | 10.845 / 11.450 | 11.263 / 12.484 | 13.608 / 13.909 |

하늘이 화면을 채우면 약 1.5–2ms의 추가 비용이 관측된다. 전술 시점은 약 31–33ms 부근의 편차와 겹치며 비용이 0이라고 보지 않는다. 대규모 전투 FPS 유지나 브라우저 성능은 별도 검증 대상이다. 최종 로그: `/tmp/airscain_sky_benchmark.log`. 진단의 하늘 교체는 서로 다른 Sky 리소스로 수행하며, 같은 Sky의 material을 반복 교체할 때 발생하던 Compatibility 종료 시 반사 텍스처 누수 로그는 최종 실행에서 발생하지 않았다.

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

## 기체·궤적 렌더 후속

동일 환경에서 `render_load_check.gd`는 UAV/전투기 각 96대, 고정 카메라·조명, 파티클/광원 제외로 기체 제출만 분리한다. 40프레임 준비 후 100프레임을 측정한다. 기준 코드는 `9339306`이며 AI를 실행하지 않는 분리 부하다.

| 192대 기체 | 재질별 메시 | 단일 surface 팔레트 |
| --- | ---: | ---: |
| 평균 프레임 | 86.352ms | 51.968ms |
| p95 | 106.549ms | 55.396ms |
| 드로 콜 | 1,152 | 576 |
| 렌더 프리미티브 | 113,664 | 113,664 |

형상 단순화 없이 기체 surface의 금속성·거칠기를 공유 데이터 텍스처에 담고 개별 기체 도색을 유지했다. 이 분리 부하에서 평균 약 40% 감소이며 전체 게임이나 웹에서 같은 개선율을 보장하지 않는다. 최종 재실행도 평균 52.033ms/p95 55.357ms, 동일 제출 개수를 기록했다(`/tmp/airscain_aircraft_final.log`). 근접 UAV·타격기와 투발 흐름을 실제 게임 창에서 검증했다.

연기 24줄·19,200표본을 15초로 고정한 `combat_perf_check --render --faded`에서는 이미 알파가 0인 표본의 CPU 회수 시점을 셰이더 감쇠 끝점에 맞췄다. 드로 콜 399→351, 프리미티브 751,082→251,930으로 투명 궤적 제출은 제거됐다. 평균 프레임은 33.954→37.737ms, p95는 41.195→41.131ms로 **프레임 시간 개선은 확인되지 않았다**. 이 변경을 파티클 합성 병목 해결로 간주하지 않는다. 보이는 표본의 수·크기·감쇠·그림자는 그대로다.

투명 카드 코너를 fragment discard로 제외하는 별도 실험은 6초 연기 부하에서 평균 40.120→43.791ms로 개선되지 않아 제거했다. 렌더 카드 모양 축소나 낮은 해상도 합성은 채택하지 않았다.

후속 원본 로그: `/tmp/airscain_aircraft_before.log`, `/tmp/airscain_aircraft_palette.log`, `/tmp/airscain_smoke_faded_before.log`, `/tmp/airscain_smoke_faded_after.log`, `/tmp/airscain_smoke_baseline.log`, `/tmp/airscain_smoke_discard.log`. 캡처: `/tmp/airscain_aircraft_load_before.png`, `/tmp/airscain_aircraft_load.png`, `/tmp/airscain_radar_strike_aircraft_model.png`.

실제 창 추가 확인: `/tmp/airscain_aircraft_closeup.png`, `/tmp/airscain_wreck_falling.png`, `/tmp/airscain_wreck_impact.png`. 추락 기체 형상·그림자·충돌 섬광을 확인했고 진단기가 `VISUAL_CAPTURE_OK falling_airframe composite_impact`로 종료했다.

전체 확대 교전 후속 실행은 평균 402.051→392.256ms, p95 723.342→706.974ms였다. 정지 전장 평균은 180.213→166.520ms, 드로 콜은 2,223→1,876이다. 기체 단독 개선율보다 전체 개선 폭은 작고, 시간 기반 VFX가 완전히 같지 않아 순수 기체 비용 차이라고 단정하지 않는다. 최대 기관포 비행탄은 이전 185발·이번 188발, 발사체 부모의 최대 child 수는 77·78이다. 로그: `/tmp/airscain_large_palette_render.log`. 실제 최종 도시 기능 8,532·적성 항적 119를 유지했다.

## 남은 큰 비용

후속 개선 후 정지 전장에서 파티클 제외 시 166.5→117.8ms, 적 메시 제외 시 166.5→132.5ms, 도시 제외 시 166.5→125.8ms였다. 각 차이는 별도 실험이며 더해서 총 비용으로 간주하지 않는다. 다음 큰 렌더 조사 대상은 보이는 파티클의 합성·광원 비용과 도시 제출 비용이다. 입자 수·보이는 수명·그림자·광원을 줄이는 품질 절충은 적용하지 않았다.

단독 기준선에서 기관포 12문·표적 60개는 평균 1.264ms, 연기 24줄·19,200개 CPU 갱신은 0.771ms였다. 작은 단독 부하 결과만으로 복합 교전이나 투명 입자 렌더 비용을 판단하지 않는다. 웹 배포의 실제 프레임과 낮/밤·다른 배치·여러 seed의 분포는 추가 측정 대상이다.

## 재현

### 사건별 순간 지연

`tools/hitch_check.gd -- --brief`는 seed 73129의 자유 모드에서 앱 VFX 예열과 실제 전장 준비를 완료한 뒤 사건 전 10프레임 안정화, 사건 호출 CPU 시간과 이후 12프레임을 기록한다. 실제 앱 폰트를 사용하며 오디오 출력/게임 시뮬레이션은 비활성화한다. 단일 폭발·16/32개 동시 폭발·일반 도시 피격·기체 등장·게임 종료를 분리한다. `--brief`를 빼면 모든 공습 콘텐츠의 생성 경로를 확인한다. 일반 피격은 피해 1로 도시 생존을 단언하고, 게임 종료는 마지막 별도 사건이다. 최대 프레임은 GPU timestamp가 아니라 프레임 완료 대기를 포함한다.

정상 플레이 상태로 수정한 동일 진단기를 기존 커밋 `cb45149`와 후속 구현에 각각 실행했다. 원본 로그는 `/tmp/airscain_hitch_verified_before.log`, `/tmp/airscain_hitch_release.log`다.

| 사건 | 기존 | 후속 |
| --- | ---: | ---: |
| UAV 첫 등장 프레임 | 164.730ms | 35.262ms |
| UAV 재등장 프레임 | 169.392ms | 33.645ms |
| 레이더 타격기 첫 등장 프레임 | 171.579ms | 33.430ms |
| 첫 32개 폭발 CPU 생성 | 30.271ms | 1.740ms |
| 최초 일반 도시 피격 프레임 | 36.258ms | 36.886ms |
| 최초 게임 종료 프레임 | 110.783ms | 57.584ms |

원시 scene 예열은 Definition setup 이후의 실전 재질을 준비하지 않았다. 기체 도색 재질을 계속 보존하고 실제 전장 환경에서도 렌더하자 반복 생성 시의 큰 지연이 제거됐다. 풀도 보존 한도 32개 전체를 미리 준비해 첫 동시 폭발에서 남은 24개를 추가 생성하지 않는다. 효과 수·수명·광원·피해·발사 빈도를 줄이지 않는다.

일반 도시 피격의 뚜렷한 최초 지연은 재현되지 않았으며 개선을 주장하지 않는다. 초기 진단은 도시 최대 기능 100에 피해 100을 주어 종료 화면 비용을 피격 비용으로 잘못 분류했고, 기본 폰트까지 달랐다. 해당 초기 로그의 도시 피격 수치는 근거에서 제외한다. 캡처로 이 문제를 발견한 뒤 정상 피격/게임 종료를 나누고 기존 구현까지 다시 측정했다.

게임 종료 패널도 로딩 차단막 뒤에서 실제 통계 텍스트로 레이아웃·글꼴 렌더를 준비한다. 예열은 도시 기능이나 세션 단계를 변경하지 않으며 종료 시에는 최신 통계로 다시 채운다.

32개 동시 폭발의 12프레임 최대는 330.224→363.214ms로 여전히 크다. 이는 첫 생성 제거만으로 해결되지 않는 지속적인 중첩 VFX/광원 비용이다. 시작 전 준비 시간은 이 진단에서 약 7.6→13.9초로 증가했으며, 앱 메뉴의 병행 시연을 포함한 실제 사용자 로딩 시간이나 브라우저 수치를 뜻하지 않는다. 샘플 수가 적고 WSL 드라이버 변동이 있으므로 작은 차이는 유의한 개선으로 보지 않는다. 별도 야간 전환·장시간 재출현·첫 발사·브라우저의 사건별 지연은 후속 검증 대상이다.

검증 캡처: `/tmp/airscain_hitch_city.png`(일반 피격, 도시 생존), `/tmp/airscain_hitch_check.png`(별도 종료 화면). 캡처는 사건의 12프레임 기록 이후 저장하므로 측정 구간에 파일 저장 시간이 포함되지 않는다.

```bash
godot --headless --audio-driver Dummy --path . --script res://tools/profile_check.gd -- --breakdown --large
godot --audio-driver Dummy --path . --script res://tools/profile_check.gd -- --breakdown --large --render --render-probe
godot --headless --audio-driver Dummy --path . --script res://tools/combat_perf_check.gd
godot --audio-driver Dummy --path . --script res://tools/combat_perf_check.gd -- --render --faded
godot --audio-driver Dummy --path . --script res://tools/render_load_check.gd
godot --audio-driver Dummy --path . --script res://tools/hitch_check.gd -- --brief
godot --audio-driver Dummy --path . --script res://tools/visual_capture.gd -- --capture-static-details-only
```

로컬 원본 로그: `/tmp/airscain_large_before_cpu.log`, `/tmp/airscain_large_occlusion_cpu.log`, `/tmp/airscain_large_before_render.log`, `/tmp/airscain_large_after_render.log`. 캡처는 `/tmp/airscain_profile_combat.png` 및 `/tmp/airscain_batched_search_radar.png`, `/tmp/airscain_batched_tracking_radar.png`, `/tmp/airscain_batched_support_facility.png`에 저장한다. `/tmp` 파일은 영구 산출물이 아니다.
