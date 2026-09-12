# 추가 전수 대조 — 추출 누락·동적 연결·계획 정확성 (2차 기록)

후속 [3차 검토](TERTIARY-AUDIT-2026-09-12.ko.md)에서 선택지·출력·기본값·Windows remote 조건을 보강했다. 이 문서의 8,151개는 2차 시점의 계수다.

2026-09-12 후속 감사. 원본 `928166f899471bbdcb72210641cdec91324d0154`를 유지하며 최신 upstream이나 실제 계정을 조회하지 않았다. 1차 도구를 반복 실행하는 것 외에 **raw 선언·실제 bootstrap 등록·양방향 링크**를 별도 검사기로 대조했다.

## 결과

추가 수정 소요가 있었다. 새 제품 기능군을 임의로 늘리지 않고 기존 **72개 기능군**의 수락 조건과 세부 추적을 보강했다. 추가로 확인한 계획·추출 결함은 아래와 같이 조치했다. 원본 제품 코드의 알려진 불일치를 수정했다고 주장하지 않으며, 그 수정은 Windows 구현 의무로 명시했다.

| ID | 발견과 근거 | 조치 | 상태 |
|---|---|---|---|
| SA-01 | 69개 provider JSON의 source_obligations가 mode 항목 생성 전에 계산돼, 해당 provider의 조회 모드 역참조가 전부 빠짐 | 모든 mode 생성 후 backlink 계산. 공유 폴더의 다른 provider 모드는 제외. 누락·dangling·cross-provider 링크 검사 추가 | 추적 도구 수정·검사 통과 |
| SA-02 | plugin d.ts scanner가 `?`와 `<T>`를 인식하지 않아 41개 optional 선언과 4개 generic method를 누락 | optional/generic/inline schema/defineProvider 및 runtime prelude export 추적. 기존 schema 위치 71→116개. 원본 인용 위치를 별도 raw 선언으로 대조 | 추출 수정·검사 통과 |
| SA-03 | 환경변수 배열·소문자 별칭이 단일 uppercase 문자열 검사에서 빠짐. 예: Crof `[CROF_API_KEY,CROFAI_API_KEY]`, Kimi OAuth host aliases, `kimi_auth_token` | 순서가 있는 27개 alias 배열과 7개 lowercase 읽기를 추가. normalization·account injection/scrub·endpoint override 규칙을 WIN-065에 명시 | 계획·추적 수정 |
| SA-04 | 실제 `ctx.date.nowMillis()`는 prelude에 있으나 원본 d.ts에 없음 | runtime 동작 보존과 Windows authoring type 일치를 WIN-047 필수 조건으로 지정. 원본 소스를 임의로 바꾸지 않음 | 구현 시 해결할 알려진 원본 불일치 |
| SA-05 | ProviderConfig의 unknown extension JSON, typed getter/setter, nil/잘못된 값 처리가 고정 설정 필드 표만으로 불명확 | 14개 확장키·28개 read/write 호출을 별도 추적. unknown non-null 보존·Int64 순서·최상위 null 생략·nested null 거부·충돌 방지·nil 삭제 fixture 명시 | 계획·추적 수정 |
| SA-06 | descriptor/파일 존재만으로 69개가 실제 등록된다는 것을 검사하지 않았음 | UsageProvider ID↔Core ProviderManifest↔App ProviderImplementationManifest의 69개 연결을 대조하고 JSON 증거 저장 | 등록 연결 검사 통과; Windows 실행 미검증 |
| SA-07 | provider protocol default hook가 빈 구현일 수 있고, typed settings 전달·keepalive callbacks는 단순 UI ID로 표현되지 않음 | app-side operation 819개, id/supportsLoginFlow property 후보 101개, settingsSection 선언 38개, runtime action 2개 추적. Augment keepalive와 provider-ID/type 검사를 WIN-063/064에 명시 | 계획·추적 수정 |
| SA-08 | 하나의 경로 규칙이 모든 provider 코드를 WIN-001로 우선 배정해 세부 책임을 가릴 수 있음 | primary 책임 외 관련 기능군을 obligation에 병기. 전체 목록 완료 boolean을 없애고 정의된 추출 범주 검사 통과만 표시 | 메타데이터·판정 수정 |
| SA-09 | runtime prelude가 별도 OpenRouter management-auth 옵션을 전달함. d.ts 보완 중 이를 일반 plugin 권한으로 확대할 위험 | WIN-047에 first-party OpenRouter·secure key·GET·HTTPS·정확한 host/path·port/userinfo/fragment 거부 조건을 명시 | 계획 보강; 원본 권한 확대 없음 |

