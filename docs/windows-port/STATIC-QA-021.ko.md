# 코드 비교 QA 021

Grok CLI availability/version/RPC에 WindowsCommandResolver를 연결했다. RPC는 WindowsLaunchTarget으로 prefix 및 PATHEXT 조정을 적용한다. 버전은 sourcePath로 ProviderVersionDetector.run에 전달해 동일 resolver를 사용한다. Gemini descriptor binaryLocator와 버전 탐색도 동일 resolver로 연결했으며 Gemini usage의 OAuth/API 전략은 변경하지 않았다.

통합 검토에서 Grok guard 문장을 #if/#else가 쪼개는 초안을 각 branch 안의 완전한 guard 문장으로 고쳤다. 원본 non-Windows 흐름은 보존한다. 아직 Claude shim 지원은 node/entry/shim fingerprint 및 background gate 의미를 함께 처리해야 하므로 native-only 상태다.

제한된 npm 9.0.2 node template만 지원하는 후보이며 다른 template·임의 batch·ConPTY·전체 Core 및 제품 이식은 미완료다. 빌드·컴파일러·테스트·앱·실계정은 실행하지 않았다. 독립 정적 리뷰 대기.

독립 최종 리뷰: target propagation 및 sourcePath 재탐색에 새 확정 결함 없음. Gemini OAuth discovery의 BinaryLocator/TTY 경로 등 기존 Core 간접 호출은 아직 남아 있다. 이는 버전/descriptor/RPC 범위의 정적 판정이다.
