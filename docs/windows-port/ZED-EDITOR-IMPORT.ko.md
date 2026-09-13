# Windows Zed 편집기 계정 가져오기

현재 코드는 작성 중이며 Windows 실행 검증을 마치지 않았다.

트레이의 `Add saved account…`에서 `Import Zed from editor…`를 선택한다. API 서버와 인증 저장 주소를 차례로 확인하고 Continue를 누르면 해당 서버의 Windows Credential Manager 항목을 읽고 API 계정 ID를 확인한다. 이름 입력 후 저장하면 기존 보호 계정 저장 경로로 추가하고 선택한다. 사용량은 Refresh로 갱신한다.

## 서버 설정 위치

기본 추천 서버는 `%APPDATA%\Zed\settings.json`의 `server_url`에서 읽는다. 기본 설정 파일이 없으면 `https://zed.dev`를 제안한다. 설정을 읽거나 해석할 수 없으면 서버 입력란을 비우고 직접 입력 안내를 표시한다.

사용자 지정 Zed 데이터 디렉터리를 사용하는 경우 CodexBar 프로세스 환경의 `CODEXBAR_ZED_DATA_DIR`에 해당 디렉터리의 절대 경로를 지정한다. 이는 CodexBar에서 제공하는 환경 변수이며 Zed의 공식 환경 변수는 아니다. 경로 값에는 따옴표 문자를 포함하지 않는다. 예: `D:\EditorProfiles\Work`를 지정하면 `D:\EditorProfiles\Work\config\settings.json`을 읽는다.

명시한 경로가 잘못되거나 파일이 없으면 기본 프로필로 대체하지 않는다. 서버를 직접 입력하거나 경로를 수정한 뒤 CodexBar를 다시 시작한다. 이 기능은 설정 파일을 만들거나 수정하지 않는다.

설정 파일은 서버를 제안하는 자료이며 계정별 토큰 파일이 아니다. Zed의 Windows 자격증명은 서버 주소를 포함한 Credential Manager target에 저장된다. 같은 서버를 사용하는 여러 데이터 디렉터리를 별개의 로그인 계정으로 보장하지 않는다.

## 현재 제한

- 실행 중인 Zed의 사용자 지정 데이터 디렉터리를 자동 탐색하지 않는다.
- `credentials_url`과 `server_url`은 각각 추천하고 확인한다. 기존 Zed 서버 신뢰 규칙이 허용하는 조합만 가져온다. 지원하지 않는 사용자 서버 간 교차 조합은 거부한다.
- 서버 입력은 HTTPS origin만 허용한다. 하위 경로, URL 내 로그인 정보, query 및 fragment는 허용하지 않는다.
- 설정의 중복 최상위 key와 1MiB 초과 파일은 거부한다.
- 실제 설치 버전, Windows UI, Credential Manager와 API 연동 검증은 사용자 지시로 아직 실행하지 않았다.
