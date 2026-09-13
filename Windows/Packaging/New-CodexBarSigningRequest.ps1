# Creates an unsigned handoff document. Never accesses certificates or signs files.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $DistributionDirectory,
    [Parameter(Mandatory = $true)][string] $OutputRequest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarBuildProvenance.ps1')
$root = Get-Item -LiteralPath $DistributionDirectory -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid distribution root.' }
$rootPrefix = $root.FullName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$output = [IO.Path]::GetFullPath($OutputRequest)
if ($output.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Keep the signing request outside the distribution.' }
$inventoryFile = Get-Item -LiteralPath (Join-Path $root.FullName 'distribution-inventory.json') -Force
if ($inventoryFile.Length -gt 16777216 -or ($inventoryFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid inventory.' }
$inventory = Get-Content -LiteralPath $inventoryFile.FullName -Raw | ConvertFrom-Json
if ($inventory.schemaVersion -ne 1 -or $inventory.status -ne 'STAGED_UNVERIFIED' -or
    $inventory.architecture -notin @('x64', 'arm64')) { throw 'Unsupported distribution inventory.' }
$provenance = Read-CodexBarBuildProvenance $inventory.provenance
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$targets = [Collections.Generic.List[object]]::new()
$files = @($inventory.files)
if ($files.Count -lt 4 -or $files.Count -gt 10000) { throw 'Invalid inventory file count.' }
foreach ($file in $files) {
    $relative = ([string] $file.path).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
        $relative -match '[:\x00-\x1f]' -or -not $seen.Add($relative) -or
        ([string] $file.sha256) -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid inventory entry.' }
    $current = $root.FullName
    foreach ($component in $relative.Split([char] '\')) {
        if ($component -in @('', '.', '..') -or $component.EndsWith('.') -or $component.EndsWith(' ')) { throw 'Invalid inventory path.' }
        $current = Join-Path $current $component
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links are unsupported in signing inputs.' }
    }
    if ($item.PSIsContainer -or $item.Length -ne $file.bytes -or
        (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -ine $file.sha256) {
        throw 'Distribution bytes differ from inventory. Regenerate the distribution before signing.'
    }
    $isApp = $relative -ieq 'CodexBarWindows.exe' -and $file.kind -eq 'application'
    $isCLI = $relative -ieq 'CodexBarCLI.exe' -and $file.kind -eq 'cli'
    $isScript = [IO.Path]::GetFileName($relative) -ieq 'Set-CodexBarUserPath.ps1' -and $file.kind -eq 'resource'
    if ($isApp -or $isCLI -or $isScript) {
        $targets.Add([pscustomobject] @{ path = $file.path; sha256BeforeSigning = $file.sha256; kind = $file.kind })
    }
}
if ($targets.Count -ne 3 -or -not $seen.Contains('CodexBarWindows.exe') -or -not $seen.Contains('CodexBarCLI.exe')) {
    throw 'Expected exactly the app, CLI and one PATH operation script as signing targets.'
}
$request = [ordered] @{
    schemaVersion = 1
    status = 'SIGNING_REQUEST_ONLY'
    architecture = $inventory.architecture
    provenance = $provenance
    targets = @($targets.ToArray())
    thirdPartyPolicy = 'PRESERVE_VENDOR_SIGNATURES'
    afterSigning = 'REGENERATE_INVENTORY_AND_VALIDATE_AUTHENTICODE_BEFORE_RELEASE'
}
if (-not $PSCmdlet.ShouldProcess('New signing request', 'Record first-party signing targets without signing')) { return }
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($request | ConvertTo-Json -Depth 6))
$stream = [IO.File]::Open($output, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
Write-Output 'Unsigned signing request created. No certificate was accessed and no signature was applied.'
