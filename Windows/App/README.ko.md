# Windows 네이티브 앱

상태: **CODE_WRITTEN_UNVERIFIED**. IMPL-598은 WinUI 3 초기 화면과 기존 Windows 트레이
런타임 사이의 통신 경로를 작성한 단계다. 복원·빌드·테스트·실행·패키징은 수행하지 않았다.
전체 W03/W04/W07 기능 완료나 배포 가능한 설치 파일을 의미하지 않는다.

## 작성한 화면과 동작

- 트레이의 “CodexBar 열기”가 앱 창을 연다. 이미 실행 중이면 다음 응답의 activation 값으로
  기존 창의 활성화를 요청한다. 창을 닫으면 트레이는 계속 실행한다.
- Overview는 기존 provider presentation의 사용량 행과 검색을 제공한다.
- Usage & Spend는 IMPL-600에서 기간(7/30/90/수집된 전체, 최대 365일)·통화 그룹 선택,
  일별 비용 차트, 365일 토큰 활동 히트맵, 공급자/모델/프로젝트/세션별 40행 페이지를
  연결했다. 차트 click/hover와 이전·다음 날 버튼으로 날짜별 수치·누락 상태를 읽는다.
  새 데이터 수집 없이 기존 scan을 재집계한다. 창의 선택 저장은 IMPL-605에서 추가했다.
- IMPL-601은 일별 차트의 선택 날짜에 시간별 비용을, 프로젝트·세션 행에 모델 상세
  40행 페이지를 연결했다. 프로젝트 상세는 기간 내 일별 비용도 표시한다. 시간대 표시는
  UTC 오프셋으로 서머타임의 반복 시각을 구분하며, 누락된 시간과 확인된 0을 분리한다.
  모델·시간대 합계가 전체 청구액을 설명한다고 가정하지 않는다.
- IMPL-603은 Compare rolling periods로 7/30/90/365일 비용·토큰·수집 범위를 함께 표시한다.
  원본 비용 카드의 comparisonSummaries처럼 같은 수집 기준일에서 끝나는 겹치는 기간이다.
  각 행에서 해당 기간의 차트로 이동한다. 확인된0과 unknown을 구분하고 날짜/공급원 coverage가
  부족한 값에는 ~와 설명을 붙인다. 이는 인접한 이전 기간 대비 증감률이 아니다.
  한 actor turn에서 동일 scan/환율표를 사용하며 추가 기간은 합계 중심으로 투영한다.
  기간 비교 자체가 과거 데이터를 추가 수집하거나 트레이 설정을 변경하지 않는다.
- IMPL-604는 선택 기간·통화의 Share Stats 미리보기, 텍스트/이미지 복사, PNG 저장,
  비용 JSON 복사/저장을 기존 Windows 네이티브 경로에 연결했다. 365일 토큰 차트를 보고
  있더라도 출력 범위는 선택 기간이다. 공유 카드는 공개 공급자·모델 이름과 허용된 요금제
  이름만 사용한다. JSON은 PII 숨김 시 source ID·별칭·비공개 모델명·숨김 source ID도
  익명화한다. 끈 경우에는 원래 source ID/라벨을 포함하며 프로젝트/세션 원문은 제외한다.
  실패/수집 중인 데이터의 공유 카드는 거절한다. 부분 JSON에는 별도 수집 상태 안내를
  표시한다. 앱 응답은 요청 접수이며 실제 복사/저장 성공 증거가 아니다.
- Display settings는 PII 숨김, credits/extra 표시, 사용량 표시 방향, reset 시각 표시의
  네 키만 저장한다. 트레이와 같은 설정 저장소·렌더링 경로를 사용한다.
- IMPL-602의 Cost settings는 비용 수집·Codex ledger·OpenCodeX logs·OpenCodeX가 있을 때
  native Codex 숨김 토글, 원본 통화 유지/지원 통화 환산, 공급원별 및 전체 포함/제외를 제공한다.
  일반 설정은 수집 결과가 없어도 읽고 저장하며, 공급원 선택은 현재 수집이 준비됐을 때 제공한다.
  공급원은 40행씩 표시하고 전체 포함/제외는 모든 페이지에 적용한다. 현재 목록에 없는
  공급원의 기존 숨김 설정은 보존한다. PII 모드에서는 계정 별칭 대신 Source N으로 표시한다.
- 연결 실패 시 이전 데이터를 내리고 컨트롤을 잠근다. 저장 응답이 유실된 변경은 자동
  재전송하지 않고, 재연결 후 현재 설정을 다시 받는다.
- IMPL-605는 마지막 탭, 비용 기간/통화/차트/분류/비교 여부, 선택 날짜를 앱 재개 시
  복원한다. backend의 별도 versioned view key에 저장하며 수집/환산 설정이나 계정 선택을
  바꾸지 않는다. 프로젝트·세션 raw ID/행 번호·일시적인 상세 revision은 저장하지 않는다.
  지정 통화가 사라지면 빈 상태와 재선택 안내를 유지한다. Automatic을 직접 선택한 경우에만
  현재 첫 통화 그룹을 사용한다. 날짜는 현지화된 문자열이나 차트 index 대신 yyyy-MM-dd로
  저장하며, 현재 차트에 없는 날짜를 다른 날로 조용히 바꾸지 않는다.
  UI에는 저장 상태와 Retry save/Restore saved view를 제공한다. 불확실한 저장은 자동
  재전송하지 않으며, 명시적 재시도는 현재 revision을 읽고 다시 flush한다.
