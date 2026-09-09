# Windows cookie 소비자 계약 027

기준 SweetCookieKit 0.5.2 / d5ea6d92298779ec0c3ddf7d3d99da186a305e14. Package.resolved에 고정된 dependency를 기준으로 분석한다.

- Mistral: domainMatch exact, includeExpired false, referenceDate 주입이 필수다. 단순 domain 목록 API로 축소하지 않는다.
- Qoder: exact domain과 provider 자체 domain 검사를 둘 다 보존한다.
- MiniMax/MiMo/Groq 등: store.profile.id와 primary/network 우선순위로 같은 profile 안에서만 병합한다. 다른 계정/프로필 쿠키를 합치지 않는다.
- MiMo: 비어 있는 cookie store도 Firefox session restoration의 시작점이므로 결과를 matching record 있는 store로만 제한하지 않는다.
- OpenCode: 작은 Chromium 연결 후보지만 Chrome/Dia 기본 순서를 Firefox로 임의 변경하지 않는다. importer, WebCookieSupport, descriptor retry의 각각 macOS guard를 추적한다.
- Amp: Firefox reader 이후 연결 후보. default order와 session cookie 조건 및 downstream guard를 함께 옮긴다.
- CLI cookie, ProviderPluginCookieBroker, UserProviderPluginCookieBroker는 독립적인 macOS guard가 있어 따로 연결해야 한다.
- BrowserLocalStorageAPI 및 Devin/Windsurf/MiniMax/Factory local storage는 cookie reader로 대체되지 않는다.

필수 타입: Query(domains,domainMatch,origin,includeExpired,referenceDate), Record(domain,scope,name,path,value,expires,isSecure,isHTTPOnly), Store(browser,profile,kind,label,databaseURL), StoreRecords(store,records). client는 stores, records, makeHTTPCookies 및 configuration.homeDirectories 계약을 갖는다. 현재 Windows에는 backend가 없고 cookie capability는 false다.

이 문서는 소스 조사 결과다. 실제 브라우저/계정/프로필 접근이나 실행 검증을 하지 않았다.
