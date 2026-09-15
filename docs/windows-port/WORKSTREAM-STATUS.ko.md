# Windows 전용 제품 작업 현황

- IMPL-535: 새 관측 없이 기존 이력을 여는 경로에도 계정/pair 이관 연결. 파일·owner·이관 근거가 같은 경우에만 read cache 재사용, 이관 후 실제 게시 데이터 revision을 전달하고 이전 chart lease 무효화. 없는 provider history JSON은 만들지 않음. CODE_WRITTEN_UNVERIFIED.

- IMPL-534: 비-Codex 계정 이력 및 legacy session/weekly pair metadata 이관 연결. Claude 이메일 키 이관과 OAuth/UUID owner 분리, unscoped adoption의 Claude veto, pair 충돌 무효화 및 Windows legacy defaults 선택 읽기 작성. CODE_WRITTEN_UNVERIFIED.

- IMPL-533: Codex의 legacy email/canonical/opaque 및 unscoped 이력 이관 규칙을 Core로 이전하고 Windows의 새 표본 저장에 연결. 저장 직전 현재 계정과 이관 근거를 재대조하도록 작성. Claude/generic 이관·삭제 lifecycle·동시 계정 소비 및 실행 검증은 남아 있음. CODE_WRITTEN_UNVERIFIED.

- IMPL-532: 열린 트레이의 사용량/예측 게시 변경에 따라 메뉴와 복사·상세·이력·계정 명령을 함께 다시 구성하는 경로 작성. 위치 유지, 중복 게시 무시, 하위 메뉴 탐색 중 갱신 유예, 닫기/선택 우선 처리. Windows 메뉴 동작 검증 미실행. CODE_WRITTEN_UNVERIFIED.

- IMPL-531: 일반 트레이의 해당 주간 행에 세션 환산 예측 연결. 파일 내용/owner 기반 읽기 cache 및 이력 revision·구간 identity·idle 분 단위 burn cache 작성. 이미 열린 Win32 메뉴의 즉시 갱신은 남아 있음. CODE_WRITTEN_UNVERIFIED.

- IMPL-530: 원본 session-equivalent burn/forecast 계산을 Core로 옮기고 주간 이력 상세에 연결. 최근 7개 후보·최소 3개 유효 표본, 구간/계정 identity 및 근무일 기준 적용. 일반 사용량 행과 cache lifecycle은 남아 있음. CODE_WRITTEN_UNVERIFIED.

- IMPL-529: 트레이 공급자별 사용량 이력 메뉴→계정 확인 조회→Win32 차트 창 연결. 최근 30개 리셋 구간, 마우스·키보드 탐색, 전체 텍스트 이력, DPI/시스템 색상 및 오래된 snapshot 닫기 작성. CODE_WRITTEN_UNVERIFIED.

- IMPL-528: 현재 공급자·계정·설정과 묶인 이력 조회 token 및 snapshot 경로 작성. 읽기 전후 소유권 재대조, 새로고침/계정/종료 무효화, 빈 이력과 읽기 실패 구분. Native 차트 창 연결은 남아 있음. CODE_WRITTEN_UNVERIFIED.

- IMPL-527: 원본 이력 차트의 공급자 series 선택·리셋 구간 peak·빈 구간·최근 30개·날짜 축을 공통 모델로 작성. 계정 조회 및 native chart UI 연결은 남아 있음. CODE_WRITTEN_UNVERIFIED.

- Git 반영 규칙: 매 구현 단위마다 커밋 및 origin/main 푸시. 누적 IMPL-340~526은 4135f98d0으로 원격 반영 완료. 검증 보류 상태는 유지한다.

- IMPL-526: 공급자별 plan-utilization 표본/구간 identity 전환을 저장소와 조회 성공 경로에 연결. 계정·설정 변경 표본 제외, 수집 오류 별도 안내. CODE_WRITTEN_UNVERIFIED.

- IMPL-525: WIN-020의 공통 이력 schema/시간당 peak reducer 및 Windows 보호 파일 저장소 작성. 공급자 수집·계정 소유권·조회 UI는 미연결. W14 plugin 이력 수집 범위 설명 정정. CODE_WRITTEN_UNVERIFIED.

- IMPL-524: 소스 백업 선택→복원 검토→교체/재설치 연결. 삭제 후 공급자 항목이 없어도 backup ID로 복원하며 설정 복구와 구분. CODE_WRITTEN_UNVERIFIED.

- IMPL-523: ID 파싱 실패/중복 ID 등 로드 실패 plugin 파일의 선택→해시 검토→파일만 삭제 경로 연결. 설정·승인·캐시 보존. CODE_WRITTEN_UNVERIFIED.

- IMPL-522: plugin 삭제 검토→명시적 확인→파일/캐시·승인·설정·secret 제거 및 부분 실패 안내 연결. 이력 정리/손상 파일 삭제는 남아 있음. CODE_WRITTEN_UNVERIFIED.

- IMPL-521: 설정/승인 기록만 남은 plugin을 메뉴에서 재설치하고 기존 파일명 충돌을 거부하도록 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-520: plugin 파일 교체 메뉴→파일 선택→명시적 검토 확인→백업/교체 runtime 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-519: plugin 교체 검토/백업/승인 해제/비활성화/게시 backend 작성. UI 미연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-518: plugin 설치 오류를 단계별 고정 enum/한국어·영어 복구 안내로 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-517: 빈 plugin 목록에서도 local file 설치 메뉴→파일 선택→runtime 설치→완료 안내 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-516: Windows 신규 local plugin 설치 staging/ID 충돌 방지/runtime 경로 작성. 파일 선택 UI 미연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-515: plugin settings combo 삽입/선택 실패를 거부해 표시 순서와 설정 키 일치 보존. CODE_WRITTEN_UNVERIFIED.

- IMPL-514: 플러그인별 설정 메뉴→native editor→runtime save/cancel 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-513: plugin 설정 선택/유지/변경/삭제 native editor 작성. 메뉴/저장 callback 미연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-512: plugin 설정 저장에 디스크 source hash 대조 및 검토 cancel/shutdown 정리 추가. CODE_WRITTEN_UNVERIFIED.

- IMPL-511: plugin plain/secure 설정 snapshot/patch/runtime 저장 경로 추가. native editor 미연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-510: 플러그인 사용 설정 불명/로드 불가/승인 필요 상태를 구분해 표시. CODE_WRITTEN_UNVERIFIED.

- IMPL-509: plugin 활성/비활성 버튼과 상태 안내를 native dialog→runtime 저장 경로에 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-508: plugin review 사용 여부 snapshot 및 활성/비활성 runtime 저장 API 추가. UI 토글 연결 미완료. CODE_WRITTEN_UNVERIFIED.

- IMPL-507: Windows 승인/철회에서 검토 당시 binding과 저장 시 binding을 잠금 안에서 비교. CODE_WRITTEN_UNVERIFIED.

- IMPL-506: Windows approval store record/remove의 read-modify-write에 공유 금지 sidecar lock 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-505: approval store 읽기 실패/손상 시 변경 저장을 거부해 기존 기록 덮어쓰기 방지. CODE_WRITTEN_UNVERIFIED.

- IMPL-504: 승인/철회 저장 응답을 공급자 refresh 완료 대기와 분리하고 파일 handle 범위 축소. CODE_WRITTEN_UNVERIFIED.

- IMPL-503: 플러그인 승인 메뉴에 256개 단위 이전/다음 페이지와 범위 표시 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-502: 삭제/로드 실패 plugin의 저장된 승인도 메뉴와 철회 전용 review에 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-501: 권한 검토 dialog의 철회 버튼→runtime 승인 기록 제거→재조회 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-500: 플러그인 권한 submenu→runtime review→native dialog→approval save→refresh 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-499: 플러그인 권한 검토/typed origin 입력용 Win32 dialog 작성. 메뉴 연결 미완료. CODE_WRITTEN_UNVERIFIED.

- IMPL-498: 플러그인 승인 검토 snapshot/일회성 token/파일 및 권한 변경 검사와 저장 runtime 경로 추가. UI 연결 미완료. CODE_WRITTEN_UNVERIFIED.

- IMPL-497: 플러그인 검색 실패 건수/재검색 안내를 트레이 rendering에 연결. CODE_WRITTEN_UNVERIFIED.

- IMPL-496: 트레이 수동 refresh에 플러그인 재검색 연결, 진행 중 refresh 후 요청 coalescing. CODE_WRITTEN_UNVERIFIED.

- IMPL-495: 호스트 시작 전 취소 요청을 보존하는 cancellation slot 및 실행 overload 추가. CODE_WRITTEN_UNVERIFIED.

- IMPL-494: Swift/native bootstrap 파이프 이름을 생성기와 같은 canonical UUID 형식으로 제한. CODE_WRITTEN_UNVERIFIED.

- IMPL-493: 외부 취소 콜백의 queue/pipe/state 소유를 weak reference로 변경해 종료 후 핸들 보유 방지. CODE_WRITTEN_UNVERIFIED.

- IMPL-492: 위젯 호스트 시작/수신/작업/정리 결과의 통합 종료 판정 추가. CODE_WRITTEN_UNVERIFIED.