- IMPL-606은 Codex model changes and service tiers 패널을 추가했다. 선택 통화·포함 공급원
  중 native Codex만 집계하며, 같은 수집/환율표에서 현재 기간과 바로 앞의 같은 경과시간
  기간을 비교한다. 40행씩 모든 모델의 비용/토큰, New/Ended/Unchanged/증감률,
  기록된 standard/priority 비용·토큰과 토큰 구성을 표시한다. 다른 공급자와 OpenCodeX는
  이 패널의 대상이 아니므로 상위 전체 비용과 범위가 다르다.
  양 기간의 공급원·모델·합계가 완전할 때만 증감을 제공한다. 가격/이력이 없으면 unknown,
  일부 알려진 값에는 ~를 표시한다. DST로 이전 기간이 하루 중간에서 시작하면 일별 자료로
  경계를 추정하지 않고 온전한 날짜의 값만 표시하며 증감률은 보류한다. 별도 과거 수집은 없다.
  PII 숨김은 분석·기본 모델 표·프로젝트/세션 모델 상세에 공개 모델 계열 또는 Model N을
  사용한다. 분석 토글/페이지는 이번 창에서만 유지한다.
- IMPL-608은 같은 모델 패널에 현재/이전 기간의 기록된 effort별 토큰과 고유 세션 참조 수·
  증감을 연결했다. 모델마다 같은 세션은 기간 내 한 번 세며 여러 모델을 사용한 세션은
  각 모델에 나타날 수 있다. 요청 수를 세션 수로 대신하지 않는다. effort가 없는 사용량은
  Unrecorded로 표시하며 명시적 none과 구분한다. 서버 적용 effort를 증명하는 수치는 아니다.
  이벤트 집계와 일별 모델 합계가 맞는 경우만 사용하며, 구형 자료·한도 초과·누락·stale은
  Unknown/~ 및 증감 보류로 표시한다. 세션 ID/경로는 보고서별 번호로 치환해 내부에서만 쓰고
  모델 집계 화면/pipe에는 집계 숫자를 전달한다. IMPL-614부터 세션 상세에서 PII 표시가
  허용된 경우 기록된 원본 ID를 표시한다. PII 숨김은 사용자 정의 effort를 Custom으로 묶는다.
  최대12개 effort 라벨을 표시하며 그보다 많으면 추가 라벨 수를 알린다.
  effort별 비용은 IMPL-612, 기간별 세션 참조 탐색은 IMPL-613에서 연결했다.
  원본 세션 ID·복사·일부 실행 창 연결은 IMPL-614에서 추가했다. WIN-057 전체 완료가 아니다.
- IMPL-609는 Focus this model / All models로 모델 하나 또는 전체를 선택하고 현재 기간의
  일/주/월 토큰·비용·세션 참조 타임라인을 보는 기능을 연결했다. 주간은 수집 시간대의
  월요일 시작이며 조회 기간 가장자리의 주/월은 실제 포함 날짜로 잘라 표시한다.
  세션 참조는 모델·공급원·구간 안에서 중복을 제거한다. 여러 구간을 합하면 같은 세션이
  반복될 수 있다. 막대 클릭/tooltip과 이전·다음 구간 버튼으로 숫자를 읽는다.
  모델 선택은 수집/기간/통화/개인정보 상태와 모델 순서에 묶인 revision 및 행 번호로 전달한다.
  상태가 바뀌면 이전 모델 선택을 해제하고 재선택 안내를 제공한다. 원본 모델 ID는 선택 요청에
  넣지 않으며 익명 Model N은 전체 모델 목록의 번호를 유지한다.
  모델 필터는 모델 표/타임라인에 적용한다. 상위 비용 및 coverage 요약은 전체 범위를 유지한다.
  선택과 timeline 옵션은 현재 창에서만 유지한다. 선택 범위 CSV는 IMPL-611에서 연결했다.
  기존 Share Stats/비용 JSON은 기간·통화 전체를 내보내며 이 모델 필터를 적용하지 않는다.
- IMPL-610은 Choose models 목록에서 여러 모델을 포함하거나 전체에서 일부를 제외하는 선택을
  연결했다. All models와 No models를 구분하며 선택 없음은 빈 표/타임라인으로 표시한다.
  선택 목록과 결과 표는 각각40개씩 독립적으로 페이지를 넘긴다. 필터로 숨겨진 모델도 다시
  추가할 수 있고 익명 Model N의 번호는 전체 목록 기준이다. include/exclude 예외는 최대256개다.
  정렬된 행 번호와 revision만 요청에 넣으며 오래된/중복/범위 밖 선택은 거절한다.
  모델 표와 일/주/월 타임라인에 같은 선택을 적용하고 기존 Share Stats/비용 JSON 범위는 유지한다.
