# Windows 비용 파일 I/O 구현 경계

IMPL-559~567. 상태: **CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION**.
Mac 호스트에서 소스를 작성한 기록이며 Windows 컴파일·실행·성능·파일 시스템 호환성을 입증하지 않는다. W06/W07 전체 기능 및 G0~G6 완료가 아니다.

## 파일 메타데이터와 캐시

- `WindowsCostFileMetadata`는 파일/폴더를 Win32 metadata handle로 열고 disk 종류·크기·수정 시각·볼륨/파일 ID를 읽는다. `FILE_FLAG_BACKUP_SEMANTICS`로 폴더를 허용한다. 기존 `stat`처럼 reparse 대상은 따라가며 credential 파일용 reparse 거부 정책을 비용 source에 임의 적용하지 않는다.
- `FileIdInfo`의 볼륨과 128-bit ID를 `win128:` 형식으로 저장한다. 해당 정보 class 미지원 오류일 때만 legacy volume/index를 `win64:`로 구분한다. 다른 I/O·권한 오류 및 0 ID는 성공으로 바꾸지 않는다. FILETIME은 정수로 변환해 부동소수점 변환에 의한 시각 반올림을 피한다.
- 정확한 FILE/PATH_NOT_FOUND만 부재로 반환한다. Codex 개별 파일 수집은 regular 파일을 요구하고 부재·디렉터리·접근 오류를 상위로 전달한다. 정렬/힌트용 기존 optional metadata 함수는 별도로 유지한다.
- Windows Codex cache의 fresh/append 경로에는 전체 ID 일치를 요구한다. 저장소 복원 시 APFS용 root device 재기록, inode 일부 비교, 크기/시각만 같은 다른 파일의 완료 판정을 사용하지 않는다. 기존 POSIX ID나 ID 없는 cache는 일치하지 않아 재수집 대상이 된다. SQLite schema는 변경하지 않고 기존 scan-state 문자열에 전체 ID를 보관한다.
- JSONL tail 판단용 크기는 Windows에서 실제 열린 FileHandle의 native handle에서 읽는다. FileHandle이 소유한 handle은 metadata helper에서 닫지 않는다. 이것만으로 parser 시작 전 path ID, 모든 중간 읽기, 최종 cache 게시가 동일 파일 버전임을 보장하지는 않는다.

## Codex 페이지 탐색

- Windows에서 DIR/opendir/readdir 대신 FindFirstFileW/FindNextFileW를 사용한다. 한 번 얻은 search handle과 첫 결과를 보존하며 기존 discovery visit budget을 따른다. 폴더 이름이 `.jsonl`로 끝나도 파일 후보에 넣지 않는다.
- ERROR_NO_MORE_FILES만 정상 종료다. 권한·공유·I/O 오류를 빈 완료 목록으로 바꾸지 않고 page → 날짜 partition → current/lookback advance → refresh로 전달한다. Task 취소 시에도 cursor를 제거하고 search handle을 닫는다.
- cursor는 최대 64개 유지한다. 재시작/eviction/offset 불일치/폴더 metadata 변경 시 그 폴더를 0부터 재열거한다. Win32 반환 순서는 정렬 계약이 없으므로 새 handle에서 과거 개수만큼 건너뛰지 않는다. 재발견 파일 처리는 기존 ID/row dedup 계약을 사용한다.
- 페이지 전후 폴더 snapshot이 달라지면 해당 페이지 후보를 내보내지 않고 소비한 visit 수와 offset 0을 반환한다. 폴더가 계속 바뀌면 완료가 지연될 수 있다. directory timestamp는 파일 시스템 snapshot/USN journal이 아니므로 동시 변경의 모든 경우를 검출했다는 뜻은 아니다.
- reset은 경로 구분자 차이를 처리하되 NTFS case-sensitive 폴더를 임의 소문자화하지 않는다. 일반 absolute file URL과 기존 앱의 long-path 설정에 의존한다. device namespace/extended-prefix 직접 입력 및 모든 UNC/long-path 조합의 지원은 입증하지 않았다.

## Claude/Vertex JSON cache 게시

