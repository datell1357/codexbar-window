function Read-CodexBarBuildProvenance($Value) {
    if ($null -eq $Value -or $Value.repository -ne 'https://github.com/datell1357/codexbar-window' -or
        ([string] $Value.revision) -notmatch '^[0-9a-fA-F]{40}$' -or
        ([string] $Value.version) -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' -or
        ([string] $Value.version).Length -gt 128 -or $Value.status -ne 'DECLARED_NOT_ATTESTED') {
        throw 'A valid declared repository revision and product version are required.'
    }
    return [ordered] @{
        repository = $Value.repository
        revision = ([string] $Value.revision).ToLowerInvariant()
        version = $Value.version
        status = 'DECLARED_NOT_ATTESTED'
    }
}
