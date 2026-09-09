# 코드 비교 QA 024

ClaudeCLIResolver에 WindowsCommandResolver를 연결하여 usage/source planning/background marker 소비자가 버전 탐색과 같은 sourcePath를 사용하게 했다. CLAUDE_CLI_PATH는 원본처럼 trim하고 Windows에서 대소문자 비민감으로 읽는다. 버전 탐색의 중복 resolver는 공통 함수를 사용하도록 바꿨다. DEBUG override와 nonWindows 분기는 유지한다. 독립 reviewer가 새 구체적 결함 없음을 보고했으며 실행 검증은 하지 않았다.

browser_surface_024 소스 지도: Browser identity는 nonMac 빈 struct, BrowserDetection은 false stub, cookie access gate는 nonMac true이나 provider metadata는 nil이다. Windows 프로필 발견과 실제 cookie import 가능성을 분리해 구현해야 한다. 프로필 존재만으로 cookie capability를 켜지 않는다. 실제 browser path 표는 repo에 없으므로 vendor 고정 근거를 확보한 뒤 locator를 구현한다. Chromium Default/Profile/user- 및 Gecko .default 이름만으로 profiles.ini 지원을 주장하지 않는다.

후속: Windows Browser identity/profile locator→실제 cookie read/decrypt→provider import 연결을 순차 검토한다. 전체 작업 상태는 WORKSTREAM-STATUS.ko.md에 별도로 표시했다. 현재 완료로 판정한 전체 작업 영역은 없다.
