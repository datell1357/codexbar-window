#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render readable planning tables from the pinned source and surface inventory."""
import json,re,subprocess
from pathlib import Path
from collections import defaultdict,Counter
out=Path('docs/windows-port')
d=json.loads((out/'FEATURE-CONTRACTS-2026-09-12.json').read_text());base=d['baseline'];groups=d['features'];obs=[json.loads(x) for x in (out/'SURFACE-OBLIGATIONS-2026-09-12.jsonl').read_text().splitlines()]
def source(p):return subprocess.check_output(['git','show',base+':'+p],text=True)
def clean(s):return s.replace('|','\\|').replace('\n',' ').replace('\r',' ')
s=['# Windows 필수 기능 계약 — 전수 표면 감사 개정','',f'원본 `{base}` 기준 **{len(groups)}개 기능군**. 원본 출시 기능, 내부 API, 디버그 도구를 구분한다. 실제 구현 및 Windows 실행 완료를 뜻하지 않는다.','', '[3차 검토](TERTIARY-AUDIT-2026-09-12.ko.md), [행동 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md), [2차 감사와 조치](SECONDARY-AUDIT-2026-09-12.ko.md), [1차 감사](FULL-COVERAGE-AUDIT-2026-09-12.ko.md), [설정](SETTINGS-COVERAGE-2026-09-12.ko.md), [CLI](CLI-COVERAGE-2026-09-12.ko.md), [공급자](PROVIDER-MATRIX-2026-09-12.ko.md), `SURFACE-OBLIGATIONS-2026-09-12.jsonl`, `FILE-COVERAGE-2026-09-12.tsv`가 상세 계약이다.','', '| ID | 기능/원본 범위 | 원본 근거 | Windows 목적지 | 수락 조건 |','|---|---|---|---|---|']
for g in groups:s.append(f"| {g['id']} | {g['area']} {g['feature']} ({g['source_scope']}) | `{g['baseline_paths'][0]}` | `{g['windows_destination']}` | {clean(g['acceptance'])} |")
s+=['','## 구현 작업자의 완료 기록','','각 source obligation의 ID·원본 blob/line에 Windows symbol·설정/default/error 대응·fixture 및 검증 로그를 연결한다. 행의 등록은 구현 완료가 아니다. 한 기능군의 모든 필수 source 계약과 플랫폼 결정이 종결돼야 그 기능군을 완료 처리한다. 동적/암묵적 동작이 추가로 발견되면 기존 ID를 유지하고 하위 항목을 추가한다. 파일 책임 분류 100%를 의미 검토나 제품 완성률로 바꾸지 않는다.']
(out/'FEATURE-CONTRACTS-2026-09-12.ko.md').write_text('\n'.join(s)+'\n')
# Settings state covers all 91 declared fields; storage/default expressions remain source-anchored.
state=[o for o in obs if o['category']=='settings_state'];init=source('Sources/CodexBar/SettingsStore.swift');defaults=source('Sources/CodexBar/SettingsStore+Defaults.swift')
s=['# 설정 전수 대응표','', '[행동 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)의 BC-005~010에 신규/기존/잘못된 값/동의/알림 defaults를 입력별로 고정했다.', '', '[추가 감사](SECONDARY-AUDIT-2026-09-12.ko.md)의 확장키·binding·typed snapshot·alias 계약을 함께 적용한다. 91개 state만으로 전체 provider 설정을 대체하지 않는다.', '',f'`SettingsDefaultsState`의 **{len(state)}개 필드 전부**와 저장/default 소스 위치를 연결했다. provider config 확장·동적 plugin schema는 별도 229개 config_property 및 provider_editor_id 계약에 포함한다. 필드 수는 UI 설정 개수와 다르다.','', '공통 수락: 원본 초기값·기존 설정 fallback·invalid 값·disabled/hidden 조건·write 실패·onChange refresh·재시작 복원을 유지한다. Raw 필드는 화면용 computed wrapper와 함께 이전한다. 표의 기본값 표현은 원본 코드 일부이며 복잡한 migration의 최종값을 실행 계산한 결과가 아니다.','', '| 필드 | 원본 초기화/기본값 근거 | Windows 처리 |','|---|---|---|']
for o in state:
 name=o['symbol'];m=re.search(r'\blet\s+'+re.escape(name)+r'\s*=',init)
 if m:
  block=init[m.start():];end=re.search(r'\n        (?:let|if|return)\b',block)
  excerpt=block[:end.start() if end else 240][:330];ref='SettingsStore.swift:'+str(init.count('\n',0,m.start())+1)
 else:
  m=re.search(r'\b'+re.escape(name)+r'\s*:',init);ref='SettingsStore.swift:'+str(init.count('\n',0,m.start())+1) if m else 'SettingsStoreState.swift:'+str(o['line']);excerpt=init[m.start():].split('\n')[0] if m else o['source_excerpt']
 policy='동일 의미의 Windows 설정/저장·관찰자'
 if 'Keychain' in name:policy='Windows credential 접근·동의 정책으로 대체; Keychain 구현은 배포 제외'
 elif name.startswith('iCloud'):policy='Sync/Fleet 동등 설정; 원본 iCloud 상호운용은 별도 G-SYNC gate'
 elif 'menuBar' in name or 'MenuBar' in name:policy='트레이/팝업/상시 패널 표시·geometry 설정으로 대응'
 elif name=='launchAtLogin':policy='Windows 자동 시작 opt-in 및 시작 상태 감지'
 elif name=='terminalAppRaw':policy='Windows terminal/editor 선택·focus capability'
 elif name.startswith('debug'):policy='Windows 진단 기능; macOS 전용 엔진/권한 항목은 대응 또는 명시된 개발 전용 범위'
 s.append(f'| `{name}` | `{ref}` — `{clean(excerpt)}` | {policy} |')
