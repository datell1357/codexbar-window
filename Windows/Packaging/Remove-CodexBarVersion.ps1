# Retires receipt-owned bytes into a recoverable directory. Never recursively deletes files.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $VersionID,
    [switch] $AllowUnvalidatedBuild,
    [switch] $PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Explicit development removal opt-in is required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
if ([string]::IsNullOrWhiteSpace($localData) -or [string]::IsNullOrWhiteSpace($programs)) { throw 'User folders are unavailable.' }
$installRoot = Join-Path $localData 'Programs\CodexBarWindows'
$version = Join-Path (Join-Path $installRoot 'versions') $VersionID
foreach ($path in @($localData, (Join-Path $localData 'Programs'), $installRoot,
        (Join-Path $installRoot 'versions'), $version, $programs)) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Managed paths must be regular directories.' }
}
$lockPath = Join-Path $installRoot 'operations.lock'
if (Test-Path -LiteralPath $lockPath) {
    $item = Get-Item -LiteralPath $lockPath -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid operations lock.' }
}
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$shell = $null
$link = $null
try {
    $receiptPath = Join-Path $version 'installation-receipt.json'
    $metadata = Get-Item -LiteralPath $receiptPath -Force
    if ($metadata.PSIsContainer -or $metadata.Length -gt 16777216 -or
        ($metadata.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installation receipt.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schemaVersion -ne 1 -or $receipt.product -ne 'CodexBarWindows' -or
        $receipt.versionID -ne $VersionID -or $receipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED') {
        throw 'A completed installation receipt is required. Incomplete installations need separate recovery.'
    }
    $entries = @($receipt.files)
    if ($entries.Count -lt 4 -or $entries.Count -gt 10000) { throw 'Invalid receipt size.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $prepared = [Collections.Generic.List[object]]::new()
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
    # A selected shortcut, PATH reference or startup command must be migrated separately.
    $shortcut = Join-Path $programs 'CodexBar Windows.lnk'
    if (Test-Path -LiteralPath $shortcut) {
        $item = Get-Item -LiteralPath $shortcut -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Shortcut conflict.' }
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $target = [IO.Path]::GetFullPath($link.TargetPath)
        if ($target.StartsWith($version + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Select another Start Menu version before removing this version.'
        }
    }
    foreach ($scope in @('User', 'Machine', 'Process')) {
        $value = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ($null -ne $value -and [Environment]::ExpandEnvironmentVariables($value).Replace('/', '\').IndexOf(
                $version, [StringComparison]::OrdinalIgnoreCase) -ge 0) { throw 'Remove or migrate the version PATH reference first.' }
    }
    foreach ($hive in @([Microsoft.Win32.Registry]::CurrentUser, [Microsoft.Win32.Registry]::LocalMachine)) {
        foreach ($subkey in @('Software\Microsoft\Windows\CurrentVersion\Run', 'Software\Microsoft\Windows\CurrentVersion\RunOnce')) {
            $key = $hive.OpenSubKey($subkey, $false)
            if ($null -eq $key) { continue }
            try {
                foreach ($name in $key.GetValueNames()) {
                    $command = [string] $key.GetValue($name)
                    if ($command.Replace('/', '\').IndexOf($version, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        throw 'Migrate the version startup command before removal.'
                    }
                }
            } finally { $key.Dispose() }
        }
    }
    foreach ($process in @(Get-Process)) {
        try {
            if ($process.ProcessName -notin @('CodexBarWindows', 'CodexBarCLI', 'codexbar')) { continue }
            $executable = $process.Path
            if ([string]::IsNullOrWhiteSpace($executable)) { throw 'Cannot establish the running CodexBar executable path.' }
            if ($executable.StartsWith($version + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Close this version before removal.' }
        } finally { $process.Dispose() }
    }
    if (-not $PSCmdlet.ShouldProcess($VersionID, 'Retire unchanged installed files into a recoverable removal directory')) { return }
    $transaction = [Guid]::NewGuid().ToString('N')
    $retired = Join-Path $installRoot ('removed-' + $transaction)
    $null = New-Item -ItemType Directory -Path $retired
    # Receipt and original directories stay in place. Unknown files are never enumerated for removal.
    [IO.File]::Copy($receiptPath, (Join-Path $retired 'installation-receipt.json'), $false)
    $journalPath = Join-Path $retired 'removal-journal.json'
    $results = [Collections.Generic.List[object]]::new()
    $journal = [ordered] @{ schemaVersion = 1; versionID = $VersionID; state = 'PREPARED';
        createdAtUtc = [DateTime]::UtcNow.ToString('o'); files = @() }
    Write-CodexBarJournal $journalPath $journal
    foreach ($file in $prepared) {
        $source = $version
        $state = 'READY'
        foreach ($part in $file.relative.Split([char] '\')) {
            $source = Join-Path $source $part
            try { $item = Get-Item -LiteralPath $source -Force }
            catch [System.Management.Automation.ItemNotFoundException] { $state = 'ALREADY_ABSENT'; break }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $state = 'PRESERVED_LINK'; break }
        }
        if ($state -eq 'READY') {
            if ($item.PSIsContainer) { $state = 'PRESERVED_DIRECTORY' }
            elseif ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $file.sha256) { $state = 'PRESERVED_MODIFIED' }
            else {
                $destination = Join-Path $retired ('payload\' + $file.relative)
                $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                # Move preserves bytes even if an external writer races the comparison; no irreversible deletion.
                [IO.File]::Move($source, $destination)
                $state = 'RETIRED'
                if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $file.sha256) {
                    $state = 'RETIRED_CHANGED_CONCURRENTLY'
                }
            }
        }
        $results.Add([pscustomobject] @{ path = $file.relative; state = $state })
        $journal.files = $results.ToArray()
        Write-CodexBarJournal $journalPath $journal
        if ($state -eq 'RETIRED_CHANGED_CONCURRENTLY') { throw 'Concurrent change preserved in the removal directory; manual recovery is required.' }
    }
    $preserved = @($results | Where-Object { $_.state -like 'PRESERVED_*' })
    $journal.state = if ($preserved.Count -gt 0) { 'PARTIALLY_RETIRED_UNVERIFIED' } else { 'RECEIPT_PAYLOAD_RETIRED_UNVERIFIED' }
    Write-CodexBarJournal $journalPath $journal
    if ($PassThru) {
        [pscustomobject] @{ transactionID = $transaction; state = $journal.state; versionID = $VersionID }
    } else {
        Write-Output ('Removal transaction: ' + $transaction + '. ' + $journal.state + '. Files remain recoverable; settings and receipts are preserved.')
    }
} catch {
    Write-Warning 'Removal did not finish cleanly. Inspect both version and removal directories; no automatic rollback or recursive cleanup was attempted.'
    throw
} finally {
    if ($null -ne $link) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
    if ($null -ne $shell) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    $lock.Dispose()
}
