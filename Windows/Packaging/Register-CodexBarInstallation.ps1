[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $VersionID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild,
    [ValidatePattern('^[0-9a-f]{32}$')][string] $ResumeRegistrationID
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarFirstPartyFiles.ps1')
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not $AllowUnvalidatedBuild) { throw 'Windows and explicit development registration opt-in are required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'User folder unavailable.' }
$root = Join-Path $localData 'Programs\CodexBarWindows'
$version = Join-Path (Join-Path $root 'versions') $VersionID
foreach ($path in @($localData, (Join-Path $localData 'Programs'), $root, (Join-Path $root 'versions'), $version, (Join-Path $version 'tools'))) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installation directory.' }
}
$lockPath = Join-Path $root 'operations.lock'
$item = Get-Item -LiteralPath $lockPath -Force
if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid operations lock.' }
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$registry = $null
$key = $null
$held = [Collections.Generic.List[IO.FileStream]]::new()
try {
    $receiptPath = Join-Path $version 'installation-receipt.json'
    $item = Get-Item -LiteralPath $receiptPath -Force
    if ($item.PSIsContainer -or $item.Length -gt 16777216 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid receipt.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schemaVersion -ne 1 -or $receipt.product -ne 'CodexBarWindows' -or $receipt.versionID -ne $VersionID -or
        $receipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED' -or $receipt.signerThumbprint -ine $ExpectedSignerThumbprint) { throw 'Receipt mismatch.' }
    $null = Assert-CodexBarFirstPartyFiles @($receipt.files)
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
    $keyPath = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexBarWindows-' + $VersionID
    $resuming = -not [string]::IsNullOrWhiteSpace($ResumeRegistrationID)
    $registrationID = if ($resuming) { $ResumeRegistrationID } else { [Guid]::NewGuid().ToString('N') }
    $bundle = Join-Path $root ('management-' + $registrationID)
    $journalPath = Join-Path $bundle 'registration.json'
    $receiptHash = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    if ($resuming) {
        $item = Get-Item -LiteralPath $bundle -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid management directory.' }
        $item = Get-Item -LiteralPath $journalPath -Force
        if ($item.PSIsContainer -or $item.Length -gt 65536 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid registration record.' }
        $record = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        if ($record.schemaVersion -ne 2 -or $record.registrationID -ne $registrationID -or
            $record.versionID -ne $VersionID -or $record.receiptHash -ine $receiptHash -or
            $record.signerThumbprint -ine $ExpectedSignerThumbprint -or
            $record.state -notin @('PREPARING_TOOLS', 'PREPARED', 'REGISTERED_RUNTIME_UNVERIFIED')) {
            throw 'Registration recovery does not match this receipt, signer or supported state.'
        }
    } else {
        $record = [ordered] @{ schemaVersion = 2; registrationID = $registrationID; versionID = $VersionID;
            receiptHash = $receiptHash; signerThumbprint = $ExpectedSignerThumbprint;
            state = 'PREPARING_TOOLS'; uninstallCommand = '' }
    }
    $key = $registry.OpenSubKey($keyPath, $false)
    if ($null -ne $key) {
        if (-not $resuming -or $key.GetValue('CodexBarRegistrationID') -cne $registrationID) {
            throw 'Registration already exists or ownership is missing; it will not be overwritten.'
        }
        $key.Dispose(); $key = $null
    }
    if (-not $PSCmdlet.ShouldProcess($VersionID, 'Prepare signed removal tools and complete the current-user development registration')) { return }
    if (-not $resuming) {
        $null = New-Item -ItemType Directory -Path $bundle
        Write-CodexBarJournal $journalPath $record
    }
    foreach ($name in Get-CodexBarLifecycleFileNames) {
        $matches = @($receipt.files | Where-Object { ([string] $_.path).Replace('/', '\') -ieq ('tools\' + $name) -and $_.kind -eq 'resource' })
        if ($matches.Count -ne 1) { throw 'Tool receipt entry missing.' }
        $source = Join-Path (Join-Path $version 'tools') $name
        $item = Get-Item -LiteralPath $source -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installed tool.' }
        $destination = Join-Path $bundle $name
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if (-not $resuming -or $item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Existing management tool conflict.' }
        } else { [IO.File]::Copy($source, $destination, $false) }
        $stream = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $held.Add($stream)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') } finally { $hasher.Dispose() }
        $signature = Get-AuthenticodeSignature -LiteralPath $destination
        if ($hash -ine $matches[0].sha256 -or $signature.Status -ne 'Valid' -or
            $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ine $ExpectedSignerThumbprint -or
            $null -eq $signature.TimeStamperCertificate) { throw 'Removal tool hash or signature mismatch.' }
    }
    $powershell = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    $launcher = Join-Path $bundle 'Invoke-CodexBarUninstall.ps1'
    if ($powershell -match '["\x00-\x1f]' -or $launcher -match '["\x00-\x1f]') { throw 'Unsupported command path.' }
    $command = '"' + $powershell + '" -NoLogo -NoProfile -STA -ExecutionPolicy AllSigned -File "' + $launcher + '" -VersionID "' + $VersionID + '" -RegistrationID ' + $registrationID
    if ($resuming -and -not [string]::IsNullOrEmpty($record.uninstallCommand) -and $record.uninstallCommand -cne $command) {
        throw 'Recorded removal command differs; registration was preserved.'
    }
    $record.uninstallCommand = $command
    $record.state = 'PREPARED'
    Write-CodexBarJournal $journalPath $record
    $values = [ordered] @{
        CodexBarRegistrationID = $registrationID
        DisplayName = 'CodexBar Windows ' + $receipt.provenance.version + ' (' + $receipt.architecture + ', development)'
        DisplayVersion = [string] $receipt.provenance.version
        Publisher = 'CodexBar Windows contributors'
        InstallLocation = $version
        UninstallString = $command
    }
    $key = $registry.OpenSubKey($keyPath, $true)
    if ($null -eq $key) {
        $key = $registry.CreateSubKey($keyPath, $true)
        # A newly appeared populated key is not ours. An empty-key creation race is still possible.
        if ($key.ValueCount -ne 0 -or $key.SubKeyCount -ne 0) { throw 'Registration appeared concurrently.' }
        $key.SetValue('CodexBarRegistrationID', $registrationID, [Microsoft.Win32.RegistryValueKind]::String)
    }
    if ($key.GetValue('CodexBarRegistrationID') -cne $registrationID -or $key.SubKeyCount -ne 0) {
        throw 'Registration ownership changed.'
    }
    $allowedNames = @($values.Keys) + @('NoModify', 'NoRepair')
    foreach ($name in $key.GetValueNames()) {
        if ($name -notin $allowedNames) { throw 'Additional registration data was preserved.' }
        $expectedKind = if ($name -in @('NoModify', 'NoRepair')) { [Microsoft.Win32.RegistryValueKind]::DWord } else { [Microsoft.Win32.RegistryValueKind]::String }
        $expectedValue = if ($name -in @('NoModify', 'NoRepair')) { 1 } else { $values[$name] }
        if ($key.GetValueKind($name) -ne $expectedKind -or $key.GetValue($name) -cne $expectedValue) {
            throw 'Existing registration value differs; no conflicting value was overwritten.'
        }
    }
    # Fill only absent values. Recheck each one after preflight, without claiming atomic compare-and-set.
    foreach ($name in $allowedNames) {
        if ($key.GetValue('CodexBarRegistrationID') -cne $registrationID) { throw 'Registration ownership changed during publication.' }
        $kind = if ($name -in @('NoModify', 'NoRepair')) { [Microsoft.Win32.RegistryValueKind]::DWord } else { [Microsoft.Win32.RegistryValueKind]::String }
        $value = if ($name -in @('NoModify', 'NoRepair')) { 1 } else { $values[$name] }
        if ($name -in $key.GetValueNames()) {
            if ($key.GetValueKind($name) -ne $kind -or $key.GetValue($name) -cne $value) { throw 'Registration changed concurrently.' }
        } else { $key.SetValue($name, $value, $kind) }
    }
    $key.Flush()
    $record.state = 'REGISTERED_RUNTIME_UNVERIFIED'
    Write-CodexBarJournal $journalPath $record
    Write-Output ('Development installation registered. Management ID: ' + $registrationID)
} catch {
    Write-Warning 'Registration incomplete. Inspect the registry entry and management-ID directory; ResumeRegistrationID can reuse a matching schema-2 record without replacing conflicting files or values.'
    throw
} finally {
    foreach ($stream in $held) { $stream.Dispose() }
    if ($null -ne $key) { $key.Dispose() }
    if ($null -ne $registry) { $registry.Dispose() }
    $lock.Dispose()
}
