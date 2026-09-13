# Implementation only; not run or validated. Does not build, sign or publish.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $InputManifest,
    [Parameter(Mandatory = $true)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarPEImports.ps1')
. (Join-Path $PSScriptRoot 'Read-CodexBarSystemPolicy.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$manifestFile = Get-Item -LiteralPath $InputManifest -Force
if ($manifestFile.PSIsContainer -or $manifestFile.Length -gt 4194304) { throw 'Invalid input manifest.' }
$manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.architecture -notin @('x64', 'arm64')) {
    throw 'Expected schemaVersion 1 and architecture x64 or arm64.'
}
$files = @($manifest.files)
if ($files.Count -lt 4 -or $files.Count -gt 10000) { throw 'Invalid distribution file count.' }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'Output already exists. Choose a new directory; nothing is overwritten.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$prepared = [Collections.Generic.List[object]]::new()
$hasRuntime = $false
$hasLicense = $false
$hasOperations = $false
foreach ($file in $files) {
    $relative = ([string] $file.destination).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Length -gt 2048 -or
        [IO.Path]::IsPathRooted($relative) -or $relative -match '[:\x00-\x1f]' -or
        $relative -ieq 'distribution-inventory.json') { throw 'Unsupported destination.' }
    foreach ($part in $relative.Split([char] '\')) {
        if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
            throw 'Unsupported destination component.'
        }
    }
    if (-not $seen.Add($relative)) { throw 'Duplicate case-insensitive destination.' }
    $source = [string] $file.source
    if (-not [IO.Path]::IsPathRooted($source)) { $source = Join-Path $manifestFile.DirectoryName $source }
    $item = Get-Item -LiteralPath $source -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Sources must be regular files, not directories or links.'
    }
    if ($file.kind -notin @('application', 'cli', 'runtime', 'resource', 'license')) { throw 'Unknown file kind.' }
    if ($relative -ieq 'CodexBarWindows.exe' -and $file.kind -ne 'application') { throw 'Invalid app kind.' }
    if ($relative -ieq 'CodexBarCLI.exe' -and $file.kind -ne 'cli') { throw 'Invalid CLI kind.' }
    if ($file.kind -eq 'runtime' -and $relative.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) { $hasRuntime = $true }
    if ($file.kind -eq 'license') { $hasLicense = $true }
    if ($file.kind -eq 'resource' -and [IO.Path]::GetFileName($relative) -ieq 'Set-CodexBarUserPath.ps1') { $hasOperations = $true }
    $prepared.Add([pscustomobject] @{ Source = $item.FullName; Destination = $relative; Kind = $file.kind })
}
if (-not $seen.Contains('CodexBarWindows.exe') -or -not $seen.Contains('CodexBarCLI.exe') -or
    -not $hasRuntime -or -not $hasLicense -or -not $hasOperations) {
    throw 'Manifest must include app, CLI, runtime DLLs, licenses and the operations resource.'
}
# Re-read current input images rather than trusting a producer's dependency status string.
$policy = $null
if ($null -ne $manifest.PSObject.Properties['systemPolicy']) { $policy = $manifest.systemPolicy }
$systemLibraries = Read-CodexBarSystemPolicy $policy $manifest.architecture
$includedDLLs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $prepared) {
    if ($file.Kind -eq 'runtime' -and [IO.Path]::GetFileName($file.Destination) -eq $file.Destination) {
        $null = $includedDLLs.Add($file.Destination)
    }
}
$missing = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$edgeCount = 0
foreach ($file in $prepared) {
    if ($file.Kind -notin @('application', 'cli', 'runtime')) { continue }
    foreach ($import in @(Read-CodexBarPEImports $file.Source)) {
        $edgeCount++
        if ($edgeCount -gt 100000) { throw 'Staging dependency edge limit exceeded.' }
        if (-not $includedDLLs.Contains($import.name) -and -not $systemLibraries.ContainsKey($import.name)) {
            $null = $missing.Add($import.name)
        }
    }
}
if ($missing.Count -gt 0) {
    throw ('Unresolved imported libraries prevent staging: ' + ((@($missing) | Sort-Object) -join ', '))
}
# Reject a file that would also need to be a directory before any output is created.
foreach ($file in $prepared) {
    $parent = [IO.Path]::GetDirectoryName($file.Destination)
    while (-not [string]::IsNullOrEmpty($parent)) {
        if ($seen.Contains($parent) -or $parent -ieq 'distribution-inventory.json') { throw 'File/directory destination collision.' }
        $parent = [IO.Path]::GetDirectoryName($parent)
    }
}
if (-not $PSCmdlet.ShouldProcess('New Windows distribution directory', 'Copy explicitly listed distribution files')) { return }
# New-Item without Force fails if another producer created the output in the meantime.
$null = New-Item -ItemType Directory -Path $outputRoot
$inventory = [Collections.Generic.List[object]]::new()
$heldFiles = [Collections.Generic.List[IO.FileStream]]::new()
$stagedDependencies = [Collections.Generic.List[object]]::new()
$expectedMachine = if ($manifest.architecture -eq 'x64') { 0x8664 } else { 0xAA64 }
try {
    foreach ($file in $prepared) {
        $destination = Join-Path $outputRoot $file.Destination
        $parent = [IO.Path]::GetDirectoryName($destination)
        $null = [IO.Directory]::CreateDirectory($parent)
        [IO.File]::Copy($file.Source, $destination, $false)
        # Analyze the copied image while a read-sharing handle excludes writes/deletion.
        # Keep every handle until the final inventory has been written.
        $held = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $heldFiles.Add($held)
        if ($file.Kind -in @('application', 'cli', 'runtime')) {
            foreach ($import in @(Read-CodexBarPEImports $destination $expectedMachine)) {
                if ($stagedDependencies.Count -ge 100000) { throw 'Staged dependency edge limit exceeded.' }
                $resolution = if ($includedDLLs.Contains($import.name)) { 'included' }
                    elseif ($systemLibraries.ContainsKey($import.name)) { 'declared_system' }
                    else { throw 'A copied image has an unresolved dependency. Staging is incomplete.' }
                $stagedDependencies.Add([pscustomobject] @{
                    importer = $file.Destination.Replace('\', '/')
                    library = $import.name
                    kind = $import.kind
                    resolution = $resolution
                })
            }
        }
        $held.Position = 0
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $digest = $hasher.ComputeHash($held) } finally { $hasher.Dispose() }
        $inventory.Add([pscustomobject] @{
            path = $file.Destination.Replace('\', '/')
            kind = $file.Kind
            bytes = $held.Length
            sha256 = [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
        })
    }
    $record = [ordered] @{
        schemaVersion = 1
        architecture = $manifest.architecture
        status = 'STAGED_UNVERIFIED'
        dependencyScope = 'STATIC_AND_RVA_DELAY_IMPORT_NAMES'
        analysisSource = 'HELD_STAGED_FILES'
        dependencies = @($stagedDependencies.ToArray())
        systemPolicy = $policy
        files = @($inventory.ToArray())
    }
    $json = $record | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $outputRoot 'distribution-inventory.json'), $json,
        [Text.UTF8Encoding]::new($false))
    Write-Output 'Distribution staged, not verified or signed. Inventory hashes record copied bytes only.'
} catch {
    Write-Warning 'Staging failed. Partial output was preserved; inspect it and use a new output directory on retry.'
    throw
} finally {
    foreach ($held in $heldFiles) { $held.Dispose() }
}
