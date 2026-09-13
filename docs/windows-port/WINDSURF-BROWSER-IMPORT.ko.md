# Windows Windsurf 브라우저 가져오기

상태: CODE_WRITTEN_UNVERIFIED. 아래 내용은 작성된 코드의 의도이며 Windows 실행으로 확인한 사용 보장이 아니다. 사용자 지시에 따라 빌드·테스트·실행 검증을 보류했다.

## 흐름

1. 사용할 브라우저에서 Windsurf에 로그인한 뒤 브라우저를 정상 종료한다. 백그라운드 프로세스가 DB를 사용하면 잠금 때문에 가져오기를 거부할 수 있다.
2. CodexBar에서 Windsurf를 활성화하고 Add saved account 메뉴의 Import Windsurf from browser를 선택한다.
3. 브라우저를 선택한다. Chrome이 기본 선택지이며 Edge, Brave, Vivaldi, Chromium과 목록에 표시된 Beta/Canary/Nightly 채널을 지원 경로로 연결했다. 다른 브라우저로 자동 전환하지 않는다.
4. 프로필 경로를 선택적으로 입력한다. 개별 프로필 폴더를 사용한다. User Data 루트나 Local Storage/leveldb 폴더를 직접 입력하지 않는다.
5. plan 응답이 있는 후보를 선택하고 이름을 입력해 저장한다. 저장하면 보호된 계정 저장 경로를 사용하고 해당 계정을 선택한다. 이후 사용량을 새로고침한다.

## 경로 선택

우선순위는 이번 입력 창의 명시 경로, CODEXBAR_WINDSURF_BROWSER_PROFILE_DIRECTORY 환경 변수, 선택 브라우저의 기본 프로필 탐색 순이다. 입력 창을 비우면 환경 변수도 적용된다. 환경 변수를 변경했다면 CodexBar를 다시 시작한다. 명시 경로가 잘못되면 기본 프로필로 대체하지 않는다.

Vivaldi 기본 경로는 LocalAppData/Vivaldi/User Data이다. standalone 설치에서는 Vivaldi의 Help > About에 표시된 Profile Path를 사용한다. 출처: [공식 프로필 설명](https://help.vivaldi.com/desktop/privacy/preventing-vivaldi-profiles-from-being-uploaded-to-git-repositories/), [standalone 설치 설명](https://help.vivaldi.com/desktop/install-update/standalone-version-of-vivaldi/).

이번 요청의 경로 입력은 저장하지 않는다. 로컬 드라이브의 기존 프로필만 받으며 UNC/장치 경로는 지원하지 않는다. 상위 junction 전체를 검증하는 기능은 아직 없다.

## 세션과 저장

프로필과 origin별 인증 값은 합치지 않는다. app.devin.ai 또는 windsurf.com 안에서 필수 값 4개가 완전해야 후보를 만든다. 삭제된 값은 복원하지 않는다. GetPlanStatus 성공은 사용 가능한 plan 응답을 뜻하며, 이 응답에는 서버 계정 ID가 없으므로 신원을 검증했다고 표시하지 않는다.

후보 선택은 5분 뒤 만료한다. 설정/선택 계정/개인정보 숨김 상태가 달라지면 저장을 거부한다. 동일한 세션 묶음만 기존 계정으로 재사용한다. 토큰·실제 파일 경로는 후보 표시나 오류에 넣지 않는다.

## 현재 제한

- Chromium localStorage schema 1 및 무압축/Snappy LevelDB 입력을 구현했다. 다른 schema/압축은 거부한다.
- 실행 중 브라우저 종료, DB repair/compaction, 쿠키 암호 해독은 수행하지 않는다.
- 탐색 프로필 최대 64개, API 조회 후보 최대 16개이며 생략/실패 수를 안내한다. 더 많은 후보를 다루려면 개별 프로필 경로를 지정할 수 있다.
- 후보가 없으면 프로필 사용 중/미지원 형식/읽기 오류/불완전 세션을 구분해 안내한다. 세션이 있지만 plan 요청에 실패한 경우는 별도 안내한다.
- 브라우저 버전별 저장 형식 호환성, 실제 UI, 보호 저장, Windows 종료/취소 동작은 모두 미검증이다.
