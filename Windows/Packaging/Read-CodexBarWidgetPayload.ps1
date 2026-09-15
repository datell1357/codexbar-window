# Shared build/staging contract. This describes bytes, not package registration or runtime readiness.
function Read-CodexBarWidgetPayload($Payload) {
    if ($null -eq $Payload -or $null -eq $Payload.PSObject.Properties['schemaVersion'] -or
        $Payload.schemaVersion -ne 1 -or $null -eq $Payload.PSObject.Properties['files']) {
        throw 'Missing or unsupported widget host payload contract.'
    }
    $files = @($Payload.files)
    if ($files.Count -lt 6 -or $files.Count -gt 4096) { throw 'Invalid widget payload file count.' }
    $result = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        foreach ($field in @('path', 'kind', 'bytes', 'sha256')) {
            if ($null -eq $file.PSObject.Properties[$field]) { throw 'Incomplete widget payload entry.' }
        }
        $relative = ([string] $file.path).Replace('/', '\')
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Length -gt 2048 -or
            [IO.Path]::IsPathRooted($relative) -or $relative -match '[:\x00-\x1f]' -or
            [string] $file.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid widget payload path or hash.' }
        foreach ($part in $relative.Split([char] '\')) {
            if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
                $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') { throw 'Invalid widget payload path component.' }
        }
        [long] $size = 0
        if (-not [long]::TryParse([string] $file.bytes, [ref] $size) -or $size -lt 0 -or $size -gt 536870912) {
            throw 'Invalid widget payload file size.'
        }
        if ($relative -ieq 'CodexBarWidgetHost.exe') {
            if ($file.kind -cne 'application' -or $size -le 0) { throw 'Invalid widget host executable entry.' }
        } elseif ([IO.Path]::GetExtension($relative) -ieq '.dll') {
            if ([IO.Path]::GetFileName($relative) -cne $relative -or $file.kind -cne 'runtime' -or $size -le 0) {
                throw 'Widget runtime DLLs must be nonempty root files.'
            }
        } elseif ($relative.StartsWith('licenses\windows-widget-host\', [StringComparison]::OrdinalIgnoreCase)) {
            if ($file.kind -cne 'license' -or $size -le 0) { throw 'Invalid widget license entry.' }
        } elseif ($file.kind -cne 'resource' -or [IO.Path]::GetExtension($relative) -notin @('.winmd', '.pri', '.mui', '.png', '.json', '.manifest', '.appxfragment')) {
            throw 'Unexpected file in widget host payload.'
        }
        if ($result.ContainsKey($relative)) { throw 'Duplicate widget payload path.' }
        $result.Add($relative, $file)
    }
    foreach ($required in @('CodexBarWidgetHost.exe', 'Microsoft.Windows.Widgets.dll', 'Microsoft.Windows.Widgets.winmd',
        'licenses\windows-widget-host\Microsoft.WindowsAppSDK.Widgets.txt',
        'licenses\windows-widget-host\Microsoft.WindowsAppSDK.Base.txt',
        'licenses\windows-widget-host\Microsoft.Windows.CppWinRT.txt')) {
        if (-not $result.ContainsKey($required) -or $result[$required].bytes -le 0) { throw "Widget payload is missing $required." }
    }
    return ,$result
}
