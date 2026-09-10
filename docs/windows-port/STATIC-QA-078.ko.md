# QA078/079 — 사용량 상세 표시

전체 UsageSnapshot/ProviderFetchResult를 보존하고 quota/credit/cost/detail 행을 표시하는 초안 작성. 독립 정적 리뷰 079 진행 중. Root는 optional usage를 가져오는데도 WithoutOptionalUsage 필터가 항상 적용되는 문제와 월간 한도가 별개 잔액 실패 때문에 숨겨지는 문제를 발견해 수정을 요청했다. 현재 REQUEST CHANGES. 차트 UI·전체 다중 계정 표시와 실Windows 검증은 완료되지 않았다.

후속 080: 개인정보 숨김 및 선택적 사용량 옵션이 presentation 기본값에만 머물러 실제 설정에 연결되지 않은 점을 확인했다. CodexBar.Windows defaults의 원본 키/기본값을 갱신 단위로 읽고 built-in/plugin 표시, fetch 옵션, 오류 게시 경로에 연결하는 작업을 시작했다. 079 독립 재검토가 진행 중이며 승인 전에는 이 단계를 완료하거나 게시하지 않는다.

080 재검토: fetch와 native/plugin 표시 및 오류 게시의 옵션 전달은 추가되었다. Root는 defaults suite 불일치(.standard 대신 CodexBar.Windows 필요)를, 079는 descriptor/generic 잔액 중복 및 hidden 스타일의 custom balance 노출을 발견했다. 담당자가 수정 중이며 최종 정적 승인 전이다.

최종 079 재검토: 080 수정과 Root의 명시적 return 보완 후 이 부분 텍스트 표시 범위의 필수 정적 차단 사항 없음. 설정 suite/갱신 단위 snapshot/optional 조회 및 표시/hidden 비용/중복 잔액 억제/개인정보 마스킹 연결을 확인했다. 부분 단계 커밋 가능. 차트, 액션, 공급자별 고급 메뉴, 모든 표시 설정과 native 설정 UI는 여전히 미완료. 빌드·테스트·Windows 실행 및 성능 검증 없음. GitHub Actions 비활성 상태를 API 읽기로 확인했다.
