# Windows 비용 파일 I/O 구현 경계

IMPL-559~560. 상태: **CODE_WRITTEN_UNVERIFIED / NOT_RUN_BY_USER_INSTRUCTION**.
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

## 남은 연결

1. Codex 비페이지/legacy Foundation 열거 경로의 부재·권한 오류 구분과 재귀 수집의 bounded/pause/resume 통합. Claude inventory 오류 전달은 IMPL-560에 작성했으며 실행 증거는 없다.
2. parser의 expected file ID와 열린 stream ID 결합, 수집 중 replace/truncate/동일 크기 재작성, 읽기 완료 후 게시 시점의 변경 처리. 메타데이터만으로 같은 ID의 내용 변경 전체를 증명할 수 없다.
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
