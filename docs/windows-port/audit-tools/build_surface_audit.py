#!/usr/bin/env python3
"""Read the pinned git tree and generate planning evidence. Never runs project code.
Run from repository root: python3 docs/windows-port/audit-tools/build_surface_audit.py
A lexical inventory is NOT a compiler, call-graph proof, or runtime certification.
"""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
from collections import Counter, defaultdict

BASE = '928166f899471bbdcb72210641cdec91324d0154'
OUT = Path('docs/windows-port')
entries = []
for line in subprocess.check_output(['git', 'ls-tree', '-r', BASE], text=True).splitlines():
    meta, path = line.split('\t', 1)
    mode, kind, blob = meta.split()
    entries.append(dict(path=path, mode=mode, kind=kind, blob=blob))
text_suffixes = {'.swift', '.c', '.h', '.ts', '.js', '.json', '.md', '.sh', '.yml', '.yaml', '.strings', '.entitlements', '.plist', '.txt', '.modulemap'}
chosen = [e for e in entries if Path(e['path']).suffix in text_suffixes or e['path'] in ('Makefile', 'LICENSE', 'Package.resolved')]
raw = subprocess.run(['git', 'cat-file', '--batch'], input=('\n'.join(e['blob'] for e in chosen)+'\n').encode(), stdout=subprocess.PIPE, check=True).stdout
pos = 0
texts = {}
for e in chosen:
    end = raw.index(b'\n', pos)
    size = int(raw[pos:end].split()[-1])
    pos = end + 1
    texts[e['path']] = raw[pos:pos+size].decode('utf-8', errors='replace')
    pos += size + 1
blobs = {e['path']: e['blob'] for e in entries}
paths = set(blobs)
groups = json.loads((OUT/'FEATURE-CONTRACTS-2026-09-12.json').read_text())['features']
group_by_id = {g['id']: g for g in groups}
original_map = defaultdict(set)
for g in groups:
    for p in g['baseline_paths']:
        original_map[p].add(g['id'])

