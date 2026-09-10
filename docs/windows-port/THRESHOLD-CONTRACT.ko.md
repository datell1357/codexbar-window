# 임계값 알림 계약117

기준 928166f899471bbdcb72210641cdec91324d0154 UsageStore+QuotaWarnings.swift 및 SessionQuotaNotifications.swift를 정적 대조했다.

키는 공급자·session/weekly·계정 discriminator·extra window ID다. 상태는 이전 잔여량·발화 threshold 집합·Antigravity source다. 최초 저잔여 관측도 가장 낮은 임계값 하나를 알린다. 선택 threshold 이상을 발화 처리하며 잔여량 회복 시 해당 threshold를 재활성화한다. reset 날짜는 dedupe 키가 아니다. source 전환은 무알림 baseline이다. missing window는 정확한 키 제거, synthetic은 상태 보존이다.

일반 lane은 primary/secondary다. 소진 알림의 6시간 제한/Copilot fallback을 재사용하면 안 된다. MiMo/Qoder·Crof balance-only 제외, Antigravity5h/7d 최대 사용량·summary/legacy, Amp 동적 라벨, Claude 알려진 scoped weekly/routines extras 예외를 보존한다. extras가 비어 있으면 이전 extra 상태를 유지하고, 알려진 extras가 하나 이상 있으면 같은 계정의 사라진 extra ID만 정리한다.

master 기본 false, session/weekly 기본 true, threshold 기본[50,20]. Core 설정 정규화를 재사용한다. provider override 우선이며 threshold 명시 시 enabled 미지정은 활성화다. global off는 상태 보존, lane off는 해당 provider/lane 모든 계정 상태 제거다. token-account:<lowercase UUID> 식별자가 우선이다. Codex owner·Claude OAuth/CLI owner와 표시 이름은 별도 계약이다.

118은 순수 Core,119는 설정 스냅샷만 작성한다. 현재 Windows 전달 경로는 session 설정으로 차단되므로 임계값 알림을 그대로 보내면 안 된다. 이후 runtime과 별도 preference envelope 연결·독립 검토가 필요하다. 예측·소리·overlay·hooks·현지화는 후속이며 전체 알림 완료로 세지 않는다. 빌드·테스트·실행 검증 없음.
