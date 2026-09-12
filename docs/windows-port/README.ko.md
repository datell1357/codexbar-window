# Windows 전용 제품 계획과 작업 기록

현재 구현은 [IMPLEMENTATION-LOG](IMPLEMENTATION-LOG.ko.md)에서 이어간다. 2026-09-12 사용자가 구현과 30분 진행 보고/계속 루틴을 승인했다. 각 구현 묶음은 관련 기록과 함께 커밋·푸시하고 30분 보고에 게시 결과를 포함한다. macOS에서는 검증을 실행하지 않는다. 계획·감사 문서의 과거 검증 기록과 새 미검증 구현을 구분한다.

현재 계획은 [2026-09-12 Windows 전용 개정](WINDOWS-PORT-PLAN.ko.md)이다. **Mac에서 제공되는 기능 중 Windows에서 구현 가능한 기능 전부**가 필수 범위다. Mac/Linux 제품 유지 자체는 목표에서 제외했다. Swift 공용 로직 재사용과 Mac 전용 host 제거는 별개의 판단이다.

- [3차 검토와 조치 — 현재](TERTIARY-AUDIT-2026-09-12.ko.md) / [행동 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)
- [2차 전수 대조와 조치](SECONDARY-AUDIT-2026-09-12.ko.md)
- [1차 전수 표면 감사와 누락 수정](FULL-COVERAGE-AUDIT-2026-09-12.ko.md)
- [설정 대응표](SETTINGS-COVERAGE-2026-09-12.ko.md) / [CLI 대응표](CLI-COVERAGE-2026-09-12.ko.md) / [공급자 대응표](PROVIDER-MATRIX-2026-09-12.ko.md)
- [원본 소스 분석과 실현 가능성](SOURCE-ANALYSIS-2026-09-12.ko.md)
- [72개 필수 기능군과 수락 조건](FEATURE-CONTRACTS-2026-09-12.ko.md)
- [69개 공급자 코드 추적](PROVIDER-COVERAGE-2026-09-12.json)
- [원본 파일/blob 인벤토리](SOURCE-INVENTORY-2026-09-12.tsv)
- [현재 구현 현황](WORKSTREAM-STATUS.ko.md)
- [상태 데이터](IMPLEMENTATION-STATE.json)

72개 기능군과 원본 2,844개 항목의 계획 책임을 연결하고 확인된 누락을 수정했다. 2차 감사에서 optional/generic schema·역참조·동적 설정을 추가 보완했다. 이는 지정된 추출 범주에 대한 대조이며 모든 의미/암묵적 경로의 검증이나 제품 완성률을 뜻하지 않는다. 구현·빌드·실계정·배포 완료는 별도다. 이번 개정에서는 문서만 수정했고 컴파일러/빌드/테스트/앱 실행, 자동화 변경, commit/push는 하지 않았다.

## 이전 작업 기록 — 당시 승인·경로·자동화 설명

다음 내용은 과거 작업 이력이며 이번 작업의 자동 실행 또는 게시 승인을 뜻하지 않는다.

# Windows 이식 작업 기록

작업 대상: https://github.com/datell1357/codexbar-window
원본 기준: steipete/CodexBar commit 928166f899471bbdcb72210641cdec91324d0154.

전체 기능 이식 진행 중이며 실행 가능한 Windows 제품 완료를 뜻하지 않는다. 현재는 macOS에서 코드 비교만 수행하며 빌드·컴파일·테스트·앱·실계정·성능 검증은 하지 않는다. 사용자 요청에 따라 이 저장소의 GitHub Actions도 비활성화했다.

사용자는 각 작업 단계의 commit/push를 승인했다. 짧은 명령형 제목, 관련 파일만 포함하는 커밋, 검토 범위와 미완료 항목을 본문에 기록한다. 기존 이력을 보존하며 강제 push하지 않는다. 원본 포크 origin에는 push하지 않는다.

10분 루틴은 구현 후 전체 원본과 독립 정적 QA를 반복한다. 부족하면 보완하고 모든 필수 정적 항목이 종결되어야 코드 기준 완료로 판정한다. 실제 Windows 동작 검증은 별도다.

이 폴더는 작업 공간 analysis/fork-parity의 계획·진행·정적 QA 기록을 단계별로 복사한 공유본이다.
