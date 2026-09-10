# 임계값 기반 코드118/119 검토120

현재 REQUEST CHANGES. lane off가 상태를 제거해야 하는데 baseline을 생성했고, Antigravity legacy lane이 원본의 primary/secondary/tertiary 전체 duration 필터 및 최대 사용량 선택을 누락했다. summary 존재 판정과 known 여부도 별개로 유지해야 한다. Amp 라벨은 현재 문자열이 같지만 공개 provider helper를 재사용한다. 구현118에 수정 전달. 설정119의 key/default/sanitize/provider override 우선순위는 해당 범위 차단 사항 없음.

runtime 전달은 미연결이다. 빌드·테스트·컴파일러·실행 검증 없음. 수정 재검토 전 게시하지 않는다.

## 수정 후 재검토120 — APPROVE(해당 범위)

lane disabled 선행 nil state 반환, Antigravity summary 존재/known 분리와 legacy 세 창 duration/max 선택, Amp helper 재사용을 수정 후 독립 대조했다. 설정119와 새 Core118 범위의 추가 차단 사항 없음. 런타임은 아직 미연결이며 임계값 기능 전체 완료가 아니다. 실행 검증 없음.