- IMPL-491: native theme observer가 고대비 on/off와 dark/light 분류가 같은 색 변경에도 카드 갱신을 요청한다. 두 이벤트 구독을 close에서 해제한다. IMPL-340~491 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-490: card batch가 고대비 palette 또는 조회 실패를 한 번 캡처해 모든 이미지에 전달한다. 조회 실패는 차트가 필요한 카드에서만 반영한다. IMPL-340~490 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-489: history/burn PNG가 Windows 고대비 상태와 시스템 전경/배경색을 읽어 적용한다. 고대비에서는 gradient 채움을 생략하고 선 종류/표식 위치로 구분한다. 실제 색 전환/렌더 검증 미실행. IMPL-340~489 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-488: 설치 정책의 실행 파일 이름/package family로 같은 Windows session의 프로세스를 찾아 핸들을 보관하고 RPC caller 인증에 연결했다. 실제 버전별 정책과 executable/bootstrap 통합은 남아 있다. IMPL-340~488 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-487: trusted-callers host 진입에서 프로세스 package full name/current-user 설치 family/Store 또는 System 서명/실행 이미지 위치를 대조한다. 실제 Windows broker family 정책·발견 및 호환성은 남아 있다. IMPL-340~487 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-486: 설정 revision 충돌 시 오래된 폼/카드를 무효화하고 native worker가 최신 snapshot을 다시 표시한다. consumed settingsChanged action만 연결을 유지하며 저장 재실행은 하지 않는다. IMPL-340~486 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-485: backend listening과 인증된 hello 수락 상태를 구분했다. 기존 native monitor가 30초 내 handshake 수락을 요구하고 미수락 시 원인을 남겨 연결을 정리한다. OS 등록/렌더 완료는 별도이다. IMPL-340~485 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-484: runtime이 backend lifecycle stream을 소비해 자체 정상 종료된 owner를 해제하고 최종 snapshot을 보존한다. 정리 실패는 owner를 유지하며 이전 연결 이벤트가 새 연결을 변경하지 못하게 한다. IMPL-340~484 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-483: 앱 종료 대기 완료 전 runtime의 widget cleanup 실패를 stderr에 보고하도록 연결했다. 기존 OS 종료 시간 제한/사용자 종료 대기는 유지한다. IMPL-340~483 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-482: runtime.shutdown의 중복 호출이 같은 teardown Task 완료를 기다리도록 변경했다. widget close를 포함한 기존 정리 순서를 유지하며 호출자 취소와 자원 정리를 분리한다. IMPL-340~482 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-481: runtime이 설정 root 아래 WindowsWidgets/settings.json store/service를 소유하고 모든 backend 재연결에 같은 service를 전달한다. 설치별 경로 주입도 지원하며 초기화만으로 파일은 만들지 않는다. IMPL-340~481 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-480: WindowsUsageRuntime에 단일 widget backend factory/close 소유권을 추가하고 기존 shutdown에 연결했다. 정리 실패 owner는 보관하여 중복 host 생성을 막고 재시도 상태를 남긴다. 실제 launcher는 미구현이다. IMPL-340~480 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-479: 위젯 차트 PNG에 정확한 256색 이하 palette encoding을 연결했다. 색/해상도 변경 없이 index를 저장하며 색이 많거나 이득이 없으면 RGB를 유지한다. PNG 디코드 검증 미실행. IMPL-340~479 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-478: card batch 생성 시 template/data/metadata/envelope 전체 JSON 크기를 제한한다. 초과 카드는 ready 대신 기존 오류 카드로 분류하며 다른 카드 전송을 유지한다. IMPL-340~478 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-477: resetTimesShowAbsolute 설정을 runtime→coordinator→card batch→quota/burn reset 표시로 전달했다. countdown은 tray 공통 formatter를 사용하고 다음 갱신을 최대 60초 또는 reset 시점으로 당긴다. IMPL-340~477 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-476: quota 행의 정확한 공통 제목 Session/Weekly/Code review를 localized labels로 표시한다. 제공자 고유 제목과 데이터/행 순서는 유지한다. IMPL-340~476 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-475: history 일별 비용/토큰/누락/불명 관측/범례 5개 문구를 나머지 지원 언어 21개에 추가했다. 데이터 없음과 실제 0의 구분을 포함한다. IMPL-340~475 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-474: burn pace 상태/주간 제한/예상 소진/리셋 이후/선 종류 범례를 21개 언어에 추가했다. history 범례 번역과 실제 화면 검수는 남아 있다. IMPL-340~474 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-473: used/remaining/updated/resets/codeReview/tokens/full/spent/maximum 기본 문구를 나머지 지원 언어 21개에 추가했다. 번역·화면 검수는 미실행이다. IMPL-340~473 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-472: 추가 사용 잔액/API 추정 비용·실제 청구액 아님 안내를 나머지 지원 언어 21개에 추가했다. 번역 및 Windows 화면 검수 미실행. IMPL-340~472 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-471: metric 제목을 typed 의미로 전달하여 카드의 credits/today/30일 비용 번역을 사용한다. 제공자 고유 기간과 API 추정·비청구 구분을 유지한다. 추가 잔액/추정 안내는 en/ko 우선 등록했다. IMPL-340~471 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-470: history 날짜 범위를 선택 언어의 날짜 형식으로 표시하고 UTC day key를 유지한다. 단일 날짜는 중복 범위를 생략하며 이미지 대체 텍스트에도 같은 caption을 사용한다. IMPL-340~470 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-469: quota/code review/burn 수치에 locale percent formatter를 적용하고 history 누락/불명 개수를 지역 숫자 형식으로 표시한다. locale 방향성 mark 3종을 text 경계에서 허용한다. IMPL-340~469 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-468: 위젯 데이터 없음/제공자 비활성/대기/오래됨/사용 불가/갱신 실패/위젯 오류 문구를 21개 언어에 추가했다. 차트 및 수치 설명 번역은 남아 있다. IMPL-340~468 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-467: 영어/한국어 외 기존 지원 언어 21개에 위젯 설정·제공자 선택·측정 항목·기간 문구 11개씩 번역을 추가했다. 카드 상태/차트 문구 및 실제 화면 검수는 남아 있다. IMPL-340~467 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-466: bootstrap 인코딩 실패와 준비 후 host 종료를 connection 정리 경로에 연결했다. deinit은 기존 close 작업을 기다리고 실패한 경우에만 순차 정리를 재시도한다. 원격 event 회수 launcher 계약은 미구현이다. IMPL-340~466 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-465: backend connection에 bounded lifecycle stream/snapshot을 추가하고 시작·serving·종료·정리 실패와 최초 종료 원인을 전달한다. launcher 소비/재연결 구현은 남아 있다. IMPL-340~465 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-464: widget backend receipt 확인을 manifest 공통 파일 추가 함수에 연결했다. import에서 발견한 backend를 검색 경로나 시스템 DLL 선언으로 대신 공급하지 못하게 하고, 의존성 추가 후 first-party 구성도 확인한다. 스크립트 미실행. IMPL-340~464 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-463: host 진입 함수가 인증된 채널로부터 event RAII 소유권을 명시적으로 받는다. JSON의 handle 숫자로 소유권을 만들지 않고 일치만 확인하며, COM/호출자 인증/파싱 실패도 전달받은 owner가 정리한다. IMPL-340~463 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-462: 원래 COM 콜백 스레드에서 RPC 호출자 PID/로컬 인증 상태를 조회하고 launcher가 신뢰 확인한 살아 있는 process handle 집합과 대조하는 구현 및 process runner 연결을 추가했다. 실제 Widgets broker 신뢰 판별·호환성은 남아 있다. IMPL-340~462 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-461: native runner가 handshake/worker/receiver/factory 생성 실패도 같은 취소·OS 내용 철회 범위로 처리한다. WidgetManager 생성 자체 실패는 상위 startup 오류로 남는다. IMPL-340~461 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-460: native process 실행 함수가 MTA/COM 보안/bootstrapped host/session 실행/COM 해제를 연결했다. 종료 콜백은 host 주소 없이 queue/pipe/shared flag만 보관한다. 실제 executable·인증 채널은 남아 있다. IMPL-340~460 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-459: 전용 native host용 COM process 보안 초기화 함수를 작성했다. 현재 사용자 local execute ACL/absolute descriptor/packet privacy를 설정한다. executable 호출과 실제 Widgets caller 인증·호환성 확인은 남아 있다. IMPL-340~459 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-458: widget DLL manifest 입력에 Release build receipt의 아키텍처/크기/해시 일치 확인을 연결했다. receipt 내부 경로는 신뢰하지 않고 명시적 입력만 읽는다. 스크립트 미실행. IMPL-340~458 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-457: native server 상태 조회는 종료 전후 gate를 확인하고 deinit 정리는 기존 close Task 완료를 먼저 기다린다. 예비 정리의 중복 실행을 줄였다. IMPL-340~457 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-456: backend connection이 native terminal 상태를 관찰해 session/server/receiver/event 정리를 호출한다. 상태 조회 오류도 별도 기록 후 종료한다. 관찰 코드는 실행하지 않았다. IMPL-340~456 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-455: build wrapper receipt에 DLL 크기/SHA256/MSBuild 파일 버전과 미증명 provenance 상태를 추가했다. native 인자 경로의 끝 역슬래시 인용 문제도 보완했다. 스크립트 미실행. IMPL-340~455 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-454: publisher가 OS 철회 전 전체 대상과 실패 결과 용량을 확보하고 예외 시 미처리/실패 ID를 유지하도록 변경했다. 성공한 obsolete ID만 재시도 목록에서 제거한다. IMPL-340~454 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-453: 배포 manifest의 명시적 widget backend DLL 입력 및 first-party 서명 대상 분류를 연결했다. 기존 PE/아키텍처/의존성 처리에 참여하며 위젯 배포 완료를 의미하지 않는다. IMPL-340~453 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-452: Windows 전용 backend MSBuild wrapper를 작성했다. 명시적 MSBuild/SDK와 실행별 새 출력 경로를 사용하며 build receipt와 검증 결과를 구분한다. 스크립트 미실행. IMPL-340~452 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-451: backend DLL용 v143 MSBuild 프로젝트(x64/ARM64)를 추가하고 pipe listener의 widget UI 헤더 의존성을 분리했다. host executable/App SDK 프로젝트·패키징 연결은 남아 있다. IMPL-340~451 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-450: native numeric_limits max 호출을 Windows max 매크로와 충돌하지 않는 표현으로 변경하고 직접 사용하는 표준 헤더를 명시했다. 빌드 호환성은 미검증이다. IMPL-340~450 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-449: session의 겹친 close 호출이 같은 구독 해제/coordinator shutdown Task 완료를 기다리도록 변경했다. native server가 정리 완료 전에 다음 종료 단계로 넘어가는 경로를 보완했다. IMPL-340~449 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-448: native bootstrap owner가 decoder→인증된 backend connector→session runner를 연결하고 event/process/queue/pipe 소유권을 관리한다. private launcher 채널 인증·COM 보안·executable 진입점은 남아 있다. IMPL-340~448 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-447: Swift bootstrap encoder/native decoder 및 connection.prepareBootstrap을 추가했다. session/pipe/remote event handle을 4KiB 이하 고정 schema로 전달한다. 인증된 전달 채널/실행 진입점 연결은 남아 있다. IMPL-340~447 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-446: connection이 bootstrap target process handle을 복제 보관하고 같은 process로만 native server를 시작하도록 연결했다. 다른 start target 주입을 제거했다. IMPL-340~446 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-445: auto-reset 무효화 이벤트의 target 복제를 1회로 제한하고 raw handle borrow 진입을 내부로 제한했다. 재연결은 새 connection/event가 필요하다. IMPL-340~445 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-444: backend connection이 시작 전 trusted host process로 이벤트를 SYNCHRONIZE 권한만 복제하는 API를 제공한다. remote handle을 별도 값 타입으로 구분한다. launcher 인증/bootstrap 전달/실패 회수는 남아 있다. IMPL-340~444 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-443: native runner가 worker 종료 철회 전에 receiver StopAndJoin을 수행하도록 연결했다. producer 종료 오류와 철회 오류를 분리 보관한다. IMPL-340~443 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-442: 내부 prepare/recordPublished 반환 전 무효화 세대를 확인하고 transfer read/ack의 대기 후 만료 시각을 다시 확인한다. 만료된 ack는 coordinator 상태도 무효화한다. IMPL-340~442 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-441: 최초 구독의 내부 무효화는 hello 전에 적용하되 native 이벤트를 보내지 않는다. native 최초 inventory 철회가 이를 담당하며 이후 실제 변경 알림은 계속 전달한다. IMPL-340~441 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-440: Native session runner connects the backend client, publisher, worker, receiver and COM registration. Executable, caller authentication and trusted launcher remain incomplete. IMPL-340 through IMPL-440 uncommitted/unpushed. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-439: native receiver가 전용 thread Start/StopAndJoin 및 상태/HRESULT를 소유한다. 중복 시작·종료 후 시작을 거부하고 thread 생성 실패도 worker 취소로 전달한다. launcher의 실제 호출/핸들 전달 연결은 남아 있다. IMPL-340~439 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-438: backend connection actor가 signal/session/native server를 조립하고 신호 실패 시 연결 종료, server drain→receiver stop/join→event close 순서를 연결한다. trusted launcher/receiver 제어 구현은 남아 있다. IMPL-340~438 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-437: Swift invalidation signal owner가 unnamed auto-reset event 생성·SetEvent·닫기를 lock으로 보호하고 session callback 형태를 제공한다. trusted launcher의 target handle 복제와 실제 소유 연결은 남아 있다. IMPL-340~437 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-436: native invalidation receiver가 신뢰한 실행부의 이벤트/백엔드 process handle을 기다려 게시 무효화와 종료를 worker에 전달한다. 실제 핸들 전달·발신부·receiver 스레드 소유 연결은 남아 있다. IMPL-340~436 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-435: session 무효화 작업이 drain되는 동안 새 요청 진입을 막고, await 후 transfer ticket/revision을 재확인해 이전 카드 전송 상태가 복원되지 않도록 했다. native 알림 receiver/launcher는 남아 있다. IMPL-340~435 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-434: native invalidation이 publisher generation/게시 가능 상태를 잠금 아래 변경하고, 최우선 queue 신호로 COM worker의 내용 철회·새 갱신에 연결된다. backend 신호를 실제 받는 통신 receiver/launcher는 남아 있다. IMPL-340~434 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-433: session이 runtime invalidation stream을 구독해 카드/ticket/설정 토큰을 무효화하고 native owner용 callback을 호출한다. runtime 종료 시 session을 닫는다. native callback 전달 구현/게시 직렬화는 남아 있다. IMPL-340~433 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-432: runtime quota context/표시·optional usage·비용 설정 변경에 bounded invalidation stream을 추가했다. 초기 구독 시 재동기화 신호를 보내고 종료 때 stream을 닫는다. session consumer/native 철회 전달은 남아 있다. IMPL-340~432 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-431: widget 요청 시작 시 runtime 계정/config/표시·비용·언어 설정 상태를 비교해 기존 카드/ticket/설정 폼 토큰을 무효화한다. native 즉시 철회 알림 및 진행 중 계정 변경과 OS 게시 직렬화는 남아 있다. IMPL-340~431 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-430: native worker 기본 theme를 Windows UISettings 색상 변경 구독에 연결했다. 배경 밝기에 따라 light/dark를 선택하고 변경 시 큐에 refresh를 요청한다. 실제 executable/고대비 전용 팔레트/계정 invalidation 연결은 남아 있다. IMPL-340~430 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-429: 테마/동일 계정 수동 갱신을 위한 thread-safe RequestRefresh를 event queue와 host worker에 연결했다. 중복 요청은 합치고 진행 중 도착한 요청은 다음 갱신으로 유지한다. 실제 UI/OS theme listener 및 계정 invalidation protocol 연결은 남아 있다. IMPL-340~429 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-428: backend terminal 상태를 server/COM 정리 이후 기록하고, host worker 종료 시 알고 있는 위젯 내용을 철회한다. 동작 오류와 철회 오류를 따로 보관하며 DLL 해제 전 join은 계속 필수다. IMPL-340~428 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-427: native host worker가 초기 OS inventory 등록, event effect 적용, prepare/card/acknowledge, monotonic 갱신 대기를 같은 스레드에서 직렬화한다. 실제 프로세스 시작/COM 등록·인증/계정 변경 신호 연결은 남아 있다. IMPL-340~427 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-426: native 일반 카드 refresh driver가 manifest/개별 카드 확인, OS 게시, 성공 ID acknowledge를 연결한다. 설정 폼은 유지하고 오래된 전송 실패가 새 generation을 철회하지 않도록 한다. 실제 host worker/타이머/launcher/build 연결은 남아 있다. IMPL-340~426 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-425: native PrepareCards/ReadCard/AcknowledgeCards를 실제 pipe와 control response decoder에 연결했다. 이벤트와 mutex/sequence를 공유한다. 카드 payload 적용/launcher/build는 남아 있다. IMPL-340~425 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-424: prepare/card/acknowledge 제어 명령을 host session wire 경로에 연결했다. 이벤트와 sequence를 공유하고 ticket·필드·상한을 확인한다. native 호출/일반 카드 게시/launcher/build는 남아 있다. IMPL-340~424 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-423: 일반 카드 manifest/개별 payload/게시 확인을 하나의 120초 transfer ticket으로 연결했다. native 제어 요청/카드 적용/launcher/build는 남아 있다. IMPL-340~423 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-422: backend effect를 native 설정 폼 게시/삭제/내용 철회/전체 갱신 요청에 연결했다. 요청 전 native generation을 캡처해 늦은 응답을 거부한다. 일반 카드 wire 갱신/launcher/build는 남아 있다. IMPL-340~422 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-421: native client/Swift session에 초기 hello 협상을 연결했다. session/version/frame/event 상한 확인 후 event sequence 0을 시작한다. launcher/build/OS effect는 남아 있다. IMPL-340~421 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-420: Swift actor가 native server/DLL/callback context를 소유하고 start/status/close를 전용 Dispatch queue로 연결한다. launcher/handshake/build 연결은 남아 있다. IMPL-340~420 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-419: Swift native DLL binding에서 ABI version/필수 export를 확인하고 제한된 DLL 검색 경로를 사용하도록 작성했다. server owner/launcher/build 연결은 남아 있다. IMPL-340~419 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-418: native 서버 owner와 생성/name/start/cancel/join/status/destroy C API를 작성했다. 전용 COM worker에서 listener→server→Swift callback을 연결한다. Swift DLL binding/launcher/build는 남아 있다. IMPL-340~418 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-417: native server handler와 Swift session 사이 C callback ABI를 작성했다. 입력 복사/고정 출력 buffer/Task 취소·context 수명 계약을 연결한다. 라이브러리 빌드·launcher 연결은 남아 있다. IMPL-340~417 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-416: native 서버 receive/reply loop를 실제 pipe I/O에 연결했다. idle 연결 유지/부분 frame 제한/handler 응답 framing을 처리한다. Swift ABI·취소 연동·launcher 연결은 남아 있다. IMPL-340~416 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-415: 현재 사용자 ACL/로컬 전용/private pipe listener 및 예상 client process 확인을 작성했다. 서버 수신 루프/Swift ABI/launcher 연결은 남아 있다. IMPL-340~415 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-414: native pipe connector가 신뢰된 backend process handle의 PID/생성시각/실행경로/Windows session과 실제 서버를 비교한다. discovery/서버 ACL·역방향 인증은 남아 있다. IMPL-340~414 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-413: native queue→event encoder→pipe exchange→response decoder를 client/pump로 연결했다. 응답 순서를 적용 후 OS 효과를 전달하며 실패는 재전송하지 않는다. 인증 endpoint/Swift server/OS effect 연결은 남아 있다. IMPL-340~413 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-412: native overlapped named-pipe request/reply I/O를 작성했다. 부분 전송/30초 deadline/취소 drain/terminal 실패를 처리한다. endpoint 개설·인증·서버 연결은 남아 있다. IMPL-340~412 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-411: native/Swift에 CBW1 길이 프레임과 분할/연속 수신 decoder를 작성했다. 손상/상한/중간 EOF는 terminal 오류다. 실제 인증 pipe 연결은 남아 있다. IMPL-340~411 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-410: native 응답 decoder에서 session/request/sequence와 effect별 필드를 검사한다. 설정 폼은 원래 customization 요청에만 대응한다. 실제 transport/consumer 연결은 남아 있다. IMPL-340~410 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-409: host 응답 JSON 직렬화와 session receiveEncoded를 연결했다. 설정 폼만 제한된 template/data/token으로 전달하며 저장 설정 원문은 제외한다. native decoder/transport 연결은 남아 있다. IMPL-340~409 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-408: host session 응답에 고정 오류 코드/요청 소비 여부/다음 sequence를 추가하고 종료 후 늦은 결과의 재보관을 차단했다. wire encoder/transport 연결은 남아 있다. IMPL-340~408 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-407: Swift host session에서 decoded OS 이벤트를 생성/삭제/크기/설정/action 처리기로 연결했다. 요청 순서와 단일 작업·게시 결과를 관리한다. 실제 transport/네이티브 consumer 연결은 남아 있다. IMPL-340~407 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-406: native 이벤트 JSON encoder와 Swift decoder를 작성했다. protocol/session/sequence/종류별 필드/size/상한을 검사한다. 인증 transport/consumer 연결은 남아 있다. IMPL-340~406 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-405: native COM singleton factory 및 클래스 등록/해제 수명 관리를 작성했다. 실행 진입점/보안/dispatcher/IPC/MSIX 연결은 남아 있다. IMPL-340~405 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-404: native IWidgetProvider2 사용자 지정 요청과 최대 256개 이벤트 큐를 작성했다. consumer/COM 인증/IPC 연결은 남아 있다. IMPL-340~404 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-403: native IWidgetProvider의 6개 기본 callback을 작성하고 OS callback 객체를 값으로 복사해 전달한다. COM 인증/dispatcher/IPC/빌드는 남아 있다. IMPL-340~403 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-402: native publisher에 실제 OS inventory 조회와 확인된 삭제 반영을 추가했다. 누적 철회 대상은 256개로 제한한다. COM/IPC 연결은 남아 있다. IMPL-340~402 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-401: C++/WinRT WidgetManager 게시/철회 sink를 작성했다. 계정 context 변경과 OS 쓰기를 mutex로 직렬화하며 철회 실패 시 새 게시를 거부한다. COM/IPC/빌드 연결은 남아 있다. IMPL-340~401 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-400: 위젯 제공자 선택을 runtime bridge의 계정/설정 최신성 및 coordinator의 정확한 게시 batch/token 검사에 연결했다. native callback 연결은 남아 있다. IMPL-340~400 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-399: 호스트 재연결 inventory를 한 번의 revision-checked 저장으로 복원하고 기존 설정을 유지한다. 누락 목록으로 삭제하지 않는다. native callback 연결은 남아 있다. IMPL-340~399 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-398: OS 인스턴스 목록을 bridge에 전달하고 definition kind가 저장된 설정과 일치하는지 렌더링 경계에서 검사한다. native host 콜백/배포 연결은 남아 있다. IMPL-340~398 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-397: 위젯 준비 결과에 표시/비용 설정 및 UI 언어를 묶고 게시 최신성 확인에 반영했다. native host 연결은 남아 있다. IMPL-340~397 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-396: runtime quota snapshot에서 localized 카드 갱신기로 이어지는 bridge를 작성했다. context/generation 확인 및 게시 확인 경로를 제공한다. native OS 게시 직렬화는 남아 있다. IMPL-340~396 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-395: 동일 fetch 결과의 Codex credits/review를 dashboard 권한과 optional 표시 설정에 따라 quota snapshot에 연결했다. 실제 OS 호스트 연결은 남아 있다. IMPL-340~395 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-394: Codex의 확인된 동일 인증 fingerprint에 한해 quota snapshot에 비용/히스토리를 연결했다. 게시 최신성에는 spend generation도 요구한다. 다른 제공자/대시보드 extras/OS 호스트 연결은 남아 있다. IMPL-340~394 미커밋. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-393: runtime quota 관측을 WidgetSnapshot으로 반환하고 config digest/context 최신성 조건을 연결했다. 비용 통합/OS 게시는 남아 있다. IMPL-340~393 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-392: runtime quota 성공 결과를 기존 계정 식별 규칙으로 위젯 관측에 보관한다. 다중/미확인 owner는 제외하고 이전 context 응답을 거부한다. snapshot/OS 연결은 남아 있다. IMPL-340~392 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-391: runtime 비용 결과를 실제 WidgetSnapshot builder에 연결하고 spend generation 최신성 조회를 추가했다. quota 통합/OS 소비는 남아 있다. IMPL-340~391 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-390: 계정/소스/수집 설정 무효화 및 종료 시 위젯 비용 owner registry를 폐기한다. 표시 옵션만 재투영하는 경로는 유지한다. IMPL-340~390 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-389: 단일 Codex/Cursor 비용 소스에 runtime revision과 기존 소유권 조건을 연결했다. 동일 source만 revision을 재사용한다. 다중 계정/다른 제공자/OS 게시 연결은 남아 있다. IMPL-340~389 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-388: 런타임에서 비용 controller 결과를 읽는 위젯 전용 경계를 작성했다. 현재 revision 일치/실패·중복 제공자 제외/상태 철회를 적용한다. 호스트 소비 미연결. IMPL-340~388 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-387: 비용 controller snapshot에 위젯 게시 상태/결과/소스별 실패를 연결했다. pending/failed는 이전 비용을 새 결과로 전달하지 않는다. runtime 소비 미연결. IMPL-340~387 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-386: 비용 수집기에 명시적 계정 revision의 위젯 비용 변환을 연결하고 Scan에 별도 결과/실패를 보관한다. revision 공급/위젯 게시 소비는 남아 있다. IMPL-340~386 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-385: CostUsageTokenSnapshot → 위젯 TokenCost adapter를 작성했다. scope fingerprint 일치 조건과 account revision 입력을 요구한다. runtime ownership 공급 미연결. IMPL-340~385 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-384: 계정 확인된 비용-only 관측을 위젯 snapshot에 추가했다. 기존 quota 관측을 덮어쓰지 않으며 quota 0을 합성하지 않는다. source adapter 미연결. IMPL-340~384 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-383: History 차트를 요약 앞에 배치하고 원본의 90/60/50 높이를 종류·크기에 맞춰 적용했다. native 렌더링 미검증. IMPL-340~383 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-382: 원본 large Usage/Switcher의 전체 행/크레딧/이력 구성을 연결하고 History의 불필요한 quota 행을 제외했다. 실 화면 크기 미검증. IMPL-340~382 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-381: OS 크기를 RenderRequest/Presentation까지 보존하고 종류별 지원 크기를 render에서 다시 확인한다. large 전용 배치/OS 연결은 남아 있다. IMPL-340~381 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-380: 원본 위젯 정의 ID/지원 크기를 Windows 호스트 매핑으로 작성하고 등록 경로에 연결했다. MSIX 선언/실제 callback 미연결. IMPL-340~380 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-379: 실패 위젯을 대체할 계정/수치 없는 안내 카드 payload를 batch에 연결했다. 실패는 성공/액션 카드로 취급하지 않는다. 실제 host 교체 미연결. IMPL-340~379 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-378: 설정 카드 취소 버튼/토큰 검사/폼 닫기/일반 갱신 enqueue를 연결하고 saved/cancelled 결과를 구분했다. host 미연결. IMPL-340~378 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-377: 전체 renderBatch 실패의 재갱신을 연결하고 기존 지난 deadline이 1분 재시도를 앞당기지 않도록 작성했다. 실행 미검증. IMPL-340~377 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-376: 카드 생성/게시 실패 항목의 1분 재갱신과 설정 폼 열기 실패 후 예약 복구를 작성했다. OS callback 미연결. IMPL-340~376 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-375: 게시된 카드 nextRefresh를 단일 취소 가능한 timer/host wake callback에 연결했다. 설정 중인 카드는 예약 대상에서 제외한다. host callback 미연결. IMPL-340~375 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-374: 설정 중인 위젯은 일반 카드 게시 대상에서 제외하고 customizing 결과를 반환한다. 폼 열기/닫기로 기존 delivery를 무효화한다. OS 게시 경로 미연결. IMPL-340~374 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-373: 설정 폼 열기/닫기/제출을 조정기에 연결했다. 같은 위젯 최신 열기만 유효하며 context 폐기 시 폼도 폐기한다. OS 이벤트 미연결. IMPL-340~373 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-372: 종류별 위젯 설정 Adaptive Card 및 bounded 제출 해석을 작성했다. 한국어/영어 label 연결. 조정기/OS 폼 이벤트 미연결. IMPL-340~372 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-371: 위젯 종류별 provider/metric/window 사용자 설정 저장 경로를 작성했다. 기존 ID/종류와 revision을 유지한다. 설정 UI/OS 이벤트 미연결. IMPL-340~371 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-370: 위젯 추가/삭제 이벤트의 설정 저장 및 context 무효화 경로를 작성했다. 중복 등록은 기존 선택을 유지한다. 실제 OS 이벤트 미연결. IMPL-340~370 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-369: presentation에 요청 크기를 보존하고 작은 카드의 보조 지표/시각/범례 표시를 압축했다. 실제 높이/레이아웃 미검증. IMPL-340~369 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-368: 위젯 label 30개를 기존 언어 catalog에 연결하고 한국어/영어 및 RTL 카드 입력을 작성했다. 다른 언어의 새 문구는 영어 fallback. IMPL-340~368 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-367: 번다운 PNG 및 단일/통합 카드 표시를 연결했다. 평균 소진/이상선/추정선과 주간 상한 차트 숨김을 작성했다. OS 레이아웃/렌더링 미검증. IMPL-340~367 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-366: 원본 BurnGeom의 평균 소진 기하/페이스/리셋/소진 예상 계산을 Windows로 옮기고 세션·주간 입력에 연결했다. 차트/카드 연결은 남아 있다. IMPL-340~366 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-365: History 카드에 일별 막대 PNG와 날짜 범위/최댓값/누락·알 수 없음 표시를 연결했다. 기존 PNG encoder 재사용, 밝은/어두운 theme 입력 지원. 실제 host 미검증. IMPL-340~365 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-364: 게시 성공 카드 보관 및 액션 수명 관리를 갱신 조정기에 연결했다. context 폐기/종료 시 액션 취소·drain을 작성했다. OS 호출 미연결. IMPL-340~364 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-363: 갱신 delivery에서 카드 payload/토큰/설정 revision 묶음을 생성하고 callback 입력에 연결했다. 실제 OS 게시 및 보관 lifecycle 미연결. IMPL-340~363 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-362: Switcher 카드 선택 UI와 Action.Execute 저장 라우팅을 작성했다. 카드 토큰/위젯 ID/표시 선택지/설정 revision을 확인한다. 실제 host callback 미연결. IMPL-340~362 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-361: Usage/Metric 위젯의 Adaptive Card template/data 생성기를 작성했다. switcher/history/burn-down 템플릿과 실제 host 연결은 남아 있다. IMPL-340~361 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-360: 직렬화 snapshot 수신을 갱신 조정기에 연결했다. decode/context 확인 후 기존 취소/세대 관리 경로로 전달한다. 실제 transport 미연결. IMPL-340~360 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-359: 버전/context ID/2 MiB 제한이 있는 위젯 snapshot JSON codec을 작성했다. 실제 IPC/host 미연결. IMPL-340~359 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-358: Codex 위젯 크레딧/코드 리뷰 입력에 계정 revision 및 dashboard attachment 구분을 반영했다. 실제 adapter 미연결. IMPL-340~358 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-357: 동일 계정 비용 입력의 일별 이력을 위젯 snapshot에 연결하고 날짜/중복/수치/기간 제한을 History와 공유했다. runtime 미연결. IMPL-340~357 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-356: 계정 revision이 일치하는 token 비용 요약을 위젯 snapshot에 연결했다. IMPL-340~356 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-355: 선택적 정보가 켜진 Devin의 추가 사용 잔액을 위젯 snapshot에 연결했다. IMPL-340~355 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-354: Codex 세션/주간/월간 시간 창 의미 분류를 위젯 snapshot에 연결했다. IMPL-340~354 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-353: Antigravity summary/legacy extra 행을 위젯 snapshot에 연결했다. runtime 미연결. IMPL-340~353 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-352: 위젯 snapshot 생성에 Claude 공통 표시 정책의 추가 사용 한도 행을 연결했다. runtime 미연결. IMPL-340~352 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-351: 계정 revision 일치 결과의 quota-only 위젯 snapshot 생성기를 작성했다. runtime 호출 미연결. IMPL-340~351 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-350: 위젯 context 무효화와 이전 context snapshot 요청 거부를 추가했다. host 이벤트 미연결. IMPL-340~350 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-349: 위젯 갱신 요청 세대/취소/drain coordinator를 작성했다. OS 게시 미연결. IMPL-340~349 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-348: 위젯 코드 리뷰/토큰 비용 보조 정보와 compact fallback 조건을 연결했다. IMPL-340~348 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-347: 동일 설정/데이터로 다중 위젯을 계산하는 batch 경로와 개별 오류를 추가했다. IMPL-340~347 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-346: 위젯 설정 저장/표시 모델/공용 provider 변경 서비스 계층을 연결했다. 실제 OS host 미연결. IMPL-340~346 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-345: 위젯 6종의 표시 모델 단일 진입점을 연결했다. 실제 호스트 미연결. IMPL-340~345 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-344: Usage 위젯 크기별 행 제한과 Antigravity 모델군별 우선 선택을 연결했다. IMPL-340~344 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-343: Usage 위젯의 Codex legacy 시간 창 복원 및 주간 상한을 연결했다. IMPL-340~343 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-342: Usage 위젯의 사용/잔여 비율 및 리셋 표시 행을 작성했다. IMPL-340~342 게시 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-341: History 차트에 날짜 offset/누락 일수 정보를 추가했다. IMPL-340과 함께 커밋 재시도 확인 대기. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-340: History 위젯의 날짜/비용/토큰 차트 투영을 작성했다. 화면 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-339: Burn Down 세션/주간 선택, 주간 소진 상한과 갱신 희망 시점을 작성했다. 호스트/차트 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-338: Metric 3종의 숫자/통화/토큰/추정치 표시 모델을 작성했다. 화면 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-337: 위젯 인스턴스와 snapshot의 제공자 선택/empty/disabled/stale 표시 상태 계산을 작성했다. 호스트 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-336: 위젯 설정 bounded read/원자 저장과 프로세스 간 writer lock을 작성했다. 호스트 호출 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-335: W10 위젯 6종의 선택 범위와 독립 인스턴스/공용 선택 설정 모델을 작성했다. 호스트/저장/화면 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-334: 열린 훅 화면의 언어 snapshot을 유지하고 메시지창 RTL 방향을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-333: 현재 catalog의 아랍어/페르시아어에 훅 form 좌우 배치와 메뉴 RTL을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-332: 훅 버튼/체크박스의 여러 줄 문구 높이와 후속 행 배치를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-331: 훅 폼의 설명문 높이를 현재 글꼴로 계산해 후속 필드와 스크롤 범위를 확장한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-330: 훅 폼·메뉴의 Windows 전용 안내/오류 문구에 한국어와 영어 fallback을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-329: 훅 인자 dropdown 취소 후 실제 선택과 값 편집 대상을 동기화한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-328: 훅 인자 오류 시 첫 실패 인자를 선택하고 순번만 안내하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-327: 훅 인자 JSON 입력을 개별 인자 선택·추가·삭제·값 편집으로 교체했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-326: 원본 훅 필드 번역과 제공자 표시 이름을 Windows 편집에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-325: 훅 실행 파일 Browse 선택과 경로 입력 연결을 추가했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-324: 훅 제공자 입력을 지원 ID 선택 목록으로 바꾸고 드롭다운 Enter/Escape 처리를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-323: 훅 form 최소화 중 배치를 보류하고 복원 시 현재 작업 영역에 맞추도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-322: 훅 form DPI/화면 구성 변경 시 대상 모니터 작업 영역에 창을 제한하고 초점 노출을 갱신한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-321: 훅 form 초점 변경과 입력 오류 시 해당 control을 스크롤 영역 안으로 노출하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-320: 훅 form 초기 창을 작업 영역에 제한하고 가로/세로 스크롤을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-319: 훅 form의 초기/변경 DPI 크기·배치와 시스템 글꼴 수명을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-318: 훅 편집 공통 문구 번역과 필드별 입력 오류/초점 이동을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-317: modal 메시지 루프의 editor drain 재진입을 보류하고 잘못 삽입된 import 함수 선언을 정리했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-316: 훅 편집 snapshot을 privacy 값에 연결하고 load/edit/save의 경계마다 변경을 확인하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-315: 트레이 훅 설정의 async load/edit/save를 host/main/runtime에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-314: 훅 규칙 목록/추가/편집/토글/삭제/정렬 메뉴를 작성했다. host 비동기 저장 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-313: 훅 form의 소유 창/개인정보/context 변경 취소와 이벤트 combo Enter 처리를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-312: Win32 훅 규칙 입력 창을 작성했다. 실제 목록/host/save 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-311: 훅 규칙 form draft, 개별 인수 편집, 사용 비율/시간 입력 변환을 작성했다. dialog 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-310: 훅 설정 runtime load/save, 저장 직전 변경 확인, 큐 재구성을 연결했다. Win32 편집 화면은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-309: Windows 훅 규칙 편집의 snapshot/변경 충돌/추가·수정·삭제·정렬 모델을 작성했다. 저장/UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-308: 사용량 표시/개인정보/추가 사용량과 알림·기록 토글에 원본 번역을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-307: 메뉴 표시 직전에 지연 타이머를 시작하고 빠른 재열기의 이전 타이머 메시지를 기한으로 걸러내도록 수정했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-306: 메뉴 열기 후 지연 갱신 옵션을 원본 기본값/설정 키로 Windows에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-305: 새로고침/종료와 갱신 주기 선택에 원본 번역을 연결했다. 전체 UI 번역은 진행 중이다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-304: 상태 메뉴 언어 선택과 시스템 언어 옵션을 Win32 메뉴에 연결했다. 전체 UI 번역은 아직 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-303: 계정 소유권 변경 시 공개 상태 훅과 rate limit 기록은 유지하고 계정 관련 훅만 무효화하도록 분리했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-302: 계정 해석 전 상태 전용 훅 관측을 제출하고 사용량 기준과 분리했다. 명령은 기존 직렬 큐를 공유한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-301: 공개 상태 조회를 계정 해석보다 먼저 수행하고 사용량 실패 시 상태 메뉴를 유지하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-300: 원본 번역에서 상태 문구를 가져와 Windows 요약/상세/설정 메뉴에 연결했다. 전체 UI 번역은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-299: 상세 조회 지연/실패 시 기한 전에 수신한 요약 상태를 갱신 내 보존하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-298: 상세 컴포넌트를 Win32 그룹 하위 메뉴에 연결하고 상태 페이지 열기를 유지했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-297: 상세 snapshot을 collect/runtime/메뉴 모델에 전달하고 descriptor 필터를 적용했다. 하위 메뉴 렌더링은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-296: incident.io 그룹/하위 항목 보존과 classic 상세 조회를 snapshot에 연결했다. runtime/메뉴 상세 전달은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-295: Windows 상태 컴포넌트 모델, classic 파서와 이름 allowlist 필터를 작성했다. 상세 조회/메뉴 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-294: 상태 갱신 예약을 선택적 사용량 설정과 분리하고 종료 시 상태 요청 취소/drain을 명시했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-293: Windows 트레이 상태 확인 토글, 표시 초기화, 진행 중 조회 취소 및 재활성화 갱신을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-292: 상태 조회를 훅 설정과 분리하고 트레이 공급자 상태 메뉴의 표시 모델에 연결했다. 화면/훅은 같은 결과를 사용한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-291: 같은 status source의 요청/결과를 갱신 내 공유하고 제출 기한의 진행 중 요청 취소를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-290: Workspace 제품 상태 피드를 Windows hook 조회에 연결했다. Gemini/Antigravity metadata의 제품 ID를 사용한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-289: Windows 상태 조회에 incident.io summary 및 classic fallback을 추가했다. unknown은 복구로 처리하지 않는다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-288: classic 상태 조회를 Windows hook 관측에 합치고 상태 설정/제한 동시성/unknown 보존을 연결했다. 다른 피드는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-287: Windows classic Statuspage 조회/indicator 변환 모듈을 작성했다. runtime 및 다른 피드 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-286: Windows hook 실행 중 설정 조건을 주기적으로 확인하고 취소/drain에 연결했다. 실제 종료 지연은 미검증이다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-285: Windows refresh hook batch 제출/규칙별 설정 재확인/종료 drain/누락 안내를 연결했다. 나머지 공급자·계정 및 설정 UI는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-284: 실제 first-party refresh에서 소유권이 정해진 hook 관측을 수집하고 변경 없는 설정의 pending batch로 보관한다. 제출은 미연결이다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-283: Windows 계정별 hook 성공/실패 결과의 batch 구성과 실패 이벤트 제출 경로를 작성했다. runtime 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-282: 부분 응답의 hook 추가 구간 기준값 보존 계약과 Windows mapper를 작성했다. runtime 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-281: Windows 사용량 lane과 고정 실패 유형을 hook 관측으로 변환하는 mapper를 작성했다. runtime batch 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-280: Windows hook 전환 관측과 설정/소유권 기준 상태 초기화를 연결했다. runtime row mapping은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-279: Windows hook 직렬 대기열과 설정 변경/종료 취소 소유권을 작성했다. runtime producer 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-278: W13 Windows hook 실행기의 취소 전파와 stdin 핸들 해제를 보완했다. runtime 이벤트 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-277: 프로필 루트/LevelDB inventory에 Windows 항목별 디렉터리 열거와 크기·취소·시간 제한을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-276: Chromium 프로필을 Default/번호순으로 정렬하고 localStorage 탐색의 프로필 내부 전체 목록 읽기를 제거했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-275: Vivaldi 기본 프로필 경로와 Windsurf 선택을 연결하고 통합 사용 안내를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-274: Brave Stable/Beta/Nightly의 Windows 기본 프로필 경로와 Windsurf 선택 항목을 추가했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-273: Windsurf 가져오기에 이번 요청만 사용하는 선택적 프로필 경로 입력 창을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-272: Windsurf 개별 브라우저 프로필 경로 환경 변수와 실패 시 기본 탐색 금지를 추가했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-271: Windsurf 가져오기에 지원 Chromium 브라우저 선택을 연결했다. Chrome 기본값과 단일 브라우저 접근 범위를 유지한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-270: Windsurf 가져오기 실패 원인을 사용 중/미지원 형식/읽기 실패/세션 오류/API 응답 실패로 구분했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-269: Windsurf Chrome 가져오기를 트레이 메뉴/후보 선택/이름 입력/저장 콜백에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-268: Windsurf runtime에 탐색/probe, 만료 ticket과 보호 계정 저장 경로를 연결했다. 트레이 UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-267: Windows Windsurf Chrome 탐색과 후보 API probe를 작성했다. 서버 신원 확인과 구분하며 runtime/UI 저장 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-266: Windows Windsurf localStorage 세션 후보 backend를 추가했다. profile/origin 분리와 기존 bundle 구조 검사를 연결했으며 API/UI 통합은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-265: Chromium schema 1의 정확한 origin 경계와 Latin-1/UTF-16 문자열 decoder를 작성했다. Windsurf 후보 및 UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-264: 잠금 안에서 CURRENT/manifest/table/WAL을 읽고 최신 mutation 상태를 복원하도록 연결했다. Chromium 문자열/세션 변환은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-263: LevelDB 파일을 한 Windows 핸들로 크기 제한/EOF/변경 검사를 포함해 읽는 모듈을 작성했다. DB 통합은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-262: 기존 LevelDB LOCK 파일의 Windows 잠금 획득/해제 코드를 작성했다. 실제 snapshot 읽기 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-261: LevelDB CURRENT 및 번호별 파일 inventory 해석을 작성했다. 실제 파일 확보는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-260: SSTable index/data 순회, 내부 키 정렬, index 및 manifest 경계 검사를 연결했다. 파일 snapshot 통합은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-259: SSTable 블록의 prefix/restart 기반 키·값 복원 파서를 작성했다. index 순회와 정렬 검사는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-258: SSTable footer/handle/CRC와 비압축·Snappy 블록 읽기를 연결했다. entry/index 해석은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-257: LevelDB table용 raw Snappy 블록 해제 파서를 작성했다. SSTable 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-256: manifest 로그/VersionEdit를 연결해 유효한 table 및 log 메타데이터를 복원하도록 작성했다. 파일 확보와 table 읽기는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-255: LevelDB manifest VersionEdit 파서를 작성했다. live table 목록 replay와 table 읽기는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-254: LevelDB 내부 키와 최신 version 선택을 구현하고 삭제 표시를 유지했다. 완전한 manifest/table/log 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-253: LevelDB WriteBatch의 sequence 및 put/delete 메모리 파서를 작성했다. 최신 상태 통합은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-252: Windows LevelDB 물리 로그의 block/fragment/CRC32C 파서를 작성했다. 실제 저장소 연결 미완료. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-251: Windows Chromium localStorage 프로필 디렉터리 탐색 모듈을 작성했다. LevelDB 읽기/세션 복원 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-250: Windsurf 선택 계정이 있을 때 로컬 캐시 fallback을 차단하고 Windows 통신 오류/timeout/취소 처리를 보완했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-249: Zed Windows 인증 오류를 플랫폼에 맞게 분리하고 가져오기 UI의 고정 오류 안내를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-248: Zed 자동 조회의 설정 오류 안내를 구분하고 선택적 null 설정을 처리했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-247: Zed 수동/선택 계정이 없을 때 편집기 자동 API 조회를 연결했다. 선택 계정 오류는 자동 계정으로 대체하지 않는다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-246: Zed API/credential 두 주소 확인 UI와 runtime 전달을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-245: Zed settings loader에 server/credential origin을 보존하는 Configuration 모델을 추가했다. 단일 origin 호출은 분리된 주소를 버리지 않고 오류 처리한다. UI 전환은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-244: Zed 가져오기 backend/runtime에서 credential origin과 API server를 구분했다. 기존 신뢰 규칙을 vault 조회 전에 적용한다. 설정/UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-243: CODEXBAR_ZED_DATA_DIR의 config/settings.json을 서버 추천 입력에 연결하고 가져오기 안내를 작성했다. 잘못된 명시 경로는 기본 프로필로 대체하지 않는다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-242: Zed 설정의 중복 root key를 거부하도록 공통 Windows JSON key scanner를 연결했다. Windsurf는 기존 64KiB 제한을 유지한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-241: Zed 서버 설정을 UI 밖에서 읽고 입력 창 기본값으로 연결했다. 읽기 실패는 빈 입력과 안내를 표시하고 명시적 확인 뒤 credential 조회를 시작한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-240: Windows Zed settings.json에서 서버를 읽는 1MiB 제한 loader와 주석/후행 쉼표 처리를 작성했다. UI 기본값 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-239: Zed 편집기 가져오기에 HTTPS 서버 주소 선택 창을 추가하고 선택 origin을 조회·확인에 전달했다. 자동 설정 탐색은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-238: 트레이 Zed 편집기 가져오기/취소와 계정 확인·이름 입력·보호 저장 콜백을 연결했다. 기본 production 서버 대상이며 custom server 탐색은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-237: Zed 편집기 가져오기 런타임에 설정 revision/선택 계정/개인정보 모드 검사, 5분 ticket, 취소와 보호 계정 저장을 연결했다. 네이티브 UI 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-236: Zed 편집기 자격증명을 한 번 읽어 같은 계정으로 API 확인하는 명시적 가져오기 백엔드를 작성했다. 런타임/저장/UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-235: Zed 원본 Windows Credential Manager 형식 reader를 작성했다. 기본 조회/UI 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-234: Cursor Windows 비용 이벤트 기본 전송을 격리하고 페이지 decode 상한/취소/고정 오류를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-233: Cursor 사용량/후보 확인과 Windsurf 수동 세션 HTTP의 Windows 기본 전송을 격리 경로에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-232: Zed/Augment Windows 수동 계정 HTTP의 ambient 쿠키·캐시·URL 자격증명을 분리했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-231: Zed Windows 자격증명에 선택적 HTTPS 서버 origin을 묶고 사용자 서버 조회를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-230: Zed Windows 상세에 예측 횟수/한도/청구 상태를 전달하고 청구 경과율을 수집 시각에 고정한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-229: Zed 수동 계정의 저장 전 형식 검사와 입력 유지 안내를 연결하고 조회 파서를 공유한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-228: Zed Windows 수동 저장 계정(user ID/token)과 원본 API 조회·응답 계정 일치를 연결했다. 편집기 자동 인증은 미구현. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-227: Augment 상세에 잔여/사용/한도 크레딧과 결제 주기·구독 정보 미확인 상태를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-226: Augment Windows 조건부 경계를 수정하고 미확인 비율의 0% 표시를 제거하며 구독 조회 실패 안내를 연결했다. 이전 이식은 조건부 경계 누락을 포함한 미검증 상태였다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-225: Augment Firefox 가져오기 트레이 시작/취소/후보 선택/이름 입력/저장 결과 UI를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-224: Augment 가져오기 runtime의 후보 확인/5분 만료/설정 변경 감지/보호 계정 저장을 연결했다. UI 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-223: Augment Firefox 프로필/partition별 후보 발견·API 확인 backend를 작성했다. UI/저장 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-222: Auggie 명시 경로의 다른 PATH 설치 fallback을 차단하고 Windows CLI 실패를 보존한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-221: Auggie account status 원본 파서를 Windows 명령 해석/제한 실행에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-220: Augment 원본 수동 쿠키 크레딧/구독 조회를 Windows에 포함하고 선택 계정의 웹 조회를 연결했다. 자동 브라우저/CLI는 미완료. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-219: 비용 프로젝트/세션 선택 목록에 표시 제목 필터와 결과 수·선택 유지·요약 복귀를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-218: 프로젝트 상세에 해당 프로젝트/기간의 모델별 비용·토큰 유형을 기존 completeness 정책으로 집계·표시한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-217: 프로젝트별 일별 비용/토큰을 보존·표시하고 합계 미확인 활동 프로젝트도 목록에 유지한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-216: 비용 상세의 프로젝트/세션 선택 목록과 개별 표시·검색·요약 복귀를 연결하고 세션 확장 버튼 노출 조건을 보완했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-215: 비용 전체 행 보기에 세션 요청 수·토큰 유형·전체 모델별 비용/토큰 상세를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-214: 비용 세션의 모델 단계 12개 제한을 제거하고 요약/모든 행 보기에서 최근 12개/전체 전환을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-213: Windsurf 수동 세션 JSON의 localStorage JSON 문자열 값을 한 겹 해석하도록 작성했다. 자동 브라우저 가져오기는 미구현. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-212: Windows Windsurf JSON 세션의 중복 root 키를 이스케이프 해석 후 검사하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-211: Windows Windsurf 세션 별칭 값 충돌 및 잘못된 JSON의 key/value 재해석을 거부하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-210: Windsurf 로컬 읽기를 Windows utility task로 분리하고 SQLite/JSON 취소 전달을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-209: Windsurf 계정 추가/교체 대화상자에 비밀값 없는 형식 오류 안내와 입력 유지 처리를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-208: Windows Windsurf 계정 추가/credential 교체 전에 수동 세션 구조를 확인하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-207: Windows Windsurf 캐시 최신성 미확인 표시와 만료 결제/리셋 구간 제외를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-206: Windsurf 저장 계정의 Windows settings 투영과 자동 로컬 조회 전략 선택을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-205: Windows Windsurf 저장 계정 adapter 및 CLI browser 지원 예외, 수동 세션 설정 표시를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-204: Windsurf 로컬 SQLite cachedPlanInfo 조회를 Windows Roaming AppData 경로에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-203: Windsurf 원본 수동 Devin 세션/GetPlanStatus/protobuf 사용량 경로를 Windows에 포함했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-202: Cursor 후보 선택에 Firefox 프로필/컨테이너 출처를 추가하고 privacy 모드에서는 세션 번호만 표시한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-201: Firefox cookie 조회의 행 수/누적 텍스트/개별 열 크기 상한을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-200: 브라우저 취소/timeout 오류 전달을 보존하고 Cursor 동일 이름 충돌/잘못된 쿠키 바이트를 거부하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-199: Cursor 탐색 deadline을 Firefox SQLite progress handler 및 row 읽기에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-198: Firefox originAttributes를 보존하고 Cursor 컨테이너/partition별 후보를 분리하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-197: Cursor 후보 ticket 5분 만료 시 메모리 참조 정리 및 열린 선택/이름 입력 UI 만료 처리를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-196: 같은 검증 ID와 세션을 재가져오면 기존 계정을 선택하도록 연결하고 이름 보존을 안내한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-195: Cursor 비용 계정 ID 확인 실패를 구분하고 요약/JSON 내보내기 안내에 재가져오기 사유를 표시하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-194: CLI cost/dashboard/serve에서 같은 선택 계정의 쿠키와 ID를 함께 해석해 Core 비용 조회에 전달하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-193: Cursor 비용 계정 확인을 Core remote snapshot 생성 이전으로 이동하고 Windows loader 중복 요청을 제거했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-192: Windows 비용 소스에 Cursor 계정 ID를 전달하고 수집 전후 확인 후 대시보드 입력으로 넘기도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-191: CLI usage/diagnose/guard/hooks watch에 선택 계정 외부 ID 전달을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-190: Windows Cursor quota 응답을 저장된 외부 계정 ID와 비교하고 미확인/불일치 응답 게시를 차단하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-189: Cursor 가져오기에서 확인한 계정 ID 저장과 credential 변경 시 ID 철회를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-188: Cursor 후보 메뉴와 가져오기 이름 입력 대화상자의 privacy 변경 감지/닫기/저장 차단을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-187: Cursor 후보 HTTP 검증에 전체 가져오기 deadline을 연결하고 초과 시 이전 확인 후보를 유지하도록 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-186: Cursor 가져오기 취소 메뉴 및 UI task/HTTP 후보 검증 취소를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-185: Cursor Firefox 탐색을 runtime actor 밖으로 분리하고 취소/종료 연결, 동일 세션 후보 중복 제거를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-184: 트레이의 Firefox Cursor 가져오기 시작/후보 선택/이름 입력/보호 저장 결과를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-183: Cursor 후보 검증 runtime과 5분 선택 ticket, 기존 보호 계정 추가 API를 연결했다. UI 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-182: Firefox 프로필별 Cursor 세션 후보 수집 및 API 계정 ID 확인 backend를 작성했다. UI/저장 미연결. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-181: Cursor 로그아웃 시 암호화된 빈 세션으로 먼저 교체해 삭제 실패 후 재실행 복원을 막는 경로를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-180: Cursor Windows 세션 저장 실패 시 이전 메모리 상태 복원, clear 실패 반환 및 인코딩 누락 처리를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-179: Windows Cursor 세션 파일의 DPAPI 보호 저장/제한 읽기와 persistenceFailure 상태를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-178: Cursor Windows 비용/snapshot capability 및 수동 cookie CLI 예외를 활성화하고 Windows 설정 안내를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-177: Cursor 원본 status/quota 모델 및 수동 cookie HTTP 경로를 Windows에 포함했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-176: 명시적 Cursor cookie 수집의 이전 결과 유지와 계정 미확인 ambient CSV fallback 차단을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-175: Windows Cursor 원격 비용 조회 범위/일별 집계/오늘 snapshot에 같은 bucket calendar를 전달한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-174: macOS에만 포함되던 Cursor usage-events 수집기를 Windows에 포함하고 명시적 cookie 비용 수집을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-173: 비-Codex 비용 캐시 경로에 선택 계정/설정/환경/쿠키/시간대 소유권 지문을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-172: 비용/토큰 부분 합계 표식과 알려진 구독 수, 모델 순위·빈 이력 표시를 원본에 맞춰 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-171: 유지된 이전 비용 결과의 일별/시간별/heatmap 조회와 stale 안내, 설정 변경 시 retained state 철회를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-170: 동일 설정/소스/지문을 가진 Codex 전용 비용 refresh에서 이전 summary/JSON을 stale로 유지하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-169: 비용 기간/숨긴 소스/중복 Codex 숨김 설정 키를 원본 이름에 맞추고 기존 Windows 키 fallback·동시 저장을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-168: 부분 수집 비용 JSON 복사/저장을 허용하고 실패·stale 상태를 JSON 밖의 안내로 전달한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-167: 원본 Spend JSON DTO 및 Copy cost JSON/Export cost JSON 트레이 동작을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-166: Windows 비용 모델에서 호출하지만 빠져 있던 ModelBreakdown 확장을 원본에서 이식했다. 이전 비용 UI/모델 구현은 이 누락을 포함한 미검증 상태였다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-165: 공유 미리보기의 중첩 저장/오류 대화상자 반환 뒤 owner 창을 닫도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-164: PNG 저장 대화상자 전후 및 클립보드 교체 직전에 캡처 유효성을 확인하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-163: 열린 상세/비용 차트/공유 미리보기에 계정·비용 설정 무효화 상태를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-162: 비용/읽기 전용 상세 창에 검색 입력·다음 찾기·Ctrl+F/F3와 순환 검색을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-161: 비용 요약에서 모델/프로젝트 전체 행 펼치기·접기를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-160: 비용 요약/차트 상세에 원본의 비용 산정 방식·계량 금액·coverage·토큰 유형을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-159: Windows Codex 지문 조회를 bounded throwing read로 연결해 파일 부재와 읽기 실패를 구분했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-158: visible Codex 계정/프로필별 비용 소스·홈/지문/시간대 캐시 분리·수집 전후 소유권 검사를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-157: OpenCodeX 로그 opt-in/공급자 fan-out 병합/독립 캐시/관찰 상태 및 중복 Codex 숨김 메뉴를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-156: OpenCodeX 증분 로그 parser/store의 Windows 파일 식별자/크기 조회를 작성했다. 실제 비용 소스 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-155: 선택 날짜의 시간별 비용 상세와 generation 검사·UTC offset 표시·시간 탐색을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-154: 비용 요약에 프로젝트/최근 세션 내역과 캡처된 개인정보 표시 상태 확인을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-153: 원본 tokenActivity를 주/요일 히트맵과 상태별 범례·날짜 상세로 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-152: 비용 차트 날짜 탐색 버튼/키보드·전체 기간 복귀·색상 범례와 텍스트 대응을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-151: native 비용 날짜별 누적 막대/통화 전환/날짜 내역/갱신 연결을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-150: native Share Stats 미리보기·비율 유지 이미지·읽기 전용 통계·저장/복사 버튼을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-149: Share Stats 이미지 복사 메뉴와 PNG/CF_DIB 이중 클립보드 전달을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-148: GDI 1200×630 공유 카드/PNG encoder/Windows PNG 저장 메뉴를 작성했다. 이미지 실행·검증 미실시. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-147: 비용 집계 소스 전체/개별 포함 선택 메뉴와 generation 확인 저장·재집계를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-146: 기간/통화/source 표시 옵션 변경 시 보관된 비용 scan을 재집계하도록 runtime에 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-145: 비용 표시 통화 메뉴와 원본 환율 갱신 호출을 연결했다. 캐시/근사 환율 사용 가능성을 요약에 표시한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-144: Copy Share Stats 메뉴와 원본 텍스트 포맷/클립보드 전달을 연결했다. ready 상태/설정 일치 조건을 적용한다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-143: 트레이 비용 요약 요청과 읽기 전용 통화/공급자/모델 요약 창을 연결했다. 전체 대시보드 대체가 아니다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-142: 트레이 비용 수집/로컬 Codex ledger/표시 기간 메뉴와 설정 변경 재수집을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-141: runtime refresh에 opt-in 비용 수집·snapshot 보관·계정 변경 무효화·shutdown 취소를 연결했다. UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-140: 비용 수집 loader/옵션 동시 교체·이전 데이터 무효화·시간대 단독 변경 거절을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-139: 비용 bucket timezone 설정과 loader/calendar 집계 전달을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-138: Windows 비용 수집 opt-in·Codex ledger 예외·capability gating 및 대시보드 옵션 설정을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-137: config/선택 계정/Codex source를 native spend loader 입력으로 변환하는 resolver를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-136: 비용 수집의 source별 실패와 성공 model을 함께 게시하는 partial 상태를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-135: Core 비용 snapshot/activity를 Windows spend 입력으로 바꾸는 loader adapter를 작성했다. 설정/Main 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-134: spend scan lifecycle·옵션 재집계·stale/share 제한 controller를 작성했다. 실제 loader/UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-133: 원본 SpendDashboardModel 및 ShareStats payload/builder/formatting을 Windows 모델로 이식했다. 수집·UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-132: Windows config 32 MiB bounded read·암호화 출력 크기 guard·복호화 필드 오류 비노출을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-131: shared OAuth cache·removal journal을 청크 단위 한도 읽기로 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-130: Windows Antigravity cache의 파일 부재와 접근 오류 구분을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-129: Antigravity shared OAuth cache의 Windows DPAPI·private ACL 저장을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-128: provider 상세 snapshot의 privacy 변경 시 숨김·닫기 및 command 재확인을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-127: 열린 metadata editor의 privacy 설정 변경 감지·취소 및 저장 직전 재확인을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-126: 기존 z.ai 계정 scope 편집에 Personal/Team 라디오 및 조건부 필드 활성화를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-125: recovery journal·암호화 config를 기존 사용자 전용 DACL writer로 저장하도록 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-124: 삭제 전 DPAPI recovery journal 저장과 재시작 복구·읽기 실패 수집 보류를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-123: 실행 중 cache cleanup 재시도와 실패 시 Antigravity fetch 중단을 작성했다. 재시작 지속성은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-122: Antigravity 계정 삭제 후 일치 shared cache 정리와 부분 실패 안내를 작성했다. 실제 삭제는 실행하지 않았다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-121: 삭제 확인에 ticket 시점의 계정 이름·위치 및 privacy 재확인을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-120: 저장 계정 삭제 메뉴·기본 No 확인 창·runtime 삭제·refresh 연결을 작성했다. 실제 삭제는 실행하지 않았다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-119: 저장 계정 삭제 ticket/선택 보존/보호 저장 backend를 작성했다. 삭제 실행 및 UI 연결은 하지 않았다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-118: account metadata 메뉴·조회·native editor·저장·refresh를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-117: 공급자별 scope/org/workspace native editor를 작성했다. 메뉴/Main 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-116: metadata 편집값과 revision ticket을 단일 config read로 캡처하는 조회 API를 작성했다. UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-115: 계정 scope/org/workspace 변경·삭제·유지 patch backend를 기존 revision ticket/보호 저장에 연결했다. UI는 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-114: credential 교체 화면에 원본 공급자별 title/subtitle/placeholder 안내를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-113: 저장 계정 credential 교체 메뉴와 begin/input/save/cancel/Main refresh 연결을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-112: 기존 native 입력 대화상자에 masked credential 교체 모드를 작성했다. host/Main 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-111: 기존 계정 credential 교체 backend와 만료·stale 편집 티켓을 작성했다. UI 연결은 남아 있다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-110: Codex reconciliation의 선택 source·runtime identity 변경 시 상태 철회를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-109: refresh 시 외부 config 계정 변경 비교·상태 철회를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-108: 계정 변경 후 해당 공급자의 대기 중 알림 철회를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-107: 선택 계정 변경 시 session baseline·Codex history cache 철회를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-106: z.ai personal/team 라디오와 조건부 team 입력을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-105: 공급자 metadata 입력 규칙과 z.ai team 필수 필드 안내를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-104: 계정 추가 입력 조건 공유·필드별 안내를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-103: 수동 계정 추가 입력 UI와 보호 저장·refresh를 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-102: 보호 설정 형식/복원/저장 실패 안내를 분리했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-101: 공급자 apiKey/secretKey/cookieHeader/pluginSecrets 보호 bundle과 config v2를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-100: config token 보호 읽기·쓰기와 다음 저장 시 legacy 변환을 작성했다. 실제 이전 미실행, CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-099: 사용자 범위 DPAPI token codec을 작성했다. 저장소 미연결, CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-098: 새 토큰 계정 추가 backend를 작성했다. UI/보호 저장 이전 미연결, CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-097: 계정 이름 창 DPI 배치·system font·초기 작업 영역 배치를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-096: Saved accounts 이름 입력 UI와 비동기 저장을 연결했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-095: credential을 보존하는 계정 이름 수정 backend를 작성했다. UI 미연결, CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-094: 계정 페이지 메뉴 강조와 keyboard return target 보존을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-093: 128개 단위 Saved accounts 페이지 이동을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-092: Saved accounts 트레이 선택과 저장 결과·refresh 연결을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-091: 토큰 계정 선택 projection과 UUID 기반 저장 backend를 작성했다. UI 미연결, CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-090: 상세 창 작업 영역 배치와 액션 버튼 줄바꿈을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-089: 상세 창 DPI 배치·시스템 글꼴 교체를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. 전체 DPI awareness·실제 모니터 검증은 남아 있다.

