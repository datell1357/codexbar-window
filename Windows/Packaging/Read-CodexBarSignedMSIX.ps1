. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXBuild.ps1')
# File metadata preparation only. Call Assert-CodexBarMSIXSignature separately before deployment.
function Read-CodexBarSignedMSIX([string] $PackageDirectory, [string] $ExpectedSignerThumbprint,
    [Collections.Generic.List[IO.FileStream]] $HeldFiles) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
    if ($ExpectedSignerThumbprint -notmatch '^[0-9a-fA-F]{40}$') { throw 'Specify the expected signer thumbprint explicitly.' }
    $root = Get-CodexBarMSIXLocalItem $PackageDirectory $true
    $receiptStream = Open-CodexBarMSIXInput (Join-Path $root.FullName 'package-signing-receipt.json') 65536 $HeldFiles
    $receipt = Read-CodexBarMSIXJSON $receiptStream
    if ($receipt.schemaVersion -ne 1 -or $receipt.status -cne 'SIGNED_MSIX_RUNTIME_UNVERIFIED' -or
        $receipt.package.path -cne 'CodexBarWindows.msix' -or $receipt.signature.status -cne 'VALID_WITH_TIMESTAMP' -or
        $receipt.signature.signerThumbprint -ine $ExpectedSignerThumbprint -or
        [string] $receipt.signature.timestampSignerThumbprint -notmatch '^[0-9a-fA-F]{40}$' -or
        $receipt.signature.requestedFileDigest -cne 'SHA256' -or $receipt.signature.requestedTimestampDigest -cne 'SHA256' -or
        $receipt.tool.name -cne 'SignTool.exe' -or $receipt.tool.signExitCode -ne 0 -or $receipt.tool.verifyExitCode -ne 0 -or
        $receipt.installation -cne 'NOT_RUN' -or $receipt.runtimeValidation -cne 'NOT_RUN') {
        throw 'Unsupported signed package receipt or unexpected signer.'
    }
    foreach ($hash in @($receipt.signingRequestSha256, $receipt.buildReceiptSha256, $receipt.sourceInventorySha256,
        $receipt.unsignedPackageSha256, $receipt.manifestSha256, $receipt.blockMapSha256, $receipt.package.sha256, $receipt.tool.sha256)) {
        if ($hash -isnot [string] -or $hash -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid signed package hash.' }
    }
    [long] $size = 0
    if (-not [long]::TryParse([string] $receipt.package.bytes, [ref] $size) -or $size -le 0 -or $size -gt 8740929536) {
        throw 'Invalid signed package size.'
    }
    $provenance = Read-CodexBarBuildProvenance $receipt.provenance
    $path = Join-Path $root.FullName 'CodexBarWindows.msix'
    $stream = Open-CodexBarMSIXInput $path 8740929536 $HeldFiles
    $hash = Get-CodexBarMSIXHash $stream
    if ($stream.Length -ne $size -or $hash -cne $receipt.package.sha256) { throw 'Signed package bytes differ from its receipt.' }
    $metadata = Read-CodexBarMSIXMetadata $stream $true
    if ($metadata.ManifestSha256 -cne $receipt.manifestSha256 -or $metadata.BlockMapSha256 -cne $receipt.blockMapSha256) {
        throw 'Embedded signed package metadata differs from its receipt.'
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($receipt.identity.$key -isnot [string] -or $receipt.identity.$key -cne $metadata.Identity[$key]) {
            throw 'Signed package identity differs from its receipt.'
        }
    }
    return [pscustomobject] @{
        Directory = $root.FullName; PackagePath = $path; PackageStream = $stream
        PackageSha256 = $hash; PackageBytes = $size; ReceiptSha256 = (Get-CodexBarMSIXHash $receiptStream)
        Identity = $metadata.Identity; Provenance = $provenance
        ManifestSha256 = $metadata.ManifestSha256; BlockMapSha256 = $metadata.BlockMapSha256
        ExpectedSignerThumbprint = $ExpectedSignerThumbprint.ToUpperInvariant()
        TimestampSignerThumbprint = $receipt.signature.timestampSignerThumbprint.ToUpperInvariant()
    }
}
function Assert-CodexBarMSIXSignature($Package) {
    # Re-evaluate OS trust now; a receipt saying VALID is not sufficient. No SDK or private key is needed.
    $signature = Get-AuthenticodeSignature -LiteralPath $Package.PackagePath
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ine $Package.ExpectedSignerThumbprint -or
        $signature.SignerCertificate.Subject -cne $Package.Identity.publisher -or
        $null -eq $signature.TimeStamperCertificate -or
        $signature.TimeStamperCertificate.Thumbprint -ine $Package.TimestampSignerThumbprint) {
        throw 'Current Windows package signature, signer, publisher or timestamp was not confirmed.'
    }
}
