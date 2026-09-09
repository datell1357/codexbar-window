# 코드 비교 QA 030

Firefox client가 profile의 compatibility.ini와 application.ini RemotingName으로 stable/ESR과 다른 채널을 구분하도록 연결했다. 고정 SweetCookieKit의 Firefox 정책은 firefox/firefox-esr만 허용하고 식별 불가능한 profile은 포함한다. Beta/Dev/Nightly로 식별된 profile은 stable Firefox store에서 제외한다. 이는 설치 확인이 아니며 자동 cookie gate는 계속 false다.

근거: [BrowserCatalog 고정본](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/BrowserCatalog.swift) GeckoProfileSelection 및 Firefox metadata; [GeckoCookieImporter 고정본](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/GeckoCookieImporter.swift#L241-L287)의 LastAppDir parent/application.ini → LastPlatformDir/application.ini 우선순위와 첫 RemotingName 동작을 보존했다.

Windows 절대 경로 처리는 기존 Firefox descriptor helper를 재사용한다. 메타데이터는 읽기 함수를 주입할 수 있고 기본 reader는 64 KiB 상한 UTF-8이다. 상한 초과/읽기 실패는 식별 불가로 취급하는 제한이 있다. 상대 app 경로는 현재 디렉터리로 해석하지 않는다. 앱/플랫폼 경로 메타데이터는 stale할 수 있으며 OS 설치 등록·실행 파일 검증을 대신하지 않는다.

합성 테스트 소스를 추가했다: unidentified fallback, stable/ESR case-folding, beta/dev/nightly 제외, CRLF metadata, LastAppDir 우선, 상대 경로 배제. 독립 정적 리뷰에서 blocking 지적은 없었다. 테스트 격리를 위해 fileExists/directoryContents뿐 아니라 readText도 반드시 주입해야 한다. nil reader는 실제 metadata 읽기로 fallback하므로 합성 테스트는 명시적인 closure를 사용한다. 빌드·테스트·컴파일·실제 프로필/설치 위치 접근은 하지 않았다.

이번 세션에서 workspace 쓰기 허용 범위가 바뀌어 승인된 저장소 파일 편집에 도구의 require_escalated 절차를 사용했고 승인됐다. 사용자에게 새로운 작업 권한을 요구하거나 외부 파일을 수정하지 않았다.

다음은 Firefox 설치 증거/구체적 cookie store 존재를 별도로 확인하는 detection, 제한된 access gate와 wrapper를 연결하고 Amp web provider 경로를 완성하는 것이다. Chromium/다른 채널/MSIX/CLI refresh/native UI 미구현은 유지한다.