- IMPL-088: 상세 창에서 명시적으로 전체 새로고침을 요청하고 닫는 동작을 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-087: 공급자 링크 실패 사용자 안내와 URL 비출력 로그를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-086: 상세 창의 공급자별 dashboard/status/release notes 버튼과 최소 창 크기를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION.

- IMPL-085: 공급자 상세 창에 크기 조절·스크롤·텍스트 선택·Ctrl+A를 작성했다. CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION. rich card·계정 선택·Windows 검증은 남아 있다.

IMPL-084: Provider detail snapshot dialogs and context-correct clipboard messages written; full native cards and Windows validation remain pending.

IMPL-083: Provider-instance usage copy with current rendering settings written; native detail UI and Windows validation remain pending.

IMPL-082: Plugin-instance error copy and independent status visibility written; account-specific detail actions and Windows validation remain pending.

IMPL-081: Current-refresh provider error copy actions written; plugin/account-specific actions and Windows validation remain pending.

IMPL-080: Redacted tray summary clipboard action written; detail-card actions and Windows validation remain pending.

IMPL-079: Opt-in Apps registration restoration and structured recovery gates written; whole-operation concurrency and Windows validation remain pending.

IMPL-078: Recorded uninstall file/reference recovery orchestration written; registration integration and Windows validation remain pending.

