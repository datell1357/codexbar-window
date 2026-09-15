# Packaging-time byte consistency check only. A local receipt is not a signed build attestation.
function Assert-CodexBarWidgetBuildReceipt([string] $ReceiptPath, [string] $ArtifactPath, [string] $Architecture,
    [ValidateSet('CodexBarWidgetBackend', 'CodexBarWidgetHost')][string] $Component = 'CodexBarWidgetBackend',
    [switch] $PassThru) {
    $maximumSize = if ($Component -eq 'CodexBarWidgetHost') { 16777216 } else { 16384 }
    $file = Get-Item -LiteralPath $ReceiptPath -Force -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $file.Length -le 0 -or $file.Length -gt $maximumSize) { throw 'Invalid widget build receipt file.' }
    $receiptStream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($receiptStream.Length -le 0 -or $receiptStream.Length -gt $maximumSize) { throw 'Widget receipt size changed.' }
        $reader = [IO.StreamReader]::new($receiptStream, [Text.UTF8Encoding]::new($false, $true), $true)
        try { $receipt = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
        finally { $reader.Dispose() }
    } finally { $receiptStream.Dispose() }
    foreach ($field in @('schemaVersion', 'component', 'architecture', 'configuration', 'artifactSize', 'artifactSHA256', 'provenanceStatus')) {
        if ($null -eq $receipt.PSObject.Properties[$field]) { throw 'Widget build receipt is missing a required field.' }
    }
    $schema = if ($Component -eq 'CodexBarWidgetHost') { 2 } else { 1 }
    if ($receipt.schemaVersion -ne $schema -or $receipt.component -cne $Component -or
        $receipt.architecture -ine $Architecture -or $receipt.configuration -cne 'Release' -or
        $receipt.provenanceStatus -cne 'LOCAL_BUILD_NOT_ATTESTED' -or
        [string] $receipt.artifactSHA256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Widget build receipt does not describe the requested release artifact.'
    }
    if ($Component -eq 'CodexBarWidgetHost') {
        foreach ($field in @('payload', 'callerPolicySHA256', 'packagesConfigSHA256', 'deployment')) {
            if ($null -eq $receipt.PSObject.Properties[$field]) { throw 'Widget host receipt lacks payload or policy information.' }
        }
        if ([string] $receipt.callerPolicySHA256 -cnotmatch '^[0-9a-f]{64}$' -or
            [string] $receipt.packagesConfigSHA256 -cnotmatch '^[0-9a-f]{64}$' -or
            $receipt.deployment -cne 'SELF_CONTAINED_COMPONENTS_PACKAGE_REGISTRATION_REQUIRED') {
            throw 'Unsupported widget host build policy.'
        }
    }
    [long] $expectedSize = 0
    if (-not [long]::TryParse([string] $receipt.artifactSize, [ref] $expectedSize) -or
        $expectedSize -le 0 -or $expectedSize -gt 536870912) { throw 'Invalid widget artifact size.' }
    # Never trust artifactPath from the receipt; the caller explicitly supplies the packaging input.
    $artifact = Get-Item -LiteralPath $ArtifactPath -Force -ErrorAction Stop
    if ($artifact.PSIsContainer -or ($artifact.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Widget artifact must be a regular file.'
    }
    $stream = [IO.File]::Open($artifact.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -ne $expectedSize) { throw 'Widget artifact size differs from its build receipt.' }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($actual -cne $receipt.artifactSHA256) { throw 'Widget artifact hash differs from its build receipt.' }
    } finally { $stream.Dispose() }
    if ($PassThru) { return $receipt }
}
