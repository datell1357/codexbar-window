# 변경 기록 메뉴 정적 QA 108/110

고정 원본 928166f899471bbdcb72210641cdec91324d0154 대비 독립 검토110: APPROVE(해당 범위만).

WindowsTrayMenuEntry와 WindowsUsageRuntime이 공급자 metadata changelogURL을 보존한다. WindowsTrayHost는 providerChangelogLinksEnabled 기본값 false와 저장 토글을 적용하고 URL이 있는 공급자 메뉴를 표시한다. 토글은 표시 재구성만 요청하며 공급자 조회를 유발하지 않는다. 기존 HTTP/HTTPS 검증과 popup 명령 수명 정리를 재사용한다.

Windows의 전체 공급자 하위 메뉴는 플랫폼 적응이다. 원본의 선택 공급자 메뉴와 외형은 다르다. 현지화·전체 표시 모드는 미완료다. 소스 비교와 git diff --check만 수행했다. 빌드·테스트·Windows 동작·성능은 검증하지 않았다.