IMPL-077: Child operation IDs persisted before uninstall execution with collision and result checks; lifecycle recovery and Windows validation remain pending.

IMPL-076: Uninstall phase records and recovery transaction IDs connected to failure dialogs; lifecycle orchestration and Windows validation remain pending.

IMPL-075: Environment notification after reference PATH writes and separate outcome recording written; lifecycle recovery handoff and Windows validation remain pending.

IMPL-074: Conflict-aware reference rollback and shortcut hash boundaries written; environment notification and Windows validation remain pending.

IMPL-073: Known user launch reference migration/detachment and uninstall integration written; transition recovery and Windows validation remain pending.

IMPL-072: Receipt-bound registration recovery and fill-only registry publication written; reference migration and Windows validation remain pending.

IMPL-071: Current-user development Apps registration and interactive uninstall invocation written; reference migration, recovery and Windows validation remain pending.

IMPL-070: Shipped lifecycle tools and shared first-party signing/install contract written; Apps registration and Windows validation remain pending.

IMPL-069: Staged payload publication and interrupted receipt/plan reconciliation written; registration, cleanup and Windows validation remain pending.

IMPL-068: Recorded incomplete-install resumption written; exact inventory/signer binding and existing-file comparison added. Registration and Windows validation remain pending.

IMPL-067: Removed payload restoration and journal replacement written; incomplete-install recovery, registration and all Windows validation remain pending.

