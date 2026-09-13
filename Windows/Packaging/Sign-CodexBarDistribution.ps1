# Implementation only. Signing requires a deliberate Windows invocation and an explicit certificate.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $DistributionDirectory,
    [Parameter(Mandatory = $true)][string] $SigningRequest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $CertificateThumbprint,
    [Parameter(Mandatory = $true)][string] $TimestampServer,
    [Parameter(Mandatory = $true)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarFirstPartyFiles.ps1')
. (Join-Path $PSScriptRoot 'Read-CodexBarBuildProvenance.ps1')
. (Join-Path $PSScriptRoot 'Read-CodexBarPEImports.ps1')
. (Join-Path $PSScriptRoot 'Read-CodexBarSystemPolicy.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$timestamp = $null
if (-not [Uri]::TryCreate($TimestampServer, [UriKind]::Absolute, [ref] $timestamp) -or
    $timestamp.Scheme -notin @('http', 'https') -or -not [string]::IsNullOrEmpty($timestamp.UserInfo)) {
    throw 'Specify the timestamp service explicitly, without credentials in its URL.'
}
$root = Get-Item -LiteralPath $DistributionDirectory -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid source directory.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Signing output must be a new directory.' }
if ($output.StartsWith($root.FullName.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Signing output must be outside the unsigned distribution.'
}
function Read-SmallJson([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.Length -gt 16777216 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid signing metadata.' }
    return (Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json)
}
$inventory = Read-SmallJson (Join-Path $root.FullName 'distribution-inventory.json')
$request = Read-SmallJson $SigningRequest
if ($inventory.schemaVersion -ne 1 -or $inventory.status -ne 'STAGED_UNVERIFIED' -or
    $request.schemaVersion -ne 1 -or $request.status -ne 'SIGNING_REQUEST_ONLY' -or
    $inventory.architecture -notin @('x64', 'arm64') -or $request.architecture -ne $inventory.architecture) {
    throw 'Signing request and distribution do not match.'
}
$sourcePolicy = $inventory.systemPolicy
$systemLibraries = Read-CodexBarSystemPolicy $sourcePolicy $inventory.architecture
$provenance = Read-CodexBarBuildProvenance $inventory.provenance
$requestProvenance = Read-CodexBarBuildProvenance $request.provenance
if ($requestProvenance.revision -ne $provenance.revision -or $requestProvenance.version -ne $provenance.version) {
    throw 'Signing provenance differs.'
}
$targets = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($target in @($request.targets)) {
    if ($targets.ContainsKey([string] $target.path)) { throw 'Duplicate signing target.' }
    $targets.Add([string] $target.path, $target)
}
$expectedTargets = Assert-CodexBarFirstPartyFiles @($inventory.files)
if ($targets.Count -ne $expectedTargets) { throw 'Signing target count does not match the first-party contract.' }
$prepared = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$matched = 0
$files = @($inventory.files)
if ($files.Count -lt 4 -or $files.Count -gt 10000) { throw 'Invalid file count.' }
foreach ($file in $files) {
    $relative = ([string] $file.path).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
        $relative -match '[:\x00-\x1f]' -or $relative -ieq 'distribution-inventory.json' -or
        -not $seen.Add($relative) -or ([string] $file.sha256) -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid inventory file.' }
    $source = $root.FullName
    foreach ($part in $relative.Split([char] '\')) {
        if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'Invalid relative path.' }
        $source = Join-Path $source $part
        $item = Get-Item -LiteralPath $source -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked signing source is unsupported.' }
    }
    if ($item.PSIsContainer -or $item.Length -ne $file.bytes -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $file.sha256) { throw 'Unsigned input has changed.' }
    $sign = $targets.ContainsKey([string] $file.path)
    if ($sign) {
        $allowed = Test-CodexBarFirstPartyFile $relative ([string] $file.kind)
        $target = $targets[[string] $file.path]
        if (-not $allowed -or $target.kind -ne $file.kind -or $target.sha256BeforeSigning -ine $file.sha256) {
            throw 'Signing target is outside the first-party contract or has changed.'
        }
        $matched++
    }
    $prepared.Add([pscustomobject] @{ source = $source; relative = $relative; entry = $file; sign = $sign })
}
if ($matched -ne $expectedTargets -or -not $targets.ContainsKey('CodexBarWindows.exe') -or -not $targets.ContainsKey('CodexBarCLI.exe')) {
    throw 'Signing targets do not cover the complete first-party contract.'
}
# WhatIf stops before certificate/private-key access and before any output mutation.
if (-not $PSCmdlet.ShouldProcess('New signed distribution', 'Sign all first-party files with the selected certificate')) { return }
$certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $CertificateThumbprint)
$codeSigning = @($certificate.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' })
if (-not $certificate.HasPrivateKey -or $codeSigning.Count -eq 0 -or
    $certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date)) {
    throw 'The selected certificate must be current and support code signing with a private key.'
}
$null = New-Item -ItemType Directory -Path $output
$newFiles = [Collections.Generic.List[object]]::new()
$heldFiles = [Collections.Generic.List[IO.FileStream]]::new()
$finalDependencies = [Collections.Generic.List[object]]::new()
$runtimeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $prepared) {
    if ($file.entry.kind -eq 'runtime' -and [IO.Path]::GetFileName($file.relative) -eq $file.relative) {
        $null = $runtimeNames.Add($file.relative)
    }
}
$expectedMachine = if ($inventory.architecture -eq 'x64') { 0x8664 } else { 0xAA64 }
try {
    foreach ($file in $prepared) {
        $destination = Join-Path $output $file.relative
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        [IO.File]::Copy($file.source, $destination, $false)
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $file.entry.sha256) {
            throw 'Copied bytes differ from the signing request.'
        }
        $signer = $null
        if ($file.sign) {
            $null = Set-AuthenticodeSignature -LiteralPath $destination -Certificate $certificate `
                -HashAlgorithm SHA256 -IncludeChain NotRoot -TimestampServer $TimestampServer -Confirm:$false
        }
        # Lock the final bytes after signing, before checking signature/imports/hash.
        $held = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $heldFiles.Add($held)
        if ($file.sign) {
            $signature = Get-AuthenticodeSignature -LiteralPath $destination
            if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
                $signature.SignerCertificate.Thumbprint -ine $CertificateThumbprint -or
                $null -eq $signature.TimeStamperCertificate) { throw 'Signature or timestamp was not confirmed.' }
            $signer = $signature.SignerCertificate.Thumbprint
        }
        if ($file.entry.kind -in @('application', 'cli', 'runtime')) {
            foreach ($import in @(Read-CodexBarPEImports $destination $expectedMachine)) {
                if ($finalDependencies.Count -ge 100000) { throw 'Final import graph exceeds its limit.' }
                $resolution = if ($runtimeNames.Contains($import.name)) { 'included' }
                    elseif ($systemLibraries.ContainsKey($import.name)) { 'declared_system' }
                    else { throw 'Signed output contains an unresolved imported DLL.' }
                $finalDependencies.Add([pscustomobject] @{
                    importer = $file.entry.path; library = $import.name
                    kind = $import.kind; resolution = $resolution
                })
            }
        }
        $held.Position = 0
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $digest = $hasher.ComputeHash($held) } finally { $hasher.Dispose() }
        $hash = [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
        if (-not $file.sign -and $hash -ine $file.entry.sha256) {
            throw 'A vendor or other unsigned file changed during finalization.'
        }
        $newFiles.Add([pscustomobject] @{
            path = $file.entry.path; kind = $file.entry.kind; bytes = $held.Length
            sha256 = $hash; signerThumbprint = $signer
        })
    }
    $record = [ordered] @{
        schemaVersion = 1; architecture = $inventory.architecture; provenance = $provenance
        status = 'SIGNED_RUNTIME_UNVERIFIED'; files = @($newFiles.ToArray())
        dependencyAnalysis = 'HELD_FINAL_FILES_STATIC_AND_RVA_DELAY_IMPORT_NAMES'
        dependencies = @($finalDependencies.ToArray()); systemPolicy = $sourcePolicy
        releaseApproved = $false
    }
    $json = $record | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $output 'distribution-inventory.json'), $json, [Text.UTF8Encoding]::new($false))
    Write-Output 'Signing and hash regeneration completed. Windows runtime and release gates remain outstanding.'
} catch {
    Write-Warning 'Signing incomplete. The unsigned source and partial signed output were preserved; use a fresh output on retry.'
    throw
} finally {
    foreach ($held in $heldFiles) { $held.Dispose() }
}