# Explicit responsibility rules supplement the previously sparse path lists.
# They classify planning responsibility, never mark a file semantically reviewed.
rules = [
 (r'InlineUsageDashboardContent', 'WIN-026'),
 (r'KeyboardShortcuts', 'WIN-011'),
 (r'SidebarResizeHandle', 'WIN-012'),
 (r'(?:CoreResourceSmoke|Generated/CodexParserHash)', 'WIN-071'),
 (r'CodexExecutableResolver', 'WIN-068'),
 (r'CodexManagedAccounts', 'WIN-004'),
 (r'CopilotUsageModels', 'WIN-064'),
 (r'Logging/', 'WIN-067'),
 (r'ProviderSessionStoreFile', 'WIN-068'),
 (r'AdaptiveReplay', 'WIN-067'), (r'AdaptiveRefresh', 'WIN-030'),
 (r'(?:CodexBarCore|CodexBar)/Providers/(?!Shared/)', 'WIN-001'),
 (r'CodexAccountPromotion', 'WIN-055'), (r'CodexResetCreditExpiry', 'WIN-058'),
 (r'OpenAICreditsPurchase', 'WIN-059'), (r'CodexModels', 'WIN-057'),
 (r'Codex(?:LocalProject|Thread|WorkspaceUsage|Workspaces|PriorityDatabase)', 'WIN-056'),
 (r'OpenCodex', 'WIN-061'), (r'ShareStats', 'WIN-070'),
 (r'(?:Sync/|Fleet|ConfigFileWatcher|SettingsStore\+Sync)', 'WIN-072'),
 (r'(?:CodexBarWidget|WidgetExtension|WidgetSnapshot)', 'WIN-039'),
 (r'CodexBarCLI/', 'WIN-043'), (r'CodexBarClaudeWatchdog', 'WIN-042'),
 (r'CodexBarClaudeWebProbe', 'WIN-028'), (r'CostStoreCrashProbe', 'WIN-023'),
 (r'(?:CQuickJS|Plugins/|UserPlugins|PluginsPane|Plugin)', 'WIN-047'),
 (r'(?:Hooks/|HooksPane|\+Hooks)', 'WIN-046'),
 (r'(?:Historical|HistoryOwnership|OwnershipContext|PlanUtilization|SessionEquivalent|UsagePace)', 'WIN-017'),
 (r'(?:Quota|LimitReset|Notifications|Confetti)', 'WIN-033'),
 (r'(?:Cost|Spend|CreditsHistory|UsageBreakdown|Chart|Currency)', 'WIN-021'),
 (r'(?:AgentSession|RemoteSession|PiFamilySession|SessionWindow|TerminalApp)', 'WIN-040'),
 (r'(?:ManagedCodex|CodexAccount|CodexHome|CodexLocalData|CodexConsumer|CodexReconciliation|TokenAccount|TokenStore|CookieStore)', 'WIN-004'),
 (r'(?:Login|Cookie|Browser|Keychain|Credential|CopilotToken)', 'WIN-063'),
 (r'(?:MenuBarLayout|MenuBarDisplay|MenuBarMetric)', 'WIN-009'),
 (r'(?:Menu|StatusItem|Icon|Switcher|ClickToCopy|DisplayLink|LoadingPattern|MouseLocation)', 'WIN-010'),
 (r'(?:Settings|Preferences|Config/|ProviderToggle|ProviderRegistry)', 'WIN-069'),
 (r'(?:Power|MemoryPressure|Refresh|ActivityConsent)', 'WIN-031'),
 (r'(?:OpenAIWeb|OpenAIDashboard|SubscriptionMetadata|WebKit)', 'WIN-028'),
 (r'(?:UsageStore|UsageFetcher|UsageSnapshot|UsagePercent|UsageFormatter|UsageProgress|RateWindow|CreditsModels|Provider.*Snapshot|ProviderDetailSection)', 'WIN-016'),
 (r'(?:Localiz|Accent|Brand|PersonalInfo|Redact|Resources/)', 'WIN-054'),
 (r'(?:Host/|Process|PathEnvironment|AppGroup|BoundedTask|Endpoint|HTTP|CoreResources|Autorelease|TextParsing|Double\+|CSQLite)', 'WIN-068'),
 (r'(?:CodexbarApp|AppDelegate|Launch|InstallOrigin|Update|Dock|HangWatchdog|Date\+|Notifications\+)', 'WIN-052'),
 (r'Providers/Shared/', 'WIN-064'),
]

def owner(path):
    for pattern, gid in rules:
        if re.search(pattern, path):
            return gid
    return None

# Preserve offsets while masking comments and string literals. Swift interpolation
# is intentionally not evaluated; raw declaration text is retained in evidence.
def masks(text):
    token = re.compile(r'(?P<string>\#*"""[\s\S]*?"""\#*|\#*"(?:\\.|[^"\\])*"\#*)|(?P<line>//[^\n]*)|(?P<block>/\*[\s\S]*?\*/)', re.M)
    code = list(text)
    comments_only = list(text)
    for m in token.finditer(text):
        for i in range(m.start(), m.end()):
            if text[i] != '\n':
                code[i] = ' '
                if m.lastgroup != 'string':
                    comments_only[i] = ' '
    return ''.join(code), ''.join(comments_only)

obligations = []
seen = set()

