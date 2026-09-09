# 간접 resolver 후속 작업

GeminiStatusProbe.swift 1227 이후 installed CLI OAuth client metadata discovery는 BinaryLocator.resolveGeminiBinary/TTY.which를 호출한다. WindowsCommandResolver target의 JS entry를 package root 탐색 시작점으로 사용해야 한다. sourcePath만 쓰면 npm bin shim 디렉터리와 실제 package root가 다를 수 있다. 524행 resolveExecutableOnEnvironmentPath는 콜론 PATH를 분리하므로 Windows fnm.exe 탐색으로 분기해야 한다. runProcess/fnm exec 경로도 Windows backend와 함께 조사해야 하며 단순 import guard만으로 완료하지 않는다.

ClaudeProviderDescriptor.swift 1219 captureMarker는 binary path+identified account scope로 background authorization을 식별한다. 버전 shim 도입에서 node.exe로 marker key를 바꾸면 계정·CLI 경계가 흔들리므로 원본 source shim path를 유지한다. getClaudeFingerprint는 node/entry/shim 의존 파일과 경로를 모두 포함해야 한다. 작업자 claude_shim_022가 구현 중이며 독립 정적 검토가 필요하다.

모두 소스 읽기 근거이며 실제 OAuth credential/CLI/파일 API 실행 검증은 하지 않았다.
