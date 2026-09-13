# Explicit recovery of a recorded uninstall; registration restoration is opt-in and the app is never launched.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $RegistrationID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $UninstallID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild,
    [switch] $RestoreRegistration
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not $AllowUnvalidatedBuild) { throw 'Windows and development recovery opt-in are required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'User folder unavailable.' }
$root = Join-Path $localData 'Programs\CodexBarWindows'
$bundle = Join-Path $root ('management-' + $RegistrationID)
foreach ($path in @($localData, (Join-Path $localData 'Programs'), $root, $bundle)) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid recovery directory.' }
}
function Read-RecoveryRecord([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.Length -gt 16777216 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid recovery record.' }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}
$handoff = Read-RecoveryRecord (Join-Path $bundle ('uninstall-' + $UninstallID + '.json'))
if ($handoff.schemaVersion -ne 2 -or $handoff.registrationID -ne $RegistrationID -or
    ([string] $handoff.versionID) -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$' -or
    ([string] $handoff.referenceTransactionID) -notmatch '^[0-9a-f]{32}$' -or
    ([string] $handoff.removalTransactionID) -notmatch '^[0-9a-f]{32}$') { throw 'Unsupported uninstall handoff.' }
$removed = Join-Path $root ('removed-' + $handoff.removalTransactionID)
$references = Join-Path $root ('references-' + $handoff.referenceTransactionID + '.json')
$hasRemoval = Test-Path -LiteralPath $removed
$hasReferences = Test-Path -LiteralPath $references
if ($hasRemoval) {
    $item = Get-Item -LiteralPath $removed -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid removal directory.' }
    $receipt = Read-RecoveryRecord (Join-Path $removed 'installation-receipt.json')
    if ($receipt.versionID -ne $handoff.versionID -or $receipt.signerThumbprint -ine $ExpectedSignerThumbprint) { throw 'Removal receipt does not belong to this recovery.' }
}
if ($hasReferences) {
    $record = Read-RecoveryRecord $references
    if ($record.fromVersionID -ne $handoff.versionID -or -not [string]::IsNullOrEmpty($record.toVersionID)) { throw 'Reference record does not describe this uninstall.' }
}
# A missing record after a reported completion is an inconsistency, not proof that nothing happened.
if (-not $hasRemoval -and $handoff.removalState -ne 'PLANNED') { throw 'Recorded removal output is missing; automatic recovery refused.' }
if (-not $hasReferences -and $handoff.referenceState -ne 'PLANNED') { throw 'Recorded reference output is missing; automatic recovery refused.' }
if ($RestoreRegistration) {
    $registration = Read-RecoveryRecord (Join-Path $bundle 'registration.json')
    if ($registration.schemaVersion -ne 2 -or $registration.registrationID -ne $RegistrationID -or
        $registration.versionID -ne $handoff.versionID -or $registration.signerThumbprint -ine $ExpectedSignerThumbprint -or
        $registration.state -notin @('PREPARING_TOOLS', 'PREPARED', 'REGISTERED_RUNTIME_UNVERIFIED')) { throw 'Registration recovery boundary differs from the uninstall.' }
}
$action = if ($RestoreRegistration) { 'Restore files, launch references and the recorded Apps registration' } else { 'Restore available removal payload first, then recorded launch references' }
if (-not $PSCmdlet.ShouldProcess($handoff.versionID, $action)) { return }
$recoveryPath = Join-Path $bundle ('uninstall-recovery-' + [Guid]::NewGuid().ToString('N') + '.json')
$progress = [ordered] @{ schemaVersion = 1; uninstallID = $UninstallID; versionID = $handoff.versionID;
    stage = 'RESTORING_FILES'; removalTransactionID = $handoff.removalTransactionID;
    referenceTransactionID = $handoff.referenceTransactionID; restoreRegistration = [bool] $RestoreRegistration;
    registrationState = 'NOT_REQUESTED' }
Write-CodexBarJournal $recoveryPath $progress
try {
    if ($hasRemoval) {
        $result = & (Join-Path $PSScriptRoot 'Restore-CodexBarRemovedVersion.ps1') -TransactionID $handoff.removalTransactionID -AllowUnvalidatedBuild -PassThru
        if ($null -eq $result -or $result.versionID -ne $handoff.versionID -or
            $result.state -ne 'RECEIPT_PAYLOAD_RESTORED_UNVERIFIED') { throw 'File recovery is partial; reference restoration was not started.' }
    }
    $progress.stage = 'RESTORING_REFERENCES'
    Write-CodexBarJournal $recoveryPath $progress
    if ($hasReferences) {
        $referenceResult = & (Join-Path $PSScriptRoot 'Restore-CodexBarVersionReferences.ps1') -TransactionID $handoff.referenceTransactionID -ExpectedSignerThumbprint $ExpectedSignerThumbprint -AllowUnvalidatedBuild -PassThru
        if ($null -eq $referenceResult -or $referenceResult.transactionID -ne $handoff.referenceTransactionID -or
            $referenceResult.versionID -ne $handoff.versionID -or $referenceResult.state -ne 'REFERENCES_RESTORED_RUNTIME_UNVERIFIED') {
            throw 'Reference recovery did not complete; registration restoration was not started.'
        }
    }
    if ($RestoreRegistration) {
        $progress.stage = 'RESTORING_REGISTRATION'
        Write-CodexBarJournal $recoveryPath $progress
        $registered = & (Join-Path $PSScriptRoot 'Register-CodexBarInstallation.ps1') -VersionID $handoff.versionID -ExpectedSignerThumbprint $ExpectedSignerThumbprint -ResumeRegistrationID $RegistrationID -AllowUnvalidatedBuild -PassThru
        if ($null -eq $registered -or $registered.registrationID -ne $RegistrationID -or
            $registered.versionID -ne $handoff.versionID -or $registered.state -ne 'REGISTERED_RUNTIME_UNVERIFIED') {
            throw 'Registration recovery did not return a matching completion record.'
        }
        $progress.registrationState = $registered.state
    }
    $progress.stage = if ($hasRemoval -or $hasReferences -or $RestoreRegistration) { 'RECORDED_STEPS_RESTORED_UNVERIFIED' } else { 'NO_CHILD_RECORDS_FOUND' }
    Write-CodexBarJournal $recoveryPath $progress
    $registrationMessage = if ($RestoreRegistration) { ' Recorded Apps registration restored.' } else { ' Apps registration was not changed.' }
    Write-Output ($progress.stage + '.' + $registrationMessage + ' Preserved management and recovery files remain available.')
} catch {
    Write-Warning ('Recovery stopped during ' + $progress.stage + '. Earlier recovery steps may have succeeded. Record: ' + $recoveryPath)
    throw
}
