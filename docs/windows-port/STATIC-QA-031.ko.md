# 코드 비교 QA 031

Windows Amp 웹 쿠키 fallback에 Firefox SQLite importer를 연결했다. 자동 모드는 stable/ESR 또는 미식별 프로필의 compatibility.ini LastPlatformDir가 가리키는 firefox.exe와 cookies.sqlite가 일반 파일일 때만 후보가 된다. 다른 브라우저의 Windows gate는 계속 닫혀 있다. manual/off 설정은 가용성 검사에서 브라우저 탐색을 생략한다. 기존 CLI/API/web 순서와 취소 처리는 보존했다.

설치 판단은 실행 파일 존재 증거일 뿐 레지스트리 등록이나 실제 실행 성공을 뜻하지 않는다. LastPlatformDir가 없는 새 설치/portable/MSIX 프로필과 Chromium 복호화는 미지원이다. applicationURL 비교는 Windows 경로 대소문자를 무시한다. 쿠키 클라이언트가 발견하는 프로필에도 같은 설치 파일 및 일반 DB 조건을 적용하여 탐지 결과와 실제 선택 조건을 맞춘다.

독립 정적 리뷰는 탐지/클라이언트 조건 불일치를 발견하여 보완했다. Amp !isEmpty 조건 반전 지적은 원문을 재확인한 리뷰어가 오판으로 철회했다. BrowserDetection/access gate 재검토에서 추가 차단 지적은 없었다. 합성 설치 경계·저장소 선택 테스트 소스는 추가하되 실행하지 않는다. 빌드·컴파일·테스트·실제 프로필/계정 접근·성능 측정은 하지 않았다. git diff --check는 공백 검토만 수행한다.

이는 Amp의 Firefox 웹 경로에 한정한 부분 연결이다. CLI refresh cache staging, 다른 공급자/인증 경로, Windows SQLite 배포, 프로세스/ConPTY, native UI/트레이/설정/위젯/동기화/설치 및 전체 기능 계약 QA는 남아 있다. 제품 전체 완료로 판정하지 않는다.
