# Explicit shipped operations contract. Adding a helper requires adding it here as well.
function Get-CodexBarLifecycleFileNames {
    return @(
        'Install-CodexBarVersion.ps1', 'Select-CodexBarVersion.ps1',
        'Restore-CodexBarActivation.ps1', 'Remove-CodexBarVersion.ps1',
        'Restore-CodexBarRemovedVersion.ps1', 'Write-CodexBarJournal.ps1',
        'Read-CodexBarBuildProvenance.ps1', 'Read-CodexBarFirstPartyFiles.ps1',
        'Register-CodexBarInstallation.ps1', 'Invoke-CodexBarUninstall.ps1',
        'Set-CodexBarVersionReferences.ps1', 'Restore-CodexBarVersionReferences.ps1',
        'Send-CodexBarEnvironmentChange.ps1', 'Restore-CodexBarUninstall.ps1'
    )
}
function Test-CodexBarFirstPartyFile([string] $RelativePath, [string] $Kind) {
    $relative = $RelativePath.Replace('/', '\')
    if ($relative -ieq 'CodexBarWindows.exe') { return $Kind -eq 'application' }
    if ($relative -ieq 'CodexBarCLI.exe') { return $Kind -eq 'cli' }
    if ($relative -ieq 'CodexBarWidgetBackend.dll') { return $Kind -eq 'runtime' }
    if ($Kind -ne 'resource') { return $false }
    if ([IO.Path]::GetFileName($relative) -ieq 'Set-CodexBarUserPath.ps1') { return $true }
    foreach ($name in Get-CodexBarLifecycleFileNames) {
        if ($relative -ieq ('tools\' + $name)) { return $true }
    }
    return $false
}
function Assert-CodexBarFirstPartyFiles([object[]] $Files, [string] $PathProperty = 'path') {
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null = $required.Add('CodexBarWindows.exe')
    $null = $required.Add('CodexBarCLI.exe')
    foreach ($name in Get-CodexBarLifecycleFileNames) { $null = $required.Add('tools\' + $name) }
    $expectedCount = $required.Count + 1
    $pathScripts = 0
    $widgetBackends = 0
    foreach ($file in $Files) {
        $relative = ([string] $file.$PathProperty).Replace('/', '\')
        if ($relative -ieq 'CodexBarWidgetBackend.dll') {
            if ([string] $file.kind -ne 'runtime' -or $widgetBackends -ne 0) {
                throw 'Widget backend must be one root runtime DLL.'
            }
            $widgetBackends++
            continue
        }
        if (Test-CodexBarFirstPartyFile $relative ([string] $file.kind)) {
            if ([IO.Path]::GetFileName($relative) -ieq 'Set-CodexBarUserPath.ps1') { $pathScripts++ }
            elseif (-not $required.Remove($relative)) { throw 'Duplicate first-party file.' }
        }
    }
    if ($required.Count -ne 0 -or $pathScripts -ne 1) {
        throw 'Distribution must include app, CLI, one PATH resource and the complete tools contract.'
    }
    return ($expectedCount + $widgetBackends)
}
