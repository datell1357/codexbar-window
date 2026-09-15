# Future Windows signing entry point. Sign only a new copy with an explicitly selected certificate.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $PackageDirectory,
    [Parameter(Mandatory = $true)][string] $SigningRequest,
    [Parameter(Mandatory = $true)][string] $SignToolPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $CertificateThumbprint,
    [Parameter(Mandatory = $true)][string] $TimestampServer,
    [Parameter(Mandatory = $true)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXBuild.ps1')
$held = [Collections.Generic.List[IO.FileStream]]::new()
$certificate = $null
try {
    $build = Read-CodexBarMSIXBuild $PackageDirectory $held
    $requestStream = Open-CodexBarMSIXInput $SigningRequest 65536 $held
    $request = Read-CodexBarMSIXJSON $requestStream
    if ($request.schemaVersion -ne 1 -or $request.status -cne 'MSIX_SIGNING_REQUEST_ONLY' -or
        $request.package.path -cne 'CodexBarWindows.msix' -or $request.package.bytes -ne $build.PackageBytes -or
        $request.package.sha256BeforeSigning -cne $build.PackageSha256 -or
        $request.buildReceiptSha256 -cne $build.ReceiptSha256 -or $request.manifestSha256 -cne $build.ManifestSha256 -or
        $request.blockMapSha256 -cne $build.BlockMapSha256 -or $request.sourceInventorySha256 -cne $build.SourceInventorySha256 -or
        $request.hashAlgorithm -cne 'SHA256' -or $request.runtimeValidation -cne 'NOT_RUN' -or
        $request.certificateSelection -cne 'EXPLICIT_CURRENT_USER_MY_THUMBPRINT_WITH_MATCHING_PUBLISHER' -or
        $request.afterSigning -cne 'VERIFY_PACKAGE_SIGNATURE_TIMESTAMP_AND_RECORD_SIGNED_BYTES') {
        throw 'Signing request does not match the current unsigned package build.'
    }
    foreach ($key in @('name', 'publisher', 'version', 'architecture')) {
        if ($request.identity.$key -isnot [string] -or $request.identity.$key -cne $build.Identity[$key]) {
            throw 'Signing identity differs from the embedded package manifest.'
        }
    }
    $requestProvenance = Read-CodexBarBuildProvenance $request.provenance
    if ($requestProvenance.revision -cne $build.Provenance.revision -or $requestProvenance.version -cne $build.Provenance.version) {
        throw 'Signing request provenance differs from the package build.'
    }
    $requestHash = Get-CodexBarMSIXHash $requestStream
    $tool = Get-CodexBarMSIXLocalItem $SignToolPath $false
    if ($tool.Name -ine 'signtool.exe') { throw 'Select the Windows SDK SignTool.exe explicitly.' }
    $toolStream = Open-CodexBarMSIXInput $tool.FullName 536870912 $held
    $toolHash = Get-CodexBarMSIXHash $toolStream
    $output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd([char] '\')
    $parent = Get-CodexBarMSIXLocalItem ([IO.Path]::GetDirectoryName($output)) $true
    $leaf = [IO.Path]::GetFileName($output)
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf.EndsWith('.') -or $leaf.EndsWith(' ') -or
        $leaf -match '[:*?"<>|\x00-\x1f]' -or $leaf -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
        throw 'Invalid signing output directory name.'
    }
    $output = Join-Path $parent.FullName $leaf
    $prefix = $build.Directory.TrimEnd([char] '\') + '\'
    if (Test-Path -LiteralPath $output) { throw 'Signing output already exists; use a new directory.' }
    if ($output.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Signing output must be outside the unsigned package directory.' }
    $timestamp = $null
    if (-not [Uri]::TryCreate($TimestampServer, [UriKind]::Absolute, [ref] $timestamp) -or
        $timestamp.Scheme -notin @('http', 'https') -or -not [string]::IsNullOrEmpty($timestamp.UserInfo) -or
        -not [string]::IsNullOrEmpty($timestamp.Query) -or -not [string]::IsNullOrEmpty($timestamp.Fragment)) {
        throw 'Specify an HTTP(S) RFC 3161 timestamp service without URL credentials, query or fragment.'
    }
    # WhatIf stops before all certificate/private-key access, SDK execution and output mutation.
    if (-not $PSCmdlet.ShouldProcess($output, 'Sign a new MSIX copy with the selected certificate and RFC 3161 timestamp service')) { return }
    $certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
    $codeSigning = @($certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' })
    $now = [DateTime]::UtcNow
    if ($certificate.Thumbprint -ine $CertificateThumbprint -or -not $certificate.HasPrivateKey -or $codeSigning.Count -eq 0 -or
        $certificate.NotBefore.ToUniversalTime() -gt $now -or $certificate.NotAfter.ToUniversalTime() -le $now) {
        throw 'Select a current code-signing certificate with a private key in CurrentUser/My.'
    }
    # Use the certificate Subject text when composing the manifest. Never rewrite package identity while signing.
    if ($certificate.Subject -cne $build.Identity.publisher) { throw 'Certificate Subject must exactly match the embedded manifest Publisher.' }
    $null = New-Item -ItemType Directory -Path $output -ErrorAction Stop
    $target = Join-Path $output 'CodexBarWindows.msix'
    $copy = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $build.PackageStream.Position = 0
        $build.PackageStream.CopyTo($copy)
        $copy.Flush($true)
        if ($copy.Length -ne $build.PackageBytes -or (Get-CodexBarMSIXHash $copy) -cne $build.PackageSha256) {
            throw 'The signing copy differs from the requested unsigned package.'
        }
    } finally { $copy.Dispose(); $build.PackageStream.Position = 0 }
    $arguments = @('sign', '/fd', 'SHA256', '/s', 'My', '/sha1', $CertificateThumbprint,
        '/tr', $timestamp.AbsoluteUri, '/td', 'SHA256', $target)
    & $tool.FullName @arguments
    $signExit = $LASTEXITCODE
    if ($signExit -ne 0) { throw "MSIX signing or timestamping failed with exit code $signExit. Partial output is preserved." }
    $signedStream = Open-CodexBarMSIXInput $target 8740929536 $held
    $verifyArguments = @('verify', '/pa', '/all', '/tw', $target)
    & $tool.FullName @verifyArguments
    $verifyExit = $LASTEXITCODE
    if ($verifyExit -ne 0) { throw "MSIX signature verification failed or warned with exit code $verifyExit. Output is preserved." }
    $signature = Get-AuthenticodeSignature -LiteralPath $target
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ine $CertificateThumbprint -or $null -eq $signature.TimeStamperCertificate) {
        throw 'The signed package signer and timestamp were not confirmed.'
    }
    $archive = [IO.Compression.ZipArchive]::new($signedStream, [IO.Compression.ZipArchiveMode]::Read, $true)
    try {
        $signatureEntry = $archive.GetEntry('AppxSignature.p7x')
        $manifestEntry = $archive.GetEntry('AppxManifest.xml')
        $blockMapEntry = $archive.GetEntry('AppxBlockMap.xml')
        if ($null -eq $signatureEntry -or $signatureEntry.Length -le 0 -or $signatureEntry.Length -gt 16777216 -or
            $null -eq $manifestEntry -or $null -eq $blockMapEntry) { throw 'Signed package footprint is incomplete.' }
        $manifestBytes = Read-CodexBarMSIXEntry $manifestEntry 1048576
        $blockMapBytes = Read-CodexBarMSIXEntry $blockMapEntry 33554432
        if ((Get-CodexBarMSIXBytesHash $manifestBytes) -cne $build.ManifestSha256 -or
            (Get-CodexBarMSIXBytesHash $blockMapBytes) -cne $build.BlockMapSha256) {
            throw 'Signing changed the package manifest or block map.'
        }
    } finally { $archive.Dispose(); $signedStream.Position = 0 }
    $receipt = [ordered] @{
        schemaVersion = 1
        status = 'SIGNED_MSIX_RUNTIME_UNVERIFIED'
        identity = $build.Identity
        provenance = $build.Provenance
        signingRequestSha256 = $requestHash
        buildReceiptSha256 = $build.ReceiptSha256
        sourceInventorySha256 = $build.SourceInventorySha256
        unsignedPackageSha256 = $build.PackageSha256
        manifestSha256 = $build.ManifestSha256
        blockMapSha256 = $build.BlockMapSha256
        package = [ordered] @{ path = 'CodexBarWindows.msix'; bytes = $signedStream.Length; sha256 = (Get-CodexBarMSIXHash $signedStream) }
        signature = [ordered] @{
            status = 'VALID_WITH_TIMESTAMP'; signerThumbprint = $signature.SignerCertificate.Thumbprint
            timestampSignerThumbprint = $signature.TimeStamperCertificate.Thumbprint
            requestedFileDigest = 'SHA256'; requestedTimestampDigest = 'SHA256'; timestampServer = $timestamp.AbsoluteUri
        }
        tool = [ordered] @{ name = 'SignTool.exe'; sha256 = $toolHash; signExitCode = $signExit; verifyExitCode = $verifyExit }
        installation = 'NOT_RUN'
        runtimeValidation = 'NOT_RUN'
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($receipt | ConvertTo-Json -Depth 12))
    if ($bytes.Length -gt 65536) { throw 'Signed package receipt exceeds its size limit.' }
    $receiptPath = Join-Path $output 'package-signing-receipt.json'
    $stream = [IO.File]::Open($receiptPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    [pscustomobject] @{ PackagePath = $target; ReceiptPath = $receiptPath; Status = $receipt.status; RuntimeValidation = 'NOT_RUN' }
} finally {
    foreach ($stream in $held) { $stream.Dispose() }
    if ($null -ne $certificate) { $certificate.Dispose() }
}
