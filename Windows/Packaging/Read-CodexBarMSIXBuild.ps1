# Reads the local unsigned package contract. Callers own and dispose every stream in HeldFiles,
# including on failure. Metadata/hash agreement is not build attestation or install/runtime validation.
. (Join-Path $PSScriptRoot 'Read-CodexBarBuildProvenance.ps1')
function Get-CodexBarMSIXLocalItem([string] $Path, [bool] $Directory) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^[a-zA-Z]:\\' -or $full -match '["\x00-\x1f]') { throw 'Use a local drive path for MSIX inputs.' }
    $cursor = [IO.Path]::GetPathRoot($full)
    $item = Get-Item -LiteralPath $cursor -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked MSIX paths are unsupported.' }
    foreach ($part in $full.Substring($cursor.Length).Split([char] '\')) {
        if ($part.Length -eq 0) { continue }
        if (-not $item.PSIsContainer -or $part -in @('.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '[:*?"<>|\x00-\x1f]' -or $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') {
            throw 'Invalid MSIX input path.'
        }
        $cursor = Join-Path $cursor $part
        $item = Get-Item -LiteralPath $cursor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked MSIX paths are unsupported.' }
    }
    if ([bool] $item.PSIsContainer -ne $Directory) { throw 'Unexpected MSIX input file/directory kind.' }
    return $item
}
function Open-CodexBarMSIXInput([string] $Path, [long] $Limit, [Collections.Generic.List[IO.FileStream]] $HeldFiles) {
    $item = Get-CodexBarMSIXLocalItem $Path $false
    $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -le 0 -or $stream.Length -gt $Limit) { throw 'MSIX input exceeds its size bounds.' }
        $HeldFiles.Add($stream)
        return ,$stream
    } catch { $stream.Dispose(); throw }
}
function Get-CodexBarMSIXHash([IO.Stream] $Stream) {
    $Stream.Position = 0
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $Stream.Position = 0 }
}
function Read-CodexBarMSIXJSON([IO.Stream] $Stream) {
    $Stream.Position = 0
    $reader = [IO.StreamReader]::new($Stream, [Text.UTF8Encoding]::new($false, $true), $true, 4096, $true)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop) }
    finally { $reader.Dispose(); $Stream.Position = 0 }
}
function Read-CodexBarMSIXEntry($Entry, [int] $Limit) {
    if ($Entry.Length -le 0 -or $Entry.Length -gt $Limit) { throw 'Package metadata exceeds its size bounds.' }
    $source = $Entry.Open()
    $output = [IO.MemoryStream]::new()
    try {
        $buffer = [byte[]]::new(65536)
        while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($output.Length + $count -gt $Limit) { throw 'Expanded package metadata exceeds its limit.' }
            $output.Write($buffer, 0, $count)
        }
        if ($output.Length -ne $Entry.Length) { throw 'Package metadata length differs from its archive record.' }
        return ,$output.ToArray()
    } finally { $source.Dispose(); $output.Dispose() }
}
function Read-CodexBarMSIXXML([byte[]] $Bytes, [long] $Limit) {
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = $Limit
    $stream = [IO.MemoryStream]::new($Bytes, $false)
    $reader = [Xml.XmlReader]::Create($stream, $settings)
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($reader); return ,$document }
    finally { $reader.Dispose(); $stream.Dispose() }
}
function Get-CodexBarMSIXBytesHash([byte[]] $Bytes) {
    $stream = [IO.MemoryStream]::new($Bytes, $false)
    try { return Get-CodexBarMSIXHash $stream } finally { $stream.Dispose() }
}
function Read-CodexBarMSIXBuild([string] $PackageDirectory, [Collections.Generic.List[IO.FileStream]] $HeldFiles) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
    $root = Get-CodexBarMSIXLocalItem $PackageDirectory $true
    $receiptStream = Open-CodexBarMSIXInput (Join-Path $root.FullName 'package-build-receipt.json') 65536 $HeldFiles
    $receipt = Read-CodexBarMSIXJSON $receiptStream
    if ($receipt.schemaVersion -ne 1 -or $receipt.status -cne 'PACKAGED_UNSIGNED_RUNTIME_UNVERIFIED' -or
        $receipt.architecture -cnotin @('x64', 'arm64') -or $receipt.signing -cne 'NOT_RUN' -or
        $receipt.installation -cne 'NOT_RUN' -or $receipt.runtimeValidation -cne 'NOT_RUN' -or
        $receipt.package.path -cne 'CodexBarWindows.msix' -or $receipt.tool.name -cne 'MakeAppx.exe' -or
        $receipt.tool.exitCode -ne 0 -or $receipt.tool.validation -cne 'SDK_DEFAULT' -or
        $receipt.sourceInventory.status -cnotin @('STAGED_UNVERIFIED', 'SIGNED_RUNTIME_UNVERIFIED')) {
        throw 'Unsupported unsigned package build receipt.'
    }
    foreach ($hash in @($receipt.sourceInventory.sha256, $receipt.configurationSha256, $receipt.manifestSha256,
        $receipt.mappingSha256, $receipt.tool.sha256, $receipt.package.sha256)) {
        if ($hash -isnot [string] -or $hash -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid package build hash.' }
    }
    [long] $size = 0
    [int] $inputCount = 0
    [int] $packageCount = 0
    if (-not [long]::TryParse([string] $receipt.package.bytes, [ref] $size) -or $size -le 0 -or $size -gt 8724152320 -or
        -not [int]::TryParse([string] $receipt.inputFileCount, [ref] $inputCount) -or $inputCount -lt 6 -or $inputCount -gt 10000 -or
        -not [int]::TryParse([string] $receipt.packageInputFileCount, [ref] $packageCount) -or $packageCount -ne $inputCount + 1) {
        throw 'Invalid package build size/count.'
    }
    $provenance = Read-CodexBarBuildProvenance $receipt.provenance
    $packagePath = Join-Path $root.FullName 'CodexBarWindows.msix'
    $packageStream = Open-CodexBarMSIXInput $packagePath 8724152320 $HeldFiles
    $packageHash = Get-CodexBarMSIXHash $packageStream
    if ($packageStream.Length -ne $size -or $packageHash -cne $receipt.package.sha256) { throw 'Package bytes differ from the build receipt.' }
    Add-Type -AssemblyName System.IO.Compression
    $archive = [IO.Compression.ZipArchive]::new($packageStream, [IO.Compression.ZipArchiveMode]::Read, $true)
    try {
        if ($archive.Entries.Count -lt 3 -or $archive.Entries.Count -gt 10010) { throw 'Unexpected package archive entry count.' }
        $entries = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.Length -gt 2048 -or $name.StartsWith('/') -or $name -match '[:\x00-\x1f]' -or
                $entries.ContainsKey($name)) { throw 'Ambiguous package archive entry.' }
            foreach ($component in $name.Split([char] '/')) {
                if ($component -in @('', '.', '..') -or $component.EndsWith('.') -or $component.EndsWith(' ')) {
                    throw 'Invalid package archive entry path.'
                }
            }
            $entries.Add($name, $entry)
        }
        if ($entries.ContainsKey('AppxSignature.p7x') -or $entries.ContainsKey('AppxMetadata/AppxBundleManifest.xml')) {
            throw 'Expected an unsigned single application package, not a signed package or bundle.'
        }
        foreach ($name in @('AppxManifest.xml', 'AppxBlockMap.xml', '[Content_Types].xml')) {
            if (-not $entries.ContainsKey($name)) { throw 'Required package metadata is missing.' }
        }
        $manifestBytes = Read-CodexBarMSIXEntry $entries['AppxManifest.xml'] 1048576
        $manifestHash = Get-CodexBarMSIXBytesHash $manifestBytes
        if ($manifestHash -cne $receipt.manifestSha256) { throw 'Embedded manifest differs from the build receipt.' }
        $manifest = Read-CodexBarMSIXXML $manifestBytes 1048576
        $foundation = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
        if ($manifest.DocumentElement.LocalName -cne 'Package' -or $manifest.DocumentElement.NamespaceURI -cne $foundation) {
            throw 'Unexpected application manifest root.'
        }
        $namespaces = [Xml.XmlNamespaceManager]::new($manifest.NameTable)
        $namespaces.AddNamespace('p', $foundation)
        $identities = $manifest.SelectNodes('/p:Package/p:Identity', $namespaces)
        if ($identities.Count -ne 1) { throw 'Expected one package identity.' }
        $node = $identities[0]
        $name = $node.GetAttribute('Name')
        $publisher = $node.GetAttribute('Publisher')
        $version = $node.GetAttribute('Version')
        $architecture = $node.GetAttribute('ProcessorArchitecture')
        if ($name -cnotmatch '^[A-Za-z0-9.-]{3,50}$' -or [string]::IsNullOrWhiteSpace($publisher) -or
            $publisher.Length -gt 8192 -or $publisher -match '[\x00-\x1f]' -or $architecture -cne $receipt.architecture -or
            $node.GetAttribute('ResourceId').Length -ne 0 -or
            $version -notmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$') {
            throw 'Invalid package identity.'
        }
        $parsedVersion = [version] $version
        foreach ($part in @($parsedVersion.Major, $parsedVersion.Minor, $parsedVersion.Build, $parsedVersion.Revision)) {
            if ($part -gt 65535) { throw 'Package version component exceeds its limit.' }
        }
        $null = [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($publisher)
        $blockMapBytes = Read-CodexBarMSIXEntry $entries['AppxBlockMap.xml'] 33554432
        $blockMap = Read-CodexBarMSIXXML $blockMapBytes 33554432
        if ($blockMap.DocumentElement.LocalName -cne 'BlockMap' -or
            $blockMap.DocumentElement.NamespaceURI -cne 'http://schemas.microsoft.com/appx/2010/blockmap' -or
            $blockMap.DocumentElement.GetAttribute('HashMethod') -cne 'http://www.w3.org/2001/04/xmlenc#sha256') {
            throw 'Only the build entry point SHA256 block-map contract is supported.'
        }
        return [pscustomobject] @{
            Directory = $root.FullName; PackagePath = $packagePath; PackageStream = $packageStream
            PackageBytes = $size; PackageSha256 = $packageHash; ReceiptSha256 = (Get-CodexBarMSIXHash $receiptStream)
            ManifestSha256 = $manifestHash; BlockMapSha256 = (Get-CodexBarMSIXBytesHash $blockMapBytes)
            Identity = [ordered] @{ name = $name; publisher = $publisher; version = $version; architecture = $architecture }
            Provenance = $provenance; HashAlgorithm = 'SHA256'; SourceInventorySha256 = $receipt.sourceInventory.sha256
        }
    } finally { $archive.Dispose(); $packageStream.Position = 0 }
}
