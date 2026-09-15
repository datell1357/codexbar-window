# Windows build-stage entry point. It creates an unsigned package, never installs or publishes it.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $DistributionDirectory,
    [Parameter(Mandatory = $true)][string] $ConfigurationPath,
    [Parameter(Mandatory = $true)][string] $MakeAppxPath,
    [Parameter(Mandatory = $true)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarBuildProvenance.ps1')
. (Join-Path $PSScriptRoot 'Read-CodexBarFirstPartyFiles.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$held = [Collections.Generic.List[IO.FileStream]]::new()
function Get-RelativePath([string] $Value) {
    $value = $Value.Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 2048 -or [IO.Path]::IsPathRooted($value) -or
        $value -match '[:*?"<>|\x00-\x1f]') { throw 'Invalid package-relative path.' }
    foreach ($part in $value.Split([char] '\')) {
        if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') { throw 'Invalid package path component.' }
    }
    return $value
}
function Get-LocalPath([string] $Value) {
    $path = [IO.Path]::GetFullPath($Value)
    if ($path -notmatch '^[a-zA-Z]:\\' -or $path -match '["\x00-\x1f]') { throw 'Use a local drive path.' }
    $relative = $path.Substring(3).TrimEnd([char] '\')
    if ($relative.Length -gt 0) { $null = Get-RelativePath $relative }
    return $path
}
function Get-RegularItem([string] $Path, [bool] $Directory) {
    $path = Get-LocalPath $Path
    $cursor = [IO.Path]::GetPathRoot($path)
    $item = Get-Item -LiteralPath $cursor -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked paths are unsupported.' }
    foreach ($part in $path.Substring($cursor.Length).Split([char] '\')) {
        if ($part.Length -eq 0) { continue }
        if (-not $item.PSIsContainer) { throw 'Invalid input parent directory.' }
        $cursor = Join-Path $cursor $part
        $item = Get-Item -LiteralPath $cursor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked paths are unsupported.' }
    }
    if ([bool] $item.PSIsContainer -ne $Directory) { throw 'Unexpected input file/directory kind.' }
    return $item
}
function Open-HeldFile([string] $Path, [long] $Limit, [bool] $AllowEmpty = $false) {
    $item = Get-RegularItem $Path $false
    $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -gt $Limit -or (-not $AllowEmpty -and $stream.Length -eq 0)) { throw 'File exceeds its size bounds.' }
        $held.Add($stream)
        return ,$stream
    } catch { $stream.Dispose(); throw }
}
function Get-Hash([IO.Stream] $Stream) {
    $Stream.Position = 0
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $Stream.Position = 0 }
}
function Read-JSON([IO.Stream] $Stream) {
    $Stream.Position = 0
    $reader = [IO.StreamReader]::new($Stream, [Text.UTF8Encoding]::new($false, $true), $true, 4096, $true)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop) }
    finally { $reader.Dispose(); $Stream.Position = 0 }
}
function Write-NewText([string] $Path, [string] $Text, [bool] $ByteOrderMark = $false) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($ByteOrderMark), 4096, $true)
        try { $writer.Write($Text); $writer.Flush(); $stream.Flush($true) }
        finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}
