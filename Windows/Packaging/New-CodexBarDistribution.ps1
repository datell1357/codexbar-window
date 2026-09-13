# Implementation only; not run or validated. Does not build, sign or publish.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $InputManifest,
    [Parameter(Mandatory = $true)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
try {
    foreach ($file in $prepared) {
        $destination = Join-Path $outputRoot $file.Destination
        $parent = [IO.Path]::GetDirectoryName($destination)
        $null = [IO.Directory]::CreateDirectory($parent)
        [IO.File]::Copy($file.Source, $destination, $false)
        $item = Get-Item -LiteralPath $destination
        $inventory.Add([pscustomobject] @{
            path = $file.Destination.Replace('\', '/')
            kind = $file.Kind
            bytes = $item.Length
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    $record = [ordered] @{
        schemaVersion = 1
        architecture = $manifest.architecture
        status = 'STAGED_UNVERIFIED'
        files = @($inventory.ToArray())
    }
    $json = $record | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $outputRoot 'distribution-inventory.json'), $json,
        [Text.UTF8Encoding]::new($false))
    Write-Output 'Distribution staged, not verified or signed. Inventory hashes record copied bytes only.'
} catch {
    Write-Warning 'Staging failed. Partial output was preserved; inspect it and use a new output directory on retry.'
    throw
}