(out/'SETTINGS-COVERAGE-2026-09-12.ko.md').write_text('\n'.join(s)+'\n')
# Options are per declaration, not deduplicated across commands with different defaults.
commands={'UsageOptions':['usage'],'CardsOptions':['cards'],'GuardOptions':['guard'],'CostOptions':['cost'],'SessionsOptions':['sessions list (default)'],'SessionsFocusOptions':['sessions focus'],'ServeOptions':['serve'],'DashboardOptions':['dashboard'],'ConfigOptions':['config validate (default)','config providers'],'ConfigDumpOptions':['config dump'],'ConfigSetAPIKeyOptions':['config set-api-key'],'ConfigProviderToggleOptions':['config enable','config disable'],'CacheOptions':['cache clear (default)'],'CookieOptions':['cookie refresh (default)'],'DiagnoseOptions':['diagnose'],'HooksOptions':['hooks list (default)','hooks enable','hooks disable'],'HooksTestOptions':['hooks test'],'HooksWatchOptions':['hooks watch'],'PluginFetchOptions':['plugins fetch']}
options=defaultdict(list);contents={}
for o in obs:
 if o['category']!='cli_option':continue
 t=contents.setdefault(o['path'],source(o['path']));start=sum(len(x) for x in t.splitlines(keepends=True)[:o['line']-1]);types=list(re.finditer(r'struct\s+(\w+)\s*:\s*CommanderParsable',t[:start]));assert types,o
 typ=types[-1].group(1);assert typ in commands,typ
 names=re.findall(r'\.(long|short)\("([^"]+)"\)',o['source_excerpt']);labels=[('--' if a=='long' else '-')+b for a,b in names]
 if not labels:labels=['<'+o['symbol']+'>']
 options[typ].append((o,labels))
s=['# CLI/HTTP 전수 대응표','', '[행동 계약](BEHAVIOR-CONTRACTS-2026-09-12.ko.md)의 BC-011~017을 함께 적용한다. TOON usage-only와 guard 종료 코드/unknown 상태는 옵션 선언 외 필수 계약이다.', '', '원본 command registration과 dispatch를 대조했다. 30개 등록 노드는 parent/default를 포함하며 30개의 서로 다른 실행 명령이라는 뜻이 아니다. 아래 옵션은 **169개 선언**이며 공유 옵션이 명령별로 반복된다.','', '기본 진입은 usage, sessions→list, config→validate, hooks→list, cache→clear, cookie→refresh, plugins→list. `plugins list`는 별도 옵션 struct가 없다. 전역 help/version과 기존 오류/종료 코드도 유지한다.','', '공통 수락: 옵션 이름/alias/형식/기본값/상호배타 조건·headless 여부·stdout/stderr·JSON-only·실패/취소·종료 코드. Mac 전용 help 문구는 Windows의 실제 capability에 맞춘다. `--allow-keychain-prompt`는 Mac Keychain API 자체가 아니라 대화형 credential 접근 허용 계약으로 명시적으로 이전/문서화하며 아무 효과 없는 성공 옵션으로 남기지 않는다.','']
for typ,cmd in commands.items():
 s+=['','## '+', '.join(cmd),'', '| 옵션 | 원본 선언·기본값 | 근거 |','|---|---|---|']
 for o,labels in options[typ]:
  declaration=o['source_excerpt'].splitlines()[-1].strip();s.append(f"| {', '.join('`'+x+'`' for x in labels)} | `{clean(declaration)}` | `{o['path']}:{o['line']}` |")
