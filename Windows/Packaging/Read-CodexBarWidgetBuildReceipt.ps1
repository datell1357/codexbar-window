# Packaging-time byte consistency check only. A local receipt is not a signed build attestation.
function Assert-CodexBarWidgetBuildReceipt([string] $ReceiptPath, [string] $ArtifactPath, [string] $Architecture) {
    $file = Get-Item -LiteralPath $ReceiptPath -Force -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $file.Length -le 0 -or $file.Length -gt 16384) { throw 'Invalid widget backend build receipt file.' }
    $receipt = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($field in @('schemaVersion', 'component', 'architecture', 'configuration', 'artifactSize', 'artifactSHA256', 'provenanceStatus')) {
        if ($null -eq $receipt.PSObject.Properties[$field]) { throw 'Widget build receipt is missing a required field.' }
    }
    if ($receipt.schemaVersion -ne 1 -or $receipt.component -cne 'CodexBarWidgetBackend' -or
        $receipt.architecture -ine $Architecture -or $receipt.configuration -cne 'Release' -or
        $receipt.provenanceStatus -cne 'LOCAL_BUILD_NOT_ATTESTED' -or
        [string] $receipt.artifactSHA256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Widget build receipt does not describe the requested release artifact.'
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
}