def add(kind, path, start, end, symbol, gid=None, detail=None):
    gid = gid or owner(path) or 'WIN-068'
    line = texts[path].count('\n', 0, start)+1
    key = (kind, path, line, symbol)
    if key in seen:
        return
    seen.add(key)
    identity = hashlib.sha256('|'.join(map(str, key)).encode()).hexdigest()[:12]
    group = group_by_id[gid]
    obligations.append(dict(id=kind.upper()+'-'+identity, category=kind, feature_group=gid,
        baseline=BASE, path=path, blob=blobs[path], line=line,
        end_line=texts[path].count('\n', 0, end)+1, symbol=symbol,
        source_excerpt=texts[path][start:end].strip(),
        windows_destination=group['windows_destination'], acceptance=detail or group['acceptance'],
        related_feature_groups=sorted(original_map[path] | {gid}),
        mapping_basis='EXPLICIT_CATEGORY_OR_PATH_RESPONSIBILITY_NOT_SEMANTIC_PROOF',
        scope_status='REQUIRED_OR_EXPLICIT_PLATFORM_DISPOSITION', implementation='UNVERIFIED',
        windows_test='NOT_RUN'))

all_symbols = defaultdict(list)
source_code = {p:t for p,t in texts.items() if p.startswith('Sources/') and Path(p).suffix in {'.swift','.c','.h','.ts','.js'}}
for p,t in source_code.items():
    code, clean = masks(t)
    for m in re.finditer(r'\b(?:class|struct|enum|protocol|actor|typealias)\s+(\w+)', code):
        all_symbols[m.group(1)].append(p)
    # CaseIterable/AppEnum choices and layout tokens are contracts beyond the control constructor.
    for enum in re.finditer(r'\benum\s+(\w+)\s*[^{}]*\{',code):
        enum_name=enum.group(1)
        header=code[enum.start():enum.end()]
        if not ('CaseIterable' in header or 'AppEnum' in header or enum_name=='MenuBarLayoutToken'):
            continue
        start=enum.end();end=start;depth=1
        while end<len(code) and depth:
            depth+=(code[end]=='{')-(code[end]=='}');end+=1
        if depth:raise ValueError(('unclosed option enum',p,enum_name))
        body=code[start:end-1]
        for case in re.finditer(r'(?m)^[ \t]*(?:indirect[ \t]+)?case[ \t]+(\w+)[^\n]*',body):
            prefix=body[:case.start()]
            if prefix.count('{')!=prefix.count('}'):continue
            add('enumerated_choice',p,start+case.start(),start+case.end(),enum_name+'.'+case.group(1),None,
                'Preserve this declared selectable enum case, raw encoding, defaults and visibility; a selector with missing cases is not parity. Internal/diagnostic enum cases retain their source scope. Match the Windows control, parser and serialized representation.')
    # Every explicit UI constructor, including callbacks not represented by MenuAction.
    if p.startswith(('Sources/CodexBar/', 'Sources/CodexBarWidget/')):
        for m in re.finditer(r'\b(Button|Toggle|Picker|TextField|SecureField|Stepper|Slider|Link|Menu|SettingsMenuPicker|ProviderSettings\w+Descriptor)\s*[({]', code):
            end=min(len(t),m.start()+650)
            add('ui_control',p,m.start(),end,m.group(1))
        for m in re.finditer(r'\b(?:\$settings|settings|self\.settings)\.(\w+)', code):
            add('settings_use',p,m.start(),min(len(t),m.end()+90),m.group(1),'WIN-069')
        for m in re.finditer(r'\\(?:SettingsStore)?\.(\w+)', code):
            if ('Settings' in p or 'ProviderImplementation' in p or 'Preferences' in p):
                add('settings_keypath_candidate',p,m.start(),m.end(),m.group(1),'WIN-069',
                    'Resolve this key path in its owner type; SettingsStore paths preserve read/write/default/visibility/onChange semantics. Non-setting paths are UI wiring, not separate features.')
        for m in re.finditer(r'@objc\s+(?:(?:private|fileprivate|internal|public|static|class)\s+)*func\s+(\w+)',code):
            add('native_action',p,m.start(),min(len(t),m.end()+160),m.group(1))
    if p.startswith(('Sources/CodexBar/', 'Sources/CodexBarWidget/')):
        for m in re.finditer(r'\.(onTapGesture|onDelete|onMove|onChange|onSubmit|keyboardShortcut|contextMenu|onOpenURL)\s*[({]',code):
            add('ui_event_binding',p,m.start(),min(len(t),m.start()+240),m.group(1))
        for m in re.finditer(r'#selector\s*\(([^)]+)\)',code):
            add('selector_binding',p,m.start(),m.end(),m.group(1))
    for m in re.finditer(r'(?m)^\s*#(?:if|elseif)\s+[^\n]+',clean):
        add('platform_or_build_guard',p,m.start(),m.end(),m.group(0).strip(),'WIN-068',
            'Inspect active Windows branch and callers before retiring original host; preserve functionality via Windows adapter, retain debug-only scope, and record no-op/unavailable as unfinished unless an explicit platform disposition exists.')
    if p=='Sources/CodexBar/SettingsStoreState.swift':
        for m in re.finditer(r'\bvar\s+(\w+)\s*:[^\n]+',code):
            add('settings_state',p,m.start(),m.end(),m.group(1),'WIN-069')
    if p.startswith('Sources/CodexBar/') and ('SettingsStore' in p or '/Config/' in p):
        for m in re.finditer(r'\bforKey:\s*(?:"[^"\n]+"|[A-Za-z_][\w.]*)',clean):
            add('settings_storage_key',p,m.start(),min(len(t),m.end()+100),m.group(0),'WIN-069')
    if p.startswith(('Sources/CodexBar/', 'Sources/CodexBarCore/')) and not ('SettingsStore' in p or '/Config/' in p):
        for m in re.finditer(r'\bforKey:\s*(?:"[^"\n]+"|[A-Za-z_][\w.]*)',clean):
            add('persistent_or_codable_key',p,m.start(),min(len(t),m.end()+70),m.group(0),None,
                'Preserve owner-scoped stored/decoded field, schema/default/migration and write failure semantics; determine whether this is persistent state or response decoding from the source owner, not a new UI setting.')
    if p=='Sources/CodexBar/CodexbarApp.swift':
        for m in re.finditer(r'\bfunc\s+(\w+)\s*\(',code):
            add('application_lifecycle_operation',p,m.start(),min(len(t),m.end()+140),m.group(1),'WIN-052')
    if p.startswith('Sources/CodexBarCore/') and (('/Config/' in p) or p.endswith(('ProviderSettings.swift','ProviderConfig.swift')) or p.endswith(('TokenAccounts.swift','TokenAccountSupport.swift'))):
        for m in re.finditer(r'(?m)^\s*(?:public\s+)?(?:var|let)\s+(\w+)\s*:[^\n]+',code):
            add('config_property',p,m.start(),m.end(),m.group(1),'WIN-064')
    if p.startswith('Sources/CodexBarCLI/'):
        for m in re.finditer(r'@(Flag|Option|Argument)\s*\(',code):
            tail=t[m.end():]; decl=re.search(r'\n\s*var\s+(\w+)[^\n]*',tail)
            if not decl or decl.start()>1800:
                raise ValueError(('unparsed CLI declaration',p,m.start()))
            end=m.end()+decl.end()
            add('cli_option',p,m.start(),end,decl.group(1),'WIN-043')
        for m in re.finditer(r'CommandDescriptor\s*\(\s*name:\s*"([^"]+)"',clean):
            add('cli_command_registration',p,m.start(),min(len(t),m.end()+220),m.group(1),'WIN-043')
        for m in re.finditer(r'case\s+(\[(?:"[^"\n]+"(?:,\s*)?)+\])',clean):
            add('cli_dispatch',p,m.start(),m.end(),m.group(1),'WIN-043')
        if p.endswith('CLIServeCommand.swift'):
            for m in re.finditer(r'case\s+"(/[^"\n]*)"',clean):
                add('http_route',p,m.start(),m.end(),m.group(1),'WIN-045')
    if p.startswith('Sources/AdaptiveReplayCLI/'):
        for m in re.finditer(r'case\s+"(--[^"\n]+)"',clean):
            add('replay_option',p,m.start(),m.end(),m.group(1),'WIN-067')
    if p=='Sources/CodexBar/MenuDescriptor.swift':
        a=clean.index('enum MenuAction:'); b=clean.index('\n    var sections',a)
        for m in re.finditer(r'(?m)^\s*case\s+([^\n]+)',clean[a:b]):
            add('menu_action',p,a+m.start(),a+m.end(),m.group(1),'WIN-010')
    if p=='Sources/CodexBarCore/Hooks/HookEvent.swift':
        for m in re.finditer(r'case\s+(\w+)\s*=\s*"([^"]+)"',clean):
            add('hook_event',p,m.start(),m.end(),m.group(2),'WIN-046')
    if p.startswith('Sources/CodexBarWidget/'):
        for m in re.finditer(r'\bstruct\s+(\w+)\s*:\s*[^\n{]*(?:Widget\b|AppIntent\b|WidgetConfigurationIntent\b)',code):
            add('widget_entry',p,m.start(),m.end(),m.group(1),'WIN-039')
        for m in re.finditer(r'@Parameter\s*\(',code):
            add('widget_parameter',p,m.start(),min(len(t),m.start()+330),'Parameter','WIN-039')
    if p.startswith('Sources/CodexBar/Providers/') and p.endswith('ProviderImplementation.swift'):
        for m in re.finditer(r'\bid:\s*"([^"\n]+)"',clean):
            add('provider_editor_id',p,m.start(),min(len(t),m.end()+180),m.group(1),'WIN-064')
    if p=='Sources/CodexBarCLI/CLIServeCommand.swift':
        for m in re.finditer(r'path\.hasPrefix\("(/[^"]*)"\)',clean):
            add('http_route_pattern',p,m.start(),min(len(t),m.end()+90),m.group(1),'WIN-045')
    if p.endswith('codexbar-plugin.d.ts'):
        for m in re.finditer(r'(?m)^\s*(?:readonly\s+)?(\w+)\s*\??\s*(?:<[^;\n{]*>)?\s*(?:\([^\n]*|:\s*[^\n]+)',clean):
            add('plugin_api_schema',p,m.start(),m.end(),m.group(1),'WIN-047')
    if p.endswith('codexbar-plugin.d.ts'):
        for m in re.finditer(r'(?<=[{;])\s*(?:readonly\s+)?(\w+)\s*\??\s*:',clean):
            add('plugin_inline_schema',p,m.start(),min(len(t),m.end()+110),m.group(1),'WIN-047')
        for m in re.finditer(r'declare\s+function\s+(\w+)\s*\(',code):
            add('plugin_entrypoint',p,m.start(),min(len(t),m.end()+180),m.group(1),'WIN-047')
    if p.endswith('provider-plugin-prelude.js'):
        # Public ctx members and object methods: preserve source location, not inferred authority.
        for m in re.finditer(r'ctx\.(\w+)\s*=',t):
            add('plugin_runtime_export',p,m.start(),min(len(t),m.end()+120),'ctx.'+m.group(1),'WIN-047')
        for m in re.finditer(r'(?m)^    (\w+)\([^\n]*\)\s*\{',t):
            add('plugin_runtime_method',p,m.start(),min(len(t),m.end()+150),m.group(1),'WIN-047')
    if p.startswith('Sources/CodexBarCore/Providers/') and p.endswith('ProviderDescriptor.swift'):
        for m in re.finditer(r'\bsettingsSection:\s*',code):
            add('settings_section_registration',p,m.start(),min(len(t),m.start()+260),'settingsSection','WIN-064',
                'Carry descriptor-registered typed settings contributions from native editor to runtime and credential source planner. Validate provider ID and section type, defaults, observation and wrong/missing-section rejection.')
    if p.startswith('Sources/CodexBarCore/Providers/') and p.endswith('ProviderConfig.swift'):
        for m in re.finditer(r'(?:extensionValue|setExtensionValue)\([^\n]*?forKey:\s*"([^"\n]+)"',clean):
            add('provider_extension_key',p,m.start(),m.end(),m.group(1),'WIN-069',
                'Preserve typed extension get/set, unknown non-null JSON fields, Int64-before-Double decoding, top-level null omission, nil removal, invalid nested-null rejection, and generic-key collision check; use round-trip fixtures, not a fixed whitelist of UI fields.')
    if p=='Sources/CodexBar/SettingsStore+Config.swift':
        a=clean.index('enum ProviderConfigStringField:'); b=clean.index('fileprivate func read',a)
        for m in re.finditer(r'(?m)^    case\s+([^\n]+)',clean[a:b]):
            add('provider_config_binding_kind',p,a+m.start(),a+m.end(),m.group(1),'WIN-064')
    if p.startswith('Sources/CodexBar/Providers/'):
        for m in re.finditer(r'\b(?:var|let)\s+(id|supportsLoginFlow)\s*:[^\n]+',code):
            add('provider_app_contract_property',p,m.start(),min(len(t),m.end()+100),m.group(1),'WIN-064')
        for m in re.finditer(r'\bfunc\s+(\w+)\s*\(',code):
            add('provider_app_operation',p,m.start(),min(len(t),m.end()+180),m.group(1),'WIN-064')
    if p=='Sources/CodexBar/Providers/Shared/ProviderRuntime.swift':
        a=clean.index('enum ProviderRuntimeAction'); b=clean.index('@MainActor',a)
        for m in re.finditer(r'(?m)^    case\s+([^\n]+)',clean[a:b]):
            add('provider_runtime_action',p,a+m.start(),a+m.end(),m.group(1),'WIN-063')
    if p.startswith(('Sources/CodexBar/', 'Sources/CodexBarCore/')):
        for m in re.finditer(r'\b(?:let|var)\s+(\w*(?:Environment|environment|Env|env)\w*)\s*(?::[^=\n]+)?=\s*\[([^\]]*)\]',clean):
            add('environment_alias_array',p,m.start(),m.end(),m.group(1),None,
                'Preserve ordered aliases including symbolic constants, blank/quote normalization, account projections and scrubbing. On Windows define deterministic case-insensitive resolution and conflicting-case precedence; preserve negative endpoint override guards.')
        for m in re.finditer(r'\b(?:environment|env)\s*\[\s*"([a-z][A-Za-z0-9_]+)"\s*\]',clean):
            add('environment_lowercase_input',p,m.start(),m.end(),m.group(1))
    if p.startswith(('Sources/CodexBar/', 'Sources/CodexBarCore/')):
        for m in re.finditer(r'\b(?:let|var)\s+(\w*(?:[Ee]nvironment|[Ee]nv)[\w]*)\s*(?::[^=\n]+)?=\s*"([A-Z][A-Z0-9_]+)"',clean):
            add('environment_constant',p,m.start(),m.end(),m.group(2))
        for m in re.finditer(r'\b(?:environment|env)\s*\[\s*"([A-Z][A-Z0-9_]+)"\s*\]',clean):
            add('environment_input',p,m.start(),m.end(),m.group(1))
    if p.startswith('Sources/CodexBar/') and ('UsageStore' in p or any(x in p for x in ('AgentSessionsStore','CloudSync','ProviderRuntime','RefreshCoordinator'))):
        for m in re.finditer(r'\bfunc\s+(\w+)\s*\(',code):
            add('runtime_operation',p,m.start(),min(len(t),m.end()+220),m.group(1))
    if p.startswith('Sources/CodexBarCore/Providers/'):
        for m in re.finditer(r'\bfunc\s+(resolveStrategies|isAvailable|shouldFallback|fetch|fetchUsage|refreshToken|loadCredentials)\s*\(',code):
            add('provider_path_operation',p,m.start(),min(len(t),m.end()+240),m.group(1),'WIN-065')

