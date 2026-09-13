[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $VersionID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild
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
    $key = $registry.OpenSubKey($keyPath, $false)
    if ($null -ne $key) { throw 'Registration already exists; it will not be overwritten.' }
    if (-not $PSCmdlet.ShouldProcess($VersionID, 'Copy signed removal tools and register a current-user development installation')) { return }
    $registrationID = [Guid]::NewGuid().ToString('N')
    $bundle = Join-Path $root ('management-' + $registrationID)
    $null = New-Item -ItemType Directory -Path $bundle
    foreach ($name in Get-CodexBarLifecycleFileNames) {
        $matches = @($receipt.files | Where-Object { ([string] $_.path).Replace('/', '\') -ieq ('tools\' + $name) -and $_.kind -eq 'resource' })
        if ($matches.Count -ne 1) { throw 'Tool receipt entry missing.' }
        $source = Join-Path (Join-Path $version 'tools') $name
        $item = Get-Item -LiteralPath $source -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installed tool.' }
        $destination = Join-Path $bundle $name
        [IO.File]::Copy($source, $destination, $false)
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
    $record = [ordered] @{ schemaVersion = 1; registrationID = $registrationID; versionID = $VersionID;
        state = 'PREPARED'; uninstallCommand = $command }
    Write-CodexBarJournal (Join-Path $bundle 'registration.json') $record
    $key = $registry.OpenSubKey($keyPath, $false)
    if ($null -ne $key) { throw 'Registration appeared concurrently.' }
    $key = $registry.CreateSubKey($keyPath, $true)
    $values = [ordered] @{
        CodexBarRegistrationID = $registrationID
        DisplayName = 'CodexBar Windows ' + $receipt.provenance.version + ' (' + $receipt.architecture + ', development)'
        DisplayVersion = [string] $receipt.provenance.version
        Publisher = 'CodexBar Windows contributors'
        InstallLocation = $version
        UninstallString = $command
    }
    foreach ($name in $values.Keys) { $key.SetValue($name, $values[$name], [Microsoft.Win32.RegistryValueKind]::String) }
    $key.SetValue('NoModify', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    $key.SetValue('NoRepair', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    $key.Flush()
    $record.state = 'REGISTERED_RUNTIME_UNVERIFIED'
    Write-CodexBarJournal (Join-Path $bundle 'registration.json') $record
    Write-Output ('Development installation registered. Management ID: ' + $registrationID)
} catch {
    Write-Warning 'Registration incomplete. Inspect the registry entry and preserved management directory before retrying.'
    throw
} finally {
    foreach ($stream in $held) { $stream.Dispose() }
    if ($null -ne $key) { $key.Dispose() }
    if ($null -ne $registry) { $registry.Dispose() }
    $lock.Dispose()
}
