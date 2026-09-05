# 기관포 음원

`gun_start_1.ogg`, `gun_loop_1.ogg`, `gun_end_1.ogg`, `gun_self_destruction_1.ogg`는 사용자가 이 프로젝트에 적용하도록 제공한 원본 파일이다. 파일 내용은 변경하지 않았으며 앞뒤 무음도 보존한다. 별도 라이선스 정보는 제공되지 않았으며 다른 전투 음원의 CC0 표기를 이 파일들에 적용하지 않는다.

`gun_sustain.ogg`는 시작음과 루프음을 이어 붙인 재생용 파생 파일이다. 44,100Hz·스테레오이며 첫 25,216프레임 이후를 반복한다. 웹에서는 작전 전에 Sample로 등록해 디코딩하고 동일 AudioBuffer를 공유한다. 시작→루프를 게임 프레임의 파일 교체 없이 연결하기 위한 구성으로, WAV 파일은 사용하지 않는다. 원본 자폭 음원에는 합치기·무음 제거를 적용하지 않는다.

재생용 파일 생성:

```sh
ffmpeg -y -v error -i defense/close_in_gun/gun_start_1.ogg -i defense/close_in_gun/gun_loop_1.ogg -filter_complex '[0:a][1:a]concat=n=2:v=0:a=1[out]' -map '[out]' -c:a libvorbis -q:a 8 defense/close_in_gun/gun_sustain.ogg
```

무음 상태 검증은 `godot --headless --audio-driver Dummy --path . --script res://tools/gun_audio_check.gd -- --stress`로 실행한다. 24기 연사에 180ms 프레임 지연과 1초 일시정지를 넣고 시작/종료 각 24회, 잔향 후 모든 재생 정지를 검사한다. 웹 검증은 `tools/gun_audio_stress.tscn`을 임시 빌드의 메인 장면으로 사용한다. 이 장면은 일반 배포의 `tools/*` 제외 규칙에 따라 배포되지 않는다. 실제 음향 출력 테스트는 사용자 확인 후 실행하며, 무음 브라우저 검증은 오디오 노드의 스피커 출력 연결을 차단한 별도 진단 페이지에서 수행한다.
