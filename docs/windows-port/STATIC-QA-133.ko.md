# 공급자별 임계값 편집 모델 — 정적 재검토 중

기준 원본: `928166f899471bbdcb72210641cdec91324d0154`.

대상: `Sources/CodexBarWindows/WindowsProviderQuotaWarningDraft.swift`.
대조: `QuotaWarningSettingsViews.swift`의 overrideModeBinding 및 `SettingsStore+Config.swift`의 임계값 setter.

최초 초안은 최초 모드와 최종 모드만 비교해 Custom → Global → Custom에서 지운 임계값을 복원하는 문제가 있었다. 현재 초안은 선택마다 임시 설정을 변경하며 Global에서 명시값을 지운다. Off의 숨겨진 값, 전역값 상속, 정규화, 변경 없는 저장 생략을 별도로 유지한다.

독립 리뷰133 재검토 진행 중이다. 저장 경로와 네이티브 UI에 아직 연결하지 않았으며 기능 완료로 집계하지 않는다. 저장 직전 최신 설정 병합 및 갱신 중인 snapshot과의 충돌은 계약134에서 검토한다.

빌드·테스트·컴파일러·앱·계정 접근 및 Windows 실행은 하지 않았다.

## 최종 정적 판정

리뷰133 재검토 APPROVE. 순차 전이, 상속값 유지, Off 숨김값 보존, 변경 없는 패치 생략을 코드로 대조했다. 승인 범위는 이 값 모델 파일이며 저장/UI 연결 및 전체 기능 완료 승인이 아니다.