- transcript/report memo stamp는 동일한 Windows metadata helper를 사용한다. Claude/Vertex cache와 report memo의 POSIX rename 경로를 Windows 보호 파일 저장기로 분기한다. 임시 파일 DACL·flush·같은 폴더 replacement는 기존 `WindowsCredentialFileWriter` 계약을 사용한다.
- cache는 게시 직전 cancellation callback을 다시 호출한다. callback 오류는 원래 오류로 전달하고 이전 destination을 교체하지 않는다. staging stamp와 게시 뒤 destination stamp가 일치할 때만 해당 stamp를 반환해 다른 writer의 결과에 이번 report를 결합하지 않는다.
- cache/memo 저장은 기존 best-effort 의미를 유지한다. cache 쓰기 실패는 stamp 없음으로 반환하며 새 memo 기준으로 사용할 수 없다. 이 변경은 전체 비용 저장소의 transaction/backup/복구를 구현한 것이 아니다.

## IMPL-560: Claude/Vertex inventory 오류 경계

- Windows 재귀 목록은 기존 Foundation의 hidden/package 제외 정책을 사용하면서 error handler의 최초 실패를 수집하고 전체 호출을 실패시킨다. root는 native metadata로 부재/존재하는 빈 폴더/디렉터리가 아닌 대상/접근 실패를 구분한다. callback 오류는 경로가 없는 일반 오류로 전달한다.
- 하위 폴더와 JSONL 파일의 native stamp를 보관하고 열거 종료 시 재관측한다. 폴더 접근/속성 읽기/목록 읽기 실패나 관측 후 부재·변경이 있으면 부분 목록을 반환하지 않는다. callback/Task 취소도 전달한다. 링크 디렉터리는 명시적으로 재귀 진입을 생략해 기존 DirectoryEnumerator 정책을 유지한다.
- helper는 크기 0 로그도 관측한다. 상위 Claude 수집은 기존의 0-byte 파일 제외/사용량 제거 의미를 유지하되, 목록 완성 전 파일이 변하면 실패하도록 작성했다. 이 동작은 root를 실제로 삭제한 경우까지 기존 사용량을 영구 보존하는 정책이 아니다.
- 파일별 cache 재사용 전과 파싱 후에 목록의 전체 stamp를 다시 대조한다. Windows Claude parser는 stream I/O나 사용자 정의 cancellation callback 오류를 `parsedBytes = startOffset`인 성공 결과로 바꾸지 않고 다시 던진다. inventory/parse가 실패하면 정상 cache/memo 게시 지점에 도달하지 않도록 연결했다.
- 각 metadata 재관측 사이/마지막 재관측 후에는 변경이 가능하다. 같은 handle의 예상 identity 결합, 동일 ID·size·mtime로 덮어쓴 내용, 최종 게시까지의 모든 변경을 입증한 것은 아니다. 대규모 재귀 inventory는 현재 bulk 수집이며 페이지화와 장기 성능 증거도 남아 있다.
- `WindowsCostSourceInventoryTests.swift`에 부재/빈/파일 root, 재귀·0-byte·jsonl 이름 폴더, 사용자 정의 취소, 목록 이후 append 거부용 합성 fixture를 작성했다. 실행하지 않았다. 실제 ACL/공유 오류·동시 변경·Windows Foundation traversal도 미검증이다.

## IMPL-561: 실제 열린 stream과 고정 읽기 경계