- IMPL-611은 Copy model CSV / Save model CSV를 Windows 클립보드와 저장 대화상자에 연결했다.
  결과 표의 현재 페이지와 관계없이 선택 모델 전체의 현재/이전 기간, 토큰 구성, 기록된 tier/effort,
  증감 상태 및 현재 선택한 metric의 일/주/월 타임라인을 출력한다. 소스의 추가 읽기는 없다.
  Windows CSV schema_version 1은 지표별 행 형식이다. record_kind/model/dimension/metric으로
  구분하고 value_status는 complete/partial/unknown, collection_status는 complete/partial/stale이다.
  날짜는 UTC 시작 포함/끝 제외 시각이며 원래 bucket 시간대를 별도 열에 넣는다.
  비교의 숫자는 백분율이 아닌 변화 비율이고 new/ended/unchanged/unavailable은 comparison_state로 구분한다.
  모델·구성·tier·effort·timeline 행에는 중복되는 사용량이 있으므로 모두 더한 값을 총계로 쓰지 않는다.
  소스 coverage는 선택한 모델만의 coverage를 뜻하지 않는다.
  PII 숨김 시 Model N 및 Custom effort를 사용하고 원본 계정·소스·세션 ID/경로는 내보내지 않는다.
  UTF-8/CRLF CSV이며 외부 텍스트의 따옴표/개행/수식 접두어를 escape한다.
  16 MiB/100000행/셀16 KiB 한도를 초과하면 전체 출력을 거절하며 조용히 자르지 않는다.
  clipboard는65,536 UTF-16 code units를 넘으면 저장을 안내한다.
  원본 Mac CSV와 동일한 schema는 아니다. 모델 단위 priced/unpriced coverage·raw aliases와
  share 비율은 IMPL-615에서 추가했으며 원본 CSV 계약 전체 대응·검증은 남아 있다. WIN-057 전체 완료가 아니다.
- IMPL-612는 현재/이전 기간의 기록된 effort별 비용과 가격 적용/미가격 토큰 수를 연결했다.
  보고서의 기존 이벤트 가격 resolver를 같은 catalog/priority/custom-pricing 값으로 호출한다.
  현재 effort 설정이나 모델 총비용을 토큰 비율로 나누지 않는다. 해당 날짜·모델의 이벤트 가격
  합계가 같은 보고서의 비용과 맞는 경우만 사용하고, Windows 집계에도 같은 통화 환산을 적용한다.
  구형 보고서의 누락 필드, 잘못된 가격/토큰 분할, 합계 불일치는 비용 unknown으로 남긴다.
  무료0과 가격 미확정은 구분하며 알려진 일부 비용에는 ~를 표시한다. 알려진 토큰/세션 정보는
  비용 근거 부족만으로 삭제하지 않는다. PII 숨김 시 사용자 정의 effort의 토큰과 비용을 Custom으로 합친다.
  CSV effort 행에 estimated_cost/priced_tokens/unpriced_tokens를 추가하며 기존 출력 한도를 유지한다.
- IMPL-613은 모델 행의 Current sessions / Previous sessions에서 해당 기간의 세션 참조 목록을
  열고, Session details에서 같은 세션에 기록된 모든 모델·effort·일별 토큰을 보는 기능을 연결했다.
  목록의 수치는 선택 모델만, 상세의 수치는 같은 세션의 모든 모델을 포함한다. 두 화면 모두 선택
  기간의 수치이며 세션의 전체 생애 사용량이 아니다. 목록과 상세 모델 행은 각각40개씩 페이지를 넘긴다.
  상세에서 목록의 원래 페이지로 돌아갈 수 있고 일별 사용량은 막대 차트/tooltip/이전·다음으로 읽는다.
  기존 보고서별 참조 번호와 공급원 위치만 내부에서 연결하며 새 세션 파일 읽기나 설정 저장은 없다.
  세션 식별자가 없는 기록은 모델 총계에 남기고 목록에는 연결하지 않는다. 비용은 기존 날짜·모델
  가격 대조 결과를 재사용한다. 구형·불완전·stale 자료는 Unknown/~로 표시하고 빈 날짜를 임의로0으로
  채우지 않는다. PII 숨김은 전체 모델 목록의 Model N 번호와 Custom effort를 그대로 사용한다.
  참조 순서·모델 소속도 HMAC revision에 묶어 수집이 바뀐 오래된 상세를 거절한다. pipe 요청은
  모델/참조 행 번호·기간·페이지·revision만 사용한다. 원본 세션 ID와 실행 창 연결은 아래 IMPL-614를 따른다.
  Share Stats/JSON/모델 CSV는 이 탐색 상태를 제외한 기존 출력 범위를 유지한다.
- IMPL-614는 보고서 내부에 참조 번호→원본 세션 ID의 optional 표를 보존한다. 최대4096개/ID512 bytes이며
  같은 UUID의 대소문자를 통일한다. 구형 표 누락·잘못된 ID·중복 참조/ID는 연결을 제공하지 않고
  기존 토큰·비용은 유지한다. 공용 daily-report JSON과 공개 AgentSession DTO에는 이 표를 넣지 않는다.
  모델 선택 revision에 원본 ID도 묶어 참조 번호가 같아도 대상이 바뀌면 이전 동작을 거절한다.
  상세에서 Copy session ID / Copy resume command / Focus running session window를 제공한다.
  ID·명령 복사는 PII 표시가 허용된 경우만 가능하며 resume 명령은 UUID로만 만든다. 명령을 실행하거나
  계정/profile/cwd를 추정하지 않으므로 원래 계정·작업 폴더에서 사용해야 한다. stale 자료의 동작은 막는다.
  Focus는 이미 켜진 local CLI sessions의 완료된 검색 목록에서 같은 UUID를 명시적으로 resume한
  Codex 프로세스가 하나일 때 기존 PID/생성시각/소유자/창 재확인 경로를 사용한다. 새 검색/프로세스 실행,
  최근 파일·폴더명 기반 매칭은 하지 않는다. 검색 꺼짐·진행 중·부분 목록·중복/누락을 별도 안내한다.
  앱 창만 활성화했으면 정확한 터미널 탭으로 이동했다고 표시하지 않는다. 최초 생성 세션,
  editor별 정확한 탭과 계정/profile/cwd를 포함한 직접 재실행은 아직 추가 구현이 필요하다.
  PII 표시가 허용된 모델 CSV에는 session_id_association 행의 dimension에 ID, value에 연결 표시1을
  넣는다. 사용량에 더할 숫자가 아니며 같은 모델/기간의 ID를 공급원 전체에서 중복 제거한다.
  PII 숨김 시 이 행을 제외하고, 구형 ID를 복원하거나 만들어 내지 않는다. 문자열 escape와 출력 상한은 유지한다.
