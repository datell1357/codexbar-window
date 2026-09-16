# Reconcile an explicitly selected deployment record. Resubmission requires -RetryIfUnchanged.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $PackageDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [Parameter(Mandatory = $true)][string] $OperationDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{32}$')][string] $ExpectedOperationId,
    [switch] $RetryIfUnchanged,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXDeployment.ps1')
if (-not $AllowUnvalidatedBuild) { throw 'Current MSIX artifacts are runtime-unverified. Explicit development installation opt-in is required.' }
$held = [Collections.Generic.List[IO.FileStream]]::new()
$operationLock = $null
function Assert-Operation($Record, $Package, [string] $UserSid) {
    if ($Record.schemaVersion -ne 1 -or $Record.operationId -isnot [string] -or
        $Record.operationId -cnotmatch '^[0-9a-f]{32}$' -or $Record.operationId -ine $ExpectedOperationId -or
        $Record.mode -notin @('Install', 'Update') -or $Record.userSid -cne $UserSid -or
        $Record.packageSha256 -cne $Package.PackageSha256 -or $Record.signingReceiptSha256 -cne $Package.ReceiptSha256 -or
        $Record.expectedSignerThumbprint -ine $Package.ExpectedSignerThumbprint -or $Record.runtimeValidation -cne 'NOT_RUN' -or
        $Record.status -cnotin @('PREPARED', 'SUBMITTING_TO_WINDOWS', 'WINDOWS_COMMAND_RETURNED',
            'DEPLOYMENT_FAILED_OR_INDETERMINATE', 'REGISTRATION_OBSERVED_RECORD_INCOMPLETE', 'REGISTRATION_RECORDED',
            'RECONCILING_REGISTRATION') -or -not (Test-CodexBarMSIXRecordTime $Record.createdAt)) {
        throw 'Deployment record does not match the selected operation, user or signed package.'
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($Record.identity.$key -isnot [string] -or $Record.identity.$key -cne $Package.Identity[$key]) {
            throw 'Deployment identity differs from the signed package.'
        }
    }
    # Do not use a recorded observation as proof of current Windows registration.
    if ($null -eq $Record.PSObject.Properties['observed'] -or @($Record.observed).Count -gt 16 -or
        $null -eq $Record.PSObject.Properties['failure'] -or $null -eq $Record.PSObject.Properties['before']) {
        throw 'Incomplete deployment record.'
    }
    $before = @($Record.before)
    if ($Record.mode -ieq 'Install') {
        if ($before.Count -ne 0) { throw 'Install recovery requires an empty original registration snapshot.' }
        return
    }
    if ($before.Count -ne 1) { throw 'Update recovery requires one original registration snapshot.' }
    foreach ($key in @('name', 'publisher', 'version', 'architecture', 'fullName', 'familyName', 'status')) {
        if ($before[0].$key -isnot [string] -or [string]::IsNullOrWhiteSpace($before[0].$key) -or
            $before[0].$key.Length -gt 8192 -or $before[0].$key -match '[\x00-\x1f]') { throw 'Invalid original registration field.' }
    }
    if ($before[0].name -cne $Package.Identity.name -or $before[0].publisher -cne $Package.Identity.publisher -or
        $before[0].architecture -cne $Package.Identity.architecture -or $before[0].status -cne 'Ok' -or
        $before[0].version -notmatch '^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}$' -or
        [version] $before[0].version -ge [version] $Package.Identity.version) { throw 'Invalid original update target.' }
}
function Get-RecoveryAction([object[]] $Installed, $Record, $Package, [bool] $ReceiptExists) {
    if ($Installed.Count -eq 1 -and $Installed[0].version -ceq $Package.Identity.version -and
        $Installed[0].architecture -ceq $Package.Identity.architecture) {
        Assert-CodexBarMSIXRegistration $Installed $Package.Identity @($Record.before)
        return 'Reconcile'
    }
    if ($ReceiptExists -or $Record.status -cin @('REGISTRATION_RECORDED', 'REGISTRATION_OBSERVED_RECORD_INCOMPLETE', 'RECONCILING_REGISTRATION')) {
        throw 'A previously observed registration has changed. Recovery will not reinstall or overwrite its receipt.'
    }
    $before = @($Record.before)
    if ($Installed.Count -ne $before.Count -or ($before.Count -eq 1 -and -not (Test-CodexBarMSIXSnapshot $Installed[0] $before[0]))) {
        throw 'Current registration differs from both the original state and the requested target.'
    }
    if (-not $RetryIfUnchanged) { throw 'The original state is unchanged. Use -RetryIfUnchanged only to deliberately resubmit this exact operation.' }
    return 'Retry'
}
function Assert-ExistingReceipt($Receipt, $Record, $Package, [object[]] $Installed) {
    if ($Receipt.schemaVersion -ne 1 -or $Receipt.status -cne 'REGISTERED_RUNTIME_UNVERIFIED' -or
        $Receipt.operationId -cne $Record.operationId -or $Receipt.mode -cne $Record.mode -or $Receipt.userSid -cne $Record.userSid -or
        $Receipt.package.sha256 -cne $Package.PackageSha256 -or $Receipt.package.bytes -ne $Package.PackageBytes -or
        $Receipt.signingReceiptSha256 -cne $Package.ReceiptSha256 -or $Receipt.signerThumbprint -ine $Package.ExpectedSignerThumbprint -or
        $Receipt.runtimeValidation -cne 'NOT_RUN' -or -not (Test-CodexBarMSIXRecordTime $Receipt.createdAt) -or
        -not (Test-CodexBarMSIXSnapshot $Receipt.registered $Installed[0])) { throw 'Existing installation receipt differs; it is preserved.' }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($Receipt.identity.$key -isnot [string] -or $Receipt.identity.$key -cne $Package.Identity[$key]) {
            throw 'Existing installation identity differs; it is preserved.'
        }
    }
    $provenance = Read-CodexBarBuildProvenance $Receipt.provenance
    if ($provenance.revision -cne $Package.Provenance.revision -or $provenance.version -cne $Package.Provenance.version) {
        throw 'Existing receipt provenance differs; it is preserved.'
    }
    $previous = @($Receipt.previous)
    $before = @($Record.before)
    if ($previous.Count -ne $before.Count -or ($before.Count -eq 1 -and -not (Test-CodexBarMSIXSnapshot $previous[0] $before[0]))) {
        throw 'Existing receipt previous registration differs; it is preserved.'
    }
}
try {
    $package = Read-CodexBarSignedMSIX $PackageDirectory $ExpectedSignerThumbprint $held
    $root = Get-CodexBarMSIXLocalItem $OperationDirectory $true
    if ($root.FullName.Equals($package.Directory, [StringComparison]::OrdinalIgnoreCase) -or
        $root.FullName.StartsWith($package.Directory.TrimEnd([char] '\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Operation records must be outside the signed package directory.'
    }
    $journalPath = Join-Path $root.FullName 'deployment-operation.json'
    $receiptPath = Join-Path $root.FullName 'package-installation-receipt.json'
    $userSid = Get-CodexBarMSIXUserSid
    $initial = Read-CodexBarMSIXDeploymentJSON $journalPath
    Assert-Operation $initial.Record $package $userSid
    Import-Module Appx -ErrorAction Stop
    $installed = @(Get-CodexBarMSIXInstalledPackage $package.Identity)
    $action = Get-RecoveryAction $installed $initial.Record $package (Test-Path -LiteralPath $receiptPath)
    # WhatIf stops before trust evaluation, ownership writes, record mutation and Appx submission.
    if (-not $PSCmdlet.ShouldProcess($initial.Record.operationId, "$action the selected MSIX deployment for the current user")) { return }
    Assert-CodexBarMSIXSignature $package
    $operationLock = Enter-CodexBarMSIXDeployment
    $current = Read-CodexBarMSIXDeploymentJSON $journalPath
    if ($current.Sha256 -cne $initial.Sha256) { throw 'Deployment record changed while acquiring ownership. Read the current record before retrying.' }
    $operation = $current.Record
    Assert-Operation $operation $package $userSid
    $installed = @(Get-CodexBarMSIXInstalledPackage $package.Identity)
    $receiptExists = Test-Path -LiteralPath $receiptPath
    $action = Get-RecoveryAction $installed $operation $package $receiptExists
    if ($receiptExists) {
        $receiptStream = Open-CodexBarMSIXInput $receiptPath 65536 $held
        Assert-ExistingReceipt (Read-CodexBarMSIXJSON $receiptStream) $operation $package $installed
        if ($operation.status -ceq 'REGISTRATION_RECORDED') {
            [pscustomobject] @{ ReceiptPath = $receiptPath; PackageFullName = $installed[0].fullName; Status = 'REGISTERED_RUNTIME_UNVERIFIED'; Recovery = 'ALREADY_RECONCILED'; RuntimeValidation = 'NOT_RUN' }
            return
        }
    }
    $registrationObserved = $action -ceq 'Reconcile'
    try {
        $operation | Add-Member -NotePropertyName lastResumeId -NotePropertyValue ([Guid]::NewGuid().ToString('N')) -Force
        $operation | Add-Member -NotePropertyName lastResumeAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        $operation.failure = $null
        $operation.status = if ($action -ceq 'Retry') { 'SUBMITTING_TO_WINDOWS' } else { 'RECONCILING_REGISTRATION' }
        Write-CodexBarJournal $journalPath $operation
        if ($action -ceq 'Retry') {
            if ($operation.mode -ieq 'Update') { Appx\Add-AppxPackage -Path $package.PackagePath -Update -ErrorAction Stop }
            else { Appx\Add-AppxPackage -Path $package.PackagePath -ErrorAction Stop }
            $operation.status = 'WINDOWS_COMMAND_RETURNED'
            Write-CodexBarJournal $journalPath $operation
        }
        $after = @(Get-CodexBarMSIXInstalledPackage $package.Identity)
        $operation.observed = @($after)
        Assert-CodexBarMSIXRegistration $after $package.Identity @($operation.before)
        $registrationObserved = $true
        if ($receiptExists) {
            Assert-ExistingReceipt (Read-CodexBarMSIXJSON $receiptStream) $operation $package $after
        } else {
            $receipt = New-CodexBarMSIXInstallationRecord $package $operation $after
            Write-CodexBarJournal $receiptPath $receipt -CreateOnly
            $receiptStream = Open-CodexBarMSIXInput $receiptPath 65536 $held
            Assert-ExistingReceipt (Read-CodexBarMSIXJSON $receiptStream) $operation $package $after
        }
        $operation.status = 'REGISTRATION_RECORDED'
        Write-CodexBarJournal $journalPath $operation
        [pscustomobject] @{ ReceiptPath = $receiptPath; PackageFullName = $after[0].fullName; Status = 'REGISTERED_RUNTIME_UNVERIFIED'; Recovery = $action; RuntimeValidation = 'NOT_RUN' }
    } catch {
        $operation.status = if ($registrationObserved) { 'REGISTRATION_OBSERVED_RECORD_INCOMPLETE' } else { 'DEPLOYMENT_FAILED_OR_INDETERMINATE' }
        $operation.failure = [ordered] @{ exceptionHResult = $_.Exception.HResult }
        try { Write-CodexBarJournal $journalPath $operation }
        catch { Write-Warning 'Recovery could not publish its final record. Preserve output and inspect current Windows registration.' }
        throw
    }
} finally {
    if ($null -ne $operationLock) { $operationLock.Dispose() }
    foreach ($stream in $held) { $stream.Dispose() }
}
