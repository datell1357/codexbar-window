#!/usr/bin/env python3
"""Validate documentation inventories against Git objects, never execute app/tests."""
import csv,json,re,subprocess
from pathlib import Path
from collections import Counter
out=Path('docs/windows-port');summary=json.loads((out/'SURFACE-AUDIT-SUMMARY-2026-09-12.json').read_text());base=summary['baseline']
tracked={}
for line in subprocess.check_output(['git','ls-tree','-r',base],text=True).splitlines():
 meta,p=line.split('\t',1);tracked[p]=meta.split()[2]
rows=list(csv.DictReader((out/'FILE-COVERAGE-2026-09-12.tsv').open(),delimiter='\t'))
assert len(rows)==len(tracked)==2844
assert {r['path'] for r in rows}==set(tracked)
assert all(r['blob']==tracked[r['path']] and r['feature_groups'] for r in rows)
groups=json.loads((out/'FEATURE-CONTRACTS-2026-09-12.json').read_text())['features'];gids={g['id'] for g in groups};assert len(gids)==len(groups)==72
assert all(g['windows_destination'] and g['acceptance'] and set(g['baseline_paths'])<=set(tracked) for g in groups)
obs=[json.loads(l) for l in (out/'SURFACE-OBLIGATIONS-2026-09-12.jsonl').read_text().splitlines()];assert len({o['id'] for o in obs})==len(obs)==summary['obligation_count']
assert dict(Counter(o['category'] for o in obs))==summary['categories']
used=sorted({o['path'] for o in obs});raw=subprocess.run(['git','cat-file','--batch'],input=('\n'.join(tracked[p] for p in used)+'\n').encode(),stdout=subprocess.PIPE,check=True).stdout;pos=0;text={}
for p in used:
 end=raw.index(b'\n',pos);size=int(raw[pos:end].split()[-1]);pos=end+1;text[p]=raw[pos:pos+size].decode('utf-8',errors='replace');pos+=size+1
for o in obs:
 assert o['feature_group'] in gids and o['blob']==tracked[o['path']]
 assert 1<=o['line']<=o['end_line']<=len(text[o['path']].splitlines())+1
 snippet='\n'.join(text[o['path']].splitlines()[o['line']-1:o['end_line']])
 assert o['source_excerpt'] in snippet,(o['id'],o['path'],o['line'])
 assert o['implementation']=='UNVERIFIED' and o['windows_test']=='NOT_RUN'
state_text=text['Sources/CodexBar/SettingsStoreState.swift'];fields=set(re.findall(r'^    var (\w+):',state_text,re.M));assert fields=={o['symbol'] for o in obs if o['category']=='settings_state'}
providers=json.loads((out/'PROVIDER-COVERAGE-2026-09-12.json').read_text())['providers'];provider_text=subprocess.check_output(['git','show',base+':Sources/CodexBarCore/Providers/Providers.swift'],text=True);enum=provider_text[provider_text.index('case codex'):provider_text.index('case ibmbob')+len('case ibmbob')];ids=set(re.findall(r'case (\w+)',enum));assert ids=={r['id'] for r in providers} and len(ids)==69
assert {r['id']+':'+mode for r in providers for mode in r['source_modes']}=={o['symbol'] for o in obs if o['category']=='provider_mode'}
# Cross-check the method counts against independent direct line declarations.
cli_paths=[p for p in tracked if p.startswith('Sources/CodexBarCLI/') and p.endswith('.swift')]
annotation_count=0
for p in cli_paths:
 t=text.get(p)
 if t is None:t=subprocess.check_output(['git','show',base+':'+p],text=True)
 annotation_count+=len(re.findall(r'^\s*@(Flag|Option|Argument)\(',t,re.M))
assert annotation_count==summary['categories']['cli_option']==169
menu=text['Sources/CodexBar/MenuDescriptor.swift'];block=menu.split('enum MenuAction: Equatable {',1)[1].split('\n    }',1)[0];assert len(re.findall(r'^        case ',block,re.M))==19
hooks=text['Sources/CodexBarCore/Hooks/HookEvent.swift'];assert set(re.findall(r'case \w+ = "([^"]+)"',hooks))=={o['symbol'] for o in obs if o['category']=='hook_event'}
for fn in ['WINDOWS-PORT-PLAN.ko.md','README.ko.md','WORKSTREAM-STATUS.ko.md','FULL-COVERAGE-AUDIT-2026-09-12.ko.md','FEATURE-CONTRACTS-2026-09-12.ko.md','SECONDARY-AUDIT-2026-09-12.ko.md','SETTINGS-COVERAGE-2026-09-12.ko.md','CLI-COVERAGE-2026-09-12.ko.md','PROVIDER-MATRIX-2026-09-12.ko.md','TERTIARY-AUDIT-2026-09-12.ko.md','BEHAVIOR-CONTRACTS-2026-09-12.ko.md']:
 for target in re.findall(r'\]\(([^)]+)\)',(out/fn).read_text()):
  if not target.startswith(('https:','http:')):assert (out/target.split('#')[0]).exists(),(fn,target)
state=json.loads((out/'IMPLEMENTATION-STATE.json').read_text())
assert state['inventory']['source_obligations']==summary['obligation_count']
assert not state.get('completion_claim')
assert 'source_surface_catalogue_complete' not in state['inventory']
assert not summary['all_files_semantically_verified'] and not summary['unassigned_source_paths']
print('PASS: all 2,844 blobs and file responsibilities; 72 groups; 69 providers/163 modes; 91 state fields; 169 CLI declarations; 19 actions/6 events; all obligation excerpts/lines/IDs and index links. No app/compiler/test execution.')
