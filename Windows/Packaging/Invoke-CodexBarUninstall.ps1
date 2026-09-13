# Interactive entry point kept outside the version being retired.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $VersionID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $RegistrationID
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
Add-Type -AssemblyName System.Windows.Forms
try {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localData)) { throw 'User folder unavailable.' }
    $root = Join-Path $localData 'Programs\CodexBarWindows'
    $bundle = Join-Path $root ('management-' + $RegistrationID)
    if ([IO.Path]::GetFullPath($PSScriptRoot) -ine $bundle) { throw 'Unexpected removal launcher location.' }
    foreach ($path in @($root, $bundle)) {
        $item = Get-Item -LiteralPath $path -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid management directory.' }
    }
    $answer = [Windows.Forms.MessageBox]::Show(
        'Remove this CodexBar Windows development version? Settings and recoverable file copies will be retained. Known Start Menu, user PATH and CodexBar startup references will be detached. Close this version first. Customized or machine-wide references may require manual changes.',
        'CodexBar Windows', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question,
        [Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { exit 0 }
    & (Join-Path $bundle 'Set-CodexBarVersionReferences.ps1') -FromVersionID $VersionID -AllowUnvalidatedBuild | Out-Null
    $result = & (Join-Path $bundle 'Remove-CodexBarVersion.ps1') -VersionID $VersionID -AllowUnvalidatedBuild -PassThru
    if ($null -eq $result -or $result.state -ne 'RECEIPT_PAYLOAD_RETIRED_UNVERIFIED') {
        throw 'Removal is partial. Registration and recoverable files were retained; inspect the removal journal.'
    }
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
    $key = $null
    try {
        $keyPath = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexBarWindows-' + $VersionID
        $key = $registry.OpenSubKey($keyPath, $false)
        if ($null -ne $key) {
            if ($key.GetValue('CodexBarRegistrationID') -ne $RegistrationID -or
                $key.GetValue('InstallLocation') -ine (Join-Path (Join-Path $root 'versions') $VersionID)) { throw 'Registration changed; it was preserved.' }
            $allowed = @('CodexBarRegistrationID', 'DisplayName', 'DisplayVersion', 'Publisher', 'InstallLocation', 'UninstallString', 'NoModify', 'NoRepair')
            if ($key.SubKeyCount -ne 0 -or @($key.GetValueNames() | Where-Object { $_ -notin $allowed }).Count -ne 0) { throw 'Registration contains additional data; it was preserved.' }
            $key.Dispose(); $key = $null
            $registry.DeleteSubKey($keyPath, $false)
        }
    } finally {
        if ($null -ne $key) { $key.Dispose() }
        $registry.Dispose()
    }
    $null = [Windows.Forms.MessageBox]::Show('Version files retired and registration removed. Settings, recovery copies and management tools were retained.', 'CodexBar Windows')
} catch {
    $null = [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CodexBar Windows removal', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
