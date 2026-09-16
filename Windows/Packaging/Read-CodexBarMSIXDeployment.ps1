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
function Get-CodexBarMSIXInstalledPackage($Identity) {
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
