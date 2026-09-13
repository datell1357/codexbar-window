# Installs a signed payload side-by-side. Activation and uninstall are separate operations.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $DistributionDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarBuildProvenance.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Current payloads are runtime-unverified. Explicit development installation opt-in is required.' }
$root = Get-Item -LiteralPath $DistributionDirectory -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid payload root.' }
$inventoryPath = Join-Path $root.FullName 'distribution-inventory.json'
$metadata = Get-Item -LiteralPath $inventoryPath -Force
if ($metadata.PSIsContainer -or $metadata.Length -gt 16777216 -or
    ($metadata.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid payload inventory.' }
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
if ($inventory.schemaVersion -ne 1 -or $inventory.status -ne 'SIGNED_RUNTIME_UNVERIFIED' -or
    $inventory.architecture -notin @('x64', 'arm64')) { throw 'Unsupported signed payload inventory.' }
$provenance = Read-CodexBarBuildProvenance $inventory.provenance
$files = @($inventory.files)
if ($files.Count -lt 4 -or $files.Count -gt 10000) { throw 'Invalid payload size.' }
$prepared = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$firstParty = 0
foreach ($file in $files) {
    $relative = ([string] $file.path).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
        $relative -match '[:\x00-\x1f]' -or $relative -in @('installation-receipt.json', 'distribution-inventory.json') -or
        -not $seen.Add($relative) -or ([string] $file.sha256) -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid payload entry.' }
    $source = $root.FullName
    foreach ($part in $relative.Split([char] '\')) {
        if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ')) { throw 'Unsafe payload path.' }
        $source = Join-Path $source $part
        $item = Get-Item -LiteralPath $source -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Payload links are unsupported.' }
    }
    if ($item.PSIsContainer -or $item.Length -ne $file.bytes -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $file.sha256) { throw 'Payload hash mismatch.' }
    $signed = ($relative -ieq 'CodexBarWindows.exe' -and $file.kind -eq 'application') -or
        ($relative -ieq 'CodexBarCLI.exe' -and $file.kind -eq 'cli') -or
        ([IO.Path]::GetFileName($relative) -ieq 'Set-CodexBarUserPath.ps1' -and $file.kind -eq 'resource')
    if ($signed) { $firstParty++ }
    $prepared.Add([pscustomobject] @{ source = $source; relative = $relative; entry = $file; signed = $signed })
}
if ($firstParty -ne 3 -or -not $seen.Contains('CodexBarWindows.exe') -or -not $seen.Contains('CodexBarCLI.exe')) {
    throw 'Missing first-party payload files.'
}
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Local application data is unavailable.' }
$installRoot = Join-Path $localData 'Programs\CodexBarWindows'
$versionID = $provenance.version + '-' + $inventory.architecture + '-' + $provenance.revision
$target = Join-Path (Join-Path $installRoot 'versions') $versionID
if (Test-Path -LiteralPath $target) { throw 'This version directory already exists; it will not be overwritten.' }
if (-not $PSCmdlet.ShouldProcess('Current-user version directory', 'Install signed development payload without activation')) { return }
# Reject known links in the managed installation path before creating or copying files.
$current = $localData
foreach ($part in @('Programs', 'CodexBarWindows', 'versions')) {
    $current = Join-Path $current $part
    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Installation path is not a regular directory.' }
    } else { $null = New-Item -ItemType Directory -Path $current }
}
$lock = [IO.File]::Open((Join-Path $installRoot 'operations.lock'), [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$heldFiles = [Collections.Generic.List[IO.FileStream]]::new()
try {
    $null = New-Item -ItemType Directory -Path $target
    foreach ($file in $prepared) {
        $destination = Join-Path $target $file.relative
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        [IO.File]::Copy($file.source, $destination, $false)
        $held = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $heldFiles.Add($held)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $digest = $hasher.ComputeHash($held) } finally { $hasher.Dispose() }
        if ([BitConverter]::ToString($digest).Replace('-', '') -ine $file.entry.sha256) { throw 'Installed bytes differ from payload.' }
        if ($file.signed) {
            $signature = Get-AuthenticodeSignature -LiteralPath $destination
            if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
                $signature.SignerCertificate.Thumbprint -ine $ExpectedSignerThumbprint -or
                $null -eq $signature.TimeStamperCertificate) { throw 'Installed first-party signature is not accepted.' }
        }
    }
    $receipt = [ordered] @{
        schemaVersion = 1; product = 'CodexBarWindows'; versionID = $versionID
        provenance = $provenance; architecture = $inventory.architecture
        signerThumbprint = $ExpectedSignerThumbprint.ToUpperInvariant()
        state = 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED'
        files = $files; installedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $target 'installation-receipt.json'),
        ($receipt | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Write-Output 'Version payload installed but inactive. Shortcuts, PATH, startup and user settings were not changed.'
} catch {
    Write-Warning 'Installation incomplete. Existing versions and partial output were preserved; no activation occurred.'
    throw
} finally {
    foreach ($held in $heldFiles) { $held.Dispose() }
    $lock.Dispose()
}
