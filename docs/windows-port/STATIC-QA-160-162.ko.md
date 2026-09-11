# 예측 소유권·설정·원시 창 정적 검토

160·162 정적 검토 완료. Codex 계정 ID는 이메일 없이 canonical key를 만들고, 이메일 fallback은 정규화 후 Crypto SHA256을 사용한다. Claude는 token UUID, 안정된 discriminator, snapshot 이메일 순서다. 이메일 fallback 금지라는 최초 지적은 원본 PredictivePaceWarnings의 명시적 fallback과 호출부를 대조한 뒤 철회했다.

설정은 false/nil/false 기본값과 원본 raw cast를 유지하며 쓰기를 하지 않는다. Codex 원시 창 wrapper는 기존 분류기만 사용하고 표시용 weekly cap을 적용하지 않는다.

Windows runtime 연결은163 진행 중이며 historical dataset과 원본 reconciler 전체는 아직 이식되지 않았다. 이 helper가 전체 동등성을 의미하지 않는다. 빌드·테스트·컴파일러·앱 실행 없음.
