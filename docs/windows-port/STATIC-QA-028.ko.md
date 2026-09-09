# 코드 비교 QA 028

## Firefox SQLite reader

WindowsFirefoxCookieReader를 추가했다. 기존 CSQLite3 모듈을 사용하고 source URL은 SQLITE_OPEN_READONLY로 열며 SQLite가 같은 SELECT의 WAL snapshot을 관리하도록 한다. 원본 Gecko importer의 DB/WAL/SHM 개별 임시 복사 대신 직접 읽기다. source DB의 schema/data를 쓰는 SQL과 임시 파일 생성·삭제 코드는 없다. WAL shared-memory 상태 접근은 SQLite에 의해 필요할 수 있고 권한/잠금 실패를 그대로 오류로 반환한다.

- [고정 Gecko reader](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/GeckoCookieImporter.swift#L129-L183): moz_cookies 7개 컬럼과 expiry Unix 초, NULL 문자열 행 생략 기준.
- [고정 query SQL](https://github.com/steipete/SweetCookieKit/blob/d5ea6d92298779ec0c3ddf7d3d99da186a305e14/Sources/SweetCookieKit/BrowserCookieImporter.swift#L330-L349): contains/suffix LIKE wildcard 및 exact 비교를 바인딩 매개변수로 옮겼다. pure in-memory matcher로 대체하지 않는다.
- [SQLite isolation](https://www.sqlite.org/isolation.html): read transaction은 commit된 snapshot을 본다.
- [SQLite read-only WAL](https://www.sqlite.org/wal.html#read_only_databases): WAL/SHM 상태 또는 디렉터리 접근 조건에 따라 read-only open이 실패할 수 있다. mutable source를 immutable로 속이지 않는다.

SQL 문자열에는 cookie domain 입력을 직접 넣지 않는다. LIKE의 %/_ 의미는 원본대로 남기고 quote는 바인딩으로 처리한다. NUL 포함 query는 오류다. sqlite3_step의 SQLITE_DONE만 성공으로 인정하고 기타 오류에서 수집된 일부 record를 반환하지 않는다. 실패한 open handle과 prepare statement를 포함해 수명을 정리한다. 오류는 숫자 SQLite code만 포함하여 cookie/SQL 내용을 노출하지 않는다.

record의 scope는 leading dot을 제거하기 전에 raw host에서 얻는다. 이는 원본 Gecko row→공용 record 변환에서 dot이 소실되던 부분의 수정이다. HTTP 변환의 scope 제한 자체는 027과 동일하게 남는다. 만료 equality 및 session expiry를 보존한다. UTF-8 SQLite 문자열은 바이트 길이로 읽어 embedded NUL에서 조용히 잘리지 않게 했다.

busy timeout은 lock contention당 250ms이며 전체 query deadline이 아니다. 연결을 빌리는 내부 read(database:query:)는 호출자가 연결과 busy-handler 수명을 소유한다. 제품 URL 진입점은 직접 열고 닫는다.

## 정적 검토 범위

디스크를 만들지 않는 :memory: fixture 테스트 소스를 작성했다. exact의 대소문자/leading dot, expiry equality, NULL 행 생략, domain scope, SQL wildcard/quote, schema 누락, query NUL 오류를 다룬다. 테스트를 실행하지 않았다. 빌드/컴파일/LSP/실제 SQLite DB/브라우저/계정 접근도 없다. git diff --check와 독립 소스 리뷰만 진행한다. 독립 리뷰에서 새 구체적 결함은 보고되지 않았다. 파일 기반 WAL/lock 오류와 도중 step 실패는 테스트 소스에서도 다루지 못한 검증 한계로 남는다.

## 완료로 세지 않는 부분

reader는 아직 Windows client stores/records, cookie gate, provider fetch에 연결되지 않았다. SQLite 배포/Windows ABI/실제 잠금·WAL 동작도 미검증이다. 다음 단계는 Firefox store discovery→reader→per-browser capability를 묶고 Amp 같은 provider의 기존 순서와 fallback 계약을 유지하며 연결하는 것이다. 그 뒤 남은 Chromium 복호화와 나머지 importer/local storage를 계속한다.