- IMPL-615는 현재/이전 모델별 priced/unpriced 토큰·가격 적용률·비용 상태와 토큰/알려진 비용/세션 참조
  비중을 모델 표와 CSV에 연결했다. 적용률은 가격 적용·미가격 토큰 합계가 같은 모델의 전체 토큰과
  일치할 때만 계산한다. 가격이 없는 자료를 미가격0으로 바꾸지 않으며 무료0과 가격 미확정을 구분한다.
  비용 상태는 known/partial/unavailable/no_usage다. 완전히 확인된 사용량0은 빈 적용률100%, 비중0이며,
  사용량이 불명확하면0으로 채우지 않는다. 구형·부분·stale 자료의 알려진 수치는 ~ 또는 partial로 표시한다.
  비중의 분모는 선택 통화·기간의 포함된 native Codex 모델 전체다. 모델 필터/페이지로 다시100%를
  만들지 않는다. 비용 비중은 알려진 비용만, 세션 참조 비중은 모델별 참조 수 합계를 사용한다.
  같은 세션이 여러 모델에 포함될 수 있으므로 고유 세션 전체의 점유율로 해석하지 않는다.
  rawAliases는 이벤트의 rawModel만 보존하고 canonical 이름으로 역추정하지 않는다. 그룹32개·
  보고서8192개·라벨256 bytes, Windows 기간/모델별256개 한도에서 알려진 목록을 유지한다.
  한도·누락·잘못된 별칭은 목록의 불완전 상태로 표시하며 토큰·가격 집계는 줄이지 않는다.
  표는 기간마다 최대6개와 추가 개수를 표시하고 문자열 예산을 적용한다. CSV는 보존된 전체 별칭을
  raw_alias_association의 dimension에 넣고 value1은 연결 표시로만 사용한다. PII 숨김은 별칭을
  화면과 CSV에서 제외한다. 별칭은 원래 모델과 canonical ID가 일치하는 기록만 연결한다.
  CSV pricing_coverage와 세 종류의 share는0~1 비율이며 cost_status는 dimension의 기호 값이다.
  cost_status의 numeric value는 비워 두고 value_status는 그 상태 판단의 완전성을 표시한다.

## 프로세스와 통신 규약

기존 `CodexBarWindows.exe`가 단일 런타임과 credential/config 소유자다.
WinUI 프로세스는 공급자에 직접 접속하거나 두 번째 백엔드를 시작하지 않는다.

1. 트레이가 새 UUID pipe 이름과 자신의 PID를 인자로 지정하여 절대 경로의 UI를 시작한다.
   handle을 상속하지 않으며, 자식 환경은 Windows·사용자 폴더 관련 키만 허용한다.
2. UI가 native named-pipe listener를 만든다. 현재 사용자 SID의 protected DACL,
   첫 인스턴스 전용, 원격 클라이언트 거절, overlapped I/O를 요청한다.
3. 양측은 native API로 얻은 peer PID를 비교한다. Swift 측은 자신이 시작한 프로세스
   handle과 세션·사용자 identity를, UI 측은 기존 백엔드 handle·경로·세션을 사용한다.
   pipe 이름이나 클라이언트가 보낸 문자열만으로 신뢰하지 않는다.
4. JSON 앞에 4바이트 little-endian 길이를 붙인다. 요청은 최대 4 KiB, 응답은 최대
   1 MiB다. Overview 문자열은 96 KiB, spend의 상위 화면과 상세 화면을 합친 문자열은
   128 KiB UTF-8 예산을 적용하고 초과 시 truncation을 표시한다. 모델 분석도 이 예산을 공유한다. Overview에는 최대
   256개 카드·1024개 행 예산과 카드당 64개 상세 행 제한이 있다. spend는 상위/상세
   각각 최대 40행, 모델 분석도 최대 40행, 차트 각각 최대 365개 지점이다.
5. 연결 첫 요청은 `hello`다. protocolVersion 1, requestID, backend generation을
   확인한다. 연결당 중복 requestID는 거절하고 4096개 뒤 재연결한다.
