# 코드 비교 QA 025

## 범위와 근거

Windows Browser identity 25개를 원본 macOS keychain switch와 대조해 정의했다. 앞선 024 조사 메시지의 27개 표기는 열거된 이름 개수와 맞지 않아 25개로 정정한다. identity 정의는 해당 브라우저의 Windows 배포나 import 지원을 뜻하지 않는다.

기본 사용자 데이터 경로 7개만 공식 근거로 연결했다. LOCALAPPDATA는 기존 case-insensitive 환경 처리와 home/AppData/Local fallback을 재사용한다.

| identity | LOCALAPPDATA 하위 경로 |
|---|---|
| chrome | Google/Chrome/User Data |
| chromeBeta | Google/Chrome Beta/User Data |
| chromeCanary | Google/Chrome SxS/User Data |
| chromium | Chromium/User Data |
| edge | Microsoft/Edge/User Data |
| edgeBeta | Microsoft/Edge Beta/User Data |
| edgeCanary | Microsoft/Edge SxS/User Data |

- [Chromium 고정 소스 문서](https://github.com/chromium/chromium/blob/0d5b704308d57e7551b5995a3e0e5b375a1ccf90/docs/user_data_dir.md#L41-L53): 채널별 Windows 경로. profile은 user data 하위 디렉터리다.
- [Microsoft Edge 채널별 경로](https://learn.microsoft.com/en-us/microsoft-edge/web-platform/devtools-mcp-server#user-data-directory-for-each-edge-channel): Stable/Beta/Canary 경로.
- [Microsoft UserDataDir 정책](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/userdatadir): 정책/명령행으로 기본 위치가 달라질 수 있다. 이번 locator는 기본 위치만 지원한다.

## 구현과 정적 대조

WindowsBrowserProfileLocator는 기존 Default/Profile /user- 이름 휴리스틱을 유지하고, 경로 구분자·colon·NUL을 거절하며 후보가 읽을 수 있는 디렉터리인지 목록 조회로 확인한다. 파일 내용, cookie DB, Local State는 읽지 않는다. BrowserDetection.hasUsableProfileData에 연결했으며 주입 가능한 환경/파일시스템 콜백, 10분 캐시와 clearCache를 지원한다. 캐시는 NSLock으로 보호한다.

프로필 존재는 설치 증거가 아니므로 isAppInstalled는 아직 false다. 쿠키 backend가 없으므로 isCookieSourceAvailable 및 Windows shouldAttempt는 false를 유지한다. provider import metadata도 켜지 않는다. macOS 분기와 Linux stub은 유지한다.

합성 경로를 사용하는 테스트 소스를 추가했다: 환경 키 대소문자, home fallback, 비디렉터리/비정상 이름 제외, 미지원 identity의 파일시스템 접근 방지, 프로필 존재와 설치/import 가능성 분리. 테스트는 실행하지 않았다. 빌드·컴파일·lint·실제 프로필 접근·Windows 실행도 하지 않았다.

독립 정적 리뷰에서 기존 nonMac 테스트의 Browser() 호출이 새 Windows enum과 충돌함을 발견했다. 기존 stub 테스트를 Linux 등 비Windows 분기로 제한하고 os.lock import도 macOS 안으로 옮겼다. 추가 구체적 production 결함은 보고되지 않았다. 주입 콜백은 cache lock 안에서 호출되므로 같은 detection 인스턴스로 재진입하지 않아야 한다. git diff --check만 실행했고 실행 통과나 전체 기능 완료 판정은 없다.

## 남은 범위

Firefox/Gecko profiles.ini, MSIX 및 채널 귀속, Brave 등 나머지 경로, 사용자 지정/정책 루트, 설치 등록 탐색, 실제 cookie read/decrypt/DPAPI 및 provider 연결이 남았다. 기본 경로 탐색만으로 브라우저 로그인 기능 완료를 주장하지 않는다. 다음 단계는 Firefox 프로필 매핑과 profiles.ini의 상대/절대 경로 계약을 공식 소스에 대조해 확장한다.
