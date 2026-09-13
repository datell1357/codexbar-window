# Installs a signed payload side-by-side. Activation and uninstall are separate operations.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $DistributionDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild,
    [switch] $ResumeIncomplete
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarBuildProvenance.ps1')
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Current payloads are runtime-unverified. Explicit development installation opt-in is required.' }
$root = Get-Item -LiteralPath $DistributionDirectory -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid payload root.' }
$inventoryPath = Join-Path $root.FullName 'distribution-inventory.json'
$metadata = Get-Item -LiteralPath $inventoryPath -Force
if ($metadata.PSIsContainer -or $metadata.Length -gt 16777216 -or
    ($metadata.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid payload inventory.' }
$inventoryBytes = [IO.File]::ReadAllBytes($inventoryPath)
if ($inventoryBytes.Length -gt 16777216) { throw 'Inventory changed beyond the size limit.' }
$inventory = [Text.Encoding]::UTF8.GetString($inventoryBytes).TrimStart([char] 0xfeff) | ConvertFrom-Json
$hasher = [Security.Cryptography.SHA256]::Create()
try { $inventoryHash = [BitConverter]::ToString($hasher.ComputeHash($inventoryBytes)).Replace('-', '') }
finally { $hasher.Dispose() }
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
if ((Test-Path -LiteralPath $target) -and -not $ResumeIncomplete) { throw 'This version directory already exists; use ResumeIncomplete only for a recorded incomplete installation.' }
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
$lockPath = Join-Path $installRoot 'operations.lock'
if (Test-Path -LiteralPath $lockPath) {
    $item = Get-Item -LiteralPath $lockPath -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installation lock.' }
}
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$heldFiles = [Collections.Generic.List[IO.FileStream]]::new()
try {
    $planPath = Join-Path $installRoot ('installation-' + $versionID + '.json')
    $receiptPath = Join-Path $target 'installation-receipt.json'
    if ($ResumeIncomplete) {
        $item = Get-Item -LiteralPath $planPath -Force
        if ($item.PSIsContainer -or $item.Length -gt 65536 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installation recovery record.' }
        $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
        if ($plan.schemaVersion -ne 1 -or $plan.versionID -ne $versionID -or
            $plan.inventoryHash -ine $inventoryHash -or $plan.signerThumbprint -ine $ExpectedSignerThumbprint -or
            $plan.state -notin @('PREPARED', 'COPYING')) { throw 'Recovery requires the same recorded inventory and signer.' }
    } else {
        if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $planPath)) {
            throw 'An installation already exists or is pending; no existing files were overwritten.'
        }
        $plan = [ordered] @{ schemaVersion = 1; versionID = $versionID; inventoryHash = $inventoryHash;
            signerThumbprint = $ExpectedSignerThumbprint.ToUpperInvariant(); state = 'PREPARED';
            createdAtUtc = [DateTime]::UtcNow.ToString('o') }
        Write-CodexBarJournal $planPath $plan
    }
    if (Test-Path -LiteralPath $target) {
        $item = Get-Item -LiteralPath $target -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid version directory.' }
    } else { $null = New-Item -ItemType Directory -Path $target }
    $existingReceipt = $null
    if (Test-Path -LiteralPath $receiptPath) {
        if (-not $ResumeIncomplete) { throw 'Installation receipt already exists.' }
        $item = Get-Item -LiteralPath $receiptPath -Force
        if ($item.PSIsContainer -or $item.Length -gt 16777216 -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid existing receipt.' }
        $existingReceipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        if ($existingReceipt.schemaVersion -ne 1 -or $existingReceipt.product -ne 'CodexBarWindows' -or
            $existingReceipt.versionID -ne $versionID -or $existingReceipt.architecture -ne $inventory.architecture -or
            $existingReceipt.signerThumbprint -ine $ExpectedSignerThumbprint -or
            $existingReceipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED' -or
            $existingReceipt.provenance.repository -ne $provenance.repository -or
            $existingReceipt.provenance.revision -ne $provenance.revision -or
            $existingReceipt.provenance.version -ne $provenance.version) { throw 'Receipt differs from the recorded installation.' }
        $receiptFiles = @($existingReceipt.files)
        if ($receiptFiles.Count -ne $files.Count) { throw 'Receipt inventory differs.' }
        for ($index = 0; $index -lt $files.Count; $index++) {
            if ($receiptFiles[$index].path -cne $files[$index].path -or
                $receiptFiles[$index].kind -ne $files[$index].kind -or
                $receiptFiles[$index].bytes -ne $files[$index].bytes -or
                $receiptFiles[$index].sha256 -ine $files[$index].sha256) { throw 'Receipt file differs from the inventory.' }
        }
    }
    $staging = $null
    function Open-VerifiedInstalledFile([string] $Path, [object] $File) {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($stream.Length -ne $File.entry.bytes) { throw 'Installed file size differs from payload.' }
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $digest = $hasher.ComputeHash($stream) } finally { $hasher.Dispose() }
            if ([BitConverter]::ToString($digest).Replace('-', '') -ine $File.entry.sha256) { throw 'Installed bytes differ from payload.' }
            if ($File.signed) {
                $signature = Get-AuthenticodeSignature -LiteralPath $Path
                if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
                    $signature.SignerCertificate.Thumbprint -ine $ExpectedSignerThumbprint -or
                    $null -eq $signature.TimeStamperCertificate) { throw 'Installed first-party signature is not accepted.' }
            }
            return $stream
        } catch { $stream.Dispose(); throw }
    }
    $plan.state = 'COPYING'
    Write-CodexBarJournal $planPath $plan
    foreach ($file in $prepared) {
        $destination = $target
        $parts = $file.relative.Split([char] '\')
        for ($index = 0; $index -lt $parts.Length - 1; $index++) {
            $destination = Join-Path $destination $parts[$index]
            if (Test-Path -LiteralPath $destination) {
                $item = Get-Item -LiteralPath $destination -Force
                if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installed parent directory.' }
            } else {
                if ($null -ne $existingReceipt) { throw 'Completed receipt has a missing directory; reconciliation does not repair files.' }
                $null = New-Item -ItemType Directory -Path $destination
            }
        }
        $destination = Join-Path $destination $parts[-1]
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if (-not $ResumeIncomplete -or $item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Installed file conflict; preserved without overwrite.' }
        } else {
            if ($null -ne $existingReceipt) { throw 'Completed receipt has a missing file; reconciliation does not repair files.' }
            if ($null -eq $staging) {
                $staging = Join-Path $installRoot ('install-staging-' + [Guid]::NewGuid().ToString('N'))
                $null = New-Item -ItemType Directory -Path $staging
            }
            # Preserve the file extension for Authenticode script handling. Partial copies stay outside the version.
            $temporary = Join-Path $staging ([Guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($destination))
            $inputStream = [IO.File]::Open($file.source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $outputStream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $inputStream.CopyTo($outputStream); $outputStream.Flush($true) }
                finally { $outputStream.Dispose() }
            } finally { $inputStream.Dispose() }
            $stagedHandle = Open-VerifiedInstalledFile $temporary $file
            $stagedHandle.Dispose()
            [IO.File]::Move($temporary, $destination)
        }
        # Recheck after publication and retain the installed handle through receipt finalization.
        $held = Open-VerifiedInstalledFile $destination $file
        $heldFiles.Add($held)
    }
    $receipt = [ordered] @{
        schemaVersion = 1; product = 'CodexBarWindows'; versionID = $versionID
        provenance = $provenance; architecture = $inventory.architecture
        signerThumbprint = $ExpectedSignerThumbprint.ToUpperInvariant()
        state = 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED'
        files = $files; installedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    if ($null -eq $existingReceipt) { Write-CodexBarJournal $receiptPath $receipt }
    $plan.state = 'RECEIPT_PUBLISHED_RUNTIME_UNVERIFIED'
    Write-CodexBarJournal $planPath $plan
    if ($null -ne $existingReceipt) {
        Write-Output 'Existing receipt and payload matched; interrupted installation record finalized without replacing the receipt or payload.'
    } else {
        Write-Output 'Version payload installed but inactive. Shortcuts, PATH, startup and user settings were not changed.'
    }
} catch {
    Write-Warning 'Installation did not finish cleanly. Inspect the receipt and installation record: receipt publication may already have completed. Existing versions and partial output were preserved; no activation occurred.'
    throw
} finally {
    foreach ($held in $heldFiles) { $held.Dispose() }
    $lock.Dispose()
}
