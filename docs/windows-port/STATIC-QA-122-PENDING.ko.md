# 임계값 연결122/123 — 상위 검토 REJECT

122가 기존 세션 알림을 추가가 아닌 교체로 변경하여 공개 API/state/evaluation이 제거됐다. 게시하지 않았다. 별도 작업자124에게 HEAD 세션 동작 보존 + 독립 threshold 추가로 수정을 배정했다.

추가 결함: fetchRows의 config 전달 미연결, optional providerConfig 해제, dictionary removeValue 라벨, weekly 비활성 extras 평가, 타 계정 extras prune, Claude 실제 fetch 전략/전후 identity/OAuth fallback 누락, 일반 공급자의 임의 account fallback. payload 문구도 원본과 대조 필요.125는 별도로 host/main만 검토한다.

빌드·테스트·실행하지 않음. 통합본은 완료 또는 검토 승인 상태가 아니다.

## 修正124 후 중간 재대조

세션 알림 경로는 복구됐고 host125는 해당 범위 승인이다. 그러나 runtime에는 optional config 전달, removeValue 인자 라벨, fetchRows 호출 인자 순서, lane off의 전 계정 정리, Claude fetch 전후 identity 및 접두사 문제가 여전히 남는다.126 독립 검토를 배정했다.124의 수정 완료 보고를 기능 완료 증거로 사용하지 않는다. 현재 변경은 게시하지 않았다.

## 상위 직접 수정 후126 재검토 요청

optional config map/fallback, 인자 순서, forKey 라벨, provider/lane 전체 정리, 불필요한 no-op callback 제거를 적용했다. Claude는 실제 fetch 직전/성공 직후 accountUuid가 정규화 후 같고 비어 있지 않을 때만 v3 hash와 claude-account 접두사를 사용한다. OAuth owner fallback을 유지했다.126 재검토 대기. tray uID는 설치된 아이콘1이며 window dedupe는 runtime Core.Key에 보존된다. balloon 전달은 현대 toast와 동등성 미판정이다.

## 최종 재검토125/126 — 해당 범위 APPROVE

125 host와126 runtime 독립 정적 재검토에서 앞선 blocker 해결을 확인했다. session 채널은 보존되고 threshold는 별도 publisher/FIFO/master로 연결된다. config optional·인자 순서·dictionary 라벨·lane 전체 정리·Claude 전후 UUID 및 OAuth owner fallback을 대조했다.

임계값 알림 연결 범위만 승인한다. global lane/custom threshold 편집 UI, provider override UI, overlay/predictive/hooks/현지화와 현대 toast 동등성은 미완료다. 상태의 windowID 격리는 Core.Key에서 유지되며 native balloon은 설치된 tray icon ID를 사용한다. Windows 빌드·실행·전달·성능 검증 미실시.