- `CostUsageFileReadSnapshot`에 native file ID·size·정밀 수정 시각을 묶고, JSONL scanner의 선택적 expectedFile 계약을 추가했다. Windows Codex/Claude의 실제 비용 parser와 Codex session ID/metadata·parent token snapshot·token-index anchor 읽기에 연결했다. 다른 JSONL 소비자는 이 expectedFile 연결만으로 자동 이식 완료된 것이 아니다.
- `WindowsCostFileReadGuard`는 실제 FileHandle과 현재 path가 관측한 파일 ID를 가리키는지 시작·chunk 사이·반환 전에 읽는다. 초기/이후 관측보다 크기가 줄거나, 크기 증가 없이 수정 시각이 바뀌면 실패한다. 사라진 path나 실제 handle 조회 오류도 전달한다. 재개 offset이 관측한 크기를 넘어가거나 기대한 EOF 이전에 끝나면 정상 결과로 반환하지 않는다.
- 읽기 한도는 최초 관측한 파일 길이와 기존 byte budget 중 작은 값으로 고정한다. 같은 파일이 더 커지는 것은 허용하되 새 tail을 이번 결과에 포함하지 않는다. cache에는 원래 size/mtime을 남겨 다음 수집이 새 tail을 처리하도록 한다. Claude의 파싱 후 대조도 이 추가분을 허용한다. JSONL의 미완성 끝줄 및 기존 resume-state 계약은 유지한다.
- Windows Codex의 metadata/parent/body read 오류는 partial row 성공으로 축소하지 않고 상위에 전달한다. 재수집의 이전 days 차감도 throwing parser가 성공한 뒤로 옮겼다. 비 Windows 파서의 기존 오류 처리 의미는 유지한다.
- Windows Codex 증분 경로는 file ID 외에도 기존 committed-offset anchor 일치를 요구한다. anchor 읽기도 expectedFile과 native handle/path를 대조한다. anchor가 없거나 다르면 전체 재파싱 경로로 돌아간다. 이 anchor는 기존 최대 64 KiB 구간 해시이며 전체 과거 prefix를 해시한 증거가 아니다.
- 합성 Windows fixture에 관측 후/open 전 교체, callback 중 append와 다음 scan의 tail 처리, callback 중 truncate, 같은 크기에서 수정 시각 변경, 범위 밖 resume를 작성했으나 실행하지 않았다. 활성 writer와 FileHandle의 실제 share mode 및 SDK 호환성도 미검증이다.
- 관측 사이에 truncate 후 재성장하거나 ID/size/시각을 유지한 내용을 변경하는 경우까지 탐지하는 immutable snapshot은 아니다. prefix 재작성·Claude의 이전 prefix 확인, 최종 cache/SQLite 게시 직전의 전체 source-version 연결, Pi 등 다른 비용 source는 후속 구현 범위다. 정상 writer의 timestamp 지연 갱신도 재시도로 이어질 수 있으며 성능/진행성 결과는 없다.

## IMPL-562: Codex 비페이지 inventory와 캐시 부재 판단

- `WindowsCostDirectoryInventory`는 native cursor로 한 폴더의 JSONL 파일/하위 폴더를 모으고, 관측 entry와 폴더 metadata를 반환 전 다시 읽는다. 정확히 없는 폴더는 nil, 정상 빈 폴더는 빈 listing이며 종류 불일치·권한/목록/metadata 오류·관측 변경·취소는 throw다. 숨김 attribute와 점으로 시작하는 이름을 제외한다.
- Codex 날짜별 비페이지 목록·최상위 로그·부모 세션 색인의 폴더 열거에 연결했다. 최근 변경 파일 및 legacy 재귀 탐색은 기존 Windows 재귀 inventory helper를 사용하도록 연결했다. legacy에서 날짜별 최상위 연도 폴더를 건너뛰는 정책을 유지한다. root 포함/날짜 ancestor 비교는 Windows 경로 구분자 두 종류를 비교용으로 정규화하되 case folding은 하지 않는다.
- 발견한 후보의 수정 시각 조회 실패를 필터 제외로 바꾸지 않는다. 비페이지 lookback 및 refresh까지 오류/cancellation을 전달하고, 날짜별 budget 정산은 오류가 나도 defer에서 수행한다. 실제 Windows 실행/성능 결과는 없다.
- cached session 후보·부모 색인의 기존 session mapping/파일 head·완료된 catch-up 경로 판단·마지막 캐시 삭제에 native 부재 구분을 연결했다. 실제 부재만 기존 삭제/완료 의미를 따르며, 조회 실패나 파일 자리에 폴더가 생긴 경우에는 missing session 또는 제거 가능한 cache로 간주하지 않는다.
- Windows용 합성 fixture에 부재/빈/파일 root, 얕은 목록의 JSONL/폴더/점 숨김 구분, 취소, 잘못된 부모 root/디렉터리 session mapping의 실패를 작성했다. fixture와 ACL/공유 오류·실제 파일 시스템 I/O는 실행하지 않았다.
- 이 공통 reader와 기존 재귀 inventory는 전체 목록을 메모리에 모으는 경로다. 대규모 단일 폴더/재귀 목록의 paging·시간 budget 세분화, native directory ID를 포함한 영속 색인 검증 및 junction cycle/alias, 목록 이후 최종 게시 사이 변경은 아직 남아 있다. 폴더/file stamp 대조는 atomic filesystem snapshot이 아니다.

## IMPL-563: 관측 source와 저장 직전 대조

