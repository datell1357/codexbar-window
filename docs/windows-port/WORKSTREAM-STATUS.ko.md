# Windows 전용 제품 작업 현황

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