6. 허용 메서드는 `hello`, `snapshot`, `refresh`, `setSetting`, `spend`,
   `spendPreferences`, `setSpendPreference`, `spendAction`,
   `viewPreferences`, `setViewPreferences`, `generalPreferences`, `setGeneralPreference`이다.
   snapshot은 2초 간격으로 요청한다. 표시 설정 쓰기는 네 키의 고정 순서 boolean SHA-256
   revision을 대조한다. 이는 오래된 화면의 저장을 감지하는 낙관적 대조이며, 트레이와
   별도 스레드에서 발생하는 모든 설정 쓰기의 원자적 직렬화를 보장하지 않는다.
   `spend`는 bounded query(days/currency/section/chart/page/detail/comparePeriods/codexModelsPage 및
   codexModel/codexGranularity/codexMetric/codexCatalogPage/codexSessions)를 받아 일반 snapshot과
   별도의 응답으로 보낸다. controller await 전후 collection/generation/publication/settings를
   대조하고, PII·문자열 예산을 적용한 표·차트만 전송한다. 내부 source/account 키는
   전송하지 않는다. 통화 그룹이 사라지면 다른 통화로 자동 합산하지 않는다.
   상세 선택은 수집 세대·통화·기간·privacy·프로젝트/세션 순서를 묶은 프로세스 키 기반
   HMAC revision과 행 번호/날짜를 보낸다. 원문 소유자 ID·프로젝트 경로는 전송하지 않는다.
   수집이나 행 순서가 바뀌면 이전 상세 요청을 거절한다. 시간별 projection은 controller
   옵션을 저장하거나 source를 다시 수집하지 않고, await 후 publication/설정을 다시 대조한다.
   비용 설정은 별도 응답이며 전체 설정·현재 공급원 순서·PII·수집 세대를 HMAC revision으로
   묶는다. 공급원 쓰기는 raw ID가 아닌 그 revision의 행 번호만 받는다. 저장 직전 값 비교와
   변경 필드 쓰기를 backend 프로세스의 동일 잠금 아래 수행하고 트레이의 비용 설정/공급원
   저장도 이 경로를 사용한다. 외부 프로세스의 설정 편집까지 원자적으로 직렬화하지는 않는다.
   저장 응답은 설정 저장 여부이며 수집 완료를 의미하지 않는다. 기존 runtime이 이후
   재집계/환율 fetch/필요한 재수집을 처리한다. 실패·응답 유실은 현재 값을 다시 읽고 자동
   재전송하지 않는다. 앱의 표시·비용·일반 설정 저장도 동시에 시작하지 않는다.
   일반 설정은 갱신 주기·절전 모드·service status·메뉴 열 때 refresh의 네 값 전체를
   SHA-256 revision으로 묶는다. 트레이의 동일 설정 저장과 cadence 기본값 migration도
   backend 프로세스의 동일 재귀 잠금 아래 수행한다. 외부 프로세스 편집은 이 잠금으로
   직렬화되지 않는다. 변경한 필드만 쓰고 synchronize 실패 시 현재 값을 다시 돌려주며,
   메모리에서 변경된 값은 runtime에 반영하되 영구 저장 성공으로 표시하지 않는다.
   응답 성공은 설정 저장 여부다. 스케줄러 재설정/전력 경계 재계산과 status 조회 완료를
   의미하지 않는다. 타 메서드 필드와 섞인 요청·비허용 enum·잘못된 revision은 거절한다.
   기간 비교는 같은 publication/generation·수집일·source catalog·통화·시간대·날짜 경계의
   결과만 사용한다. 별도 FX fetch 없이 rate table을 한 번 캡처하며 시간별 상세에도 같은
   table을 전달한다. 누락/비정상 환율은 기존 원본 통화 그룹으로 유지한다.
   비교의 최대4행도 spend의 공유128 KiB 문자열/1 MiB 응답 예산 안에 포함한다.
   `spendAction`은 공유/JSON6개, 모델 CSV2개, 세션3개 동작 및 현재 출력/선택 revision을 추가로 받는다.
   세션 동작은 model/reference 행 번호와 원본 ID까지 묶인 모델 revision을 대조한다. 복사는 기존
   native mailbox, 창 이동은 기존 local-session runtime으로 보낸다. 실행 직전 수집/PII/환율 및
   세션 검색 활성 상태를 다시 확인한다. 명령문·원본 ID·PID를 동작 요청으로 받지 않는다.
   모델 CSV revision은 기존 수집/view/model-order revision에 포함·제외 선택/간격/metric도 묶으며
   표/선택 목록 페이지에는 의존하지 않는다. 기존 revision은 환율표에도 묶인다.
   생성된 PNG/DIB/JSON/CSV bytes·저장 경로·HWND는 pipe로 전송하지 않는다.
   backend 내부 단일 UI mailbox가 트레이 UI 스레드의 미리보기/클립보드/저장 대화상자에
   전달하고, 실행 직전과 대화상자 동안 수집 무효화·설정·PII·환율 변화를 대조한다.
   진행 중인 native action이나 pending action이 있으면 중복 접수를 거절하며 modal loop
   재진입도 막는다. 응답 유실 시 자동 재전송하지 않는다. JSON/이미지/CSV 산출물은16 MiB,
   clipboard text는65,536 UTF-16 code units로 제한한다. 저장 취소를 성공으로 보고하지 않는다.
   view 설정은 `windowsNativeAppViewV1` Data key의 최대4 KiB JSON이다. 저장 직전
   raw data SHA-256 revision을 대조하고 read/compare/write를 같은 프로세스 잠금으로
   직렬화한다. 계정/source ID나 credential은 포함하지 않는다. 누락은 기본값, 손상/다른
   schema/읽기 실패는 보존·쓰기 거절로 처리한다. flush 후 읽은 값이 다르면 실패로 응답한다.
   in-memory 쓰기 이후 synchronize 실패도 성공으로 바꾸지 않는다.
   UI는400ms 동안 선택 변경을 합쳐 저장하며 저장 중 후속 선택은 성공 응답 뒤 이어 쓴다.
   `AppWindow.Closing`에서 close를 즉시 취소한 뒤 최대2초 동안 미전송 선택을 처리하고
   닫는다. backend 종료는 기다리지 않는다. 비정상 종료·시간초과의 마지막 선택 보존을
   보장하지 않으며 기존의 불확실한 저장을 닫기 과정에서 자동 재시도하지 않는다.