- `CostUsagePublicationObservations`에 파일·폴더·실제 부재를 기록하고 immutable `CostUsageSourcePublication`으로 동결해 저장 경계로 넘긴다. collector는 잠금으로 보호하고 SQLite actor에는 mutable collector나 취소 closure를 보내지 않는다. raw source 경로는 메모리 관측에만 사용하며 새 로그/영속 파일에 저장하지 않는다.
- 파일은 같은 native ID와 관측 크기 이상을 요구한다. 크기가 같을 때에는 정밀 수정 시각도 일치해야 하며, 늘어난 tail은 기존 고정 읽기 경계에 따라 다음 수집으로 넘긴다. 폴더는 관측 snapshot 일치, 부재는 계속 부재여야 한다. native 조회 실패와 Task/custom 취소는 성공으로 취급하지 않는다.
- Codex의 개별 수집·의존/재시도 파일, 부모 색인의 cached mapping/head·폴더 열거, 명시적 missing cache 제거를 같은 관측 집합에 연결했다. SQLite 저장 전과 writer transaction의 COMMIT 직전에 대조한다. 실패 시 진행 중 save를 rollback하고 별도 `sourceValidationFailed`를 반환하며, scanner는 이를 throw하여 새 캐시의 보고서를 성공으로 반환하지 않는다. source 오류를 SQLite corruption 분류/rebuild에 넘기지 않는다. 저장 반환 후에도 대조한다.
- unchanged 저장 전에 수행하는 기존 retention은 별도 transaction이다. 이후 source 실패로 save를 rollback해도 이미 끝난 retention까지 원복하는 계약은 아니다. COMMIT 이후 scanner 대조에서만 변경을 관측하면 저장된 snapshot은 남고 이번 report 호출은 실패한다. OS 파일 변경과 SQLite COMMIT은 하나의 원자적 transaction이 아니다.
- Claude/Vertex 재귀 inventory는 빈 파일·폴더·없는 root까지 관측 집합에 포함한다. JSON cache의 protected writer staging callback에서 최종 교체 직전에 대조하고, 실패를 best-effort 디스크 저장 실패에 섞어 숨기지 않는다. report memo도 디스크 교체 전과 메모리 설치 전에 대조하며 source/cancellation 실패를 전달한다. 기존 memo fast return과 최종 report 반환에도 연결했다.
- cache 교체 후 memo 단계에서 source가 바뀌면 cache 파일까지 이전 버전으로 되돌리는 다중 파일 transaction은 아니다. 디스크 memo I/O는 기존처럼 선택적이며, source 대조 실패와 구분한다. 마지막 관측 뒤 파일 시스템이 다시 바뀌는 경쟁도 남아 있다.
- `WindowsCostPublicationTests.swift`에 append 허용/교체 거부, missing root 재등장/폴더 교체, staging 중 source 축소 시 Claude cache 및 memo의 이전 bytes/메모리 유지, Codex changed/identical save의 rollback·lastScan 보존·rebuild 없음용 합성 fixture를 작성했다. **실행하지 않았으며 통과 결과가 없다.**
- 현재 Codex 관측 집합은 실제 연결한 수집/부모 탐색/명시적 부재 경로에 한정된다. 주 discovery의 날짜/flat/legacy/paged 전체 목록 세대와 모든 비수집 cache 재사용을 게시 경계에 묶는 작업은 남는다. 이것으로 전체 inventory·전체 prefix·모든 비용 source의 일관성을 완성했다고 판단하지 않는다. 대조의 전체 목록 순회/metadata I/O 비용과 writer lock 점유 시간도 미측정이다.

## IMPL-564: 주 discovery와 캐시 재사용 관측 연결

