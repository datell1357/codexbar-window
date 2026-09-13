# Selects the Start Menu launch target; does not launch, stop or remove any version.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $VersionID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
if (-not $AllowUnvalidatedBuild) { throw 'Explicit development activation opt-in is required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
if ([string]::IsNullOrWhiteSpace($localData) -or [string]::IsNullOrWhiteSpace($programs)) { throw 'User folders are unavailable.' }
$installRoot = Join-Path $localData 'Programs\CodexBarWindows'
$versions = Join-Path $installRoot 'versions'
$version = Join-Path $versions $VersionID
foreach ($path in @($installRoot, $versions, $version, $programs)) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Managed paths must be regular directories.' }
}
$lock = [IO.File]::Open((Join-Path $installRoot 'operations.lock'), [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$shell = $null
$link = $null
try {
    $receiptFile = Get-Item -LiteralPath (Join-Path $version 'installation-receipt.json') -Force
    if ($receiptFile.Length -gt 16777216 -or ($receiptFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid installation receipt.' }
    $receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json
    if ($receipt.schemaVersion -ne 1 -or $receipt.product -ne 'CodexBarWindows' -or
        $receipt.versionID -ne $VersionID -or $receipt.signerThumbprint -ine $ExpectedSignerThumbprint -or
        $receipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED') { throw 'Installation receipt does not match the selection.' }
    $appEntries = @($receipt.files | Where-Object { $_.path -ieq 'CodexBarWindows.exe' -and $_.kind -eq 'application' })
    if ($appEntries.Count -ne 1) { throw 'Missing app receipt entry.' }
    $app = Join-Path $version 'CodexBarWindows.exe'
    $item = Get-Item -LiteralPath $app -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-FileHash -LiteralPath $app -Algorithm SHA256).Hash -ine $appEntries[0].sha256) { throw 'Installed app differs from its receipt.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $app
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ine $ExpectedSignerThumbprint) { throw 'App signer is not accepted.' }
    $shortcut = Join-Path $programs 'CodexBar Windows.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $previousHash = $null
    if (Test-Path -LiteralPath $shortcut) {
        $existing = Get-Item -LiteralPath $shortcut -Force
        if ($existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Shortcut conflict.' }
        $link = $shell.CreateShortcut($shortcut)
        $previousTarget = [IO.Path]::GetFullPath($link.TargetPath)
        if (-not $previousTarget.StartsWith($versions + '\', [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($previousTarget) -ine 'CodexBarWindows.exe' -or
            -not [string]::IsNullOrEmpty($link.Arguments)) { throw 'Existing shortcut is not a managed CodexBar launch target.' }
        $previousHash = (Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash
        $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
        $link = $null
    }
    if (-not $PSCmdlet.ShouldProcess('CodexBar Windows Start Menu shortcut', 'Select the installed version and preserve the previous shortcut')) { return }
    $transaction = [Guid]::NewGuid().ToString('N')
    $temporary = Join-Path $programs ('CodexBar-' + $transaction + '.lnk')
    $backup = Join-Path $programs ('CodexBar-' + $transaction + '.previous.lnk')
    $journal = Join-Path $installRoot ('activation-' + $transaction + '.json')
    $record = [ordered] @{
        schemaVersion = 1; versionID = $VersionID; state = 'PREPARED'
        shortcut = $shortcut; previousShortcutBackup = $backup; candidateShortcut = $temporary
        previousHash = $previousHash; createdAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $link = $shell.CreateShortcut($temporary)
    $link.TargetPath = $app
    $link.WorkingDirectory = $version
    $link.Description = 'CodexBar Windows'
    $link.IconLocation = $app + ',0'
    $link.Save()
    $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
    $link = $null
    $record['candidateHash'] = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ($null -ne $previousHash) {
        if ((Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash -ne $previousHash) { throw 'Shortcut changed concurrently.' }
        [IO.File]::Replace($temporary, $shortcut, $backup)
    } else { [IO.File]::Move($temporary, $shortcut) }
    $record.state = 'SHORTCUT_SELECTED_RUNTIME_UNVERIFIED'
    $record['selectedShortcutHash'] = (Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-Output 'Start Menu target selected. Running apps, PATH and startup entries were not changed.'
} catch {
    Write-Warning 'Selection did not finish cleanly. Inspect the actual shortcut and activation journal; the shortcut may already have changed.'
    throw
} finally {
    if ($null -ne $link) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
    if ($null -ne $shell) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    $lock.Dispose()
}