# Direct source-mode declarations plus the shared API-token constructor.
provider_file = OUT/'PROVIDER-COVERAGE-2026-09-12.json'
provider_data=json.loads(provider_file.read_text())
provider_rows=provider_data['providers']
for row in provider_rows:
    p=row['baseline_descriptors'][0];t=texts[p];_,clean=masks(t)
    modes=sorted(set(re.findall(r'\.(auto|web|api|oauth|cli)\b',' '.join(re.findall(r'sourceModes:\s*\[([^]]*)\]',clean)))))
    mode_evidence=[dict(path=p,line=clean.count('\n',0,m.start())+1,expression=m.group(0)) for m in re.finditer(r'sourceModes:\s*\[[^]]*\]',clean)]
    if not modes and 'fetchPlan: .apiToken' in clean:
        modes=['auto','api']
        helper='Sources/CodexBarCore/Providers/APITokenFetchStrategy.swift'
        if helper not in texts:
            helper=next(q for q,s in texts.items() if q.startswith('Sources/') and 'static func apiToken' in s)
        mode_evidence.append(dict(path=helper,line=texts[helper].count('\n',0,texts[helper].index('static func apiToken'))+1,expression='Shared apiToken factory; auto/api'))
    assert modes,row['id']
    cost=re.search(r'supportsTokenCost:\s*(true|false)',clean)
    folder=p.rsplit('/',1)[0]; appfolder=folder.replace('CodexBarCore','CodexBar')
    appfiles=sorted(q for q in paths if q.startswith(appfolder+'/'))
    linked=row['baseline_provider_files']+appfiles
    # Source mode names are NOT transport names: e.g. cli may read local files.
    strategies=sorted(set(re.findall(r'\b(\w+FetchStrategy)\b',clean)))
    row.update(source_modes=modes,source_mode_evidence=mode_evidence,app_files=appfiles,
        strategy_symbols=strategies,supports_token_cost_declared=cost.group(1)=='true' if cost else None,
        windows_status='PLANNED_ALL_DECLARED_MODES_RUNTIME_UNVERIFIED',
        windows_destination='Core/Providers/'+folder.split('/')[-1]+' + Runtime/ProviderEditors',
        source_obligations=[o['id'] for o in obligations if o['path'] in linked],
        acceptance=list(dict.fromkeys(row['acceptance']+['Preserve runtime app/cli and explicit-mode/account branches; source mode is not transport label','Preserve app-side settings, organization selectors, login actions, optional data, custom presentation, and declared token-cost capability'])))
    row.pop('source_modes_old',None)
    for mode in modes:
        add('provider_mode',p,clean.index('sourceModes:') if 'sourceModes:' in clean else clean.index('fetchPlan:'),
            (clean.index('sourceModes:') if 'sourceModes:' in clean else clean.index('fetchPlan:'))+180,
            row['id']+':'+mode,'WIN-065',
            'Provider '+row['id']+' source '+mode+': implement original app/CLI/selected-account strategy selection, credential scope, fallback, optional completeness, cancellation, and error outcomes; see source_mode_evidence and provider_path_operation obligations.')