- 게시 관측 집합을 `loadCodexDaily`의 refresh-plan 생성 전부터 유지한다. 날짜별/flat/legacy/최근 변경 재귀 목록, current-window/lookback 페이지, 캐시 후보와 부모 session 후보, 완료 후보/남은 tail 판단까지 같은 집합을 전달한다. 현재 호출에서 실제로 읽은 root·날짜 폴더·파일·부재를 최종 대조에 포함한다.
- Windows page reader는 선택된 파일의 native snapshot을 모아 페이지 반환 전에 다시 대조하고, 안정된 폴더와 파일 관측을 합쳐 반환한다. custom cancellation을 page/current/lookback 경로로 전달하고 실패 시 live cursor를 정리한다. 기존 visit limit과 최대 64개 cursor는 유지하며 숨김 attribute/점 파일 제외를 비페이지 목록과 맞춘다.
- 설정된 root와 scan window에 관련된 캐시 파일을 재사용하기 전에 native metadata로 관측한다. 저장된 ID·size·밀리초 수정 시각과 다르거나 실제로 없으면 refresh interval이 남아 있어도 priority/usage 갱신 대상으로 삼고, 변경 경로를 durable lookback 대기 목록에 추가한다. 이미 완료된 날짜 탐색 때문에 변경된 캐시 파일이 계속 빠지는 것을 방지하도록 연결했다. 보고서 반환/과거 보고서 fallback 반환 직전에도 현재 관측 집합을 대조한다.
- 이전 실행의 durable 후보가 없어졌다면 native 부재를 관측하고 기존 usage/alias/history 항목을 정리한 processed 후보로 넘긴다. 이에 따라 분할 수집 queue에서 제거할 수 있다. 같은 호출에서 이미 있던 것으로 관측한 파일이 사라지면 관측 집합 충돌로 실패하며, 부재가 유지되는 후속 호출에서 정리한다. 권한/공유/I/O·wrong-kind 오류는 이 경로에 들어가지 않는다.
- 부모 색인의 기존 폴더 유효성 확인에도 Windows throwing metadata와 관측 집합을 연결했다. 이 변경은 이전에 영속화한 directory ID 증명이 아니며, 이전 mtime/count 세대의 의미를 새 파일 identity로 치환하지 않는다.
- `WindowsCostDiscoveryPublicationTests.swift`는 기존 serialized suite에 추가했다. paged/full 수집의 missing root 재등장, 날짜 폴더 생성, 캐시의 같은 size/mtime 교체·append·부재·wrong-kind·취소, timed/byte 후보의 안정된 부재 정리용 합성 시나리오를 작성했다. source/cache/trace 경로는 fixture 폴더로 지정하며 실행 결과는 없다.
- 범위: 현재 호출에서 관측한 입력을 묶은 것이며 이전 실행에서 완료로 남긴 모든 폴더/페이지의 세대를 영속적으로 증명하지 않는다. cache preflight는 관련 파일 목록을 순회하며 새 metadata I/O의 전체 상한/시간 예산 통합과 SQLite 저장 직전 대조 비용은 남는다. refresh interval 안에서 새로 생긴 미캐시 파일의 발견 주기를 바꾸는 watcher도 아니다.
- 캐시와 비교하는 과거 시각은 기존 `mtimeUnixMs`다. 같은 ID·size·밀리초 시각 내 재작성, 전체 prefix 변경, truncate 후 재성장, final check 이후 변경까지 검출하는 계약은 아니다. 기존 pending/priority 실패 시 과거 보고서 제공 정책은 유지하며 이를 새로 검증한 usage로 표시한 것은 아니다. 파일 탐색 범위 연결이 W06 전체 또는 G0~G6 완료를 뜻하지 않는다.

## IMPL-565: 영속 부모 세션 색인의 Windows 식별 정보

