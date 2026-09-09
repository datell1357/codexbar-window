# 코드 비교 QA 019

Codex Windows RPC의 실행 대상을 WindowsLaunchTarget(executable, argumentPrefix)으로 전달한다. WindowsProcess target overload는 prefix + caller arguments를 기존 native 실행 backend에 전달하며 shell 경로를 추가하지 않는다. 기존 resolver 주입과 default empty prefix는 유지한다. 이는 npm shim의 node+entry 전환을 준비하는 연결 단계이며 shim 탐색/실행 지원 완료가 아니다.

launch_target_019_review가 memberwise initializer/접근 범위/빈 prefix 원본 유지/호출부 연결을 정적으로 검토하여 확정 결함 없음으로 판정했다. 기존 테스트 파일은 읽기만 했고 실행하지 않았다. 빌드·컴파일·테스트·provider·실계정 실행은 하지 않았다. 전체 이식은 미완료다.

shim_source_019에서 실제 npm template 고정 원본을 조사 중이다. 확인한 template만 다음 단계에 허용하고 임의 batch 실행으로 확장하지 않는다.
