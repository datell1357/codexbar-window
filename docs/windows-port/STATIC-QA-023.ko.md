# 코드 비교 QA 023

Claude 담당 claude_shim_022가 pending_init 상태로 수정 없이 대기했음을 확인해 중단하고 통합 담당이 직접 ProviderVersionDetector를 수정했다. Windows Claude 버전/탐색에 narrow npm target을 연결했다. 캐시는 source shim뿐 아니라 target node/native 실행 파일 및 JS entry의 정규화 경로와 WindowsFileIdentity metadata를 포함한다. PATH가 다른 Node로 바뀌어도 별도 fingerprint가 된다. background gate는 sourcePath를 그대로 사용하며 우회하지 않는다. DEBUG hook 및 비Windows cache 흐름 보존. claude_023_review에서 구체적 결함 없음 확인.

GeminiStatusProbe에서는 installed CLI metadata 탐색 시작점을 npm target JS entry로 연결했다. native는 기존 source path를 쓴다. Windows fnm PATH 탐색/실행은 native adapter로 분기하고 경로 판별은 대소문자 비민감으로 했다. Unix TTY fallback은 nonWindows에만 남기고 lazy 탐색 순서를 보존한다. legacy→fnm→package root 탐색은 유지한다. 최종 독립 리뷰 대기.

실제 credential/CLI/컴파일러/테스트/빌드/앱 실행은 하지 않았다. fnm 내부 npm dispatch, Windows 전체 browser/auth/PTY/UI 대응 및 전수 기능 검토는 미완료다.

Gemini 최종 독립 정적 리뷰에서도 구체적 결함 없음 확인. 실행 검증 통과를 의미하지 않는다.