IMPL-066: receipt 파일의 복구 가능한 버전 제거 경로·참조 차단·부분 상태 기록을 작성했다. 영구 정리/자동 복구/실행 검증은 남아 있다.

IMPL-065: candidate hash 기반 shortcut 복구와 displaced backup 보존을 연결했다. 제거/원자적 journal/실행 검증은 남아 있다.

IMPL-064: 시작 메뉴 버전 선택·이전 shortcut 보존·activation journal을 연결했다. 복구/제거/실행 검증은 남아 있다.

IMPL-063: 사용자별 version payload 설치·서명/hash 대조·완료 receipt 코드를 작성했다. 활성 전환/제거/실행 검증은 남아 있다.

IMPL-062: 서명된 최종 파일 handle 유지·서명/import/hash 결합을 연결했다. 설치 lifecycle과 실행 검증은 남아 있다.

IMPL-061: 명시적 인증서 Authenticode 서명·새 output·서명 후 해시 기록 코드를 작성했다. 실제 서명/Windows 검증은 미실시다.

IMPL-060: 선언된 빌드 출처와 first-party 서명 요청 인계를 연결했다. 실제 서명/attestation/실행 검증은 남아 있다.

IMPL-059: 복사 대상 handle 유지·machine/import 재분석·동일 stream 해시 기록을 연결했다. 실행/서명/OS 정책 검증은 남아 있다.

