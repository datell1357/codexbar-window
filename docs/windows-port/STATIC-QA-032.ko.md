# 코드 비교 QA 032

Windows `cookie refresh --provider amp` 및 `--all`에 현재 연결된 Amp만 노출한다. macOS 공급자 선택은 보존하고 Windows 오류 안내는 Amp/Firefox에 맞춘다. manual/off 설정은 기존 preflight에서 skip한다. Chromium/다른 공급자는 지원 대상으로 올리지 않는다.

Amp 자동 브라우저 쿠키는 HTML 응답 검증·파싱 성공 이후에만 캐시 저장한다. 수동 override는 sourceLabel이 없어 저장하지 않고 API/debug probe도 저장하지 않는다. CLI refresh suppression 상태에서는 메모리에 staging하고 상위 CLI가 성공 및 staging 1건의 영속화 결과를 확인한다. 실패 시 staged mutation을 버려 기존 자격증명을 유지한다. Amp fetcher는 저장된 캐시를 아직 조회하지 않으며 브라우저 읽기 최적화는 남아 있다.

연결 대조에서 CookieHeaderCache의 POSIX open/flock 경계를 추가로 발견했다. Windows 분기는 CreateFileW(OPEN_ALWAYS) 및 동기 LockFileEx 독점 잠금으로 교체하고 defer UnlockFileEx/CloseHandle을 연결했다. 독립 리뷰에서 파일 교체가 잠금을 우회할 수 있는 FILE_SHARE_DELETE를 지적해 제거했다. non-Windows 경로는 그대로 유지한다. WinSDK ABI/Windows 파일잠금 동작은 실행·컴파일 미검증이다.

합성 CLI 대상 선택·Keychain 승인 불필요 테스트 소스를 추가했다. 독립 코드 리뷰와 git diff --check만 수행했다. 빌드·테스트 실행·프로필/계정 조회·성능 측정은 전혀 하지 않았다. 새로운 캐시 저장 경로의 실패/경합 통합 테스트 소스와 Windows 실행 검증은 남아 있다. 이는 전체 CLI나 공급자의 Windows 완료 판정이 아니다.

다음: 캐시 저장/실패 경계의 합성 소스 검토 확대, 다른 공급자의 Windows 인증·쿠키 경로와 공통 POSIX 잔여 경계 이식. 네이티브 UI/트레이/갱신/위젯/동기화/설치 및 전체 기능 계약 QA 미완료.
