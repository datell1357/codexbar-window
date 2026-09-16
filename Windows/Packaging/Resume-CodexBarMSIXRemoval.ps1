# Reconcile a receipt-bound removal, or deliberately resubmit the same current-user target.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][string] $InstallationReceipt,
    [Parameter(Mandatory = $true)][string] $OperationDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{32}$')][string] $ExpectedOperationId,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]{1,256}$')][string] $ExpectedPackageFullName,
    [switch] $RetryIfUnchanged,
    [switch] $AcknowledgePackageDataRemoval,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXRemoval.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Explicit development removal recovery opt-in is required.' }
$held = [Collections.Generic.List[IO.FileStream]]::new()
$operationLock = $null
function Assert-RemovalOperation($Operation, $Installation, [string] $UserSid) {
    if ($Operation.schemaVersion -ne 1 -or $Operation.operationId -isnot [string] -or
        $Operation.operationId -cnotmatch '^[0-9a-f]{32}$' -or $Operation.operationId -ine $ExpectedOperationId -or
        $Operation.userSid -cne $UserSid -or $Operation.expectedPackageFullName -cne $ExpectedPackageFullName -or
        $Operation.expectedPackageFullName -cne $Installation.Record.registered.fullName -or
        $Operation.installationOperationId -cne $Installation.Record.operationId -or
        $Operation.installationReceiptSha256 -cne $Installation.Sha256 -or
        $Operation.runtimeValidation -cne 'NOT_RUN' -or $Operation.dataValidation -cne 'NOT_RUN' -or
        -not (Test-CodexBarMSIXRecordTime $Operation.createdAt) -or
        $Operation.status -cnotin @('PREPARED', 'SUBMITTING_REMOVAL_TO_WINDOWS', 'WINDOWS_COMMAND_RETURNED',
            'REMOVAL_RECORDED', 'REMOVAL_FAILED_OR_INDETERMINATE', 'UNREGISTRATION_OBSERVED_RECORD_INCOMPLETE', 'RECONCILING_REMOVAL')) {
        throw 'Removal record differs from the selected operation, user, installation receipt or package.'
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($Operation.identity.$key -isnot [string] -or $Operation.identity.$key -cne $Installation.Record.identity.$key) {
            throw 'Removal record identity differs from the installation.'
        }
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture', 'fullName', 'familyName')) {
        if ($Operation.before.$key -isnot [string] -or $Operation.before.$key -cne $Installation.Record.registered.$key) {
            throw 'Recorded removal target differs from the installation.'
        }
    }
    if ($Operation.before.status -isnot [string] -or [string]::IsNullOrWhiteSpace($Operation.before.status) -or
        $Operation.before.status.Length -gt 8192 -or $Operation.before.status -match '[\x00-\x1f]' -or
        $Operation.before.installLocation -isnot [string] -or $Operation.before.installLocation.Length -gt 2048 -or
        $Operation.before.installLocation -match '["\x00-\x1f]' -or
        ($Operation.before.installLocation.Length -gt 0 -and $Operation.before.installLocation -notmatch '^[a-zA-Z]:\\') -or
        $null -eq $Operation.PSObject.Properties['observed'] -or @($Operation.observed).Count -gt 16 -or
        $null -eq $Operation.PSObject.Properties['failure']) { throw 'Invalid original removal snapshot or observation fields.' }
    Assert-CodexBarMSIXRemovalDataPolicy $Operation.dataPolicy
}
function Get-RemovalRecoveryAction([object[]] $Installed, $Operation, [bool] $ReceiptExists, $Installation) {
    if ($Installed.Count -eq 0) { return 'Reconcile' }
    if ($ReceiptExists -or $Operation.status -cin @('REMOVAL_RECORDED', 'UNREGISTRATION_OBSERVED_RECORD_INCOMPLETE', 'RECONCILING_REMOVAL')) {
        throw 'A package is registered after removal was previously observed. Recovery will not remove a possible new installation.'
    }
    Assert-CodexBarMSIXRemovalTarget $Installed $Installation.Record $ExpectedPackageFullName
    if (-not (Test-CodexBarMSIXSnapshot $Installed[0] $Operation.before) -or
        $Installed[0].installLocation -cne $Operation.before.installLocation) {
        throw 'Current package snapshot differs from the original removal target.'
    }
    if (-not $RetryIfUnchanged -or -not $AcknowledgePackageDataRemoval) {
        throw 'Resubmission requires both -RetryIfUnchanged and -AcknowledgePackageDataRemoval for this exact current package.'
    }
    return 'Retry'
}
try {
    $userSid = Get-CodexBarMSIXUserSid
    $installationItem = Get-CodexBarMSIXLocalItem $InstallationReceipt $false
    $installation = Read-CodexBarMSIXInstallation $installationItem.FullName $userSid $held
    $root = Get-CodexBarMSIXLocalItem $OperationDirectory $true
    $journalPath = Join-Path $root.FullName 'removal-operation.json'
    $receiptPath = Join-Path $root.FullName 'package-removal-receipt.json'
    $initial = Read-CodexBarMSIXDeploymentJSON $journalPath
    Assert-RemovalOperation $initial.Record $installation $userSid
    # The saved location only excludes record destinations; it is never opened or deleted as a target.
    Assert-CodexBarMSIXRemovalRecordLocation $root.FullName $initial.Record.before
    Assert-CodexBarMSIXRemovalRecordLocation $installationItem.FullName $initial.Record.before
    Import-Module Appx -ErrorAction Stop
    $installed = @(Get-CodexBarMSIXInstalledPackage $installation.Record.identity -IncludeInstallLocation)
    $initialAction = Get-RemovalRecoveryAction $installed $initial.Record (Test-Path -LiteralPath $receiptPath) $installation
    $description = if ($initialAction -ceq 'Retry') { 'Retry removal of this exact current-user package and Windows-managed data; no backup is created' }
        else { 'Reconcile removal records without invoking Windows package removal' }
    # WhatIf stops before ownership/record writes or Remove-AppxPackage.
    if (-not $PSCmdlet.ShouldProcess($ExpectedPackageFullName, $description)) { return }
    $operationLock = Enter-CodexBarMSIXDeployment
    $current = Read-CodexBarMSIXDeploymentJSON $journalPath
    if ($current.Sha256 -cne $initial.Sha256) { throw 'Removal record changed while acquiring ownership. Read the current record before retrying.' }
    $operation = $current.Record
    Assert-RemovalOperation $operation $installation $userSid
    $installed = @(Get-CodexBarMSIXInstalledPackage $installation.Record.identity -IncludeInstallLocation)
    if ($initialAction -ceq 'Reconcile' -and $installed.Count -ne 0) {
        throw 'A registration appeared after absence was observed. Record reconciliation will not become a removal operation.'
    }
    $receiptExists = Test-Path -LiteralPath $receiptPath
    $action = Get-RemovalRecoveryAction $installed $operation $receiptExists $installation
    if ($installed.Count -eq 1) {
        Assert-CodexBarMSIXRemovalRecordLocation $root.FullName $installed[0]
        Assert-CodexBarMSIXRemovalRecordLocation $installationItem.FullName $installed[0]
    }
    if ($receiptExists) {
        $receiptStream = Open-CodexBarMSIXInput $receiptPath 65536 $held
        Assert-CodexBarMSIXRemovalReceipt (Read-CodexBarMSIXJSON $receiptStream) $operation $installation
        if ($operation.status -ceq 'REMOVAL_RECORDED') {
            [pscustomobject] @{ ReceiptPath = $receiptPath; PackageFullName = $ExpectedPackageFullName; Status = 'UNREGISTERED_DATA_EFFECTS_UNVERIFIED'; Recovery = 'ALREADY_RECONCILED'; DataValidation = 'NOT_RUN' }
            return
        }
    }
    $unregistrationObserved = $action -ceq 'Reconcile'
    try {
        $operation | Add-Member -NotePropertyName lastResumeId -NotePropertyValue ([Guid]::NewGuid().ToString('N')) -Force
        $operation | Add-Member -NotePropertyName lastResumeAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        $operation.failure = $null
        $operation.status = if ($action -ceq 'Retry') { 'SUBMITTING_REMOVAL_TO_WINDOWS' } else { 'RECONCILING_REMOVAL' }
        Write-CodexBarJournal $journalPath $operation
        if ($action -ceq 'Retry') {
            Appx\Remove-AppxPackage -Package $ExpectedPackageFullName -Confirm:$false -ErrorAction Stop
            $operation.status = 'WINDOWS_COMMAND_RETURNED'
            Write-CodexBarJournal $journalPath $operation
        }
        $after = @(Get-CodexBarMSIXInstalledPackage $installation.Record.identity)
        $operation.observed = @($after)
        if ($after.Count -ne 0) { throw 'A registration remains or changed during recovery; it will not be removed automatically.' }
        $unregistrationObserved = $true
        if ($receiptExists) {
            Assert-CodexBarMSIXRemovalReceipt (Read-CodexBarMSIXJSON $receiptStream) $operation $installation
        } else {
            $receipt = New-CodexBarMSIXRemovalRecord $installation $operation
            Write-CodexBarJournal $receiptPath $receipt -CreateOnly
            $receiptStream = Open-CodexBarMSIXInput $receiptPath 65536 $held
            Assert-CodexBarMSIXRemovalReceipt (Read-CodexBarMSIXJSON $receiptStream) $operation $installation
        }
        $operation.status = 'REMOVAL_RECORDED'
        Write-CodexBarJournal $journalPath $operation
        [pscustomobject] @{ ReceiptPath = $receiptPath; PackageFullName = $ExpectedPackageFullName; Status = 'UNREGISTERED_DATA_EFFECTS_UNVERIFIED'; Recovery = $action; DataValidation = 'NOT_RUN' }
    } catch {
        $operation.status = if ($unregistrationObserved) { 'UNREGISTRATION_OBSERVED_RECORD_INCOMPLETE' } else { 'REMOVAL_FAILED_OR_INDETERMINATE' }
        $operation.failure = [ordered] @{ exceptionHResult = $_.Exception.HResult }
        try { Write-CodexBarJournal $journalPath $operation }
        catch { Write-Warning 'Removal recovery could not publish its final record. Preserve output and inspect current Windows registration.' }
        throw
    }
} finally {
    if ($null -ne $operationLock) { $operationLock.Dispose() }
    foreach ($stream in $held) { $stream.Dispose() }
}