7. UI는 15초, Swift I/O는 30초의 대기를 제한한다. Swift는 취소한 overlapped 작업의
   완료를 기다린 뒤 buffer/event를 해제한다. 백엔드 종료를 감지하면 UI도 닫힌다.

전달 데이터는 표시 문자열·상태·표시/비용 설정과 불투명한 revision/행 번호다. API 키, cookie, OAuth token, raw config,
파일 경로를 위한 필드는 없다. 실제 Win32 PID/ACL/취소·보안 동작은 Windows 검증이 필요하다.

## 배포 위치와 의존성

계획한 파일 배치는 다음과 같다. 앱 폴더 전체를 동일 버전으로 배치해야 한다.

```text
<version-root>/
  CodexBarWindows.exe
  CodexBarCLI.exe
  <Swift runtime and backend resources>
  App/
    CodexBarApp.exe
    CodexBarApp.dll
    CodexBarApp.deps.json
    CodexBarApp.runtimeconfig.json
    <.NET and Windows App SDK publish output, XAML/PRI/resources>
```

프로젝트는 Windows 11 최소 빌드 22000, Windows SDK 26100, .NET 10, WinUI 3,
x64/ARM64를 대상으로 한다. `Microsoft.WindowsAppSDK 2.2.0` 및
`Microsoft.Windows.SDK.BuildTools 10.0.26100.4654`를 지정하고, .NET/App SDK의
self-contained 파일 배포를 요청한다. single-file publish와 trimming은 끈다.
위젯 host의 SDK 파일과 UI의 SDK 파일은 폴더를 분리한다.

**IMPL-599에서 publish·조립·서명 연결 코드를 작성했으나 실행하지 않았다.**
`Publish-CodexBarApp.ps1`은 명시적인 dotnet.exe, 기존 lockfile, 검토된 라이선스
폴더, revision/version/architecture와 새 출력 폴더를 입력받는다. 실제 호출하면
locked restore와 self-contained publish를 수행하므로 현재 macOS 구현 단계에서는 실행하지 않는다.

- Windows에서 의존성을 restore하여 실제 `packages.lock.json`을 생성·검토하고
  `-PackageLockFile`로 지정해야 한다. 현재 저장소에는 lockfile이 없고 전이 의존성을
  확인하지 않았다. 스크립트는 전달받은 lockfile을 복사하여 locked mode로 사용한다.
- output은 소스 프로젝트 밖의 새 디렉터리만 허용한다. publish/bin/obj/packages를 분리하고
  실패 결과도 보존한다. `LicenseDirectory`에는 실제 의존성 라이선스와
  `THIRD-PARTY-NOTICES.txt`가 필요하다. 내용의 법적 완전성을 자동 판정하지 않는다.
- 결과는 `publish/`와 별도 `build-receipt.json`이다. receipt에는 전체 App 파일의
  종류·크기·SHA-256, lock digest, 선언된 소스 revision/version이 들어간다.
  로컬 파일 일치 기록이며 서명된 빌드 attestation은 아니다.
- `New-CodexBarDistributionManifest.ps1`에 `-AppPublishDirectory`와
  `-AppBuildReceipt`를 함께 전달한다. 기존 Swift runtime/resource/license 입력도
  필요하다. App 파일을 RuntimeFiles나 ResourceDirectories로 중복 공급하지 않는다.
- producer/조립/서명은 App 파일을 별도 payload로 다루고 실제 파일 바이트·분류·누락을
  대조한다. App의 EXE와 `CodexBarApp.dll`을 first-party 서명 목록에 추가하며,
  서명 후 변경된 크기/해시로 App payload를 재작성한다.
- DLL 이름은 root 백엔드와 App 애플리케이션 디렉터리를 구분하여 해석한다. App에서 부족한
  DLL을 Swift/widget 검색 폴더에서 자동 보충하지 않는다. 관리 DLL의 PE32는 CLR 헤더,
  ILONLY, 32-bit/native 제약 등을 읽어 명시적으로 허용한 App DLL에만 수용한다.

기존 portable 설치와 MSIX pack은 인벤토리의 하위 파일을 포함하는 경로를 사용한다.
설치/갱신/rollback의 실제 동작, WinUI runtime/PRI/bootstrap, Windows x64/ARM64,
장시간 재연결·프로세스 종료·패키지 identity는 아직 검증하지 않았다.
PE import 검사는 .NET assembly reference, P/Invoke, 동적 LoadLibrary, XAML/PRI 로딩을
증명하지 않는다. 실제 publish 결과와 deps/runtimeconfig에 대한 후속 대조 및 Windows 실행이 필요하다.

## 남은 앱 구현

