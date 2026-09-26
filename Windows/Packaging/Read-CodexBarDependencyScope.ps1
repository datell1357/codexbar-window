# Deliberately models application-directory imports, not PATH, cwd or arbitrary sibling DLL directories.
function Get-CodexBarRuntimeImportPath([string] $Importer, [string] $Library) {
    if ($Library -notmatch '^[A-Za-z0-9_.+-]+\.dll$') { throw 'Invalid imported library name.' }
    if ($Importer.Replace('/', '\').StartsWith('App\', [StringComparison]::OrdinalIgnoreCase)) {
        return ('App\' + $Library)
    }
    return $Library
}

function Test-CodexBarManagedILInput([string] $Destination) {
    $relative = $Destination.Replace('/', '\')
    return $relative.StartsWith('App\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetExtension($relative) -ieq '.dll'
}
