# Shared schema boundary. A policy declaration is not runtime validation.
function Read-CodexBarSystemPolicy($Policy, [string] $Architecture) {
    $result = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $Policy) { return ,$result }
    if ($Policy.schemaVersion -ne 1 -or $Policy.architecture -ne $Architecture -or
        [string]::IsNullOrWhiteSpace([string] $Policy.minimumWindowsVersion) -or
        ([string] $Policy.minimumWindowsVersion) -notmatch '^10\.0\.[0-9]{4,6}(\.[0-9]{1,6})?$') {
        throw 'Invalid system dependency policy version, architecture or Windows floor.'
    }
    $libraries = @($Policy.libraries)
    if ($libraries.Count -gt 4096) { throw 'System dependency policy exceeds the entry limit.' }
    foreach ($library in $libraries) {
        $name = [string] $library.name
        if ($name -notmatch '^[A-Za-z0-9_.+-]+\.dll$' -or $name.Length -gt 259 -or
            $library.kind -notin @('system', 'apiSet') -or
            [string]::IsNullOrWhiteSpace([string] $library.reason) -or
            ([string] $library.reason).Length -gt 2048) { throw 'Invalid system policy library entry.' }
        $reference = $null
        if (-not [Uri]::TryCreate([string] $library.reference, [UriKind]::Absolute, [ref] $reference) -or
            $reference.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($reference.Host)) {
            throw 'Every system dependency declaration requires an HTTPS evidence reference.'
        }
        if ($result.ContainsKey($name)) { throw 'Duplicate system dependency declaration.' }
        $result.Add($name, $library)
    }
    return ,$result
}