- 부모 세션 discovery의 directory/file stamp와 partial head에 native ID·size·정밀 수정 시각 snapshot을 선택적 Codable 필드로 추가했다. 폴더 부재는 별도 `windowsObservedMissing`으로 표시한다. 과거 필드 없는 payload는 decode할 수 있지만 Windows 재사용 증거로 인정하지 않는다. DDL은 바꾸지 않고 기존 discovery JSON payload 경로를 사용한다.
- Windows 폴더 유효성 판단은 snapshot 전체 또는 명시적으로 저장한 부재를 대조한다. mtime/count만 있는 legacy stamp와 generation은 새 탐색으로 전환한다. 음수/범위 밖 validation cursor도 새 탐색으로 돌린다. `windows-v2:` 세대 키는 sorted-key JSON으로 root·폴더·파일 경로와 snapshot을 함께 해시하며 기존 문자열 합치기 세대와 구분한다.
- parent session ID → path 재사용은 해당 header를 읽을 때의 native snapshot을 요구한다. caller가 제공한 cachedSessionFiles는 후보 경로로만 사용한다. 실제 header parse가 없으면 새로 stat한 metadata만으로 오래된 ID에 새 snapshot을 붙이지 않으며, 기존의 head-proven mapping이 맞을 때만 유지한다. 파싱된 ID와 전달된 ID가 일치하는 전체/초기 증분 parser 결과를 `remember`에 연결했다.
- 기존 mapping의 교체/축소/같은 크기 정밀 시각 변경/부재가 관측되면 해당 ID를 반환하지 않고, 알려진 후보와 폴더를 기존 budget 경로에서 다시 탐색한다. 같은 경로에 남은 다른 ID 연결도 header 결과를 기록하기 전에 제거한다. 헤더가 없는 파일을 오래된 ID로 다시 승인하지 않도록 작성했다.
- partial head에는 당시 native snapshot을 보관한다. ID/size/시각 또는 resume offset 범위가 맞지 않거나 과거 snapshot이 없으면 buffer/offset을 재사용하지 않고 처음부터 읽는다. reader에는 metadata 단계의 같은 expectedFile을 넘긴다. 같은 파일의 append-compatible metadata는 기존 prefix/offset 유지 정책을 따른다.
- negative lookup은 폴더 대조 뒤 이미 읽은 파일도 정확한 snapshot으로 다시 대조한다. 폴더 mtime이 그대로인 파일 append/rewrite 때문에 이전 missing 결과를 그대로 반환하지 않도록 연결했다. `validationFileIndex`로 파일 대조 진행을 저장해 기존 byte/time admission으로 다음 호출에서 재개한다. 오류/취소 때 admission을 정산하고 결과를 성공으로 바꾸지 않는다.
- `WindowsCostSessionIdentityTests.swift`에 같은 시각 폴더 교체, 같은 크기/시각 파일 교체, caller/cached ID의 무근거 연결 거부, partial head 교체, 폴더 시각이 그대로인 append, legacy JSON migration과 작은 budget의 파일 대조 재개용 합성 source를 작성했다. JSON producer/consumer round-trip 코드를 포함하지만 **컴파일·실행하지 않았다.**
- 이 필드는 부모 session discovery에 추가한 것이다. 일반 usage-cache의 과거 정밀 시각/prefix, main lookback의 모든 완료 폴더 세대, junction cycle/alias는 별도 연결이 남는다. 여러 호출에 나뉜 inventory 대조가 하나의 FS snapshot이 되지는 않는다. 같은 native ID를 유지한 prefix 재작성/재성장과 append 중 과거 header 변경은 내용 해시 또는 immutable source 결합 없이는 모두 검출하지 못한다.
- 전체 metadata I/O·tree 재탐색 비용과 실제 Windows SDK/파일 시스템 동작은 미측정·미검증이다. 전체 W06/W01~W16/G0~G6 완료가 아니다.

## IMPL-566: 사용량 캐시의 native source와 전체 prefix 재사용

- `CostUsageFileUsage`에 `codexWindowsSource`와 `codexWindowsContentGeneration`을 추가했다. 기존 JSON Codable과 SQLite file details에 선택 필드로 저장·복원하므로 별도 DDL 변경은 없다. 과거 payload는 필드 없는 상태로 읽히며 Windows reuse/append 증거로 사용할 수 없다. pricing/row filtering은 원본의 두 필드를 보존한다.
- native snapshot은 ID·size·초/나노초 수정 시각을 보존하며 cache/model metadata의 ID/size도 함께 대조한다. fresh reuse는 정확한 일치, append/resume는 같은 ID의 성장 또는 정확히 같은 snapshot을 요구한다. 같은 millisecond 안의 write-time 변경도 동일한 파일로 간주하지 않는다.
- Windows `codexTokenIndexAnchor`는 `windowStart = 0`부터 committed offset까지 SHA-256을 계산한다. 기존 `windowStart > 0` tail anchor는 대조 전에 거부한다. 64 KiB씩 읽으므로 전체 파일을 메모리에 올리지 않으며 각 chunk 사이 Task/custom 취소와 native handle/path 관측을 수행한다. 비Windows anchor 범위는 기존대로 유지한다.
- report timer의 cache source 확인, fresh reuse, append/partial/frozen/buffered retry, parent token snapshot, logical-target 완료 및 persisted completion 대조에 연결했다. 부모 의존성 키는 정밀 시각과 전체 관측 길이의 digest를 포함하여 같은 길이/시각의 부모 재작성도 자식의 재계산을 요청한다. native/hash 실패로 key를 만들 수 없으면 throw한다.
- full rescan에서 이전 native source와 prefix가 일치하지 않으면 이전 session/project/lineage 및 scan window 밖의 days/costs/tokens/rows를 새 파싱 결과에 섞지 않는다. 기존 global day 기여분은 파싱 성공 뒤 차감한다. full rescan에는 새 content generation을 부여하고 검증된 append에는 기존 generation을 유지한다.
- SQLite `persistFile`은 full rescan의 generation 변경을 row/token snapshot 교체 사유로 처리한다. 같은 parsed offset와 같은 개수만 보고 이전 row 또는 token snapshot을 재사용하던 경로를 분리했다. 이 generation은 실제 filesystem version 번호가 아니라 parser 작업 계보이며 append-only 증거는 native snapshot과 prefix hash가 담당한다.
- `WindowsCostUsageSourceTests.swift`에 정밀 시각·prefix 밖 재작성·append·legacy decode·취소·SQLite producer/consumer와 동일 개수 교체·전체 scanner의 session/history 분리 코드를 작성했다. 기존 discovery fixture의 trusted cache에도 새 evidence를 넣었다. **컴파일·테스트·fixture 실행은 하지 않았다.**
- 전체 prefix hash는 별도 파일 읽기다. parser가 소비한 바이트 자체의 digest를 저장하거나 최종 SQLite COMMIT에서 같은 내용 버전을 다시 보장하는 구현은 아직 아니다. metadata가 원상 복구되는 동시 재작성이나 parsing/hash 사이의 내용 변경까지 검출했다고 주장하지 않는다. parent head discovery의 자체 identity 증거에도 별도 content 결합이 남는다.
- chunk 크기는 메모리 제한이며 전체 I/O/시간 예산은 아니다. 현재 여러 재사용/진행 계산 경로에서 prefix를 다시 읽을 수 있다. 반복 hash의 공유·durable resumable validation과 scan budget 정산, 대형 파일 성능 검증은 후속 필수 작업이다. 기존 pending 상태의 과거 보고서 제공 정책과 이후 변경 관측 한계도 유지한다.

