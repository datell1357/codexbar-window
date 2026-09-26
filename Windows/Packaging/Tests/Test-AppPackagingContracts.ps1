# Synthetic files only; written but NOT RUN. No build, signing, installation or executable loading.
[CmdletBinding()]
param([Parameter(Mandatory)][string] $FixtureDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packaging = Split-Path -Parent $PSScriptRoot
. (Join-Path $packaging 'Read-CodexBarPEImports.ps1')
. (Join-Path $packaging 'Read-CodexBarAppPayload.ps1')
. (Join-Path $packaging 'Read-CodexBarDependencyScope.ps1')
. (Join-Path $packaging 'Read-CodexBarFirstPartyFiles.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'These fixtures require Windows path semantics.' }
if (Test-Path -LiteralPath $FixtureDirectory) { throw 'Use a new fixture directory. Existing files are preserved.' }
$root = (New-Item -ItemType Directory -Path $FixtureDirectory).FullName
function Assert-Fixture([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock] $Body) {
    $rejected = $false
    try { $null = & $Body } catch { $rejected = $true }
    Assert-Fixture $rejected 'Expected fixture rejection.'
}
function Write-PEFixture([string] $Name, [bool] $PE32 = $false, [bool] $Managed = $false,
    [uint32] $Flags = 1, [int] $Machine = 0x8664, [bool] $DelayImport = $false, [uint32] $DelayAttributes = 1) {
    $data = New-Object byte[] 1536
    function U16([int] $Offset, [uint16] $Value) { [BitConverter]::GetBytes($Value).CopyTo($data, $Offset) }
    function U32([int] $Offset, [uint32] $Value) { [BitConverter]::GetBytes($Value).CopyTo($data, $Offset) }
    U16 0 0x5A4D
    U32 0x3C 0x80
    U32 0x80 0x4550
    U16 0x84 $Machine
    U16 0x86 1
    $optional = 0x98
    $directoryBase = if ($PE32) { 96 } else { 112 }
    $optionalSize = $directoryBase + 128
    U16 0x94 $optionalSize
    U16 0x96 0x2002
    U16 $optional $(if ($PE32) { 0x10B } else { 0x20B })
    U32 ($optional + 60) 512
    U32 ($optional + $directoryBase - 4) 16
    $section = $optional + $optionalSize
    U32 ($section + 12) 0x2000
    U32 ($section + 16) 1024
    U32 ($section + 20) 512
    if ($Managed) {
        U32 ($optional + $directoryBase + 8 * 14) 0x2000
        U32 ($optional + $directoryBase + 8 * 14 + 4) 72
        U32 512 72
        U32 520 0x2100
        U32 524 16
        U32 528 $Flags
        U32 768 0x424A5342
    }
    if ($DelayImport) {
        U32 ($optional + $directoryBase + 8 * 13) 0x2200
        U32 ($optional + $directoryBase + 8 * 13 + 4) 64
        U32 1024 $DelayAttributes
        U32 1028 0x2280
        [Text.Encoding]::ASCII.GetBytes("Example.dll`0").CopyTo($data, 1152)
    }
    $path = Join-Path $root $Name
    [IO.File]::WriteAllBytes($path, $data)
    return $path
}

# Portable IL is accepted only with explicit permission; x86-required/preferred/native PE32 stay rejected.
$il = Write-PEFixture 'portable-il.dll' $true $true 1 0x14C
Assert-Fixture (Read-CodexBarPEImage $il 0x8664 $true).portableIL 'Expected portable managed IL.'
Assert-Fixture (Read-CodexBarPEImage $il 0xAA64 $true).portableIL 'Portable IL must serve either supported architecture.'
Assert-Rejected { Read-CodexBarPEImage $il 0x8664 }
foreach ($flags in @(0, 3, 0x20003, 0x11)) {
    $path = Write-PEFixture ("unsupported-$flags.dll") $true $true $flags 0x14C
    Assert-Rejected { Read-CodexBarPEImage $path 0x8664 $true }
}
$native32 = Write-PEFixture 'native-x86.dll' $true $false 0 0x14C
Assert-Rejected { Read-CodexBarPEImage $native32 0x8664 $true }
$native = Write-PEFixture 'native-x64.dll'
Assert-Fixture (-not (Read-CodexBarPEImage $native 0x8664).managed) 'Native x64 classification differs.'
Assert-Rejected { Read-CodexBarPEImage $native 0xAA64 $true }
$malformed = Write-PEFixture 'bad-metadata.dll' $true $true 1 0x14C
$bytes = [IO.File]::ReadAllBytes($malformed)
$bytes[768] = 0
[IO.File]::WriteAllBytes($malformed, $bytes)
Assert-Rejected { Read-CodexBarPEImage $malformed 0x8664 $true }
$delay = Write-PEFixture 'delay.dll' $false $false 0 0x8664 $true
$imports = @(Read-CodexBarPEImports $delay 0x8664)
Assert-Fixture ($imports.Count -eq 1 -and $imports[0].name -ceq 'example.dll' -and
    $imports[0].kind -ceq 'delayImport') 'RVA delay import changed.'
$delayVA = Write-PEFixture 'delay-va.dll' $false $false 0 0x8664 $true 0
Assert-Rejected { Read-CodexBarPEImports $delayVA 0x8664 }

# App and backend imports with the same name resolve to distinct application directories.
Assert-Fixture ((Get-CodexBarRuntimeImportPath 'CodexBarWindows.exe' 'same.dll') -ceq 'same.dll') 'Root scope changed.'
Assert-Fixture ((Get-CodexBarRuntimeImportPath 'App/CodexBarApp.exe' 'same.dll') -ceq 'App\same.dll') 'App scope changed.'
Assert-Fixture ((Get-CodexBarRuntimeImportPath 'App/fr/Example.resources.dll' 'same.dll') -ceq 'App\same.dll') 'Satellite escaped app scope.'
Assert-Fixture (-not (Test-CodexBarManagedILInput 'CodexBarCLI.exe')) 'Root image must not gain managed exemption.'
Assert-Fixture (-not (Test-CodexBarManagedILInput 'App/CodexBarApp.exe')) 'App host must remain native architecture-specific.'
Assert-Fixture (Test-CodexBarManagedILInput 'App/fr/Example.resources.dll') 'Managed satellite must be allowed.'

function New-Payload {
    $paths = @('App/CodexBarApp.exe', 'App/CodexBarApp.dll', 'App/CodexBarApp.deps.json',
        'App/CodexBarApp.runtimeconfig.json', 'App/coreclr.dll', 'App/hostfxr.dll', 'App/hostpolicy.dll',
        'App/System.Private.CoreLib.dll', 'App/Microsoft.UI.Xaml.dll', 'App/resources.pri',
        'App/licenses/THIRD-PARTY-NOTICES.txt')
    return [pscustomobject] @{ schemaVersion = 1; files = @($paths | ForEach-Object {
        $kind = if ($_ -like '*.exe') { 'application' } elseif ($_ -like '*.dll') { 'runtime' }
            elseif ($_ -like 'App/licenses/*') { 'license' } else { 'resource' }
        [pscustomobject] @{ path = $_; kind = $kind; bytes = 1; sha256 = ('a' * 64) }
    }) }
}
$payload = New-Payload
Assert-Fixture ((Read-CodexBarAppPayload $payload).Count -eq 11) 'Expected complete synthetic payload.'
Assert-CodexBarAppPayloadFiles $payload $payload.files -CompareHashes
$missing = New-Payload
$missing.files = @($missing.files | Where-Object { $_.path -ne 'App/hostfxr.dll' })
Assert-Rejected { Read-CodexBarAppPayload $missing }
$duplicate = New-Payload
$duplicate.files += [pscustomobject] @{ path = 'app/CODEXBARAPP.DLL'; kind = 'runtime'; bytes = 1; sha256 = ('a' * 64) }
Assert-Rejected { Read-CodexBarAppPayload $duplicate }
$traversal = New-Payload
$traversal.files += [pscustomobject] @{ path = 'App/../outside.json'; kind = 'resource'; bytes = 1; sha256 = ('a' * 64) }
Assert-Rejected { Read-CodexBarAppPayload $traversal }
$reclassified = New-Payload
$reclassified.files[1].kind = 'resource'
Assert-Rejected { Read-CodexBarAppPayload $reclassified }
$changed = New-Payload
$changed.files[1].sha256 = 'b' * 64
Assert-Rejected { Assert-CodexBarAppPayloadFiles $payload $changed.files -CompareHashes }
Assert-Rejected { Assert-CodexBarAppPayloadFiles $null $payload.files }
$extra = New-Payload
$extra.files += [pscustomobject] @{ path = 'App/extra.txt'; kind = 'resource'; bytes = 1; sha256 = ('a' * 64) }
Assert-Rejected { Assert-CodexBarAppPayloadFiles $payload $extra.files }

$base = @([pscustomobject] @{ path = 'CodexBarWindows.exe'; kind = 'application' },
    [pscustomobject] @{ path = 'CodexBarCLI.exe'; kind = 'cli' },
    [pscustomobject] @{ path = 'resources/Set-CodexBarUserPath.ps1'; kind = 'resource' })
$base += @(Get-CodexBarLifecycleFileNames | ForEach-Object { [pscustomobject] @{ path = "tools/$_"; kind = 'resource' } })
$baselineCount = Assert-CodexBarFirstPartyFiles $base
Assert-Fixture ((Assert-CodexBarFirstPartyFiles ($base + $payload.files)) -eq ($baselineCount + 2)) 'App must add two first-party signing targets.'
Assert-Rejected { Assert-CodexBarFirstPartyFiles ($base + @($payload.files | Where-Object { $_.path -ne 'App/CodexBarApp.dll' })) }
Assert-Fixture (Test-CodexBarFirstPartyFile 'App/CodexBarApp.dll' 'runtime') 'App assembly requires signing.'
Assert-Fixture (-not (Test-CodexBarFirstPartyFile 'App/Microsoft.UI.Xaml.dll' 'runtime')) 'Vendor DLL must retain its signature.'
Write-Output "Synthetic packaging fixtures completed. Files retained at $root; no executable was loaded."
