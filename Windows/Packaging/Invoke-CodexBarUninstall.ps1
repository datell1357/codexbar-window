# Interactive entry point kept outside the version being retired.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $VersionID,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string] $RegistrationID
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
$handoff = $null
$handoffPath = $null
function Read-FailureTransaction([Exception] $Exception, [string] $Key) {
    $current = $Exception
    for ($depth = 0; $depth -lt 8 -and $null -ne $current; $depth++) {
        $value = [string] $current.Data[$Key]
        if ($value -match '^[0-9a-f]{32}$') { return $value }
        $current = $current.InnerException
    }
    return $null
}
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
    $handoffPath = Join-Path $bundle ('uninstall-' + [Guid]::NewGuid().ToString('N') + '.json')
    $handoff = [ordered] @{ schemaVersion = 1; versionID = $VersionID; registrationID = $RegistrationID;
        stage = 'DETACHING_REFERENCES'; referenceTransactionID = $null; removalTransactionID = $null;
        referenceState = $null; removalState = $null; environmentNotification = $null }
    Write-CodexBarJournal $handoffPath $handoff
    $reference = & (Join-Path $bundle 'Set-CodexBarVersionReferences.ps1') -FromVersionID $VersionID -AllowUnvalidatedBuild -PassThru
    if ($null -eq $reference -or $reference.transactionID -notmatch '^[0-9a-f]{32}$' -or
        $reference.state -ne 'REFERENCES_UPDATED_RUNTIME_UNVERIFIED') { throw 'Reference update did not return a supported completion record.' }
    $handoff.referenceTransactionID = $reference.transactionID
    $handoff.referenceState = $reference.state
    $handoff.environmentNotification = $reference.environmentNotification
    $handoff.stage = 'RETIRING_FILES'
    Write-CodexBarJournal $handoffPath $handoff
    $result = & (Join-Path $bundle 'Remove-CodexBarVersion.ps1') -VersionID $VersionID -AllowUnvalidatedBuild -PassThru
    if ($null -ne $result -and $result.transactionID -match '^[0-9a-f]{32}$') {
        $handoff.removalTransactionID = $result.transactionID
        $handoff.removalState = $result.state
        Write-CodexBarJournal $handoffPath $handoff
    }
    if ($null -eq $result -or $result.state -ne 'RECEIPT_PAYLOAD_RETIRED_UNVERIFIED') {
        throw 'Removal is partial. Registration and recoverable files were retained; inspect the removal journal.'
    }
    $handoff.stage = 'REMOVING_REGISTRATION'
    Write-CodexBarJournal $handoffPath $handoff
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
    $handoff.stage = 'COMPLETED_RUNTIME_UNVERIFIED'
    Write-CodexBarJournal $handoffPath $handoff
    $null = [Windows.Forms.MessageBox]::Show('Version files retired and registration removed. Settings, recovery copies and management tools were retained.', 'CodexBar Windows')
} catch {
    $failure = $_.Exception
    $message = $failure.Message
    if ($null -ne $handoff) {
        $referenceID = Read-FailureTransaction $failure 'CodexBarReferenceTransactionID'
        $removalID = Read-FailureTransaction $failure 'CodexBarRemovalTransactionID'
        if ($null -ne $referenceID) { $handoff.referenceTransactionID = $referenceID }
        if ($null -ne $removalID) { $handoff.removalTransactionID = $removalID }
        $message += "`r`n`r`nStopped during: " + $handoff.stage
        $message += "`r`nManagement ID: " + $RegistrationID
        if ($null -ne $handoff.removalTransactionID) {
            $message += "`r`nFile recovery ID: " + $handoff.removalTransactionID
            $message += "`r`nIf files were moved, restore that removal payload first."
        }
        if ($null -ne $handoff.referenceTransactionID) {
            $message += "`r`nReference recovery ID: " + $handoff.referenceTransactionID
            $message += "`r`nRestore references only after the original app and CLI are present. The original signer is required."
        }
        $message += "`r`nNo automatic rollback was performed. Keep the recovery files."
        try {
            Write-CodexBarJournal $handoffPath $handoff
            $message += "`r`nRecovery record: " + $handoffPath
        } catch {
            $message += "`r`nThe final recovery record could not be saved. Retain the IDs shown here and inspect actual files and registration."
        }
    }
    $null = [Windows.Forms.MessageBox]::Show($message, 'CodexBar Windows removal', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