IMPL-058: 명시적 OS 의존성 정책과 미해결 import 조립 차단을 연결했다. OS 근거 목록/바이트 일치/실행 검증은 남아 있다.

IMPL-057: 명시적 runtime 폴더 재귀 DLL 탐색·후보 모호성·미해결 목록을 연결했다. OS 정책/배포 gate/실행 검증은 남아 있다.

IMPL-056: PE32+ import/delay-import 그래프를 배포 입력에 연결했다. 외부 DLL 해석과 전체 closure/실행 검증은 남아 있다.

IMPL-055: 지정 runtime/resource 목록 생성과 PE machine 경계 코드를 작성했다. 의존성 closure/실행/패키징 검증은 남아 있다.

IMPL-054: 명시적 목록 기반 Windows 배포 조립과 파일 인벤토리 코드를 작성했다. 실제 패키징/의존성 완전성/서명/실행은 미검증이다.

IMPL-053: PATH 결과 프로토콜과 쓰기 성공 후 환경 변경 통지를 연결했다. 실행/전체 broadcast 상한/배포 검증은 남아 있다.

IMPL-052: PATH helper 소유권·launch/stop 직렬화·bounded drain과 종료 미확인 재실행 차단을 연결했다. 실행 미검증이다.

IMPL-051: PATH 리소스·트레이 확인·background helper 결과를 연결했다. helper 종료 소유권과 배포/실행 검증은 남아 있다.

