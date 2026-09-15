# Records an explicit package signing handoff. Never reads certificates or invokes a signer.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $PackageDirectory,
    [Parameter(Mandatory = $true)][string] $OutputRequest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarMSIXBuild.ps1')
$held = [Collections.Generic.List[IO.FileStream]]::new()
try {
    $build = Read-CodexBarMSIXBuild $PackageDirectory $held
    $output = [IO.Path]::GetFullPath($OutputRequest)
    $parent = Get-CodexBarMSIXLocalItem ([IO.Path]::GetDirectoryName($output)) $true
    $name = [IO.Path]::GetFileName($output)
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,119}\.json$' -or
        $name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') { throw 'Use a simple JSON output filename.' }
    $output = Join-Path $parent.FullName $name
    $prefix = $build.Directory.TrimEnd([char] '\') + '\'
    if ($output.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Keep the signing request outside the package build directory.' }
    $request = [ordered] @{
        schemaVersion = 1
        status = 'MSIX_SIGNING_REQUEST_ONLY'
        provenance = $build.Provenance
        identity = $build.Identity
        buildReceiptSha256 = $build.ReceiptSha256
        sourceInventorySha256 = $build.SourceInventorySha256
        package = [ordered] @{ path = 'CodexBarWindows.msix'; bytes = $build.PackageBytes; sha256BeforeSigning = $build.PackageSha256 }
        manifestSha256 = $build.ManifestSha256
        blockMapSha256 = $build.BlockMapSha256
        hashAlgorithm = $build.HashAlgorithm
        certificateSelection = 'EXPLICIT_CURRENT_USER_MY_THUMBPRINT_WITH_MATCHING_PUBLISHER'
        afterSigning = 'VERIFY_PACKAGE_SIGNATURE_TIMESTAMP_AND_RECORD_SIGNED_BYTES'
        runtimeValidation = 'NOT_RUN'
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($request | ConvertTo-Json -Depth 10))
    if ($bytes.Length -gt 65536) { throw 'Signing request exceeds its size limit.' }
    if (-not $PSCmdlet.ShouldProcess($output, 'Write a signing request bound to the unsigned package bytes and embedded publisher')) { return }
    $stream = [IO.File]::Open($output, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    [pscustomobject] @{ RequestPath = $output; Status = $request.status; RuntimeValidation = 'NOT_RUN' }
} finally {
    foreach ($stream in $held) { $stream.Dispose() }
}