# Build backlinks only after every mode row exists; shared provider folders must not link another provider's modes.
for row in provider_rows:
    linked=set(row['baseline_provider_files']+row['app_files'])
    row['source_obligations']=sorted(o['id'] for o in obligations if
        (o['category']=='provider_mode' and o['symbol'].split(':',1)[0]==row['id']) or
        (o['category']!='provider_mode' and o['path'] in linked))
provider_data['method']='Pinned source descriptor modes and shared factory; app files and lexical path obligations. Not runtime certification.'
provider_file.write_text(json.dumps(provider_data,ensure_ascii=False,indent=2)+'\n')

# Source-level obligations need a destination even for implementation-only code.
file_rows=[]
unassigned=[]
for e in entries:
    p=e['path'];gid=owner(p); ids=set(original_map[p]);
    if gid:ids.add(gid)
    if p.startswith('Sources/'):
        kind='PRODUCT_SOURCE_OR_RESOURCE'
        if not ids:
            unassigned.append(p)
            kind='UNASSIGNED_SOURCE'
    elif p.startswith(('Tests','Scripts/')):
        kind='VALIDATION_OR_BUILD_TOOL';ids.add('WIN-071')
    elif p.startswith(('docs/','.agents/')) or p.endswith('.md'):
        kind='REFERENCE_NOT_PRODUCT_FEATURE';ids.add('WIN-071')
    else:
        kind='PACKAGING_RESOURCE_LICENSE_OR_HOST_METADATA';ids.add('WIN-071')
    if 'CostStoreCrashProbe' in p:kind='TEST_HELPER_NOT_SHIPPED'
    if 'AdaptiveReplay' in p:kind='DIAGNOSTIC_TOOL'
    if p.startswith(('Sources/CQuickJS/quickjs','Sources/CQuickJS/lib')):kind='VENDORED_ENGINE'
    file_rows.append(dict(path=p,blob=e['blob'],kind=kind,feature_groups=sorted(ids),
        review='PLANNING_RESPONSIBILITY_CLASSIFIED' if ids else 'UNASSIGNED',
        semantic_proof='NOT_CLAIMED_BY_PATH_MAPPING'))

