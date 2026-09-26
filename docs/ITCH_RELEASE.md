# itch.io 배포 패키지

Godot 4.7.2와 같은 버전의 공식 내보내기 템플릿(Web, Windows x86_64)을 설치한 뒤 저장소 루트에서 실행합니다.

```powershell
python tools/package_itch.py
```

스크립트는 한국 시간의 빌드 날짜와 현재 Git 커밋을 게임 메뉴에 주입하고 다음 두 ZIP과 `build/itch/SHA256SUMS.txt`를 만듭니다. 추적된 파일에 커밋되지 않은 변경이 있으면 메뉴의 빌드 ID에 `-dirty`가 붙습니다.

| 업로드 파일 | 용도 |
|---|---|
| `build/itch/Airscain-web-itch.zip` | 브라우저 플레이용 HTML5 빌드. ZIP 루트에 `index.html`이 있습니다. |
| `build/itch/Airscain-windows-x64.zip` | Windows 64비트 다운로드 빌드. 압축을 풀고 `Airscain.exe`를 실행합니다. |

itch.io 프로젝트 종류는 **HTML Game**으로 설정하고 웹 ZIP을 브라우저 플레이 파일로 지정합니다. Windows ZIP은 별도 다운로드 파일로 올리고 Windows 플랫폼을 선택합니다. 웹 임베드는 **Click to launch in fullscreen**이 게임의 16:9 화면과 가변 브라우저 크기에 적합합니다. 키보드와 마우스를 사용하는 게임이므로 모바일 친화 옵션은 선택하지 않습니다. 업로드 후 itch.io의 미리보기에서 새 게임을 시작해 봅니다. itch.io의 [HTML 게임 업로드 규격](https://itch.io/docs/creators/html5)은 ZIP 루트의 `index.html`, 최대 1,000개 파일, 개별 파일 200MB 이하, 압축 해제 후 총 500MB 이하를 요구하며, 스크립트가 이 파일·크기 조건과 ZIP 무결성을 검사합니다.

패키지는 `build/itch/`에만 생성되어 Git에 포함되지 않습니다. Godot 내보내기 로그도 같은 폴더에 남습니다. 출시에 사용할 패키지는 커밋이 확정된 뒤 다시 실행해 최종 커밋 ID로 찍습니다.

## English upload notes

Run `python tools/package_itch.py` with Godot 4.7.2 and its official Web and Windows x86_64 export templates installed. Upload `Airscain-web-itch.zip` as the browser-playable file for an **HTML Game**, and `Airscain-windows-x64.zip` as a separate Windows download. Use **Click to launch in fullscreen** for the web embed and preview the game on itch.io before publishing. Keep `Airscain.exe` and `Airscain.pck` together when extracting the Windows ZIP.
