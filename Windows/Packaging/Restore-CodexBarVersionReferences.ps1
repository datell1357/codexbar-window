[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $TransactionID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not $AllowUnvalidatedBuild) { throw 'Windows and development opt-in are required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
if ([string]::IsNullOrWhiteSpace($localData) -or [string]::IsNullOrWhiteSpace($programs)) { throw 'User folders unavailable.' }
$root = Join-Path $localData 'Programs\CodexBarWindows'
function Assert-ReferenceDirectory([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid recovery directory.' }
}
function Get-ReferenceHash([string] $Path) {
    try { $item = Get-Item -LiteralPath $Path -Force }
    catch [System.Management.Automation.ItemNotFoundException] { return $null }
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid recovery file.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
foreach ($path in @($localData, (Join-Path $localData 'Programs'), $root, $programs, (Join-Path $root 'versions'))) { Assert-ReferenceDirectory $path }
$lockPath = Join-Path $root 'operations.lock'
$null = Get-ReferenceHash $lockPath
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$environmentKey = $null; $runKey = $null
try {
    $journal = Join-Path $root ('references-' + $TransactionID + '.json')
    $null = Get-ReferenceHash $journal
    if ((Get-Item -LiteralPath $journal).Length -gt 1048576) { throw 'Recovery record exceeds limit.' }
    $record = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json
    if ($record.schemaVersion -ne 2 -or $record.state -notin @('PREPARED', 'REFERENCES_UPDATED_RUNTIME_UNVERIFIED') -or
        ([string] $record.fromVersionID) -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$' -or
        $record.changePath -isnot [bool] -or $record.changeRun -isnot [bool]) { throw 'Unsupported recovery boundary.' }
    $from = Join-Path (Join-Path $root 'versions') $record.fromVersionID
    Assert-ReferenceDirectory $from
    $receiptPath = Join-Path $from 'installation-receipt.json'
    $null = Get-ReferenceHash $receiptPath
    if ((Get-Item -LiteralPath $receiptPath).Length -gt 16777216) { throw 'Receipt exceeds limit.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schemaVersion -ne 1 -or $receipt.product -ne 'CodexBarWindows' -or $receipt.versionID -ne $record.fromVersionID -or
        $receipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED' -or $receipt.signerThumbprint -ine $ExpectedSignerThumbprint) { throw 'Restore the original version payload before its references.' }
    foreach ($name in @('CodexBarWindows.exe', 'CodexBarCLI.exe')) {
        $entries = @($receipt.files | Where-Object { $_.path -ieq $name })
        $path = Join-Path $from $name
        if ($entries.Count -ne 1 -or (Get-ReferenceHash $path) -ine $entries[0].sha256) { throw 'Original executable missing or changed.' }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Thumbprint -ine $ExpectedSignerThumbprint) { throw 'Original signer mismatch.' }
    }
    $options = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    $environmentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $runKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true)
    $restorePath = $false; $restoreRun = $false; $restoreShortcut = $false
    if ($record.changePath) {
        if ($null -eq $environmentKey -or $record.pathKind -notin @('String', 'ExpandString') -or
            $null -eq $record.oldPath -or $null -eq $record.newPath -or
            ([string] $record.oldPath).Length -gt 32766 -or ([string] $record.newPath).Length -gt 32766) { throw 'Invalid PATH recovery boundary.' }
        $current = $environmentKey.GetValue('Path', $null, $options)
        if ($null -eq $current -or [string] $environmentKey.GetValueKind('Path') -ne $record.pathKind) { throw 'PATH type changed.' }
        if ($current -cne $record.oldPath) {
            if ($current -cne $record.newPath) { throw 'PATH changed externally; preserved.' }
            $restorePath = $true
        }
    }
    if ($record.changeRun) {
        if ($null -eq $runKey -or $record.oldRun -cne ('"' + (Join-Path $from 'CodexBarWindows.exe') + '"')) { throw 'Invalid startup recovery boundary.' }
        $current = $runKey.GetValue('CodexBarWindows', $null, $options)
        if ($null -ne $current -and $runKey.GetValueKind('CodexBarWindows') -ne [Microsoft.Win32.RegistryValueKind]::String) { throw 'Startup value type changed.' }
        if ($current -cne $record.oldRun) {
            if ($current -cne $record.newRun) { throw 'Startup changed externally; preserved.' }
            $restoreRun = $true
        }
    }
    $shortcut = Join-Path $programs 'CodexBar Windows.lnk'
    $backup = Join-Path $programs ('CodexBar-' + $TransactionID + '.references.previous.lnk')
    $currentShortcut = $null
    if ($null -ne $record.shortcutHash) {
        if (([string] $record.shortcutHash) -notmatch '^[0-9a-fA-F]{64}$' -or
            ($null -ne $record.shortcutNewHash -and ([string] $record.shortcutNewHash) -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid shortcut hash boundary.' }
        $currentShortcut = Get-ReferenceHash $shortcut
        if ($currentShortcut -ine $record.shortcutHash) {
            if ($currentShortcut -ine $record.shortcutNewHash -or
                (Get-ReferenceHash $backup) -ine $record.shortcutHash) { throw 'Shortcut or backup changed; preserved.' }
            $restoreShortcut = $true
        }
    }
    if (-not $PSCmdlet.ShouldProcess($record.fromVersionID, 'Restore recorded user references after conflict preflight')) { return }
    $recoveryID = [Guid]::NewGuid().ToString('N')
    $recoveryPath = Join-Path $root ('references-recovery-' + $recoveryID + '.json')
    $recovery = [ordered] @{ schemaVersion = 1; transactionID = $TransactionID; state = 'PREPARED';
        restorePath = $restorePath; restoreRun = $restoreRun; restoreShortcut = $restoreShortcut }
    Write-CodexBarJournal $recoveryPath $recovery
    if ($restorePath) {
        if ($environmentKey.GetValue('Path', $null, $options) -cne $record.newPath -or
            [string] $environmentKey.GetValueKind('Path') -ne $record.pathKind) { throw 'PATH changed during recovery.' }
        $environmentKey.SetValue('Path', $record.oldPath, [Microsoft.Win32.RegistryValueKind] ([Enum]::Parse([Microsoft.Win32.RegistryValueKind], $record.pathKind)))
    }
    if ($restoreRun) {
        if ($runKey.GetValue('CodexBarWindows', $null, $options) -cne $record.newRun) { throw 'Startup changed during recovery.' }
        if ($null -ne $record.newRun -and $runKey.GetValueKind('CodexBarWindows') -ne [Microsoft.Win32.RegistryValueKind]::String) { throw 'Startup type changed during recovery.' }
        $runKey.SetValue('CodexBarWindows', $record.oldRun, [Microsoft.Win32.RegistryValueKind]::String)
    }
    if ($restoreShortcut) {
        $temporary = Join-Path $programs ('CodexBar-' + $recoveryID + '.reference-restore.lnk')
        [IO.File]::Copy($backup, $temporary, $false)
        if ((Get-ReferenceHash $temporary) -ine $record.shortcutHash -or
            (Get-ReferenceHash $shortcut) -ine $currentShortcut) { throw 'Shortcut changed during recovery.' }
        if ($null -eq $currentShortcut) { [IO.File]::Move($temporary, $shortcut) }
        else { [IO.File]::Replace($temporary, $shortcut, (Join-Path $programs ('CodexBar-' + $recoveryID + '.reference-displaced.lnk'))) }
    }
    $recovery.state = 'REFERENCES_RESTORED_RUNTIME_UNVERIFIED'
    Write-CodexBarJournal $recoveryPath $recovery
    Write-Output 'Recorded references restored. Reopen shells to use the restored environment; recovery copies remain.'
} catch {
    Write-Warning 'Reference recovery incomplete. Earlier writes may have succeeded; preserved journals and shortcut copies remain available.'
    throw
} finally {
    if ($null -ne $environmentKey) { $environmentKey.Dispose() }
    if ($null -ne $runKey) { $runKey.Dispose() }
    $lock.Dispose()
}
