# Omitting ToVersionID detaches known current-user references. No version files are removed.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $FromVersionID,
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?-(x64|arm64)-[0-9a-fA-F]{40}$')][string] $ToVersionID,
    [ValidatePattern('^[0-9a-fA-F]{40}$')][string] $ExpectedSignerThumbprint,
    [switch] $AllowUnvalidatedBuild,
    [switch] $PassThru,
    [ValidatePattern('^[0-9a-f]{32}$')][string] $OperationID
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$transaction = $null
. (Join-Path $PSScriptRoot 'Write-CodexBarJournal.ps1')
. (Join-Path $PSScriptRoot 'Send-CodexBarEnvironmentChange.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not $AllowUnvalidatedBuild) { throw 'Windows and development opt-in are required.' }
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
if ([string]::IsNullOrWhiteSpace($localData) -or [string]::IsNullOrWhiteSpace($programs)) { throw 'User folders unavailable.' }
$root = Join-Path $localData 'Programs\CodexBarWindows'
$versions = Join-Path $root 'versions'
$from = Join-Path $versions $FromVersionID
$to = $null
if (-not [string]::IsNullOrWhiteSpace($ToVersionID)) {
    if ($FromVersionID -eq $ToVersionID -or [string]::IsNullOrWhiteSpace($ExpectedSignerThumbprint)) { throw 'Choose a different destination version and its signer.' }
    $to = Join-Path $versions $ToVersionID
}
$directories = @($localData, (Join-Path $localData 'Programs'), $root, $versions, $from, $programs)
if ($null -ne $to) { $directories += $to }
foreach ($path in $directories) {
    if ($path -match '[;"%\x00-\x1f]') { throw 'Unsupported managed path.' }
    $item = Get-Item -LiteralPath $path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid managed directory.' }
}
$lockPath = Join-Path $root 'operations.lock'
$item = Get-Item -LiteralPath $lockPath -Force
if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid operations lock.' }
$lock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$environmentKey = $null; $runKey = $null; $shell = $null; $link = $null
function Update-ReferencePath([string] $Raw) {
    if ($Raw.Length -gt 32766) { throw 'PATH exceeds the editing limit.' }
    if ($Raw.Length -eq 0) { return $Raw }
    $updated = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Raw.Split([char] ';')) {
        $literal = $entry.Trim()
        if ($literal.Length -ge 2 -and $literal.StartsWith('"') -and $literal.EndsWith('"')) {
            $literal = $literal.Substring(1, $literal.Length - 2)
        }
        $literal = $literal.Replace('/', '\').TrimEnd('\')
        if ($literal -ieq $from) { if ($null -ne $to) { $updated.Add($to) } }
        else { $updated.Add($entry) }
    }
    $result = $updated -join ';'
    if ($result.Length -gt 32766) { throw 'Updated PATH exceeds the limit.' }
    return $result
}
try {
    if ($null -ne $to) {
        $receiptPath = Join-Path $to 'installation-receipt.json'
        $item = Get-Item -LiteralPath $receiptPath -Force
        if ($item.PSIsContainer -or $item.Length -gt 16777216 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid destination receipt.' }
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        if ($receipt.schemaVersion -ne 1 -or $receipt.product -ne 'CodexBarWindows' -or $receipt.versionID -ne $ToVersionID -or
            $receipt.state -ne 'INSTALLED_INACTIVE_RUNTIME_UNVERIFIED' -or $receipt.signerThumbprint -ine $ExpectedSignerThumbprint) { throw 'Destination receipt mismatch.' }
        foreach ($name in @('CodexBarWindows.exe', 'CodexBarCLI.exe')) {
            $entry = @($receipt.files | Where-Object { $_.path -ieq $name })
            $path = Join-Path $to $name
            $item = Get-Item -LiteralPath $path -Force
            if ($entry.Count -ne 1 -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry[0].sha256) { throw 'Destination executable mismatch.' }
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
                $signature.SignerCertificate.Thumbprint -ine $ExpectedSignerThumbprint) { throw 'Destination signer mismatch.' }
        }
    }
    $options = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    $environmentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $runKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true)
    $oldPath = $null; $newPath = $null; $pathKind = $null; $oldRun = $null; $newRun = $null
    if ($null -ne $environmentKey) {
        $oldPath = $environmentKey.GetValue('Path', $null, $options)
        if ($null -ne $oldPath) {
            $pathKind = $environmentKey.GetValueKind('Path')
            if ($pathKind -notin @([Microsoft.Win32.RegistryValueKind]::String, [Microsoft.Win32.RegistryValueKind]::ExpandString)) { throw 'Unsupported PATH value type.' }
            $newPath = Update-ReferencePath ([string] $oldPath)
        }
    }
    $changeRun = $false
    if ($null -ne $runKey) {
        $oldRun = $runKey.GetValue('CodexBarWindows', $null, $options)
        $expectedRun = '"' + (Join-Path $from 'CodexBarWindows.exe') + '"'
        if ($null -ne $oldRun -and ([string] $oldRun).IndexOf($from, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            if ($runKey.GetValueKind('CodexBarWindows') -ne [Microsoft.Win32.RegistryValueKind]::String -or $oldRun -cne $expectedRun) { throw 'Startup command is customized; it was preserved.' }
            $changeRun = $true
            if ($null -ne $to) {
                $newRun = '"' + (Join-Path $to 'CodexBarWindows.exe') + '"'
                if ($newRun.Length -ge 260) { throw 'Destination startup command exceeds the supported length.' }
            }
        }
    }
    $shortcut = Join-Path $programs 'CodexBar Windows.lnk'
    $shortcutHash = $null
    if (Test-Path -LiteralPath $shortcut) {
        $item = Get-Item -LiteralPath $shortcut -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid shortcut.' }
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        if ([IO.Path]::GetFullPath($link.TargetPath) -ieq (Join-Path $from 'CodexBarWindows.exe')) {
            if (-not [string]::IsNullOrEmpty($link.Arguments)) { throw 'Shortcut arguments are customized; preserved.' }
            $shortcutHash = (Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash
        }
        $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link); $link = $null
    }
    if (-not $PSCmdlet.ShouldProcess($FromVersionID, 'Migrate or detach known user launch references, preserving a recovery record')) { return }
    $candidateID = if ([string]::IsNullOrWhiteSpace($OperationID)) { [Guid]::NewGuid().ToString('N') } else { $OperationID }
    foreach ($reserved in @((Join-Path $root ('references-' + $candidateID + '.json')),
            (Join-Path $programs ('CodexBar-' + $candidateID + '.references.previous.lnk')),
            (Join-Path $programs ('CodexBar-' + $candidateID + '.references.lnk')))) {
        if (Test-Path -LiteralPath $reserved) { throw 'Reference operation ID is already in use; choose a new operation, not an existing recovery ID.' }
    }
    $transaction = $candidateID
    $journalPath = Join-Path $root ('references-' + $transaction + '.json')
    $record = [ordered] @{ schemaVersion = 2; fromVersionID = $FromVersionID; toVersionID = $ToVersionID;
        state = 'PREPARED'; oldPath = $oldPath; newPath = $newPath; pathKind = [string] $pathKind;
        oldRun = $oldRun; newRun = $newRun; changeRun = $changeRun;
        changePath = ($null -ne $oldPath -and $oldPath -cne $newPath);
        shortcutHash = $shortcutHash; shortcutNewHash = $null; environmentNotification = 'NOT_NEEDED' }
    Write-CodexBarJournal $journalPath $record
    if ($null -ne $oldPath -and $oldPath -cne $newPath) {
        if ($environmentKey.GetValue('Path', $null, $options) -cne $oldPath -or $environmentKey.GetValueKind('Path') -ne $pathKind) { throw 'PATH changed concurrently.' }
        $environmentKey.SetValue('Path', $newPath, $pathKind)
        $record.environmentNotification = Send-CodexBarEnvironmentChange
        Write-CodexBarJournal $journalPath $record
        if ($record.environmentNotification -ne 'SENT_REFRESH_NOT_GUARANTEED') {
            Write-Warning 'PATH was changed, but environment notification was not confirmed. Sign out and sign in to inherit the change.'
        }
    }
    if ($changeRun) {
        if ($runKey.GetValue('CodexBarWindows', $null, $options) -cne $oldRun -or
            $runKey.GetValueKind('CodexBarWindows') -ne [Microsoft.Win32.RegistryValueKind]::String) { throw 'Startup changed concurrently.' }
        if ($null -eq $newRun) { $runKey.DeleteValue('CodexBarWindows', $false) }
        else { $runKey.SetValue('CodexBarWindows', $newRun, [Microsoft.Win32.RegistryValueKind]::String) }
    }
    if ($null -ne $shortcutHash) {
        $backup = Join-Path $programs ('CodexBar-' + $transaction + '.references.previous.lnk')
        if ((Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash -ine $shortcutHash) { throw 'Shortcut changed concurrently.' }
        if ($null -eq $to) { [IO.File]::Move($shortcut, $backup) }
        else {
            $temporary = Join-Path $programs ('CodexBar-' + $transaction + '.references.lnk')
            $link = $shell.CreateShortcut($temporary)
            $link.TargetPath = Join-Path $to 'CodexBarWindows.exe'
            $link.WorkingDirectory = $to; $link.Description = 'CodexBar Windows'
            $link.IconLocation = (Join-Path $to 'CodexBarWindows.exe') + ',0'
            $link.Save()
            $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link); $link = $null
            $record.shortcutNewHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
            Write-CodexBarJournal $journalPath $record
            if ((Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash -ine $shortcutHash) { throw 'Shortcut changed during preparation.' }
            [IO.File]::Replace($temporary, $shortcut, $backup)
        }
    }
    $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    if ($null -ne $processPath) { [Environment]::SetEnvironmentVariable('Path', (Update-ReferencePath $processPath), 'Process') }
    $record.state = 'REFERENCES_UPDATED_RUNTIME_UNVERIFIED'
    Write-CodexBarJournal $journalPath $record
    if ($PassThru) {
        [pscustomobject] @{ transactionID = $transaction; state = $record.state;
            environmentNotification = $record.environmentNotification; fromVersionID = $FromVersionID }
    } else {
        Write-Output ('Reference transaction: ' + $transaction + '. Existing processes retain their inherited environment.')
    }
} catch {
    if ($null -ne $transaction) { $_.Exception.Data['CodexBarReferenceTransactionID'] = $transaction }
    Write-Warning 'Reference update incomplete. Earlier changes may have succeeded; inspect the journal and shortcut backup before retrying.'
    throw
} finally {
    if ($null -ne $link) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) }
    if ($null -ne $shell) { $null = [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    if ($null -ne $environmentKey) { $environmentKey.Dispose() }
    if ($null -ne $runKey) { $runKey.Dispose() }
    $lock.Dispose()
}
