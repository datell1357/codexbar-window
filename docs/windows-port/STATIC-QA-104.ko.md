# QA104–105 — 공급자 상태 페이지 메뉴

고정 원본 928166f899471bbdcb72210641cdec91324d0154의 상태 페이지 metadata.statusPageURL ?? metadata.statusLinkURL 우선순위를 Windows에 연결했다. 활성 first-party 공급자에 대해 조회 성공 여부와 무관하게 메뉴를 구성하고 행과 링크를 함께 전달한다. 원본 plugin manifest에는 상태 링크 계약이 없어 endpoint를 링크로 추정하지 않는다. 동적 대시보드 링크는 별도 미완료 항목이다.

독립 검토 105의 개인정보 숨김 누락과 실패한 하위 메뉴의 소유권 문제를 수정했다. 팝업 명령 맵, 기존 설정 명령, HTTP(S) URL 검증, ShellExecuteW 오류 처리를 정적 대조했다. 초기 게시도 기존 행 표시 함수를 재사용한다.

소스 읽기 및 git diff --check만 수행했다. Windows ABI·셸·브라우저 실행, 빌드·테스트는 미검증이다. 전체 기능 이식 완료가 아니다.
