# QA106–107 — 대시보드 동적 링크 수정 중

독립 코드 대조 107 판정은 REQUEST CHANGES다. 공용 항목을 대시보드 조건으로 필터링하여 상태 전용 공급자를 누락한 문제, 원본 지역 기본값 미적용, Z.ai 선택 계정의 usageScope 대신 pluginSettings를 사용한 문제, Qoder 런타임 sourceLabel과 설정 source의 혼동, Claude 구독 snapshot 판별 누락을 수정한다.

실제 조회 결과와 계정 문맥을 URL 결정에 연결한 뒤 다시 독립 검토하며 아직 커밋하지 않는다. 빌드·테스트·실행은 하지 않았다. 전체 기능 동등성은 미완료다.

재검토: 갱신 실패 시 마지막 성공 문맥 보존은 동일 계정·설정에 한정해야 한다. 원본의 알 수 없는 Claude plan 및 Qoder source fallback도 재대조한다. 설정 오류 이전에 현재 상태 메뉴를 만들고 대시보드 표시 조건은 metadata만 사용하도록 수정 중이다. 아직 승인하지 않았다.

추가 검토: 마지막 성공 문맥의 문자열 fingerprint가 동일 ID의 자격증명 변경 및 ambient 계정 변경을 판별하지 못한다. 충돌 가능한 구분자 연결도 제거하고 확실히 연결된 계정 범위에만 캐시를 적용하도록 재검토 중이다.

최종 정적 판정 107: APPROVE. 지역 기본값·동적 7개 분기, Claude 구독/기본 billing, 활성 Z.ai 범위, Qoder 실제 sourceLabel, metadata 표시 조건을 연결했다. typed cache key는 명시적 계정과 token/API/secret/cookie digest별로 분리한다. ambient 계정은 이전 문맥을 재사용하지 않으며 실패 시 descriptor 기본 링크를 사용한다. 기존 swift-crypto 제품을 Windows 타깃 직접 의존성으로 연결했다. git diff --check 통과; 빌드·테스트·실행 및 Windows ABI는 미검증이다. 전체 기능 완료가 아니다.
