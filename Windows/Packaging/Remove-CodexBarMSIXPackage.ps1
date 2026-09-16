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
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXDeployment.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Explicit development removal opt-in is required.' }
if (-not $AcknowledgePackageDataRemoval) {
    throw 'Windows may remove this package user data. Back up required data separately and explicitly select -AcknowledgePackageDataRemoval to proceed.'
}
$held = [Collections.Generic.List[IO.FileStream]]::new()
$operationLock = $null
function Assert-RemovalTarget([object[]] $Installed, $Record) {
    if ($Installed.Count -ne 1 -or $Installed[0].fullName -cne $ExpectedPackageFullName -or
        $Record.registered.fullName -cne $ExpectedPackageFullName) { throw 'Select the exact currently installed package recorded in the receipt.' }
    # A damaged registration may still need removal; its current status is recorded but need not be Ok.
    foreach ($key in @('name', 'publisher', 'version', 'architecture', 'fullName', 'familyName')) {
        if ($Installed[0].$key -cne $Record.registered.$key) { throw 'Current registration differs from the selected installation receipt.' }
    }
}
function Assert-RecordLocation([string] $Path, $Installed) {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Current-user application data location is unavailable.' }
    $dataRoot = Join-Path (Join-Path $localData 'Packages') $Installed.familyName
    foreach ($protected in @($dataRoot, $Installed.installLocation)) {
        if ([string]::IsNullOrWhiteSpace($protected)) { continue }
        $root = [IO.Path]::GetFullPath($protected).TrimEnd([char] '\')
        if ($Path.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $Path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Keep installation/removal records outside package installation and package data directories.'
        }
    }
}
try {
    $userSid = Get-CodexBarMSIXUserSid
    $receiptItem = Get-CodexBarMSIXLocalItem $InstallationReceipt $false
    $installation = Read-CodexBarMSIXInstallation $receiptItem.FullName $userSid $held
    $record = $installation.Record
    Import-Module Appx -ErrorAction Stop
    $before = @(Get-CodexBarMSIXInstalledPackage $record.identity -IncludeInstallLocation)
    Assert-RemovalTarget $before $record
    $output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd([char] '\')
    $parent = Get-CodexBarMSIXLocalItem ([IO.Path]::GetDirectoryName($output)) $true
    $leaf = [IO.Path]::GetFileName($output)
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf.EndsWith('.') -or $leaf.EndsWith(' ') -or
        $leaf -match '[:*?"<>|\x00-\x1f]' -or $leaf -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
        throw 'Invalid removal output directory name.'
    }
    $output = Join-Path $parent.FullName $leaf
    if (Test-Path -LiteralPath $output) { throw 'Use a new removal output directory. Existing records are preserved.' }
    Assert-RecordLocation $receiptItem.FullName $before[0]
    Assert-RecordLocation $output $before[0]
    # WhatIf stops before ownership/output writes and Windows removal. This invocation never requests all users.
    if (-not $PSCmdlet.ShouldProcess($ExpectedPackageFullName, 'Remove this current-user package and its Windows-managed data; no backup is created')) { return }
    $operationLock = Enter-CodexBarMSIXDeployment
    $current = @(Get-CodexBarMSIXInstalledPackage $record.identity -IncludeInstallLocation)
    Assert-RemovalTarget $current $record
    if (-not (Test-CodexBarMSIXSnapshot $current[0] $before[0]) -or $current[0].installLocation -cne $before[0].installLocation) {
        throw 'Current registration changed while preparing removal.'
    }
    Assert-RecordLocation $receiptItem.FullName $current[0]
    Assert-RecordLocation $output $current[0]
    $null = New-Item -ItemType Directory -Path $output -ErrorAction Stop
    $journalPath = Join-Path $output 'removal-operation.json'
    $policy = [ordered] @{
        packageData = 'WINDOWS_PACKAGE_REMOVAL_ACKNOWLEDGED'
        externalData = 'NO_EXPLICIT_DELETE_REQUESTED'
        backup = 'NOT_CREATED'
    }
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
        $receipt = [ordered] @{
            schemaVersion = 1; status = 'UNREGISTERED_DATA_EFFECTS_UNVERIFIED'; operationId = $journal.operationId
            userSid = $userSid; identity = $record.identity; removedPackageFullName = $ExpectedPackageFullName
            installationOperationId = $record.operationId; installationReceiptSha256 = $installation.Sha256
            provenance = $installation.Provenance; previous = $before[0]; dataPolicy = $policy
            observation = 'CURRENT_USER_MAIN_REGISTRATION_ABSENT'
            runtimeValidation = 'NOT_RUN'; dataValidation = 'NOT_RUN'; createdAt = [DateTime]::UtcNow.ToString('o')
        }
        $receiptPath = Join-Path $output 'package-removal-receipt.json'
        Write-CodexBarJournal $receiptPath $receipt -CreateOnly
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
