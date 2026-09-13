# Implementation only; not executed or validated on Windows.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Add', 'Remove')]
    [string] $Action,
    [Parameter(Mandatory = $true)]
    [string] $Directory,
    [switch] $ResultProtocolV1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This command requires Windows.'
}
# Require a literal local drive path. Do not expand variables or resolve relative paths.
if ($Directory -notmatch '^[A-Za-z]:[\\/]' -or $Directory -match '[;"%\x00-\x1f]' -or
    $Directory.Length -gt 2048) {
    throw 'Specify an absolute local CLI directory without PATH separators, quotes or variables.'
}
$targetDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
if ($targetDirectory.Length -eq 2) { throw 'Do not add an entire drive root to PATH.' }

function Test-TargetEntry([string] $Entry) {
    $literal = $Entry.Trim()
    if ($literal.StartsWith('"') -and $literal.EndsWith('"') -and $literal.Length -ge 2) {
        $literal = $literal.Substring(1, $literal.Length - 2)
    }
    # Do not equate environment references, junctions or other indirect spellings.
    return [string]::Equals($literal.Replace('/', '\').TrimEnd('\'),
        $targetDirectory.Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase)
}

if ($Action -eq 'Add') {
    $folder = Get-Item -LiteralPath $targetDirectory -Force
    if (-not $folder.PSIsContainer -or ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The CLI directory must be a regular directory.'
    }
    $found = $false
    foreach ($name in @('CodexBarCLI.exe', 'codexbar.exe')) {
        $candidate = Join-Path $targetDirectory $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $file = Get-Item -LiteralPath $candidate -Force
            if (-not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $found = $true }
        }
    }
    if (-not $found) { throw 'No regular CodexBar CLI candidate exists in this directory.' }
}

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
if ($null -eq $key) { throw 'The user Environment key is unavailable; no change was made.' }
try {
    $options = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    $oldValue = $key.GetValue('Path', $null, $options)
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    if ($null -ne $oldValue) {
        $kind = $key.GetValueKind('Path')
        if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and
            $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) {
            throw 'User Path has an unsupported value type.'
        }
    }
    $raw = if ($null -eq $oldValue) { '' } else { [string] $oldValue }
    if ($raw.Length -gt 32766) { throw 'User Path is too large to edit.' }
    $entries = if ($raw.Length -eq 0) { @() } else { @($raw.Split([char] ';')) }
    $matching = @($entries | Where-Object { Test-TargetEntry $_ })
    if ($Action -eq 'Add') {
        if ($matching.Count -gt 0) {
            if ($ResultProtocolV1) { exit 21 }
            Write-Output 'Already present; user Path unchanged.'; return
        }
        # Append to preserve the precedence of all existing entries, including empty entries.
        $updated = if ($raw.Length -eq 0) { $targetDirectory } else { $raw + ';' + $targetDirectory }
    } else {
        if ($matching.Count -eq 0) {
            if ($ResultProtocolV1) { exit 21 }
            Write-Output 'No matching literal entry; user Path unchanged.'; return
        }
        $updated = (@($entries | Where-Object { -not (Test-TargetEntry $_) }) -join ';')
    }
    if ($updated.Length -gt 32766) { throw 'The resulting user Path would be too large.' }
    if (-not $PSCmdlet.ShouldProcess('Current user Path', "$Action the specified CLI directory")) {
        if ($ResultProtocolV1) { exit 22 }
        return
    }
    # Detect intervening edits before mutation. Registry provides no atomic compare-and-swap here.
    $current = $key.GetValue('Path', $null, $options)
    if (-not [object]::Equals($current, $oldValue) -or
        ($null -ne $current -and $key.GetValueKind('Path') -ne $kind)) {
        throw 'User Path changed concurrently. Retry after reviewing your environment settings.'
    }
    $key.SetValue('Path', $updated, $kind)
    if ($ResultProtocolV1) { exit 20 }
    Write-Output 'User Path updated. Sign out and sign in again so newly launched apps inherit the change.'
    Write-Output 'The CLI was not executed. Existing processes and machine Path were not changed.'
} finally {
    $key.Dispose()
}
