# A local publish receipt binds a complete App/ tree to bytes; it is not a signed build attestation.
function Read-CodexBarAppPayload($Payload) {
    if ($null -eq $Payload -or $null -eq $Payload.PSObject.Properties['schemaVersion'] -or
        $Payload.schemaVersion -ne 1 -or $null -eq $Payload.PSObject.Properties['files']) {
        throw 'Missing or unsupported Windows app payload.'
    }
    $files = @($Payload.files)
    if ($files.Count -lt 10 -or $files.Count -gt 4096) { throw 'Invalid Windows app payload count.' }
    $result = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    [long] $total = 0
    foreach ($file in $files) {
        foreach ($field in @('path', 'kind', 'bytes', 'sha256')) {
            if ($null -eq $file.PSObject.Properties[$field]) { throw 'Incomplete Windows app payload entry.' }
        }
        $relative = ([string] $file.path).Replace('/', '\')
        if ($relative.Length -gt 2048 -or -not $relative.StartsWith('App\', [StringComparison]::OrdinalIgnoreCase) -or
            $relative -match '[:\x00-\x1f]' -or [string] $file.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Invalid Windows app payload path or hash.'
        }
        foreach ($part in $relative.Split([char] '\')) {
            if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
                $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') { throw 'Invalid app path component.' }
        }
        [long] $size = 0
        if (-not [long]::TryParse([string] $file.bytes, [ref] $size) -or $size -lt 0 -or $size -gt 536870912) {
            throw 'Invalid Windows app payload size.'
        }
        $total += $size
        if ($total -gt 2147483648) { throw 'Windows app payload exceeds 2 GiB.' }
        $extension = [IO.Path]::GetExtension($relative)
        if ($extension -ieq '.exe') {
            if ($file.kind -cne 'application' -or $size -eq 0) { throw 'Invalid Windows app executable.' }
        } elseif ($extension -ieq '.dll') {
            if ($file.kind -cne 'runtime' -or $size -eq 0) { throw 'Invalid Windows app DLL.' }
        } elseif ($relative.StartsWith('App\licenses\', [StringComparison]::OrdinalIgnoreCase)) {
            if ($file.kind -cne 'license' -or $size -eq 0 -or $extension -notin @('.txt', '.md', '.html', '.json')) {
                throw 'Invalid Windows app license file.'
            }
        } elseif ($file.kind -cne 'resource' -or $extension -notin @(
            '.json', '.pri', '.xbf', '.xaml', '.winmd', '.manifest', '.appxfragment', '.mui',
            '.png', '.jpg', '.jpeg', '.ico', '.svg', '.xml', '.txt', '.md', '.pdb', '.bin')) {
            throw 'Unexpected Windows app payload file.'
        }
        if ($result.ContainsKey($relative)) { throw 'Duplicate Windows app payload path.' }
        $result.Add($relative, $file)
    }
    foreach ($required in @('App\CodexBarApp.exe', 'App\CodexBarApp.dll', 'App\CodexBarApp.deps.json',
        'App\CodexBarApp.runtimeconfig.json', 'App\coreclr.dll', 'App\hostfxr.dll', 'App\hostpolicy.dll',
        'App\System.Private.CoreLib.dll', 'App\Microsoft.UI.Xaml.dll', 'App\resources.pri',
        'App\licenses\THIRD-PARTY-NOTICES.txt')) {
        if (-not $result.ContainsKey($required) -or $result[$required].bytes -le 0) {
            throw "Windows app payload is missing $required."
        }
    }
    foreach ($path in $result.Keys) {
        $parent = [IO.Path]::GetDirectoryName($path)
        while (-not [string]::IsNullOrEmpty($parent)) {
            if ($result.ContainsKey($parent)) { throw 'Windows app file/directory collision.' }
            $parent = [IO.Path]::GetDirectoryName($parent)
        }
    }
    return ,$result
}

function Assert-CodexBarAppPayloadFiles($Payload, [object[]] $Files, [string] $PathProperty = 'path',
    [switch] $CompareHashes) {
    $appFiles = @($Files | Where-Object {
        ([string] $_.$PathProperty).Replace('/', '\').StartsWith('App\', [StringComparison]::OrdinalIgnoreCase)
    })
    if ($null -eq $Payload) {
        if ($appFiles.Count -ne 0) { throw 'App files require the complete Windows app payload contract.' }
        return
    }
    $expected = Read-CodexBarAppPayload $Payload
    if ($appFiles.Count -ne $expected.Count) { throw 'Windows app payload has missing or extra files.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $appFiles) {
        $relative = ([string] $file.$PathProperty).Replace('/', '\')
        if (-not $seen.Add($relative) -or -not $expected.ContainsKey($relative) -or
            $file.kind -cne $expected[$relative].kind) { throw 'Windows app payload classification differs.' }
        if ($CompareHashes -and ($file.bytes -ne $expected[$relative].bytes -or
            $file.sha256 -cne $expected[$relative].sha256)) { throw 'Windows app inventory differs from payload bytes.' }
    }
}

function Read-CodexBarAppBuildReceipt([string] $Path, [string] $Architecture, [string] $Revision, [string] $Version) {
    $file = Get-Item -LiteralPath $Path -Force
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $file.Length -le 0 -or $file.Length -gt 4194304) { throw 'Invalid Windows app build receipt.' }
    $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -le 0 -or $stream.Length -gt 4194304) { throw 'Windows app receipt size changed.' }
        $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true)
        try { $receipt = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    foreach ($field in @('schemaVersion', 'component', 'architecture', 'configuration', 'sourceRevision',
        'productVersion', 'provenanceStatus', 'deployment', 'packagesLockSHA256', 'payload')) {
        if ($null -eq $receipt.PSObject.Properties[$field]) { throw 'Incomplete Windows app build receipt.' }
    }
    if ($receipt.schemaVersion -ne 1 -or $receipt.component -cne 'CodexBarApp' -or
        $receipt.architecture -cne $Architecture -or $receipt.configuration -cne 'Release' -or
        $receipt.sourceRevision -cne $Revision -or $receipt.productVersion -cne $Version -or
        $receipt.provenanceStatus -cne 'LOCAL_BUILD_NOT_ATTESTED' -or
        $receipt.deployment -cne 'SELF_CONTAINED_WINUI' -or
        [string] $receipt.packagesLockSHA256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Windows app build receipt does not match this distribution.'
    }
    $null = Read-CodexBarAppPayload $receipt.payload
    return $receipt
}