s+=['','## HTTP 및 replay','','HTTP: GET `/`, `/icons/<name>.svg`, `/health`, `/usage`, `/cost`, `/dashboard/v1/snapshot`. 정적 web UI/icon과 데이터 route 각각의 auth 경계·Host allowlist·method/path 거부·provider/detail/query 검증·cache TTL·강제 refresh/timeout·종료 drain을 유지한다. 실제 경로 선택은 CLIServeRouter와 CLI read request 함수를 근거로 한다.','', 'AdaptiveReplayCLI: `--json`, `--raw-wall-clock`, `--gap-grace`, `--policy` 및 help/input trace·종료 코드. adaptive/adaptive-activity/fixed-2m/5m/15m/30m/manual 정책과 source trace 의미를 유지한다. 개발/진단 도구로 분류하며 원본 GUI 설정과 혼동하지 않는다.']
(out/'CLI-COVERAGE-2026-09-12.ko.md').write_text('\n'.join(s)+'\n')
providers=json.loads((out/'PROVIDER-COVERAGE-2026-09-12.json').read_text())['providers']
s=['# 공급자 전수 대응표','', '[이차 감사](SECONDARY-AUDIT-2026-09-12.ko.md)에서 69개 Core/App 등록 chain과 조회 mode의 양방향 링크를 대조했다. 구현·실행 통과를 뜻하지 않는다.', '', '69개 provider ID, 163개 source mode 선언을 원본 descriptor와 공용 apiToken factory에서 추출했다. `auto`를 포함한 설정 모드 수이며 API endpoint나 성공 경로의 개수가 아니다. 모드 이름과 transport를 혼동하지 않는다: JetBrains의 cli 모드는 로컬 파일 조회일 수 있다.','', '각 행의 모든 모드에 app/CLI, 명시/auto, 선택 계정/ambient, org/region/workspace, 성공/0/nil/stale/auth 실패/권한/429/네트워크/파싱/timeout/cancel fixture를 적용한다. 원본상 불가능한 조합은 원본 거부 결과를 검증하며 새 지원으로 부풀리지 않는다. 상세 strategy/credential/provider UI 경로와 source evidence는 JSON에 있다. 비용 true는 capability 선언이며 실제 금액 가용성/표시 조건까지 같아야 한다.','', '| ID | 필수 source 모드 | token cost 선언 | 원본 descriptor |','|---|---|---|---|']
for r in providers:s.append(f"| {r['id']} | {', '.join(r['source_modes'])} | {'true' if r['supports_token_cost_declared'] else 'false'} | `{r['baseline_descriptors'][0]}` |")
s+=['','## 별도 확인한 조건부 분기','','- DeepSeek: API key가 있으면 auto API, 없으면 platform web; optional platform 데이터와 profile scope 포함.','- Doubao: 저장된 API/AK-SK가 있으면 auto API, 없으면 arkcli. 명시 CLI/API는 다른 계정의 인증으로 fallback하지 않는다.','- Antigravity: app-local/agy CLI/IDE-local/OAuth/offline을 구분; 선택 계정과 live local 계정 불일치는 OAuth 소유권 경로로 처리한다.','- Grok: CLI/web/OAuth와 local session/cost 경로를 구분한다. Groq도 API뿐 아니라 console web source를 포함한다.','- Codex/Claude: app와 CLI의 auto 순서·외부 credential 소유권·PAT/admin key·재인증 조건이 다르므로 하나의 fallback 목록으로 평준화하지 않는다.','- Kilo org, Notion workspace, z.ai team, Copilot budgets, OpenCode Go scoped auto, 지역별 MiniMax/Moonshot/Bedrock 등은 provider editor 및 planner 계약과 함께 구현한다.','- OpenRouter/xAI/Grok/Antigravity를 포함한 12개 token-cost 선언을 보존한다. 금액이 알려지지 않는 로컬 token history를 0달러라고 표시하지 않는다.']
(out/'PROVIDER-MATRIX-2026-09-12.ko.md').write_text('\n'.join(s)+'\n')
print('Rendered 72 feature groups, 91 state fields, 169 CLI declarations, 69 providers.')
