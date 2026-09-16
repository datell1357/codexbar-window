. (Join-Path $PSScriptRoot 'Read-CodexBarSignedMSIX.ps1')
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
function Get-CodexBarMSIXUserSid {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { return $identity.User.Value } finally { $identity.Dispose() }
}
function Test-CodexBarMSIXRecordTime($Value) {
    # ConvertFrom-Json can materialize ISO timestamps as DateTime on newer PowerShell versions.
    if ($Value -is [DateTime] -or $Value -is [DateTimeOffset]) { return $true }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 128) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None, [ref] $parsed)
}
function Get-CodexBarMSIXInstalledPackage($Identity, [switch] $IncludeInstallLocation) {
    $packages = @(Appx\Get-AppxPackage -Name $Identity.name -PackageTypeFilter Main -ErrorAction Stop)
    if ($packages.Count -gt 16) { throw 'Unexpected installed package count.' }
    foreach ($package in $packages) {
        if ($package.Name -cne $Identity.name -or $package.Publisher -cne $Identity.publisher -or
            -not [string]::IsNullOrEmpty($package.ResourceId) -or $package.IsFramework -or $package.IsDevelopmentMode) {
            throw 'An installed package with this name has a different or unsupported identity.'
        }
        $snapshot = [pscustomobject] @{
            name = [string] $package.Name; publisher = [string] $package.Publisher
            version = $package.Version.ToString(); architecture = $package.Architecture.ToString().ToLowerInvariant()
            fullName = [string] $package.PackageFullName; familyName = [string] $package.PackageFamilyName
            status = $package.Status.ToString()
        }
        if ($IncludeInstallLocation) {
            # Obtain this from the current OS query, never use a persisted path as a removal target.
            $snapshot | Add-Member -NotePropertyName installLocation -NotePropertyValue ([string] $package.InstallLocation)
        }
        $snapshot
    }
}
function Read-CodexBarMSIXInstallation([string] $Path, [string] $UserSid, [Collections.Generic.List[IO.FileStream]] $HeldFiles) {
    $stream = Open-CodexBarMSIXInput $Path 65536 $HeldFiles
    $record = Read-CodexBarMSIXJSON $stream
    if ($record.schemaVersion -ne 1 -or $record.status -cne 'REGISTERED_RUNTIME_UNVERIFIED' -or
        $record.operationId -isnot [string] -or $record.operationId -cnotmatch '^[0-9a-f]{32}$' -or
        $record.mode -notin @('Install', 'Update') -or $record.userSid -cne $UserSid -or
        $record.runtimeValidation -cne 'NOT_RUN' -or -not (Test-CodexBarMSIXRecordTime $record.createdAt) -or
        [string] $record.signerThumbprint -notmatch '^[0-9a-fA-F]{40}$' -or
        [string] $record.signingReceiptSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string] $record.package.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Unsupported installation receipt or different Windows user.' }
    [long] $bytes = 0
    if (-not [long]::TryParse([string] $record.package.bytes, [ref] $bytes) -or $bytes -le 0 -or $bytes -gt 8740929536) {
        throw 'Invalid recorded package size.'
    }
    $provenance = Read-CodexBarBuildProvenance $record.provenance
    $identity = $record.identity
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($identity.$key -isnot [string]) { throw 'Invalid recorded package identity.' }
    }
    if ($identity.name -cnotmatch '^[A-Za-z0-9.-]{3,50}$' -or [string]::IsNullOrWhiteSpace($identity.publisher) -or
        $identity.publisher.Length -gt 8192 -or $identity.publisher -match '[\x00-\x1f]' -or
        $identity.architecture -cnotin @('x64', 'arm64') -or
        $identity.version -notmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$') {
        throw 'Invalid recorded package identity fields.'
    }
    $version = [version] $identity.version
    foreach ($part in @($version.Major, $version.Minor, $version.Build, $version.Revision)) {
        if ($part -gt 65535) { throw 'Invalid recorded package version.' }
    }
    $null = [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($identity.publisher)
    $registered = $record.registered
    foreach ($key in @('name', 'publisher', 'version', 'architecture', 'fullName', 'familyName', 'status')) {
        if ($registered.$key -isnot [string] -or [string]::IsNullOrWhiteSpace($registered.$key) -or
            $registered.$key.Length -gt 8192 -or $registered.$key -match '[\x00-\x1f]') { throw 'Invalid recorded registration.' }
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($registered.$key -cne $identity.$key) { throw 'Recorded registration and identity differ.' }
    }
    if ($registered.status -cne 'Ok' -or $registered.fullName -cnotmatch '^[A-Za-z0-9._-]{1,256}$' -or
        $registered.familyName -cnotmatch '^[A-Za-z0-9._-]{1,256}$' -or $registered.familyName -in @('.', '..')) {
        throw 'Invalid completed installation registration.'
    }
    return [pscustomobject] @{ Record = $record; Sha256 = (Get-CodexBarMSIXHash $stream); Provenance = $provenance }
}
function Enter-CodexBarMSIXDeployment {
    $stateRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $null = Get-CodexBarMSIXLocalItem $stateRoot $true
    foreach ($part in @('CodexBar', 'MSIXDeployment')) {
        $stateRoot = Join-Path $stateRoot $part
        if (-not (Test-Path -LiteralPath $stateRoot)) { $null = New-Item -ItemType Directory -Path $stateRoot -ErrorAction Stop }
        $null = Get-CodexBarMSIXLocalItem $stateRoot $true
    }
    $path = Join-Path $stateRoot 'operations.lock'
    if (Test-Path -LiteralPath $path) { $null = Get-CodexBarMSIXLocalItem $path $false }
    $stream = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        if ($stream.Length -ne 0) { throw 'The deployment lock contains unexpected data; it has been preserved.' }
        $null = Get-CodexBarMSIXLocalItem $path $false
        return ,$stream
    } catch { $stream.Dispose(); throw }
}
function Test-CodexBarMSIXSnapshot($Left, $Right) {
    foreach ($key in @('name', 'publisher', 'version', 'architecture', 'fullName', 'familyName', 'status')) {
        if ($null -eq $Left -or $null -eq $Right -or $Left.$key -isnot [string] -or $Right.$key -isnot [string] -or
            $Left.$key -cne $Right.$key) { return $false }
    }
    return $true
}
function Assert-CodexBarMSIXRegistration([object[]] $Installed, $Identity, [object[]] $Previous) {
    if ($Installed.Count -ne 1 -or $Installed[0].name -cne $Identity.name -or $Installed[0].publisher -cne $Identity.publisher -or
        $Installed[0].version -cne $Identity.version -or $Installed[0].architecture -cne $Identity.architecture -or
        $Installed[0].status -cne 'Ok' -or [string]::IsNullOrWhiteSpace($Installed[0].fullName) -or
        [string]::IsNullOrWhiteSpace($Installed[0].familyName)) { throw 'Windows registration does not match the requested package.' }
    if ($Previous.Count -gt 1 -or ($Previous.Count -eq 1 -and
        ($Installed[0].familyName -cne $Previous[0].familyName -or $Installed[0].fullName -ceq $Previous[0].fullName))) {
        throw 'Observed update does not preserve the existing package family or advance its full name.'
    }
}
function New-CodexBarMSIXInstallationRecord($Package, $Operation, [object[]] $Installed) {
    Assert-CodexBarMSIXRegistration $Installed $Package.Identity @($Operation.before)
    return [ordered] @{
        schemaVersion = 1; status = 'REGISTERED_RUNTIME_UNVERIFIED'; operationId = $Operation.operationId; mode = $Operation.mode
        userSid = $Operation.userSid; identity = $Package.Identity; provenance = $Package.Provenance
        registered = $Installed[0]; previous = @($Operation.before)
        package = [ordered] @{ sha256 = $Package.PackageSha256; bytes = $Package.PackageBytes }
        signingReceiptSha256 = $Package.ReceiptSha256; signerThumbprint = $Package.ExpectedSignerThumbprint
        runtimeValidation = 'NOT_RUN'; createdAt = [DateTime]::UtcNow.ToString('o')
    }
}
# Return parsed metadata and its exact byte identity, closing the stream before an owned journal update.
function Read-CodexBarMSIXDeploymentJSON([string] $Path) {
    $held = [Collections.Generic.List[IO.FileStream]]::new()
    try {
        $stream = Open-CodexBarMSIXInput $Path 65536 $held
        return [pscustomobject] @{ Record = (Read-CodexBarMSIXJSON $stream); Sha256 = (Get-CodexBarMSIXHash $stream) }
    } finally { foreach ($stream in $held) { $stream.Dispose() } }
}