## 설정과 동적 연결의 수락 조건

- 일반 설정 91개 state 필드와 provider JSON schema는 별개다. unknown provider 확장 값은 지원되는 타입 범위에서 재저장 후 유지한다. 최상위 unknown null을 생략하는 원본과 nested null을 거부하는 원본을 “모든 JSON null 보존”으로 바꾸지 않는다.
- `providerConfigBinding(.secretWorkspace(logField: ...))`는 평문 workspace UI와 로그 취급이 다르다. 동일 저장 필드를 쓴다는 이유로 비밀 로그 정책을 잃지 않는다.
- native 설정→observation→typed snapshot→credential planner는 한 흐름이다. `ProviderSettingsSectionRegistration.accepts`의 provider ID/section type 일치를 보존하며 빈 default contribution이 선택 계정의 실제 설정을 지우지 않게 한다.
- 브라우저 로그인과 provider keepalive는 별도다. 시작·비활성화·조회 실패·강제 session refresh·복구 callback·종료 시 timer/작업 정리까지 포함한다.
- 대소문자를 다르게 가진 synthetic 환경 dictionary나 여러 alias가 동시에 주어질 때 처리 순서를 명시적으로 검증한다. 원본 alias 순서와 선택 계정의 credential 우선순위를 유지하고, 모호한 값을 임의 선택해 다른 계정으로 조회하지 않는다.

## 플러그인 대응 범위

`costUsage`, `nextRegenPercent`, `nextRegenAmount`, `subscriptionExpiresAt`, identity-only 응답, optional dates/details 등은 실제 mapper/host 동작과 함께 구현한다. optional 선언은 “구현 안 해도 되는 기능”이 아니라 특정 응답에서 값이 생략될 수 있다는 뜻이다. 제네릭 TypeScript 선언을 보존하되 QuickJS의 런타임 타입 검증·숫자 범위·부분 데이터 의미는 별도로 유지한다.

`ctx.date.nowMillis`는 실제 원본 runtime API로 보존한다. Windows용 type declaration 정합성을 맞출 때 private/bundled-only auth 예외까지 공개 API로 넓히지 않는다. 원본에는 OpenRouter management key를 읽기 전용 공식 endpoint에 묶는 검사가 있다.

## 검증과 수치

정확한 현재 계수는 `SURFACE-AUDIT-SUMMARY-2026-09-12.json`, 별도 검사 결과는 `SECONDARY-AUDIT-2026-09-12.json`을 따른다. 이차 감사 후 추적 단위는 **8,151개**이며, 1차의 6,943개와 마찬가지로 사용처/선언의 중복을 포함한다. 기능 수나 완성률 분모가 아니다.

- 69개 ID/Core/App 등록 chain 일치.
- 69개 provider의 163개 mode backlink 누락 0, 다른 provider mode 혼입 0.
- optional 41개 + generic method 4개의 source declaration이 schema 추적에 포함됨.
- 14개 extension key의 read/write 쌍 존재와 추적 일치.
- 27개 alias 배열의 raw 선언과 추적 일치.
- 별도 raw-line UI event scan에서 기존 추적과 다른 누락 0.
- 기존 2,844개 경로/blob, 72개 기능군, 91개 state, 169개 CLI declaration, 19개 action, 6개 Hook, 문서 링크·source excerpt 검사 재실행.

실행한 것은 Python 문서 추출/검사 도구뿐이다. Swift/compiler/manifest evaluation, 앱, provider probe, 실계정, 원격 Windows, CI를 실행하지 않았다. 새로 검사한 범위에서는 미조치 추적 결함이 없지만, 이것을 모든 동적 경로의 의미 검증 또는 Windows 배포 가능 판정으로 바꾸지 않는다. 원본 불일치 SA-04와 외부 서비스/OS 게이트는 구현·검증 단계의 명시적 미완료 의무다.
