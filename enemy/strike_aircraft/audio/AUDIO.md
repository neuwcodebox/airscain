# 타격기 접근·통과음

사용자가 제공한 `jet_flyover_1.ogg`, `jet_flyover_2.ogg` 원본을 그대로 포함한다. 원본 제공 위치는 Windows 바탕화면이며 이 파일명에 대응하는 원 출처 URL과 라이선스 자료는 제공되지 않았다.

| 음원 | 길이 | 원본 LUFS | 원본 True Peak | 재생 보정 | 보정 후 LUFS / True Peak |
| --- | ---: | ---: | ---: | ---: | ---: |
| jet_flyover_1.ogg | 30.646초 | −16.5 | −1.3dBFS | −9.5dB | −26.0 / −10.8dBFS |
| jet_flyover_2.ogg | 20.383초 | −17.4 | +0.3dBFS | −8.6dB | −26.0 / −8.3dBFS |

FFmpeg ebur128의 전체 음원 측정치 기준. 원본의 접근·이탈 다이내믹과 인코딩을 보존하며 고정 gain은 `ThreatApproachAudio`에 둔다. 사용자가 지정한 6~7초 최근접 구간의 중간인 6.5초를 예상 투발과 맞춘다. 실제 전투 믹스의 청감은 별도로 조정할 수 있다.