obligations.sort(key=lambda o:(o['path'],o['line'],o['category'],o['symbol']))
with (OUT/'SURFACE-OBLIGATIONS-2026-09-12.jsonl').open('w') as f:
    for o in obligations:f.write(json.dumps(o,ensure_ascii=False)+'\n')
with (OUT/'FILE-COVERAGE-2026-09-12.tsv').open('w') as f:
    w=csv.writer(f,delimiter='\t');w.writerow(['path','blob','classification','feature_groups','scope_review','semantic_proof'])
    for r in file_rows:w.writerow([r['path'],r['blob'],r['kind'],','.join(r['feature_groups']),r['review'],r['semantic_proof']])
# Test references are candidly candidates, not evidence of passed tests.
tests=[]
for p,t in texts.items():
    if p.startswith(('Tests/','TestsLinux/','TestsPlugin/')) and p.endswith('.swift'):
        names=sorted(set(re.findall(r'\bfunc\s+(test\w+|`[^`]+`)\s*\(',t)))
        referenced=sorted({q for token in set(re.findall(r'\b[A-Z]\w+\b',t)) for q in all_symbols.get(token,[])})
        linked=sorted({gid for q in referenced for gid in original_map[q]}|{owner(q) for q in referenced if owner(q)})
        tests.append(dict(path=p,blob=blobs[p],test_declaration_candidates=names,source_reference_candidates=referenced,
            feature_groups=linked or ['WIN-071'],status='PORT_OR_CLASSIFY_FIXTURE_NOT_RUN'))
(OUT/'TEST-TRACEABILITY-2026-09-12.json').write_text(json.dumps(dict(baseline=BASE,method='Identifier-based reference candidates, not call-graph or test-pass proof',tests=tests),ensure_ascii=False,indent=2)+'\n')
summary=dict(baseline=BASE,revision='2026-09-12-tertiary-audit',tracked_entries=len(entries),
    source_code_files=len(source_code),text_files_scanned=len(texts),feature_groups=len(groups),provider_ids=len(provider_rows),
    provider_mode_contracts=sum(len(r['source_modes']) for r in provider_rows),
    cost_capable_providers=[r['id'] for r in provider_rows if r['supports_token_cost_declared']],
    obligation_count=len(obligations),categories=dict(sorted(Counter(o['category'] for o in obligations).items())),
    test_source_files=len(tests),unassigned_source_paths=unassigned,
    all_files_semantically_verified=False,windows_execution='NOT_RUN',
    limitations=['Lexical surface extraction may not discover dynamically constructed or implicit behavior','File responsibility coverage is not whole-source semantic proof','Test references are candidates and no tests were executed','External compatibility decisions remain validation gates, not automatic feature exclusions'])
(OUT/'SURFACE-AUDIT-SUMMARY-2026-09-12.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
