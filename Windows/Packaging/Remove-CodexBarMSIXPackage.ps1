# Removes one receipt-selected main package for the current user through Windows, never by file deletion.
# Windows-managed package data can be removed; no backup is created by this operation.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][string] $InstallationReceipt,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]{1,256}$')][string] $ExpectedPackageFullName,
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [switch] $AcknowledgePackageDataRemoval,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXRemoval.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Explicit development removal opt-in is required.' }
if (-not $AcknowledgePackageDataRemoval) {
    throw 'Windows may remove this package user data. Back up required data separately and explicitly select -AcknowledgePackageDataRemoval to proceed.'
}
$held = [Collections.Generic.List[IO.FileStream]]::new()
$operationLock = $null
try {
    $userSid = Get-CodexBarMSIXUserSid
    $receiptItem = Get-CodexBarMSIXLocalItem $InstallationReceipt $false
    $installation = Read-CodexBarMSIXInstallation $receiptItem.FullName $userSid $held
    $record = $installation.Record
    Import-Module Appx -ErrorAction Stop
    $before = @(Get-CodexBarMSIXInstalledPackage $record.identity -IncludeInstallLocation)
    Assert-CodexBarMSIXRemovalTarget $before $record $ExpectedPackageFullName
    $output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd([char] '\')
    $parent = Get-CodexBarMSIXLocalItem ([IO.Path]::GetDirectoryName($output)) $true
    $leaf = [IO.Path]::GetFileName($output)
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf.EndsWith('.') -or $leaf.EndsWith(' ') -or
        $leaf -match '[:*?"<>|\x00-\x1f]' -or $leaf -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
        throw 'Invalid removal output directory name.'
    }
    $output = Join-Path $parent.FullName $leaf
    if (Test-Path -LiteralPath $output) { throw 'Use a new removal output directory. Existing records are preserved.' }
    Assert-CodexBarMSIXRemovalRecordLocation $receiptItem.FullName $before[0]
    Assert-CodexBarMSIXRemovalRecordLocation $output $before[0]
    # WhatIf stops before ownership/output writes and Windows removal. This invocation never requests all users.
    if (-not $PSCmdlet.ShouldProcess($ExpectedPackageFullName, 'Remove this current-user package and its Windows-managed data; no backup is created')) { return }
    $operationLock = Enter-CodexBarMSIXDeployment
    $current = @(Get-CodexBarMSIXInstalledPackage $record.identity -IncludeInstallLocation)
    Assert-CodexBarMSIXRemovalTarget $current $record $ExpectedPackageFullName
    if (-not (Test-CodexBarMSIXSnapshot $current[0] $before[0]) -or $current[0].installLocation -cne $before[0].installLocation) {
        throw 'Current registration changed while preparing removal.'
    }
    Assert-CodexBarMSIXRemovalRecordLocation $receiptItem.FullName $current[0]
    Assert-CodexBarMSIXRemovalRecordLocation $output $current[0]
    $null = New-Item -ItemType Directory -Path $output -ErrorAction Stop
    $journalPath = Join-Path $output 'removal-operation.json'
    $policy = New-CodexBarMSIXRemovalDataPolicy
    $journal = [ordered] @{
        schemaVersion = 1; operationId = [Guid]::NewGuid().ToString('N'); status = 'PREPARED'
        userSid = $userSid; identity = $record.identity; expectedPackageFullName = $ExpectedPackageFullName
        installationOperationId = $record.operationId; installationReceiptSha256 = $installation.Sha256
        before = $before[0]; observed = @(); dataPolicy = $policy; failure = $null
        runtimeValidation = 'NOT_RUN'; dataValidation = 'NOT_RUN'; createdAt = [DateTime]::UtcNow.ToString('o')
    }
    Write-CodexBarJournal $journalPath $journal -CreateOnly
    $unregistrationObserved = $false
    try {
        $journal.status = 'SUBMITTING_REMOVAL_TO_WINDOWS'
        Write-CodexBarJournal $journalPath $journal
        # PreserveApplicationData is not supported for a normal signed MSIX; do not claim it preserves this app's data.
        Appx\Remove-AppxPackage -Package $ExpectedPackageFullName -Confirm:$false -ErrorAction Stop
        $journal.status = 'WINDOWS_COMMAND_RETURNED'
        Write-CodexBarJournal $journalPath $journal
        $after = @(Get-CodexBarMSIXInstalledPackage $record.identity)
        $journal.observed = @($after)
        if ($after.Count -ne 0) { throw 'A registration is still present or changed during removal. It has not been removed automatically.' }
        $unregistrationObserved = $true
        $receipt = New-CodexBarMSIXRemovalRecord $installation $journal
        $receiptPath = Join-Path $output 'package-removal-receipt.json'
        Write-CodexBarJournal $receiptPath $receipt -CreateOnly
        $receiptStream = Open-CodexBarMSIXInput $receiptPath 65536 $held
        Assert-CodexBarMSIXRemovalReceipt (Read-CodexBarMSIXJSON $receiptStream) $journal $installation
        $journal.status = 'REMOVAL_RECORDED'
        Write-CodexBarJournal $journalPath $journal
        [pscustomobject] @{ ReceiptPath = $receiptPath; PackageFullName = $ExpectedPackageFullName; Status = $receipt.status; DataValidation = 'NOT_RUN' }
    } catch {
        $journal.status = if ($unregistrationObserved) { 'UNREGISTRATION_OBSERVED_RECORD_INCOMPLETE' } else { 'REMOVAL_FAILED_OR_INDETERMINATE' }
        $journal.failure = [ordered] @{ exceptionHResult = $_.Exception.HResult }
        try { Write-CodexBarJournal $journalPath $journal }
        catch { Write-Warning 'Removal could not publish its final record. Preserve output and inspect current Windows registration.' }
        throw
    }
} finally {
    if ($null -ne $operationLock) { $operationLock.Dispose() }
    foreach ($stream in $held) { $stream.Dispose() }
}