전체 설정 pane, 계정·인증·provider 편집, 최초 생성 세션·정확한 terminal/editor 탭·직접 재실행 연결과
원본 모델 CSV 계약 전체 대응 및 큰 이력/메타데이터 한도 처리,
작업별 action/copy/open/login,
레이아웃 편집, 전역 단축키·창 위치/스크롤 보존,
전체 현지화, 키보드/Narrator/고대비·다중 모니터 QA가 남아 있다.
현재 UI 문구는 영어이며, 트레이의 열기 항목만 기존 en/ko 사전에 연결했다.
`WIN-007/010/012/013/015/026`은 부분 구현 상태로 유지한다.

`TestsWindows/WindowsAppProtocolTests.swift`에는 framing, JSON 키와 필수 필드,
설정 revision/allowlist, Unicode/escape byte 예산의 합성 fixture 11개를 작성했다.
실행하지 않았으며, native pipe·WinUI·실계정 기능의 동작 증거가 아니다.
IMPL-600의 `TestsWindows/WindowsAppSpendProjectionTests.swift`에는 query 경계·통화 분리,
0/누락·PII·paging·heatmap·stale/partial·응답 바이트 예산의 fixture 9개를 추가했다.
이 테스트와 UI 실행도 미실행이다. 비용 collection 활성화는 트레이와 Cost settings에서 설정한다.
IMPL-601은 `TestsWindows/WindowsAppSpendDetailTests.swift`에 상세 요청/날짜 경계,
수집·행 순서·privacy HMAC 결합, 모델 paging/PII, 프로젝트 누락/중복/0,
DST 23/25시간, 시간별 publication/페이지, 합산 바이트 예산의 합성 fixture 8개를
작성했다. 기존 controller fixture에도 선택 날짜가 공유 옵션을 바꾸지 않는 경우를 추가했다.
모든 fixture와 WinUI 상호작용은 미실행이다.
IMPL-602의 `WindowsAppSpendPreferencesTests.swift`에는 공급원 paging/PII,
수집 미완료 상태의 일반 설정, 잘못된 catalog 거절, revision 변경, 미수집 공급원 설정 보존,
허용된 설정 shape/통화, 큰 이름의 응답 상한, 요청 wire fixture 8개를 작성했다.
모두 미실행이며 UserDefaults 저장·동시성·UI·환율 fetch의 실제 동작 증거가 아니다.
IMPL-603의 `WindowsAppSpendComparisonTests.swift`에는 DST 날짜 경계, 누락/중복/통화,
partial/stale/0, 다른 수집·source·기간 거절, 주입 환율/원본 통화 fallback, 요약 집계,
추가 수집/공유 설정 변경 없음, wire/PII의 fixture 9개를 작성했다. 실행하지 않았다.
기존 controller fixture의 필수 publisher 인수도 보완했다. 컴파일·성능·UI 검증은 보류했다.
IMPL-604의 `WindowsAppSpendExportTests.swift`에는 action/wire, 기간/통화 범위,
PII와 로컬 JSON, 공유 alias 제거, 주입 renderer의 출력 전달, partial/stale 안내,
잘못된 선택/렌더 실패, clipboard 상한, 환율 revision, delivery 철회의 fixture10개를
작성했다. 모두 미실행이며 실제 클립보드·PNG·대화상자·저장 파일 품질은 검증하지 않았다.
IMPL-605의 `WindowsAppViewPreferencesTests.swift`에는 기본값/무쓰기, 값·날짜 allowlist,
저장 round trip, 손상/과대/newer schema 보존, revision 충돌, flush 전후 실패와 재시도,
readback 불일치, wire 경계, heatmap 날짜 키의 합성 fixture9개를 작성했다.
실제 defaults·WinUI 재개/닫기·debounce/동시 선택·다중 인스턴스·강제 종료는 검증하지 않았다.
IMPL-606의 `WindowsCodexModelAnalysisTests.swift`에는 인접 기간/증감, 미가격 모델,
불완전/빈 이력, service-tier 누락/불일치, 중복 날짜·합계·날짜 오류, overflow, DST,
주입 FX/통화 범위, stale, 공급원 숨김/재수집 없음, paging/PII/응답 예산의 합성 fixture12개를
작성했다. 기존 상세 fixture는 비공개 모델 이름의 익명화와 PII off 동작을 추가했다.
모두 미실행이다. 실제 수집 자료의 완전성, 컴파일, WinUI 배치·키보드·성능은 검증하지 않았다.
IMPL-607은 rollout의 기록된 effort를 이벤트/증분 캐시/sidecar/내부 fragment에 보관하고
기존 캐시를 수집 예산 안에서 이관하는 코드를 추가했다. 현재 thread 설정으로 과거 값을 채우지 않는다.
이 값의 Windows 집계·WinUI 표시는 다음 IMPL-608에서 연결했다.
`WindowsCodexEffortTests.swift`에 파서·context 경계·resume·legacy decode·재가격·캐시 교체·
sidecar migration/rollback 합성 fixture12개를 작성했다. 컴파일·테스트·실제 마이그레이션은 미실행이다.
IMPL-608의 WindowsCodexActivityTests.swift에는 세션 중복/익명 번호·legacy/none·집계 상한/overflow·
공개 JSON 제외/내부 보고서 보존·다른 자료 병합·기간별 집계·합계/날짜/누락 경계·privacy/stale
합성 fixture8개를 작성했다. 모두 미실행이며 실제 Windows 화면·성능·정확도를 검증하지 않았다.
IMPL-609는 WindowsCodexTimelineTests.swift에 모델 범위/환산·구간별 session 중복·월요일/DST/월 경계·
누락/부분/미가격·선택 revision·익명화/오래된 선택 거절·wire 경계·365일/stale 합성 fixture8개를 작성했다.
기존 모델 분석 wire fixture도 timeline과 별도 selection revision을 포함하도록 확장했다.
전부 미실행이며 WinUI 그래프·클릭·키보드/Narrator·컴파일·성능은 검증하지 않았다.
IMPL-610의 WindowsCodexModelSelectionTests.swift에는 포함/제외 집계, privacy/wire, 전체/빈 선택,
선택 목록의 독립 페이지, 여러 모델의 세션 참조 의미, 구형 선택/잘못된 형식, 요청 상한,
오래된/범위 밖 선택 거절 합성 fixture8개를 작성했다. 전부 미실행이다.
IMPL-611의 WindowsCodexModelCSVTests.swift에는 페이지 밖 선택 전체, all/none/exclude, privacy,
미가격/누락/partial, stale/증감, 달력/metric, CSV escape, 출력/clipboard 상한, export revision,
action/query/전송 경계 합성 fixture10개를 작성했다. 모두 미실행이며 실제 CSV 파일/표 계산 앱,
WinUI 버튼/클립보드/저장 대화상자·경쟁 조건·컴파일·성능은 검증하지 않았다.
IMPL-612의 WindowsCodexEffortPricingTests.swift에는 이벤트별 가격, 무료/미가격/불안정 행,
잘못된 분할/overflow, legacy decode, 비용 합계/환산, 불일치 시 토큰 보존, 부분 가격,
구형 소스/Custom privacy, stale/bounded evidence, 환율 누락 합성 fixture10개를 작성했다.
모두 미실행이다. parser hash는 쓰기 모드로 생성했으며 check 모드·빌드·UI 검증은 실행하지 않았다.
IMPL-613의 WindowsCodexSessionNavigationTests.swift에는 공급원/기간별 참조 분리, 같은 세션의 다른
모델·일별 사용량, 식별자 누락, 목록/상세 독립 페이지, privacy/wire, legacy/stale 가격,
참조 순서·모델 소속 revision과 오래된 선택 거절, query/내보내기 경계 합성 fixture8개를 작성했다.
모두 미실행이다. WinUI 이동/돌아가기/스크롤/막대 차트·컴파일·실자료·성능은 검증하지 않았다.
IMPL-614의 WindowsCodexSessionActionsTests.swift에는 내부 ID 표/구형 호환, 모호·잘못된 표의 연결
철회와 토큰 보존, 공급원/기간 격리, PII 표시·복사 차단, UUID 명령, ID 변경 revision, 유일한
명시 resume 프로세스 매칭, prompt의 resume 단어가 ID를 바꾸지 않는 경우, CSV privacy/escape,
동작 요청 경계 합성 fixture11개를 작성했다. 기존 activity fixture도 행/내부 표/공용 JSON의 경계에
맞춰 갱신했다. 전부 미실행이다. 실제 프로세스·창 이동·클립보드·resume 실행·컴파일은 검증하지 않았다.
IMPL-615의 WindowsCodexModelMetricsTests.swift에는 원본 별칭/구형 누락, 별칭 한도와 사용량 보존,
잘못된 별칭 격리, 무료/미가격/부분/구형 가격, 혼합 소스 coverage, 전체 범위·모델별 세션 비중,
확정된 사용량0, 누락 비용·세션, stale/부분 완전성, 비정상 비율, CSV 기호 상태·비율·PII,
optional codec/공용 JSON, 모델별256개 한도 합성 fixture13개를 작성했다. 전부 미실행이다.

