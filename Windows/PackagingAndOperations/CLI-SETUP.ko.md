# Windows CLI 사용자 PATH 설정

구현 코드이며 Windows에서 실행·검증하지 않았다. 전체 Windows 배포물의 CLI, DLL, 리소스를 함께 유지한다. 이 스크립트는 다운로드·바이너리 설치나 MSIX execution alias를 제공하지 않는다.

Windows PowerShell에서 `Set-CodexBarUserPath.ps1 -Action Add -Directory 'C:\Apps\CodexBar'`를 명시적으로 실행하면 해당 폴더를 사용자 PATH 끝에 추가한다. 먼저 `-WhatIf`를 붙여 변경 의도를 볼 수 있다. PATH 문자열 전체와 개인정보 경로는 출력하지 않는다. 관리자 권한과 execution policy 변경을 요구하지 않으며 조직 정책에 의해 스크립트 실행이 차단되면 관리자의 배포 절차를 따른다.

제거는 `Set-CodexBarUserPath.ps1 -Action Remove -Directory 'C:\Apps\CodexBar'`이다. 지정 폴더와 일치하는 literal 항목을 모두 제거하므로 사용자가 별도로 추가한 동일 항목도 제거된다. 파일을 지우지 않으며 이전 설치 폴더가 사라진 경우에도 제거할 수 있다. 환경 변수로 간접 참조한 항목은 유지한다.

Add는 CLI 후보 파일의 존재만 확인한다. 신뢰성·서명·의존성·실행 가능은 판정하지 않는다. 기존 항목 순서와 값 형식(REG_SZ/REG_EXPAND_SZ)을 보존하고 환경 변수를 확장하지 않는다. 다른 설치본이 앞서 있으면 그 우선순위를 유지한다. 머신 PATH와 현재 프로세스 환경은 수정하지 않으며, 적용 후 로그아웃·로그인해서 새 환경을 상속받는다.

변경 직전 값/형식 재조회로 감지한 외부 편집은 중단한다. 이 재조회와 쓰기는 원자적이지 않으며 외부 registry writer와의 경쟁을 완전히 막지는 않는다. 상위 폴더 junction/파일 변경 경쟁도 별도 검증 대상이다. 실패 시 기존 PATH 전체를 임의 복원하지 않는다.