IMPL-050: 명시적 Windows 사용자 PATH 등록·제거 스크립트와 사용 문서를 작성했다. 실행/앱 연결/배포 검증은 남아 있다.

IMPL-049: CLI 진행 상태·모달 뒤 결과 재전달과 worker/창 종료 순서를 연결했다. 실행은 미검증이다.

IMPL-048: CLI worker 분리·협력 취소·privacy 변경 결과 폐기를 연결했다. 모달 뒤 재전달 보강과 실행 검증은 남아 있다.

IMPL-047: process PATH 제한 탐색·후보 수·중복 설치 안내를 연결했다. 실행 미검증이며 UI 비동기화와 자동 설치는 남아 있다.

IMPL-046: sibling CLI 후보 탐색과 개인정보 설정을 따르는 수동 설정 안내를 연결했다. PATH 탐색/자동 설치/실행 검증은 남아 있다.

IMPL-045: 자동 시작 상태별 상세·OS 설정 복구 안내와 registry 조회 실패 분류를 연결했다. 실행은 미검증이며 자동 복구/MSIX는 미완료다.

IMPL-044: Windows 시작 앱 설정 이동과 열기 실패 시 수동 경로 안내를 연결했다. 실제 OS 설정 이동은 미검증이며 MSIX/경로 충돌 복구는 남아 있다.