IMPL-616은 Settings 화면에 일곱 갱신 주기, Off/On/Automatic 절전 모드, 서비스 상태 확인,
트레이 메뉴 열 때 refresh를 기존 표시 설정과 함께 연결했다. 저장된 settings navigation ID는 유지한다.
기존 adaptiveAgentAware 값은 읽어 표시하지만 선택은 금지하며, 다른 주기로 바꾸도록 안내한다.
활동 감지 scheduler/동의 흐름 자체는 아직 구현되지 않았고 이번 변경도 이를 완료로 계산하지 않는다.
원래 activityConsent 저장값은 변경하지 않는다. 화면 이탈/다른 저장으로 오래된 응답을 철회하고,
응답 유실의 쓰기는 자동 재전송하지 않는다. 전체 설정·계정·인증·provider 편집은 계속 남아 있다.

WindowsAppGeneralPreferencesTests.swift에 선택지/다른 값 보존, 미지원 legacy 모드, 요청 shape/allowlist,
revision 범위, 트레이 변경과의 충돌, no-op/invalid 쓰기, 저장 결과, flush 실패, 외부 변경,
요청 혼합 거절, bounded wire의 합성 fixture11개를 작성했다. 모두 미실행이며 실제 defaults/전력
상태/타이머/계정/네트워크/WinUI를 열지 않는 fixture다. 빌드·lint·Windows UI 검증도 미실행이다.

## API 참고

- [CreateNamedPipeW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipew)
- [GetNamedPipeServerProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeserverprocessid)
- [Windows App SDK self-contained 배포 문서](https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps.md)
- [Windows App SDK 공식 릴리스](https://github.com/microsoft/WindowsAppSDK/releases)
- [Windows 앱 색상과 테마](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/color)
- [AppWindowClosingEventArgs.Cancel](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindowclosingeventargs.cancel?view=windows-app-sdk-2.0)
