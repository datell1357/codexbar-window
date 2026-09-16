. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXDeployment.ps1')
function Assert-CodexBarMSIXRemovalTarget([object[]] $Installed, $Installation, [string] $ExpectedFullName) {
    if ($Installed.Count -ne 1 -or $Installed[0].fullName -cne $ExpectedFullName -or
        $Installation.registered.fullName -cne $ExpectedFullName) { throw 'Select the exact current package recorded in the installation receipt.' }
    # Keep damaged packages removable; compare identity without requiring the current Status to be Ok.
    foreach ($key in @('name', 'publisher', 'version', 'architecture', 'fullName', 'familyName')) {
        if ($Installed[0].$key -cne $Installation.registered.$key) { throw 'Current registration differs from the selected installation receipt.' }
    }
}
function Assert-CodexBarMSIXRemovalRecordLocation([string] $Path, $Snapshot) {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Current-user application data location is unavailable.' }
    $dataRoot = Join-Path (Join-Path $localData 'Packages') $Snapshot.familyName
    foreach ($protected in @($dataRoot, $Snapshot.installLocation)) {
        if ([string]::IsNullOrWhiteSpace($protected)) { continue }
        $root = [IO.Path]::GetFullPath($protected).TrimEnd([char] '\')
        if ($Path.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
            $Path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Keep operation records outside package installation and package data directories.'
        }
    }
}
function New-CodexBarMSIXRemovalDataPolicy {
    return [ordered] @{
        packageData = 'WINDOWS_PACKAGE_REMOVAL_ACKNOWLEDGED'
        externalData = 'NO_EXPLICIT_DELETE_REQUESTED'
        backup = 'NOT_CREATED'
    }
}
function Assert-CodexBarMSIXRemovalDataPolicy($Policy) {
    if ($null -eq $Policy -or $Policy.packageData -cne 'WINDOWS_PACKAGE_REMOVAL_ACKNOWLEDGED' -or
        $Policy.externalData -cne 'NO_EXPLICIT_DELETE_REQUESTED' -or $Policy.backup -cne 'NOT_CREATED') {
        throw 'Unsupported package removal data policy.'
    }
}
function New-CodexBarMSIXRemovalRecord($Installation, $Operation) {
    Assert-CodexBarMSIXRemovalDataPolicy $Operation.dataPolicy
    return [ordered] @{
        schemaVersion = 1; status = 'UNREGISTERED_DATA_EFFECTS_UNVERIFIED'; operationId = $Operation.operationId
        userSid = $Operation.userSid; identity = $Installation.Record.identity; removedPackageFullName = $Operation.expectedPackageFullName
        installationOperationId = $Installation.Record.operationId; installationReceiptSha256 = $Installation.Sha256
        provenance = $Installation.Provenance; previous = $Operation.before; dataPolicy = (New-CodexBarMSIXRemovalDataPolicy)
        observation = 'CURRENT_USER_MAIN_REGISTRATION_ABSENT'
        runtimeValidation = 'NOT_RUN'; dataValidation = 'NOT_RUN'; createdAt = [DateTime]::UtcNow.ToString('o')
    }
}
function Assert-CodexBarMSIXRemovalReceipt($Receipt, $Operation, $Installation) {
    if ($Receipt.schemaVersion -ne 1 -or $Receipt.status -cne 'UNREGISTERED_DATA_EFFECTS_UNVERIFIED' -or
        $Receipt.operationId -cne $Operation.operationId -or $Receipt.userSid -cne $Operation.userSid -or
        $Receipt.removedPackageFullName -cne $Operation.expectedPackageFullName -or
        $Receipt.installationOperationId -cne $Installation.Record.operationId -or
        $Receipt.installationReceiptSha256 -cne $Installation.Sha256 -or
        $Receipt.observation -cne 'CURRENT_USER_MAIN_REGISTRATION_ABSENT' -or
        $Receipt.runtimeValidation -cne 'NOT_RUN' -or $Receipt.dataValidation -cne 'NOT_RUN' -or
        -not (Test-CodexBarMSIXRecordTime $Receipt.createdAt) -or
        -not (Test-CodexBarMSIXSnapshot $Receipt.previous $Operation.before) -or
        $Receipt.previous.installLocation -isnot [string] -or $Receipt.previous.installLocation -cne $Operation.before.installLocation) {
        throw 'Existing removal receipt differs; it is preserved.'
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($Receipt.identity.$key -isnot [string] -or $Receipt.identity.$key -cne $Installation.Record.identity.$key) {
            throw 'Existing removal identity differs; it is preserved.'
        }
    }
    $provenance = Read-CodexBarBuildProvenance $Receipt.provenance
    if ($provenance.revision -cne $Installation.Provenance.revision -or $provenance.version -cne $Installation.Provenance.version) {
        throw 'Existing removal provenance differs; it is preserved.'
    }
    Assert-CodexBarMSIXRemovalDataPolicy $Receipt.dataPolicy
}
