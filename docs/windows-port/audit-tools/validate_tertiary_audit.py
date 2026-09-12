#!/usr/bin/env python3
"""Validate behavior-plan evidence and original enum/DTO boundaries, without running Swift tests."""
import json,re,subprocess
from pathlib import Path
OUT=Path('docs/windows-port');BASE='928166f899471bbdcb72210641cdec91324d0154'
def source(path):return subprocess.check_output(['git','show',BASE+':'+path],text=True)
ob=[json.loads(l) for l in (OUT/'SURFACE-OBLIGATIONS-2026-09-12.jsonl').read_text().splitlines()]
choices={o['symbol'] for o in ob if o['category']=='enumerated_choice'}
def cases(path,name):
 t=source(path);a=re.search(r'\benum\s+'+re.escape(name)+r'\b[^\n{]*\{',t).end();b=t.find('\n    static ',a)
 if b<0:b=t.find('\n    var ',a)
 body=t[a:b if b>=0 else len(t)]
 return re.findall(r'^    case (\w+)',body,re.M)
wp='Sources/CodexBarWidget/CodexBarWidgetProvider.swift';bp='Sources/CodexBarWidget/BurnDownWidgetProvider.swift'
wpids=cases(wp,'ProviderChoice');assert len(wpids)==17
assert {f'ProviderChoice.{p}' for p in wpids}<=choices
assert cases(wp,'CompactMetric')==['credits','todayCost','last30DaysCost']
assert cases(bp,'BurnProviderChoice')==['codex','claude'] and cases(bp,'BurnWindowChoice')==['session','weekly']
provider_rows=json.loads((OUT/'PROVIDER-COVERAGE-2026-09-12.json').read_text())['providers']
assert 'widgetSelectable: Bool = true' in source('Sources/CodexBarCore/Providers/Providers.swift')
selectable=[]
for r in provider_rows:
 t=source(r['baseline_descriptors'][0]);value=re.search(r'widgetSelectable:\s*(true|false)',t)
 if value is None or value.group(1)=='true':selectable.append(r['id'])
assert set(selectable)==set(wpids)
widget_test=source('Tests/CodexBarTests/WidgetProviderChoiceTests.swift')
assert set(re.findall(r'^        "(\w+)": "',widget_test,re.M))==set(wpids)
bundle=source('Sources/CodexBarWidget/CodexBarWidgetBundle.swift');families={}
for m in re.finditer(r'struct (\w+Widget): Widget \{([\s\S]*?)(?=\nstruct |\nenum |\Z)',bundle):
 f=re.search(r'\.supportedFamilies\(\[([^]]+)\]',m.group(2));assert f,m.group(1)
 families[m.group(1)]=re.findall(r'\.(\w+)',f.group(1))
assert len(families)==6
layout=source('Sources/CodexBar/MenuBarLayout.swift');a=layout.index('enum MenuBarConditionalMetric:');b=layout.index('\n    var ',a)
metrics=re.findall(r'^    case (\w+)',layout[a:b],re.M);assert len(metrics)==18 and {f'MenuBarConditionalMetric.{m}' for m in metrics}<=choices
# Verify claimed source/DTO distinctions from fixed declarations, not model names.
spend=source('Sources/CodexBar/PreferencesSpendDashboardPane.swift');a=spend.index('struct SpendDashboardExportPayload:');b=spend.index('    static func make(',a)
serialized_fields=re.findall(r'\blet (\w+):',spend[a:b]);assert not {'sessions','projects'}&set(serialized_fields)
assert {'requestedDays','selectedDay','groups','hiddenSourceIDs','providers','models'}<=set(serialized_fields)
remote=source('Sources/CodexBarCore/RemoteSessionFetcher.swift');assert 'operatingSystem == "macOS" || operatingSystem == "linux"' in remote
assert 'host, "sh", "-lc"' in remote and '/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI' in remote
out=source('Sources/CodexBarCLI/CLIOutputPreferences.swift');assert 'return first == "usage"' in out and 'allowsToon: Bool = false' in out and 'values.options["format"]?.last' in out
cg=source('Sources/CodexBarCLI/CLIGuardCommand.swift');assert 'remainingPercent >= minimumRemainingPercent' in cg and 'case unavailable = 69' in cg and 'isSyntheticPlaceholder' in cg
assert 'case usage = 64' in source('Sources/CodexBarCLI/CLIExitCode.swift')
settings=source('Sources/CodexBar/SettingsStore.swift');assert 'rawValue == nil && !hadPreviousInstallationState ? .adaptive : .fiveMinutes' in settings
contracts=json.loads((OUT/'BEHAVIOR-CONTRACTS-2026-09-12.json').read_text())['contracts'];assert len(contracts)==len({r['id'] for r in contracts})==25
gids={g['id'] for g in json.loads((OUT/'FEATURE-CONTRACTS-2026-09-12.json').read_text())['features']}
group_rows=json.loads((OUT/'FEATURE-CONTRACTS-2026-09-12.json').read_text())['features']
for g in group_rows:
 assert set(g['behavior_contract_ids'])=={r['id'] for r in contracts if r['group']==g['id']}
for r in contracts:
 assert r['group'] in gids and r['expected'] and r['input']
 ev=r['source'];t=source(ev['path']);assert t.splitlines()[ev['line']-1].find(ev['anchor'])>=0
 assert ev['blob']==subprocess.check_output(['git','rev-parse',BASE+':'+ev['path']],text=True).strip()
 if r['test_source']:subprocess.run(['git','cat-file','-e',BASE+':'+r['test_source']],check=True)
 assert r['execution']=='NOT_RUN'
report=dict(baseline=BASE,status='PASS_DEFINED_SOURCE_AND_PLAN_CHECKS',widget_provider_ids=wpids,widget_families=families,
 conditional_metrics=metrics,enumerated_choice_rows=sum(o['category']=='enumerated_choice' for o in ob),behavior_contract_count=len(contracts),
 spend_export_fields=sorted(set(serialized_fields)),windows_remote_adaptation_required=True,execution='NOT_RUN',all_files_semantically_verified=False)
(OUT/'TERTIARY-AUDIT-2026-09-12.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
s=['# 입력·예상 결과 기반 구현 계약','', '3차 소스 대조에서 보강한 25개 사례다. Python 검사는 원본 anchor/blob과 선언을 대조할 뿐 아래 동작을 실행한 테스트가 아니다. Windows 구현 후 해당 fixture와 실제 동작 증거를 연결해야 한다.','', '| ID / 기능군 | 상황 | 기대 결과 | 근거 |','|---|---|---|---|']
for r in contracts:
 s.append(f"| {r['id']} / {r['group']} | {r['title']}: {r['input']} | {r['expected']} | `{r['source']['path']}:{r['source']['line']}` |")
(OUT/'BEHAVIOR-CONTRACTS-2026-09-12.ko.md').write_text('\n'.join(s)+'\n')
print('PASS: 17 widget choices match descriptor defaults and source test literal; 6 widget families; 18 conditional metrics; usage-only TOON/guard codes/default branches/export DTO/remote OS boundary; 25 source-anchored behavior plans. No project code or tests executed.')