## IMPL-567: parser 소비 바이트와 게시 시점의 내용 대조

- JSONL scanner는 선택적인 Windows content capture를 지원한다. `WindowsCostContentRead`는 같은 FileHandle에서 읽어 parser에 넘긴 Data chunk를 누적하며, read offset/마지막 완결 줄 offset에 대응하는 두 hash state를 유지한다. 모든 줄마다 새 전체 hash를 계산하지 않는다.
- partial JSON resume는 열린 handle의 0..startOffset을 읽어 기존 prefix hash와 비교한 뒤 parsing을 시작한다. snapshot/offset/anchor 불일치와 읽기 오류는 throw하며 cached JSON prefix/누적 token state를 성공 결과로 반환하지 않는다. 이 선행 prefix I/O는 아직 scan budget으로 분할 재개하지 않는다.
- 전체 Codex parser는 `windowsReadAnchor`를 반환한다. 관측 tail이 미완성 JSON이라 마지막 완결 줄로 parsedBytes/target을 되돌리면 committed anchor를 선택한다. Windows cache 생성은 이 digest만 사용하며 parser 반환 뒤 별도 파일 읽기로 새 hash를 붙이지 않는다.
- 본문 앞의 session metadata 읽기도 실제 소비한 chunk의 auxiliary anchor를 반환한다. 부분 수집에서는 이 범위가 parsedBytes보다 길 수 있으므로 별도로 유지한다. usage-cache/SQLite details의 `codexWindowsReadProofVersion = 1`과 auxiliary anchors를 encode/decode하며, 기존 필드 없는 IMPL-566 이전/동일 형태 자료는 Windows 재사용 증거가 없는 것으로 보고 재파싱한다.
- cached fresh/증분/history 재사용은 기본 prefix와 auxiliary anchors를 모두 대조한다. full rescan/append의 메타데이터 지문은 offset별로 병합하며 같은 offset의 서로 다른 hash는 오류다. row filtering과 SQLite round-trip은 proof version/auxiliary data를 보존한다.
- immutable publication entry는 관측 파일별 여러 prefix anchor를 보관한다. metadata 재관측이 content 증거를 덮어쓰지 않으며, 같은 길이의 상충 내용도 overwrite하지 않는다. 한 파일의 여러 길이는 오름차순 한 번의 순차 읽기로 대조하며 read guard와 Task/custom 취소를 유지한다.
- cache fresh/retained source, full/partial parser, 재사용하는 과거 history 및 부모 dependency-key hash를 publication ledger에 연결했다. 기존 저장 전/COMMIT 직전/반환 직전 검사가 이제 연결된 prefix 내용도 대조한다. observed content 실패는 기존 sourceValidationFailed/rollback 경로를 따른다. 빈 source와 directory/missing 관측은 기존 metadata 정책을 유지한다.
- `WindowsCostContentReadTests.swift`에 같은 size/mtime 재작성에도 parser digest가 실제 옛 Data를 보존하는 경우, partial line/같은 handle 재개·변경된 prefix 거부, EOF rollback, metadata의 추가 관측 범위, 다중 지문 및 changed/identical SQLite 저장 직전 rewrite 시나리오를 작성했다. 기존 usage source fixture에 proof version과 auxiliary SQLite 복원 항목을 추가했다. **컴파일·실행·검증은 하지 않았다.**
- 내용 대조가 끝난 뒤 writer가 다시 변경할 수 있으며, 여러 파일의 일관된 immutable snapshot이나 writer 차단을 제공하지 않는다. source를 안정적으로 잠그거나 버전 snapshot으로 고정한 구현이 아니다. 같은 호출의 연결된 읽기 증거를 최종 경계에서 비교하는 계약이다.
- 전체 I/O/벽시계 예산과 대규모 prefix 재개의 durable state는 남는다. 같은 entry 안의 여러 anchor는 한 pass로 묶었지만 scanner의 서로 다른 재사용/완료/저장 경계는 여전히 반복 읽을 수 있다. parent session discovery head의 자체 proof·Claude/다른 비용 source·전체 Windows 실행/성능 검증도 후속 필수 작업이다.

