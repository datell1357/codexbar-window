# Implementation only; no binaries are executed by this manifest producer.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $BuildDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string] $Architecture,
    [Parameter(Mandatory = $true)][string[]] $RuntimeFiles,
    [string[]] $RuntimeSearchDirectories = @(),
    [Parameter(Mandatory = $true)][string[]] $ResourceDirectories,
    [Parameter(Mandatory = $true)][string] $LicenseDirectory,
    [Parameter(Mandatory = $true)][string] $OutputManifest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarPEImports.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$entries = [Collections.Generic.List[object]]::new()
$destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$expectedMachine = if ($Architecture -eq 'x64') { 0x8664 } else { 0xAA64 }

function Add-ManifestFile([string] $Source, [string] $Destination, [string] $Kind) {
    if ($entries.Count -ge 10000) { throw 'Distribution file limit reached.' }
    $file = Get-Item -LiteralPath $Source -Force
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Manifest inputs must be regular files.'
    }
    if (-not $destinations.Add($Destination)) { throw 'Duplicate distribution destination.' }
    if ($Kind -in @('application', 'cli', 'runtime')) {
        # Only PE signature and machine are inspected; imports and signatures need separate handling.
        $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $reader = [IO.BinaryReader]::new($stream)
        try {
            if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'Missing DOS header.' }
            $stream.Position = 0x3C
            $offset = $reader.ReadUInt32()
            if ($offset -lt 64 -or $offset -gt 1048576 -or $offset -gt $stream.Length - 24) {
                throw 'Unsupported PE header offset.'
            }
            $stream.Position = $offset
            if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne $expectedMachine) {
                throw 'PE signature or architecture does not match the requested distribution.'
            }
        } finally { $reader.Dispose() }
    }
    $entries.Add([pscustomobject] @{ source = $file.FullName; destination = $Destination; kind = $Kind })
}

function Add-ManifestTree([string] $Directory, [string] $Prefix, [string] $Kind) {
    $root = Get-Item -LiteralPath $Directory -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Resource and license roots must be regular directories.'
    }
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject] @{ directory = $root.FullName; prefix = $Prefix; depth = 0 })
    $visited = 0
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        if ($node.depth -gt 32) { throw 'Resource tree depth limit reached.' }
        foreach ($child in Get-ChildItem -LiteralPath $node.directory -Force) {
            $visited++
            if ($visited -gt 20000) { throw 'Resource tree entry limit reached.' }
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links in resource trees are unsupported.' }
            $destination = $node.prefix + '/' + $child.Name
            if ($child.PSIsContainer) {
                $queue.Enqueue([pscustomobject] @{
                    directory = $child.FullName; prefix = $destination; depth = $node.depth + 1
                })
            } else { Add-ManifestFile $child.FullName $destination $Kind }
        }
    }
}

Add-ManifestFile (Join-Path $BuildDirectory 'CodexBarWindows.exe') 'CodexBarWindows.exe' 'application'
Add-ManifestFile (Join-Path $BuildDirectory 'CodexBarCLI.exe') 'CodexBarCLI.exe' 'cli'
if ($RuntimeFiles.Count -eq 0 -or $ResourceDirectories.Count -eq 0) { throw 'Explicit runtime and resource inputs are required.' }
foreach ($runtime in $RuntimeFiles) {
    if ([IO.Path]::GetExtension($runtime) -ine '.dll') { throw 'Runtime inputs must be DLL files.' }
    Add-ManifestFile $runtime ([IO.Path]::GetFileName($runtime)) 'runtime'
}
foreach ($directory in $ResourceDirectories) {
    $root = Get-Item -LiteralPath $directory -Force
    Add-ManifestTree $root.FullName $root.Name 'resource'
}
Add-ManifestTree $LicenseDirectory 'licenses' 'license'
$dependencies = [Collections.Generic.List[object]]::new()
$runtimeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $entries) {
    if ($file.kind -eq 'runtime') { $null = $runtimeNames.Add($file.destination) }
}
if ($RuntimeSearchDirectories.Count -gt 32) { throw 'Too many runtime search directories.' }
$searchRoots = [Collections.Generic.List[string]]::new()
$rootSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($directory in $RuntimeSearchDirectories) {
    $root = Get-Item -LiteralPath $directory -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Runtime search roots must be regular directories.'
    }
    if ($rootSet.Add($root.FullName)) { $searchRoots.Add($root.FullName) }
}
$queue = [Collections.Generic.Queue[object]]::new()
foreach ($file in $entries) {
    if ($file.kind -in @('application', 'cli', 'runtime')) { $queue.Enqueue($file) }
}
$scanned = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$lookupCache = @{}
while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    if (-not $scanned.Add($file.destination)) { continue }
    if ($scanned.Count -gt 1024) { throw 'Imported image limit exceeded.' }
    foreach ($import in @(Read-CodexBarPEImports $file.source)) {
        if ($dependencies.Count -ge 100000) { throw 'Dependency edge limit exceeded.' }
        if (-not $runtimeNames.Contains($import.name)) {
            if (-not $lookupCache.ContainsKey($import.name)) {
                $candidates = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($root in $searchRoots) {
                    $candidate = Join-Path $root $import.name
                    try { $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop }
                    catch {
                        if ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound) { continue }
                        throw
                    }
                    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                        throw 'Imported DLL candidate is a directory or link.'
                    }
                    $null = $candidates.Add($item.FullName)
                }
                if ($candidates.Count -gt 1) {
                    throw 'Ambiguous imported DLL candidates. Select the intended DLL explicitly with RuntimeFiles.'
                }
                $lookupCache[$import.name] = @($candidates)
            }
            $resolved = @($lookupCache[$import.name])
            if ($resolved.Count -eq 1) {
                Add-ManifestFile $resolved[0] $import.name 'runtime'
                $null = $runtimeNames.Add($import.name)
                $queue.Enqueue($entries[$entries.Count - 1])
            }
        }
        $dependencies.Add([pscustomobject] @{
            importer = $file.destination
            library = $import.name
            kind = $import.kind
            resolution = $(if ($runtimeNames.Contains($import.name)) { 'included' } else { 'external_unclassified' })
        })
    }
}
$unresolved = @($dependencies | Where-Object { $_.resolution -eq 'external_unclassified' } |
    ForEach-Object { $_.library } | Sort-Object -Unique)
$manifest = [ordered] @{
    schemaVersion = 1
    architecture = $Architecture
    dependencyClosure = 'RECURSIVE_IMPORT_GRAPH_UNVERIFIED'
    unresolvedLibraries = $unresolved
    dependencies = @($dependencies.ToArray())
    files = @($entries.ToArray() | Sort-Object destination)
}
$json = $manifest | ConvertTo-Json -Depth 6
if (-not $PSCmdlet.ShouldProcess('New distribution input manifest', 'Write explicit runtime and resource file list')) { return }
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$stream = [IO.File]::Open([IO.Path]::GetFullPath($OutputManifest), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
Write-Output 'Input manifest created. Dependency completeness, signatures and runtime behavior remain unverified.'
