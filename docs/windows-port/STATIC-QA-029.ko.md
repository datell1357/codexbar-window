# 코드 비교 QA 029

## Windows client 연결

변환 전용 BrowserCookieClient를 Sendable struct와 별도 변환 extension으로 바꾸고 WindowsFirefoxCookieReader를 연결했다. Configuration.homeDirectories, stores(for:/in:), records(matching:in:logger:), cookies overload와 기본 home 탐색을 제공한다. 실제 지원하는 browser는 현재 일반 설치 Firefox뿐이다. unsupported store load는 오류이며 자동 가져오기 gate는 아직 false다.

store는 profiles.ini로 발견한 profile 중 cookies.sqlite가 있는 경우만 생성한다. label은 원본의 Firefox + 공백 + profile 이름을 사용하고 default-release/default/나머지 이름 우선순위를 유지한다. profile id는 정규화 경로이며 (파일시스템 identity/alias 기준 중복 제거는 아직 아님) 중복 home에서 같은 store가 반복되지 않게 한다. records(browser)는 query 결과가 빈 store를 생략하지만 stores API 자체는 그런 store도 반환하므로 session restoration 진입점이 사라지지 않는다. profile load 오류는 이전 profile 결과를 성공으로 반환하지 않는다.

현재 사용자의 APPDATA를 다른 configured home에 적용하지 않는다. public init은 현재 home에만 process environment를 적용하고 다른 home은 해당 home의 AppData/Roaming을 사용한다. 내부 주입 init은 명시적 환경/파일시스템/registry/reader 콜백으로 실제 환경 접근 없이 계약을 표현한다. 기본 HOME/USERPROFILE 후보는 절대 경로만 사용한다.

근거: [고정 client API](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/BrowserCookieImporter.swift), [고정 Gecko stores](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/GeckoCookieImporter.swift#L34-L68), 같은 소스의 profileSortKey.

## 검토

합성 콜백 테스트 소스는 cookie 값 읽기 없는 store 열거, 선호 순서·label·중복제거·DB 누락, query 전달, 빈 결과 profile 생략, 후속 profile 실패 전파, unsupported browser 오류를 다룬다. 실행하지 않았다. 독립 소스 리뷰에서 새 blocking 지적은 없었고 컴파일·빌드·테스트·LSP·브라우저/계정/프로필 접근은 하지 않았다.

## 다음 연결의 필수 조건

Amp 소스 조사에서 importer와 automatic resolveCookieHeader 및 descriptor availability가 각각 macOS guard임을 확인했다. Windows Firefox만 지원하는 order를 provider에 한정해야 하며 공유 defaultOrder를 켜서 다른 모든 미이식 공급자의 지원을 광고해서는 안 된다. BrowserDetection과 CookieAccessGate 및 codexBarRecords wrapper도 함께 연결해야 한다.

Firefox remotingName/channel ownership 필터 및 설치 탐색이 남았다. surviving profile을 설치 여부로 세지 않는다. SQLite 실제 동작/배포, MSIX와 channel, Chromium 및 기타브라우저, local storage는 미완료다. client API 연결을 provider 자동로그인 완료로 보고하지 않는다.

Amp generic CLI cookie refresh는 cache stagedCount > 0을 요구하지만 Amp fetch/import에는 CookieHeaderCache 저장이 없어 guard만 넓히면 실패한다. native 설정 UI도 별도다. 따라서 다음 단계의 Amp web 연결과 CLI refresh/UI 완료를 분리해 추적한다. 이 문제는 원본 코드 비교에서 발견한 계약 차이이며 실제 실행 결과가 아니다.