## 남은 연결

1. 비페이지/legacy·부모 세션 index/캐시 부재 오류 전달은 IMPL-562에 작성했다. 대규모 재귀/단일 폴더의 bounded/pause/resume 통합, IMPL-565에서 parent discovery의 native directory/file snapshot과 legacy 재탐색을 작성했다. main lookback의 완료 폴더 세대와 junction cycle/alias 처리는 남는다. 실행 증거는 없다.
2. IMPL-561은 expected-file/열린 stream, IMPL-563~564는 게시 직전 metadata, IMPL-566은 usage native snapshot/전체 prefix, IMPL-567은 Codex parser 실제 바이트·선행 metadata·게시 경계의 내용 비교를 작성했다. 아직 immutable multi-file snapshot, 관측 뒤 재작성, Claude 이전 prefix와 기타 source, parent head 자체의 내용 결합 및 이전 호출의 전체 directory 세대가 남는다. hashing의 전체 I/O 예산·durable resume·경계 간 반복 읽기 공유도 후속 작업이다.
3. 날짜/flat/legacy 루트, hard link/junction, case-sensitive NTFS, UNC/SMB, ReFS/FAT, 삭제 후 재생성, 장기 resume 및 모든 비용 source와의 통합. 파일 ID의 파일 시스템별 재사용·불안정성도 포함한다.
4. 실제 Windows SDK 컴파일, x64/ARM64, native UI와 설치된 제품에서의 비용 표시, full WinUI3 제품 그래프 및 배포 준비.

## 작성했지만 실행하지 않은 회귀 fixture

`TestsLinux/WindowsCostFileIOTests.swift`는 기존 cross-platform test target 안에서 Windows에만 포함되도록 작성했다. 임시 합성 폴더만 사용하도록 구성했으며 지금 실행한 작업은 없다.

- 같은 크기/mtime의 교체 파일 구별, 원본을 다른 이름으로 보존한 상태의 rename ID 안정성, 열린 stream/path ID 일치.
- 한글 파일명·여러 next 호출·폴더와 파일 구별·정상 끝·없는 경로·regular 파일 요구.
- 두 번째 Claude cache가 실제 새 바이트를 게시하는지, 게시 직전 취소가 기존 바이트와 stamp를 유지하는지.

페이지 registry의 재시작/eviction, 공유/ACL 오류 및 concurrent writer를 실제 재현한 결과는 없다. 빌드·테스트·lint·formatter·compiler/manifest 평가·원격 Windows·CI·실계정 접근을 실행하지 않았다.

## API 근거

- [FILE_ID_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_info): volume과 128-bit file ID 결합.
- [GetFileInformationByHandleEx](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getfileinformationbyhandleex): handle 기반 정보 class/구조체 계약.
- [FindFirstFileW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-findfirstfilew): 비정렬 열거, 첫 결과/FindClose 수명, 검색 및 경로 오류 조건.

공식 API 문서는 구현 설계 근거다. 이 저장소 코드의 실제 동작 증거로 사용하지 않는다.
