# 코드 비교 QA 027

## Cookie 타입과 변환 기반

Package.resolved의 SweetCookieKit 0.5.2, commit d5ea6d92298779ec0c3ddf7d3d99da186a305e14에서 순수 Query/Profile/Store/Record/Error 모델과 domain matcher, expiry filter, HTTP 변환을 Windows 전용 소스로 이관했다. 원문은 analysis/fork-parity/sweetcookie-027-evidence에 보존한다. MIT 저작권 표시와 전문을 docs/windows-port/SweetCookieKit-LICENSE.txt에 포함했다. 새 패키지 의존성은 추가하지 않았다.

- [모델 소스](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/BrowserCookieModels.swift): query defaults와 mutable 속성, origin resolver, profile/store identity, record scope를 보존한다. record initializer는 domain 원문을 저장하므로 부정확한 normalized 주석은 수정했다.
- [변환 및 matcher 소스](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/BrowserCookieImporter.swift#L234-L349): 한 leading dot 제거, 대소문자 비민감 contains/suffix/exact, expiry equality 및 session cookie 보존. suffix는 DNS label boundary 검사가 아닌 문자열 suffix다.
- [Gecko reader 소스](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/GeckoCookieImporter.swift#L89-L183): 다음 SQLite 구현의 기준으로 조사했다. DB/WAL/SHM, 7개 컬럼, Unix 초 expiry, NULL row 및 step 실패를 따로 다뤄야 한다.

BrowserCookieClient는 현재 변환 메서드만 제공한다. stores/records/configuration을 구현한 client가 아니다. 실제 cookie 읽기·Chromium 복호화·provider 연결은 미구현이며 Windows cookie gate는 여전히 false다. 타입이 존재한다고 기능 완료로 세지 않는다. 상세 소비자 지도는 COOKIE-CONSUMER-CONTRACT-027.ko.md를 참고한다.

## 정적 리뷰

독립 리뷰에서 FoundationNetworking의 HTTPCookie initializer가 Secure를 Bool로 받지 않는 차이를 발견했다. [corelibs 고정 소스](https://github.com/swiftlang/swift-corelibs-foundation/blob/11764d002e34ed0302365f149ea79b046374db77/Sources/FoundationNetworking/HTTPCookie.swift#L310-L316)에 맞춰 true일 때 문자열 TRUE를 설정하고 false일 때 속성을 생략하도록 수정했다. FALSE 문자열도 nonempty라 true가 되므로 사용하지 않는다. record.scope는 upstream처럼 HTTP 변환에서 별도 반영하지 않는다. 향후 URLSession cookie jar 연결 시 host-only/domain 의미를 다시 검토해야 한다.

합성 테스트 소스는 원문 domain/scope 구분, 세 종류 domain match, expiry boundary, Secure true/false, HttpOnly, 빈 domain 제외를 포함한다. 독립 재검토에서 Secure 수정과 양쪽 분기의 테스트 소스를 확인했고 추가 blocking 지적은 없었다. git diff --check 외 빌드·테스트·컴파일·LSP·브라우저/프로필/계정 접근은 하지 않았다.

## 다음 단계

Windows Firefox SQLite reader를 query/store 모델에 연결한다. WAL 일관성과 잠금 오류, SQLITE_DONE 이외 종료 및 원본 SQL LIKE wildcard 의미와 pure matcher 차이를 명시적으로 처리한다. Gecko scope 손실은 raw host에서 scope를 먼저 읽어 해결할 후보이며 아직 구현하지 않았다. 이후 브라우저 capability와 Amp 등의 실제 fetch 경로를 함께 연결한다. Chromium App-Bound encryption과 기타 브라우저·local storage·CLI/plugin guard는 남아 있다.
