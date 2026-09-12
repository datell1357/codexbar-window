#!/usr/bin/env python3
"""Independent read-only comparisons for gaps not caught by the first surface scanner.
Uses direct source declaration/registration checks, not build_surface_audit.masks.
Never evaluates Swift manifests, application code, plugins or live credentials.
"""
import json,re,subprocess
from pathlib import Path
from collections import defaultdict

OUT=Path('docs/windows-port')
BASE='928166f899471bbdcb72210641cdec91324d0154'
obs=[json.loads(l) for l in (OUT/'SURFACE-OBLIGATIONS-2026-09-12.jsonl').read_text().splitlines()]
providers=json.loads((OUT/'PROVIDER-COVERAGE-2026-09-12.json').read_text())['providers']
groups=json.loads((OUT/'FEATURE-CONTRACTS-2026-09-12.json').read_text())['features']
gids={g['id'] for g in groups}
entries=[]
for l in subprocess.check_output(['git','ls-tree','-r',BASE,'Sources'],text=True).splitlines():
 meta,path=l.split('\t',1)
 if path.endswith(('.swift','.js','.ts')):entries.append((path,meta.split()[-1]))
data=subprocess.run(['git','cat-file','--batch'],input=('\n'.join(b for p,b in entries)+'\n').encode(),stdout=subprocess.PIPE,check=True).stdout
pos=0;texts={}
for p,b in entries:
 end=data.index(b'\n',pos);n=int(data[pos:end].split()[-1]);pos=end+1;texts[p]=data[pos:pos+n].decode('utf-8',errors='replace');pos+=n+1
bycat=defaultdict(list)
for o in obs:bycat[o['category']].append(o)
for o in obs:assert o['feature_group'] in o['related_feature_groups'] and set(o['related_feature_groups'])<=gids
byid={o['id']:o for o in obs}
for p in providers:
 expected={o['id'] for o in bycat['provider_mode'] if o['symbol'].split(':')[0]==p['id']}
 assert expected and expected<=set(p['source_obligations']),('missing mode backlink',p['id'])
 actual={x for x in p['source_obligations'] if byid[x]['category']=='provider_mode'}
 assert actual==expected,('cross-provider mode backlink',p['id'])
 assert all(x in byid for x in p['source_obligations'])

core_manifest_path='Sources/CodexBarCore/Providers/ProviderManifest.swift'
app_manifest_path='Sources/CodexBar/Providers/Shared/ProviderImplementationManifest.swift'
core_refs=re.findall(r'^\s*(\w+ProviderDescriptor)\.descriptor,?\s*$',texts[core_manifest_path],re.M)
app_refs=re.findall(r'\{\s*(\w+ProviderImplementation)\(\)\s*\}',texts[app_manifest_path])
assert len(core_refs)==len(set(core_refs))==69 and len(app_refs)==len(set(app_refs))==69
core_ids={}
for p in providers:
 path=p['baseline_descriptors'][0]
 name=re.search(r'public enum (\w+ProviderDescriptor)',texts[path]).group(1)
 core_ids[name]=p['id']
assert set(core_refs)==set(core_ids)
app_ids={}
for name in app_refs:
 matching=[p for p,t in texts.items() if p.endswith('/'+name+'.swift') and re.search(r'struct\s+'+name+r'\b',t)]
 assert len(matching)==1,(name,matching)
 p=matching[0]
 match=re.search(r'\b(?:let|var)\s+id\s*:\s*UsageProvider\s*=\s*\.(\w+)',texts[p])
 assert match,(name,'unresolved id')
 app_ids[name]=match.group(1)
assert set(app_ids.values())==set(core_ids.values())=={p['id'] for p in providers}
registry_chain=[dict(provider_id=core_ids[name],core_registration=name,app_registration=next(a for a,v in app_ids.items() if v==core_ids[name])) for name in core_refs]

# Optional fields/generic methods need exact declaration-line obligations.
dts_path='Sources/CodexBarCore/Resources/Plugins/codexbar-plugin.d.ts'
dts=texts[dts_path]; declared={(n,o['symbol']) for o in bycat['plugin_api_schema'] if o['path']==dts_path for n in range(o['line'],o['end_line']+1)}
optional=[];generic=[]
for n,line in enumerate(dts.splitlines(),1):
 m=re.match(r'\s*(\w+)\?\s*:',line)
 if m:optional.append((n,m.group(1)))
 m=re.match(r'\s*(\w+)<[^>]+>\(',line)
 if m:generic.append((n,m.group(1)))
