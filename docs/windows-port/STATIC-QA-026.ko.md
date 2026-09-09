# 코드 비교 QA 026

## Windows Firefox 기본 설치 레지스트리

APPDATA/Mozilla/Firefox/profiles.ini를 사용하는 기본 설치의 프로필 탐색을 연결했다. APPDATA 환경 키는 Windows 대소문자 비민감 처리, 없으면 home/AppData/Roaming을 사용한다. Firefox 전용 registry reader는 1 MiB 상한, UTF-8 및 BOM 표시 UTF-16LE를 지원한다. readText와 파일시스템 콜백을 주입할 수 있으며 이번 작업에서는 실제 파일을 읽지 않았다. 파일 내용 읽기 코드는 구현만 했다.

원본 계약 근거는 Mozilla 고정 commit a641c7b27bb8a3fa8ffd47c312e1981456626ab2다.

- [Profile 열거](https://github.com/mozilla-firefox/firefox/blob/a641c7b27bb8a3fa8ffd47c312e1981456626ab2/toolkit/profile/nsToolkitProfileService.cpp#L1178-L1218): Profile0부터 연속 열거, IsRelative 누락은 종료, Name/Path 누락은 해당 항목 생략. 정확히 1만 상대 경로다.
- [INI parser](https://github.com/mozilla-firefox/firefox/blob/a641c7b27bb8a3fa8ffd47c312e1981456626ab2/xpcom/base/nsINIParser.cpp#L22-L114): BOM, CR/LF, 선두 공백, 값 공백 유지, case-sensitive key 및 중복 값 갱신을 대조했다.
- [tokenizer](https://github.com/mozilla-firefox/firefox/blob/a641c7b27bb8a3fa8ffd47c312e1981456626ab2/xpcom/base/nsCRTGlue.cpp#L40-L66): 닫는 괄호 없는 section도 이름이 유효하면 받아들이는 실제 동작을 반영했다.
- [상대 descriptor](https://github.com/mozilla-firefox/firefox/blob/a641c7b27bb8a3fa8ffd47c312e1981456626ab2/xpcom/io/nsLocalFileCommon.cpp#L434-L482): Firefox root 기준 slash 경로와 선두 ../를 처리한다.
- [Windows 절대 경로](https://github.com/mozilla-firefox/firefox/blob/a641c7b27bb8a3fa8ffd47c312e1981456626ab2/xpcom/io/nsLocalFileWin.cpp#L1096-L1153): drive-rooted backslash/UNC만 수용하고 forward slash는 거부한다.
- [프로필 서비스 문서](https://firefox-source-docs.mozilla.org/toolkit/profile/): roaming profile과 local cache를 구분한다.

임의 이름을 가진 등록 프로필도 탐색한다. 반환된 경로는 읽을 수 있는 디렉터리인지 확인한 후 기존 profile-presence API에 전달한다. 설치 탐색 및 cookie import는 여전히 false이며 Firefox Beta/Dev/Nightly로의 채널 추정은 하지 않는다. Chrome/Edge 경로에서는 registry read를 하지 않는다.

## 검토와 미실행

합성 문자열/경로 테스트 소스를 추가했다. 상대/절대 및 부모 경로, IsRelative 누락 종료, Name 누락 생략, empty Name, BOM/중복 키/공백/미닫힘 section, roaming locator 연결을 포함한다. 기존 미지원 identity 테스트는 Firefox 대신 Zen으로 변경했다.

독립 정적 리뷰에서 Swift Character 단위 분리가 CRLF를 나누지 못하는 오류를 발견했다. CRLF를 LF로 먼저 정규화하도록 수정하고 정상 CRLF 문서의 회귀 테스트 소스를 추가했다. 재검토에서 해당 오류 해소를 코드로 확인했고 추가 구체적 지적은 없었다. git diff --check 외 빌드·컴파일·테스트·lint·앱/프로필/키체인 접근은 하지 않았다. 코드상 부분 연결이며 전체 기능 완료 또는 Windows 실행 성공을 뜻하지 않는다.

## 남은 경계

MSIX 패키지 루트, Firefox 채널 귀속, selectable profile group SQLite registry, native legacy encoding, 1 MiB를 넘는 registry는 미지원이다. Mozilla의 비정상 상대 descriptor에서 무시되는 Append 실패 및 중간 ../ 같은 기형 경로 동작도 아직 동일하지 않다. 특수 device/NTFS descriptor는 범위 밖이며 오류 입력은 profile 없음으로 처리한다. 설치 등록, 브라우저별 cookie 저장소 읽기/복호화와 공급자 연결도 남았다.

다음에는 고정 SweetCookieKit 의존성의 cookie query/store/profile 계약을 읽고 Windows backend가 필요한 파일·SQLite·복호화 경계를 추적한다. 위 신규 Firefox 저장 방식이 고정 CodexBar 기준 기능에 포함되는지도 의존성에서 재대조한다.