IMPL-043: package identity가 있거나 불명인 경우 Run registry 경로를 차단했다. StartupTask와 실행 검증은 남아 있다. 이전 IMPL-042: 사용자별 unpackaged Run 등록·해제와 registry 상태 메뉴를 연결했다. 실제 등록/로그온은 미검증이다. 이전 IMPL-041: WIN-052 시스템 session 종료 message와 bounded helper drain을 연결했다. 실제 로그오프/종료는 미검증이다. 이전 IMPL-040: active shortcut과 saved selection 표시·명시적 적용 경로를 분리했다. OS/외부설정 실행은 미검증이다. 이전 IMPL-039: invalid shortcut 저장값의 등록 차단·미설정 구분과 재선택 안내를 연결했다. 실제 복구는 미검증이다. 이전 IMPL-038: modifier/key 저장 모델·legacy 호환과72개 grouped shortcut 선택을 연결했다. 실제 등록/입력은 미검증이다. 이전 IMPL-037: keyboard 초기 submenu highlight와 정적 mnemonic을 연결했다. 접근성/입력은 미검증이다. 이전 IMPL-036: keyboard popup 취소 시 제한적 foreground 복원과 페이지 간 대상 보존을 연결했다. 입력/동작은 미검증이다. 이전 IMPL-035: hotkey popup의 foreground monitor 작업영역 anchor와 페이지 anchor 보존을 연결했다. 화면/키 입력은 미검증이다. 이전 IMPL-034: hotkey 단계별 오류와 inactive 등록 정리 재시도를 연결했다. OS 실패/실행은 미검증이다. 이전 IMPL-033: 단축키 preset 저장·선택과 staged 등록 교체를 연결했다. 임의 키 editor와 실패 정리/실행 검증은 남아 있다. 이전 IMPL-032: WIN-011 기본 off 전역 Ctrl+Alt+C 트레이 메뉴 단축키를 연결했다. 사용자 지정 키와 실행 검증은 남아 있다. 이전 IMPL-031: CLI --diagnostics-json aggregate envelope를 연결하고 기존 JSON 배열 경로를 유지했다. 실행은 미검증이다. 이전 IMPL-030: 반환 row 기반 provider 진단 모델과 runtime 상세 표시를 연결했다. 실행은 미검증이다. 이전 IMPL-029: 수동 title cache reset·세대별 재조회와 저장 entry 상태를 연결했다. 실행은 미검증이다. 이전 IMPL-028: 메모리 title cache와 file fingerprint/source 세대 무효화를 연결했다. 증분 parsing·성능/실행은 미검증이다. 이전 IMPL-027: Claude 파일별 deadline과 시간 초과/미시도 건수 안내를 연결했다. 실행은 미검증이다. 이전 IMPL-026: 기본 매칭 후 provider별 title 예산을 분리하고 Codex DB 후보 계산의 잘못된 위치를 수정했다. 실행은 미검증이다. 이전 IMPL-025: SQLite agent_path 역할·구형 schema fallback과 database role 출처를 연결했다. 실행은 미검증이다. 이전 IMPL-024: SQLite code별 실패 원인·복구 안내와 prepare 실패 cleanup을 연결했다. 실행은 미검증이다. 이전 IMPL-023: SQLite source GUI 선택·비활성화·환경 복귀와 runtime override를 연결했다. 실행은 미검증이다. 이전 IMPL-022: 명시적 SQLite title source의 읽기 전용 UUID fallback과 index 우선순위를 연결했다. 배포/소유권/실행은 미검증이다. 이전 IMPL-021: 원격 연속 페이지에 host 상태 문맥 행과 보이는 session 범위를 연결했다. 실행은 미검증이다. 이전 IMPL-020: 원격 host 상태 행에 snapshot 상세 보기와 별도 non-focus 명령 map을 연결했다. 실제 실행은 미검증이다. 이전 IMPL-019: 로컬 상태90자 요약과 popup snapshot 상세 보기를 연결했다. dialog 실행은 미검증이다. 이전 IMPL-018: 로컬 session 설정과 source 안내를 별도 하위 메뉴로 이동하고 privacy 지역 값 선언을 보완했다. 메뉴 동작은 미검증이다. 이전 IMPL-017: source 비활성화·누락·잘못된 경로의 안내를 기존 복구 명령에 연결했다. 파일 접근과 UI 동작은 미검증이다. 이전 IMPL-016: 세션별 metadata/title 출처를 optional JSON 필드와 로컬/원격 행에 연결했다. 호환성과 UI는 미검증이다. 이전 IMPL-015: 큰 제목 파일의 마지막1MiB 읽기와 잘린 첫 행 제외·UUID별 미해결 결과를 연결했다. 전체 검색/증분 cache는 남아 있다. 이전 IMPL-014: 제목 source의 접근·크기·형식·변경·예산·취소 진단을 연결했다. 큰 파일 지원은 아직 미구현이다. 이전 IMPL-013: 기본 off인 Claude custom-title metadata 읽기와 GUI/CLI 옵션을 연결했다. 관찰된 schema와 bounded 전체 읽기 범위이며 미검증이다. 이전 IMPL-012: GUI 제목 소스 폴더 선택·비활성화·환경 설정 복귀·개인정보 보호 표시와 runtime override를 연결했다. 이전 IMPL-011: 명시적 Codex title index의 UUID 제목을 CLI/환경 설정으로 연결했다. GUI 파일 선택과 SQLite/Claude 제목은 남아 있다. 이전 IMPL-010: Codex persisted role 이름과 단일 Windows handle의 bounded header reader를 연결했다. 사용자 지정 thread title source는 아직 미구현이다. 이전 IMPL-009:  기본 off인 신규 Codex/Claude 세션 metadata 추론 옵션을 작성했다. 알려진 cwd의 단일 프로세스와 생성 시각 이후 단일 파일 후보에 한정하며 추론임을 안내한다. 전체 CLI grammar·실제 profile 소유권·thread title 및 실행 검증은 남아 있다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-007: native64 process cwd 후보 reader와 기본 off 실험 옵션/CLI flag를 작성했다. 내부 RTL layout에 의존하므로 지원 확정·배포 가능 상태로 세지 않는다. identity/길이/값 변화 guard가 있어도 실제 Windows 검증은 미실시다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-006: local/remote 결과 페이지와 remote host 순환 cursor·last-success 상태를 작성했다. 표시상 first-N 절단을 줄였으며 원본 scanner/remote CLI 수집 한도는 유지한다. native cwd·전체 correlation·exact-tab은 미완료이며 모든 신규 코드는 미검증이다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-005: explicit Codex launch cwd 및 선택된 Pi/OMP session header를 부분 연결하고 project/title/combined label 설정을 추가했다. PID+생성 시각 ID를 유지한다. 실제 cwd/Claude·Codex correlation·전체 root/옵션·exact-tab은 미완료이며 전부 미검증이다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-004: remote host OS/CLI path editor와 opt-in discovery/60초 조회/트레이 목록·오류·typed focus 연결을 작성했다. 미검증이며 대형 목록 pagination·metadata·exact-tab·UI 품질 작업은 남았다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-003: structured Windows scan outcome과 opt-in 로컬 세션 actor/30초 주기/트레이 목록·focus 연결을 작성했다. 오류 시 이전 목록을 비활성화하며 late-result/종료 처리를 추가했다. 미검증이고 원격 통합·metadata·정확한 tab focus는 남아 있다. [구현 로그](IMPLEMENTATION-LOG.ko.md) 참고.

IMPL-002: Windows live CLI PID/생성 시각 세션 및 보수적인 root/ancestor 창 활성화 코드를 연결했다. 미검증이며 cwd/대화 매칭·Desktop/IDE·정확한 탭 focus·트레이 session 통합은 남았다. 현재 구현 상태는 [로그](IMPLEMENTATION-LOG.ko.md)를 따른다.

구현 재개: IMPL-001에서 원격 OS별 세션 transport/Windows 실행 파일 경로 및 plugin nowMillis 타입을 작성했다. CODE_WRITTEN_UNVERIFIED이며 W11 전체 완료는 아니다. [구현 로그](IMPLEMENTATION-LOG.ko.md)를 우선 참고한다. 아래 표는 QA206 시점의 정적 현황이며 새 코드의 검증 결과로 승격하지 않는다.

2026-09-12 3차 검토: [추가 조치](TERTIARY-AUDIT-2026-09-12.ko.md)로 위젯 17개 선택지, Windows remote peer/명령 adapter, 출력·기본값·export 동작 조건을 보완했다. 72개 기능군은 유지하며 실제 구현 완료를 추가하지 않았다.

2026-09-12 계획 이차 감사: [추가 조치](SECONDARY-AUDIT-2026-09-12.ko.md)에서 발견한 mode 역참조·plugin 선언·동적 설정 추적 결함을 수정했다. 기능군 수는 유지하며 구현 완료를 추가하지 않는다.

2026-09-12 계획 개정: [현재 계획](WINDOWS-PORT-PLAN.ko.md)의 Windows 가능 기능 전부가 필수다. 아래 구현 상태는 `80f6b484b`/QA204–206 기준으로 유지한다. 계획 수정으로 코드 구현 상태를 승격하지 않는다. 전수 표면 감사로 72개 기능군·69개 공급자/163개 모드·91개 state·169개 CLI 옵션을 source obligation에 연결했다. 파일의 계획 책임 미분류는 0이며 Windows 구현·실행 증거는 여전히 미완료다. 기존 상태 JSON의 QA155/157 다음 작업은 오래된 기록으로 이동했다.

Mac/Linux 제품 유지를 위한 작업은 제품 범위에서 제외하되 공용 기능 추출·fixture 이관·라이선스 보존 후 Mac 전용 파일을 정리한다. 위젯·Sync/Fleet도 Windows에서 가능한 사용자 기능은 필수다. 외부 서비스 조건 미확정은 완료 또는 자동 제외가 아니다.

정적 코드 비교 기준. 기존 Swift 원본이 있는 것과 Windows 대응 완료를 구분한다. 현재 완료 판정된 작업 묶음은 없다. 기존 569개 후보는 전체 분모가 아니다. 새 원본 표면 추적표의 각 의무를 실제 Windows 구현·검증 증거와 연결하는 작업이 남았다.

| 계획 영역 | Windows 상태 | 남은 핵심 경계 |
|---|---|---|
| W01 공급자 | 부분 연결 (Windows descriptor/process 경계) | 69개 × 인증/조회 소스의 Windows 연결 및 오류 경로 (`Sources/CodexBarCore/Providers`, `STATIC-QA-021/024`) |
| W02 계정 | Credential Manager·browser profile·소유권 snapshot 일부 | 외부 CLI 계정 소유권·OAuth/browser import·전환 (`Sources/CodexBarCore/WindowsCredentialCacheStore.swift`, `STATIC-QA-177-180`) |
| W03 트레이 | native 메뉴·상세 사용량·표시 토글·publisher 연결 일부 | 모든 표시 모드와 native tray/popup 동작 (`Sources/CodexBarWindows/WindowsTrayHost.swift`, `STATIC-QA-061`) |
| W04 설정 | 경로·사용/잔여·리셋 시각·refresh/predictive/quota/web 설정 일부 | 전체 native UI·설정 상태·migration (`Sources/CodexBarWindows/Windows*Settings*.swift`, `STATIC-QA-173-174/204-206`) |
| W05 사용량/예측 | canonical 이력·학습 예측·근무일·계정 소유권·authorized dashboard 역채우기 소비자 일부 | 레거시 소유권 연속성, producer/역채우기 전체, 전체 표시 연결 (`Sources/CodexBarWindows/WindowsUsageRuntime.swift`, `STATIC-QA-163-164/172-175/187-188/193`) |
| W06 비용 | 원본 cost 경로 보존, Windows 전용 연결 미판정 | 파일/증분/회전/계정별 경로 (`Sources/CodexBarCore/Vendored/CostUsage`, `STATIC-QA-033`) |
| W07 대시보드 | HTTP client·authorized fetch·snapshot 게시 경계 일부 | native 표시·집계·export 및 web producer/cache 전체 (`Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardHTTPClient.swift`, `STATIC-QA-036/193/200`) |
| W08 갱신 | fixed/adaptive timer·power snapshot·AC/resume·Battery Saver 등록·reset boundary·시작 재시도 일부 | agent-aware scanner·thermal/cost 정책·전체 refresh 정책 (`Sources/CodexBarWindows/WindowsPowerState.swift`, `WindowsTrayHost.swift`, `STATIC-QA-071/074`) |
| W09 알림 | session reset/recovery·threshold·provider editor·predictive candidate·balloon/overlay/sound·FIFO publisher 일부 | hooks 포함 전체 전달 정책, 현지화·실행/중복 동작 (`Sources/CodexBarWindows/Windows*Notification*.swift`, `WindowsQuotaWarningOverlay.swift`, `STATIC-QA-163-164/165-167`) |
| W10 위젯 | 미연결 | Windows 표면과 snapshot 연결 (`Sources/CodexBarWidget`, Windows target 부재) |
| W11 세션 | Codex/Antigravity ConPTY·process identity 연결, Claude 일부 | Claude 지속 세션 완성, 프로세스/터미널/원격 전수 (`Sources/CodexBarCore/Host/PTY`, `STATIC-QA-039/046/049/069`) |
| W12 CLI/HTTP | Windows process·console·Winsock HTTP·dashboard output 일부 | 직접 POSIX/TTY/명령 계약 및 전체 CLI 표면 (`Sources/CodexBarCore/Host/Process`, `Sources/CodexBarCLI`, `STATIC-QA-034/036/037/039`) |
| W13 Hooks | native process/dispatch 경계 일부 | event runtime, Windows 시나리오 전수 대조 (`Sources/CodexBarCore/Hooks`, `STATIC-QA-005`) |
| W14 Plugins | QuickJS·승인된 plugin 조회/Windows resource 경계 일부 | 재검색·cookie·설치/승인/설정 UI (`Sources/CodexBarCore/Plugins`, `STATIC-QA-001/002`) |
| W15 Sync/Fleet | 미연결 | CloudKit 대응·충돌·계정·offline |
| W16 운영 | Windows target/startup/shutdown·native settings 연결 일부 | 설치/서명/update/접근성·배포 (`Sources/CodexBarWindows/WindowsMain.swift`, `STATIC-QA-061/204-206`) |

단계별 코드 리뷰 기록은 STATIC-QA 문서에서 확인한다. 전체 제품 완성률을 파일/커밋 수로 계산하지 않는다. 실행 검증은 사용자 지시로 전혀 하지 않으며 별도 승인 없는 상태에서 자동 CI도 재활성화하지 않는다.
과거 agent203이 금지된 `swiftc -parse`를 실행했다는 기록은 STATIC-QA-204-206에 적힌 대로 검증 근거에서 제외한다. 이를 근거로 컴파일러 실행 이력을 부정하지 않는다.
