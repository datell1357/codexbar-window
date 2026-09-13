# Restores receipt-owned payloads from one removal transaction without overwriting files.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $TransactionID,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Explicit development recovery opt-in is required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Local application data is unavailable.' }
$installRoot = Join-Path $localData 'Programs\CodexBarWindows'
$retired = Join-Path $installRoot ('removed-' + $TransactionID)
function Assert-RegularDirectory([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Recovery directory is not regular.' }
}
function Get-RecoveryHash([string] $Path) {
    try { $item = Get-Item -LiteralPath $Path -Force }
    catch [System.Management.Automation.ItemNotFoundException] { return $null }
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Recovery file is not regular.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
foreach ($path in @($localData, (Join-Path $localData 'Programs'), $installRoot,
        (Join-Path $installRoot 'versions'), $retired)) { Assert-RegularDirectory $path }
$lockPath = Join-Path $installRoot 'operations.lock'
if (Test-Path -LiteralPath $lockPath) { $null = Get-RecoveryHash $lockPath }
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $receiptPath = Join-Path $retired 'installation-receipt.json'
    $null = Get-RecoveryHash $receiptPath
    $item = Get-Item -LiteralPath $receiptPath -Force
    if ($item.Length -gt 16777216) { throw 'Receipt exceeds recovery limit.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schemaVersion -ne 1 -or $receipt.product -ne 'CodexBarWindows' -or
        $receipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED' -or
        ([string] $receipt.versionID) -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$') { throw 'Invalid removal receipt.' }
    $version = Join-Path (Join-Path $installRoot 'versions') $receipt.versionID
    Assert-RegularDirectory $version
    # Require the preserved original receipt to agree, even when the last removal journal write was interrupted.
    if ((Get-RecoveryHash (Join-Path $version 'installation-receipt.json')) -ine (Get-RecoveryHash $receiptPath)) {
        throw 'The original installation receipt changed; automatic recovery refused.'
    }
    $entries = @($receipt.files)
    if ($entries.Count -lt 4 -or $entries.Count -gt 10000) { throw 'Invalid receipt size.' }
    $prepared = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        $relative = ([string] $entry.path).Replace('/', '\')
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
            $relative -match '[:\x00-\x1f]' -or $relative -in @('installation-receipt.json', 'distribution-inventory.json') -or
            -not $seen.Add($relative) -or ([string] $entry.sha256) -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid receipt entry.' }
        foreach ($part in $relative.Split([char] '\')) {
            if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
                $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw 'Unsafe receipt path.' }
        }
        $prepared.Add([pscustomobject] @{ relative = $relative; sha256 = [string] $entry.sha256 })
    }
    if (-not $PSCmdlet.ShouldProcess($receipt.versionID, 'Restore available removal payloads without overwriting existing files')) { return }
    $recoveryPath = Join-Path $retired ('restore-' + [Guid]::NewGuid().ToString('N') + '.json')
    $results = [Collections.Generic.List[object]]::new()
    $record = [ordered] @{ schemaVersion = 1; transactionID = $TransactionID; versionID = $receipt.versionID;
        state = 'PREPARED'; files = @() }
    Write-CodexBarJournal $recoveryPath $record
    foreach ($file in $prepared) {
        $source = Join-Path $retired 'payload'
        $destination = $version
        $parts = $file.relative.Split([char] '\')
        $sourceAvailable = Test-Path -LiteralPath $source
        if ($sourceAvailable) { Assert-RegularDirectory $source }
        # No new destination directories: retirement leaves original directories in place.
        for ($index = 0; $index -lt $parts.Length - 1; $index++) {
            $source = Join-Path $source $parts[$index]
            $destination = Join-Path $destination $parts[$index]
            Assert-RegularDirectory $destination
            if ($sourceAvailable) {
                $sourceAvailable = Test-Path -LiteralPath $source
                if ($sourceAvailable) { Assert-RegularDirectory $source }
            }
        }
        $source = Join-Path $source $parts[-1]
        $destination = Join-Path $destination $parts[-1]
        $destinationHash = Get-RecoveryHash $destination
        $state = 'NOT_IN_TRANSACTION'
        if ($null -ne $destinationHash) {
            $state = if ($destinationHash -ieq $file.sha256) { 'ALREADY_PRESENT' } else { 'PRESERVED_DESTINATION_CONFLICT' }
        } elseif ($sourceAvailable) {
            $sourceHash = Get-RecoveryHash $source
            if ($null -ne $sourceHash) {
                if ($sourceHash -ine $file.sha256) { $state = 'PRESERVED_SOURCE_CONFLICT' }
                else {
                    # Copy, not move: retain recovery bytes if later files or journal writes fail.
                    [IO.File]::Copy($source, $destination, $false)
                    if ((Get-RecoveryHash $destination) -ine $file.sha256) { throw 'Restored bytes changed; inspect the preserved source and destination.' }
                    $state = 'RESTORED'
                }
            }
        }
        $results.Add([pscustomobject] @{ path = $file.relative; state = $state })
        $record.files = $results.ToArray()
        Write-CodexBarJournal $recoveryPath $record
    }
    $remaining = @($results | Where-Object { $_.state -notin @('RESTORED', 'ALREADY_PRESENT') })
    $record.state = if ($remaining.Count -gt 0) { 'PARTIAL_RECOVERY_UNVERIFIED' } else { 'RECEIPT_PAYLOAD_RESTORED_UNVERIFIED' }
    Write-CodexBarJournal $recoveryPath $record
    Write-Output ($record.state + '. Removal copies were retained. No launch target or startup configuration was changed.')
} catch {
    Write-Warning 'Recovery incomplete. Original files and recovery copies were retained; inspect both directories before retrying.'
    throw
} finally { $lock.Dispose() }
