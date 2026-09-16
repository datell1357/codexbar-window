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
. (Join-Path $PSScriptRoot 'Read-CodexBarSignedMSIX.ps1')
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if (-not $AllowUnvalidatedBuild) { throw 'Current MSIX artifacts are runtime-unverified. Explicit development installation opt-in is required.' }
if ($Mode -eq 'Update') {
    if ([string]::IsNullOrWhiteSpace($ExpectedInstalledPackageFullName) -or $ExpectedInstalledPackageFullName.Length -gt 256 -or
        $ExpectedInstalledPackageFullName -match '[\x00-\x1f]') { throw 'Updates require the exact existing package full name.' }
} elseif (-not [string]::IsNullOrEmpty($ExpectedInstalledPackageFullName)) { throw 'An existing package selector is only supported in Update mode.' }
$held = [Collections.Generic.List[IO.FileStream]]::new()
$operationLock = $null
function Get-InstalledPackage($Identity) {
    # Never query/provision other accounts. Exact comparisons follow the module's name filter.
    $packages = @(Appx\Get-AppxPackage -Name $Identity.name -PackageTypeFilter Main -ErrorAction Stop)
    if ($packages.Count -gt 16) { throw 'Unexpected installed package count.' }
    foreach ($package in $packages) {
        if ($package.Name -cne $Identity.name -or $package.Publisher -cne $Identity.publisher -or
            -not [string]::IsNullOrEmpty($package.ResourceId) -or $package.IsFramework -or $package.IsDevelopmentMode) {
            throw 'An installed package with this name has a different or unsupported identity.'
        }
        [pscustomobject] @{
            name = [string] $package.Name; publisher = [string] $package.Publisher
            version = $package.Version.ToString(); architecture = $package.Architecture.ToString().ToLowerInvariant()
            fullName = [string] $package.PackageFullName; familyName = [string] $package.PackageFamilyName
            status = $package.Status.ToString()
        }
    }
}
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
    $before = @(Get-InstalledPackage $package.Identity)
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
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $userSid = $currentIdentity.User.Value } finally { $currentIdentity.Dispose() }
    $stateRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $null = Get-CodexBarMSIXLocalItem $stateRoot $true
    foreach ($part in @('CodexBar', 'MSIXDeployment')) {
        $stateRoot = Join-Path $stateRoot $part
        if (-not (Test-Path -LiteralPath $stateRoot)) { $null = New-Item -ItemType Directory -Path $stateRoot -ErrorAction Stop }
        $null = Get-CodexBarMSIXLocalItem $stateRoot $true
    }
    $lockPath = Join-Path $stateRoot 'operations.lock'
    if (Test-Path -LiteralPath $lockPath) { $null = Get-CodexBarMSIXLocalItem $lockPath $false }
    $operationLock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    if ($operationLock.Length -ne 0) { throw 'The deployment lock contains unexpected data; it has been preserved.' }
    $null = Get-CodexBarMSIXLocalItem $lockPath $false
    # Cooperating installers serialize through this lock; Windows/other installers can still race.
    $current = @(Get-InstalledPackage $package.Identity)
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
        $after = @(Get-InstalledPackage $package.Identity)
        $journal.observed = @($after)
        if ($after.Count -ne 1 -or $after[0].version -cne $package.Identity.version -or
            $after[0].architecture -cne $package.Identity.architecture -or $after[0].status -cne 'Ok' -or
            [string]::IsNullOrWhiteSpace($after[0].fullName) -or [string]::IsNullOrWhiteSpace($after[0].familyName)) {
            throw 'Windows registration does not yet match the requested package. No automatic removal or rollback was attempted.'
        }
        if ($before.Count -eq 1 -and ($after[0].familyName -cne $before[0].familyName -or $after[0].fullName -ceq $before[0].fullName)) {
            throw 'Observed update does not preserve the existing package family or advance its full name.'
        }
        $registrationObserved = $true
        $receipt = [ordered] @{
            schemaVersion = 1; status = 'REGISTERED_RUNTIME_UNVERIFIED'; operationId = $journal.operationId; mode = $Mode
            userSid = $userSid; identity = $package.Identity; provenance = $package.Provenance
            registered = $after[0]; previous = @($before)
            package = [ordered] @{ sha256 = $package.PackageSha256; bytes = $package.PackageBytes }
            signingReceiptSha256 = $package.ReceiptSha256; signerThumbprint = $package.ExpectedSignerThumbprint
            runtimeValidation = 'NOT_RUN'; createdAt = [DateTime]::UtcNow.ToString('o')
        }
        $receiptPath = Join-Path $output 'package-installation-receipt.json'
        Write-CodexBarJournal $receiptPath $receipt
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