try {
    $root = Get-RegularItem $DistributionDirectory $true
    $configuration = Get-RegularItem $ConfigurationPath $false
    $tool = Get-RegularItem $MakeAppxPath $false
    if ($tool.Name -ine 'makeappx.exe') { throw 'Select the Windows SDK MakeAppx.exe explicitly.' }
    $output = (Get-LocalPath $OutputDirectory).TrimEnd([char] '\')
    $rootPrefix = $root.FullName.TrimEnd([char] '\') + '\'
    if ($output.Equals($root.FullName.TrimEnd([char] '\'), [StringComparison]::OrdinalIgnoreCase) -or
        $output.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the distribution.' }
    $null = Get-RegularItem ([IO.Path]::GetDirectoryName($output)) $true
    if (Test-Path -LiteralPath $output) { throw 'Output already exists; use a new directory. Existing output is preserved.' }
    $inventoryStream = Open-HeldFile (Join-Path $root.FullName 'distribution-inventory.json') 4194304
    $configurationStream = Open-HeldFile $configuration.FullName 65536
    $toolStream = Open-HeldFile $tool.FullName 536870912
    $inventory = Read-JSON $inventoryStream
    if ($inventory.schemaVersion -ne 1 -or $inventory.architecture -cnotin @('x64', 'arm64') -or
        $inventory.status -cnotin @('STAGED_UNVERIFIED', 'SIGNED_RUNTIME_UNVERIFIED')) { throw 'Unsupported distribution inventory.' }
    $provenance = Read-CodexBarBuildProvenance $inventory.provenance
    $entries = @($inventory.files)
    if ($entries.Count -lt 6 -or $entries.Count -gt 10000) { throw 'Invalid inventory file count.' }
    $null = Assert-CodexBarFirstPartyFiles $entries
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $mapping = [Collections.Generic.List[string]]::new()
    $mapping.Add('[Files]')
    [long] $totalBytes = 0
    foreach ($entry in $entries) {
        if ($entry.path -isnot [string]) { throw 'Expected an inventory path string.' }
        $path = Get-RelativePath $entry.path
        $first = $path.Split([char] '\')[0]
        if ($first -iin @('AppxManifest.xml', 'AppxBlockMap.xml', 'AppxSignature.p7x', 'AppxMetadata', '[Content_Types].xml', 'distribution-inventory.json') -or
            -not $paths.Add($path) -or $entry.kind -cnotin @('application', 'cli', 'runtime', 'resource', 'license')) {
            throw 'Duplicate, reserved or invalid package file record.'
        }
        [long] $size = 0
        if (-not [long]::TryParse([string] $entry.bytes, [ref] $size) -or $size -lt 0 -or $size -gt 536870912 -or
            [string] $entry.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid inventory file identity.' }
        $totalBytes += $size
        if ($totalBytes -gt 8589934592) { throw 'This packaging entry point limits input to eight GiB.' }
        $source = Join-Path $root.FullName $path
        $stream = Open-HeldFile $source 536870912 $true
        if ($stream.Length -ne $size -or (Get-Hash $stream) -cne $entry.sha256) { throw 'Package input differs from its inventory.' }
        # All sources and destinations have already rejected quotes and control characters.
        $mapping.Add('"' + $source + '" "' + $path + '"')
    }
    $inventoryHash = Get-Hash $inventoryStream
    $configurationHash = Get-Hash $configurationStream
    $toolHash = Get-Hash $toolStream
    if (-not $PSCmdlet.ShouldProcess($output, 'Create a new unsigned MSIX using the explicit Windows SDK MakeAppx tool')) { return }
    $null = New-Item -ItemType Directory -Path $output -ErrorAction Stop
    $manifestPath = Join-Path $output 'AppxManifest.xml'
    # Generate against the same held distribution/configuration bytes, never reuse a stale manifest.
    $manifestResult = & (Join-Path $PSScriptRoot 'New-CodexBarMSIXManifest.ps1') `
        -DistributionDirectory $root.FullName -ConfigurationPath $configuration.FullName -OutputManifest $manifestPath -Confirm:$false
    if ($null -eq $manifestResult -or $manifestResult.Status -cne 'MANIFEST_WRITTEN_UNVERIFIED' -or
        $manifestResult.Architecture -cne $inventory.architecture) { throw 'Manifest composition did not complete.' }
    $manifestStream = Open-HeldFile $manifestPath 1048576
    $manifestHash = Get-Hash $manifestStream
    $mapping.Add('"' + $manifestPath + '" "AppxManifest.xml"')
    $mappingPath = Join-Path $output 'package-files.txt'
    # UTF-8 BOM keeps non-ASCII source paths explicit for the native SDK text reader.
    Write-NewText $mappingPath (($mapping -join "`r`n") + "`r`n") $true
    $mappingStream = Open-HeldFile $mappingPath 67108864
    $mappingHash = Get-Hash $mappingStream
    $packagePath = Join-Path $output 'CodexBarWindows.msix'
    # /no refuses overwrite without prompting. Do not suppress MakeAppx's normal semantic checks.
    $arguments = @('pack', '/f', $mappingPath, '/p', $packagePath, '/h', 'SHA256', '/no')
    & $tool.FullName @arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "MakeAppx failed with exit code $exitCode. All output is preserved at $output" }
    $packageStream = Open-HeldFile $packagePath 8724152320
    $receipt = [ordered] @{
        schemaVersion = 1
        status = 'PACKAGED_UNSIGNED_RUNTIME_UNVERIFIED'
        architecture = $inventory.architecture
        provenance = $provenance
        sourceInventory = [ordered] @{ sha256 = $inventoryHash; status = $inventory.status }
        configurationSha256 = $configurationHash
        manifestSha256 = $manifestHash
        mappingSha256 = $mappingHash
        inputFileCount = $entries.Count
        packageInputFileCount = $entries.Count + 1
        inputBytes = $totalBytes
        tool = [ordered] @{ name = 'MakeAppx.exe'; sha256 = $toolHash; exitCode = $exitCode; validation = 'SDK_DEFAULT' }
        package = [ordered] @{ path = 'CodexBarWindows.msix'; bytes = $packageStream.Length; sha256 = (Get-Hash $packageStream) }
        signing = 'NOT_RUN'
        installation = 'NOT_RUN'
        runtimeValidation = 'NOT_RUN'
        createdAt = [DateTime]::UtcNow.ToString('o')
    }
    $receiptPath = Join-Path $output 'package-build-receipt.json'
    Write-NewText $receiptPath (($receipt | ConvertTo-Json -Depth 12) + "`r`n")
    [pscustomobject] @{ PackagePath = $packagePath; ReceiptPath = $receiptPath; Status = $receipt.status; RuntimeValidation = 'NOT_RUN' }
} finally {
    foreach ($stream in $held) { $stream.Dispose() }
}