assert all(x in declared for x in optional+generic)
assert {o['symbol'] for o in bycat['plugin_entrypoint']}=={'defineProvider'}
assert any(o['symbol']=='nowMillis' for o in bycat['plugin_runtime_method'])
assert not re.search(r'\bnowMillis\s*\(',dts) # Known baseline mismatch, explicitly planned, not a parser omission.

extension_keys=defaultdict(lambda:{'read':False,'write':False,'paths':set()})
for p,t in texts.items():
 if not (p.startswith('Sources/CodexBarCore/Providers/') and p.endswith('ProviderConfig.swift')):continue
 for kind,pat in [('read',r'extensionValue\([^\n]*?forKey:\s*"([^"]+)"'),('write',r'setExtensionValue\([^\n]*?forKey:\s*"([^"]+)"')]:
  for m in re.finditer(pat,t):
   key=m.group(1);extension_keys[key][kind]=True;extension_keys[key]['paths'].add(p)
assert len(extension_keys)==14 and all(v['read'] and v['write'] for v in extension_keys.values())
assert set(extension_keys)=={o['symbol'] for o in bycat['provider_extension_key']}

alias_arrays=[]
for p,t in texts.items():
 if not p.startswith(('Sources/CodexBar/','Sources/CodexBarCore/')):continue
 for m in re.finditer(r'\b(?:let|var)\s+(\w*(?:Environment|environment|Env|env)\w*)\s*(?::[^=\n]+)?=\s*\[([^\]]*)\]',t):
  if t[t.rfind('\n',0,m.start())+1:m.start()].strip().startswith('//'):continue
  n=t.count('\n',0,m.start())+1
  alias_arrays.append((p,n,m.group(1)))
actual={(o['path'],o['line'],o['symbol']) for o in bycat['environment_alias_array']}
assert set(alias_arrays)<=actual
assert {'KIMI_AUTH_TOKEN'}<={o['symbol'] for o in bycat['environment_input']}
assert {'kimi_auth_token'}<={o['symbol'] for o in bycat['environment_lowercase_input']}

# Raw-line UI callback scan: different detection route from the lexical masker.
ui_missing=[]
for p,t in texts.items():
 if not p.startswith('Sources/CodexBar/'):continue
 for n,l in enumerate(t.splitlines(),1):
  if l.lstrip().startswith('//'):continue
  if re.search(r'\.(onChange|onTapGesture|onSubmit|onMove|onDelete|contextMenu|keyboardShortcut)\s*[({]',l):
   if not any(o['path']==p and o['line']==n for o in bycat['ui_event_binding']):ui_missing.append(dict(path=p,line=n))
assert not ui_missing
assert len(bycat['provider_runtime_action'])==2

result=dict(baseline=BASE,revision='2026-09-12-secondary-audit',status='PASS_DEFINED_CHECKS',
 registry_chain=registry_chain,provider_mode_backlinks_complete=69,other_provider_mode_backlinks=0,
 plugin_optional_declarations_covered=len(optional),plugin_generic_methods_covered=len(generic),
 plugin_schema_rows=len(bycat['plugin_api_schema']),provider_extension_keys=[dict(key=k,paths=sorted(v['paths'])) for k,v in sorted(extension_keys.items())],
 environment_alias_arrays_covered=len(alias_arrays),unmapped_raw_ui_event_lines=ui_missing,
 known_baseline_contract_discrepancies=[dict(id='SA-04',item='ctx.date.nowMillis exists in prelude but not d.ts',plan_group='WIN-047',resolution='Preserve runtime behavior; align Windows shipped authoring types during implementation; do not claim source bug fixed here')],
 feature_groups=len(groups),obligation_count=len(obs),all_files_semantically_verified=False,windows_execution='NOT_RUN')
(OUT/'SECONDARY-AUDIT-2026-09-12.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('PASS: 69 enum/core/app registration chains; 69 complete mode backlinks; '+str(len(optional))+' optional schema fields/'+str(len(generic))+' generic methods; 14 paired extension keys; '+str(len(alias_arrays))+' alias arrays; raw UI callback cross-check. Known original nowMillis declaration gap remains a planned implementation item.')
