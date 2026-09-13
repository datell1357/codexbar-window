# Restores only a journaled shortcut transition; preserves all displaced files.
[CmdletBinding(SupportsShouldProcess = $true)]
param([Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $TransactionID)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
if ([string]::IsNullOrWhiteSpace($localData) -or [string]::IsNullOrWhiteSpace($programs)) { throw 'User folders unavailable.' }
$installRoot = Join-Path $localData 'Programs\CodexBarWindows'
foreach ($directory in @($installRoot, $programs)) {
    $item = Get-Item -LiteralPath $directory -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsupported recovery directory.' }
}
$shortcut = Join-Path $programs 'CodexBar Windows.lnk'
$backup = Join-Path $programs ('CodexBar-' + $TransactionID + '.previous.lnk')
$journal = Join-Path $installRoot ('activation-' + $TransactionID + '.json')
function Get-RegularHash([string] $Path) {
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch {
        if ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound) { return $null }
        throw
    }
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Recovery file is not regular.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
$lock = [IO.File]::Open((Join-Path $installRoot 'operations.lock'), [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $item = Get-Item -LiteralPath $journal -Force
    if ($item.PSIsContainer -or $item.Length -gt 65536 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid activation journal.' }
    $record = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json
    if ($record.schemaVersion -ne 1 -or $record.state -notin @('PREPARED', 'SHORTCUT_SELECTED_RUNTIME_UNVERIFIED') -or
        $record.shortcut -ine $shortcut -or $record.previousShortcutBackup -ine $backup -or
        ([string] $record.candidateHash) -notmatch '^[0-9a-fA-F]{64}$' -or
        ($null -ne $record.previousHash -and ([string] $record.previousHash) -notmatch '^[0-9a-fA-F]{64}$')) {
        throw 'Journal lacks a supported, complete recovery boundary.'
    }
    $currentHash = Get-RegularHash $shortcut
    if ($currentHash -eq $record.previousHash) {
        Write-Output 'Shortcut already matches the pre-transition state; no change made.'
        return
    }
    if ($currentHash -ine $record.candidateHash) { throw 'Shortcut changed after this transition; automatic restore refused.' }
    if ($null -ne $record.previousHash -and (Get-RegularHash $backup) -ine $record.previousHash) {
        throw 'Previous shortcut backup is missing or changed.'
    }
    if (-not $PSCmdlet.ShouldProcess('CodexBar Start Menu shortcut', 'Restore the recorded previous state and preserve the current link')) { return }
    $recoveryID = [Guid]::NewGuid().ToString('N')
    $displaced = Join-Path $programs ('CodexBar-' + $recoveryID + '.displaced.lnk')
    $recoveryPath = Join-Path $installRoot ('recovery-' + $recoveryID + '.json')
    $recovery = [ordered] @{
        schemaVersion = 1; transactionID = $TransactionID; state = 'PREPARED'
        displacedShortcut = $displaced; expectedCurrentHash = $currentHash
        restoredHash = $record.previousHash
    }
    [IO.File]::WriteAllText($recoveryPath, ($recovery | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ((Get-RegularHash $shortcut) -ine $currentHash) { throw 'Shortcut changed during recovery preparation.' }
    if ($null -ne $record.previousHash) {
        $replacement = Join-Path $programs ('CodexBar-' + $recoveryID + '.restore.lnk')
        [IO.File]::Copy($backup, $replacement, $false)
        if ((Get-RegularHash $replacement) -ine $record.previousHash) { throw 'Copied backup differs from the journal.' }
        [IO.File]::Replace($replacement, $shortcut, $displaced)
    } else {
        # The first activation had no previous link; moving preserves the selected link.
        [IO.File]::Move($shortcut, $displaced)
    }
    $recovery.state = 'RESTORED_RUNTIME_UNVERIFIED'
    [IO.File]::WriteAllText($recoveryPath, ($recovery | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-Output 'Previous shortcut state restored. Installed versions and user data were preserved.'
} catch {
    Write-Warning 'Recovery incomplete. Inspect the actual shortcut and recovery records before retrying.'
    throw
} finally { $lock.Dispose() }
