# Development installation/update of the signed MSIX contract for the current Windows user.
# Does not import certificates, force-stop applications, downgrade, launch, or remove packages/data.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $PackageDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [Parameter(Mandatory = $true)][ValidateSet('Install', 'Update')][string] $Mode,
    [string] $ExpectedInstalledPackageFullName,
    [Parameter(Mandatory = $true)][string] $OutputDirectory,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Mode = if ($Mode -ieq 'Install') { 'Install' } else { 'Update' }
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXDeployment.ps1')
if (-not $AllowUnvalidatedBuild) { throw 'Current MSIX artifacts are runtime-unverified. Explicit development installation opt-in is required.' }
if ($Mode -eq 'Update') {
    if ([string]::IsNullOrWhiteSpace($ExpectedInstalledPackageFullName) -or $ExpectedInstalledPackageFullName.Length -gt 256 -or
        $ExpectedInstalledPackageFullName -match '[\x00-\x1f]') { throw 'Updates require the exact existing package full name.' }
} elseif (-not [string]::IsNullOrEmpty($ExpectedInstalledPackageFullName)) { throw 'An existing package selector is only supported in Update mode.' }
$held = [Collections.Generic.List[IO.FileStream]]::new()
$operationLock = $null
function Assert-DeploymentPrecondition([object[]] $Installed, $Identity) {
    if ($Mode -eq 'Install') {
        if ($Installed.Count -ne 0) { throw 'The package is already installed. Select its exact full name in Update mode.' }
        return
    }
    if ($Installed.Count -ne 1 -or $Installed[0].fullName -cne $ExpectedInstalledPackageFullName -or
        $Installed[0].architecture -cne $Identity.architecture -or $Installed[0].status -cne 'Ok') {
        throw 'Installed package differs from the requested update target or is not healthy.'
    }
    if ([version] $Identity.version -le [version] $Installed[0].version) { throw 'Updates require a strictly newer package version.' }
}
try {
    $package = Read-CodexBarSignedMSIX $PackageDirectory $ExpectedSignerThumbprint $held
    Import-Module Appx -ErrorAction Stop
    $before = @(Get-CodexBarMSIXInstalledPackage $package.Identity)
    Assert-DeploymentPrecondition $before $package.Identity
    $output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd([char] '\')
    $parent = Get-CodexBarMSIXLocalItem ([IO.Path]::GetDirectoryName($output)) $true
    $leaf = [IO.Path]::GetFileName($output)
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf.EndsWith('.') -or $leaf.EndsWith(' ') -or
        $leaf -match '[:*?"<>|\x00-\x1f]' -or $leaf -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
        throw 'Invalid deployment output directory name.'
    }
    $output = Join-Path $parent.FullName $leaf
    if (Test-Path -LiteralPath $output) { throw 'Use a new deployment output directory. Existing records are preserved.' }
    if ($output.StartsWith($package.Directory.TrimEnd([char] '\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment records must be outside the signed package directory.'
    }
    # WhatIf stops before OS signature/trust evaluation, lock/output writes and deployment.
    if (-not $PSCmdlet.ShouldProcess($package.Identity.name, "$Mode signed MSIX for the current Windows user")) { return }
    Assert-CodexBarMSIXSignature $package
    $userSid = Get-CodexBarMSIXUserSid
    $operationLock = Enter-CodexBarMSIXDeployment
    # Cooperating installers serialize through this lock; Windows/other installers can still race.
    $current = @(Get-CodexBarMSIXInstalledPackage $package.Identity)
    Assert-DeploymentPrecondition $current $package.Identity
    if ($current.Count -ne $before.Count -or ($current.Count -eq 1 -and $current[0].fullName -cne $before[0].fullName)) {
        throw 'Installed package changed while preparing the operation.'
    }
    $null = New-Item -ItemType Directory -Path $output -ErrorAction Stop
    $journalPath = Join-Path $output 'deployment-operation.json'
    $journal = [ordered] @{
        schemaVersion = 1; operationId = [Guid]::NewGuid().ToString('N'); mode = $Mode; status = 'PREPARED'
        userSid = $userSid; identity = $package.Identity; packageSha256 = $package.PackageSha256
        signingReceiptSha256 = $package.ReceiptSha256; expectedSignerThumbprint = $package.ExpectedSignerThumbprint
        before = @($before); observed = @(); failure = $null; runtimeValidation = 'NOT_RUN'
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
    Write-CodexBarJournal $journalPath $journal
    $registrationObserved = $false
    try {
        $journal.status = 'SUBMITTING_TO_WINDOWS'
        Write-CodexBarJournal $journalPath $journal
        if ($Mode -eq 'Update') { Appx\Add-AppxPackage -Path $package.PackagePath -Update -ErrorAction Stop }
        else { Appx\Add-AppxPackage -Path $package.PackagePath -ErrorAction Stop }
        $journal.status = 'WINDOWS_COMMAND_RETURNED'
        Write-CodexBarJournal $journalPath $journal
        $after = @(Get-CodexBarMSIXInstalledPackage $package.Identity)
        $journal.observed = @($after)
        Assert-CodexBarMSIXRegistration $after $package.Identity $before
        $registrationObserved = $true
        $receipt = New-CodexBarMSIXInstallationRecord $package $journal $after
        $receiptPath = Join-Path $output 'package-installation-receipt.json'
        Write-CodexBarJournal $receiptPath $receipt -CreateOnly
        $journal.status = 'REGISTRATION_RECORDED'
        Write-CodexBarJournal $journalPath $journal
        [pscustomobject] @{ ReceiptPath = $receiptPath; PackageFullName = $after[0].fullName; Status = $receipt.status; RuntimeValidation = 'NOT_RUN' }
    } catch {
        $journal.status = if ($registrationObserved) { 'REGISTRATION_OBSERVED_RECORD_INCOMPLETE' } else { 'DEPLOYMENT_FAILED_OR_INDETERMINATE' }
        $journal.failure = [ordered] @{ exceptionHResult = $_.Exception.HResult }
        try { Write-CodexBarJournal $journalPath $journal }
        catch { Write-Warning 'The final deployment record could not be written. Preserve existing output and inspect Windows registration before retrying.' }
        throw
    }
} finally {
    if ($null -ne $operationLock) { $operationLock.Dispose() }
    foreach ($stream in $held) { $stream.Dispose() }
}
