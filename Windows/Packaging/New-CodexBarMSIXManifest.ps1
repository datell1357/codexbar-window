# Writes a manifest only. This does not run MakeAppx/MakePri, sign, register, install or launch a package.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string] $DistributionDirectory,
    [Parameter(Mandatory = $true)][string] $ConfigurationPath,
    [Parameter(Mandatory = $true)][string] $OutputManifest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-CodexBarFirstPartyFiles.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$root = Get-Item -LiteralPath $DistributionDirectory -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The distribution must be a regular directory.'
}
$held = [Collections.Generic.Dictionary[string,IO.FileStream]]::new([StringComparer]::OrdinalIgnoreCase)
$files = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
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
function Get-Hash([IO.Stream] $Stream) {
    $Stream.Position = 0
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $Stream.Position = 0 }
}
function Read-JSONFile([string] $Path, [long] $Limit) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid JSON input file.' }
    $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -le 0 -or $stream.Length -gt $Limit) { throw 'JSON input exceeds its size limit.' }
        $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true)
        try { return ($reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop) }
        finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}
function Get-Text($Value, [string] $Name, [int] $Limit = 256) {
    $property = if ($null -eq $Value) { $null } else { $Value.PSObject.Properties[$Name] }
    if ($null -eq $property -or $property.Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($property.Value) -or $property.Value.Length -gt $Limit -or
        $property.Value -match '[\x00-\x1f]') { throw "Missing or invalid $Name." }
    return [string] $property.Value
}
function Get-Version([string] $Value) {
    if ($Value -notmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$') {
        throw 'Expected a four-part Windows version.'
    }
    $version = [version] $Value
    foreach ($part in @($version.Major, $version.Minor, $version.Build, $version.Revision)) {
        if ($part -gt 65535) { throw 'Version component exceeds the Windows package limit.' }
    }
    return $version
}
function Use-PackageFile([string] $Relative, [string] $Kind) {
    $path = Get-RelativePath $Relative
    if (-not $files.ContainsKey($path) -or $files[$path].kind -cne $Kind) { throw 'A required package file is missing or has the wrong kind.' }
    if (-not $held.ContainsKey($path)) {
        $source = $root.FullName
        foreach ($component in $path.Split([char] '\')) {
            $source = Join-Path $source $component
            $item = Get-Item -LiteralPath $source -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked package inputs are unsupported.' }
        }
        if ($item.PSIsContainer) { throw 'Expected a package file.' }
        $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($stream.Length -le 0 -or $stream.Length -ne $files[$path].bytes -or (Get-Hash $stream) -cne $files[$path].sha256) {
                throw 'A manifest input differs from the distribution inventory.'
            }
            $held.Add($path, $stream)
        } catch { $stream.Dispose(); throw }
    }
    return $path
}
function Use-Image([string] $Relative, [bool] $Widget = $false) {
    $path = Use-PackageFile $Relative 'resource'
    if ([IO.Path]::GetExtension($path) -ine '.png' -or $held[$path].Length -le 0 -or
        ($Widget -and -not $path.StartsWith('WidgetAssets\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Images must be nonempty PNG resources; widget images must be under WidgetAssets.'
    }
    return $path
}
function Use-Label([string] $Value) {
    if ($Value.StartsWith('ms-resource:', [StringComparison]::OrdinalIgnoreCase)) {
        $null = Use-PackageFile 'resources.pri' 'resource'
    }
    return $Value
}
$foundation = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
$uap = 'http://schemas.microsoft.com/appx/manifest/uap/windows10'
$uap3 = 'http://schemas.microsoft.com/appx/manifest/uap/windows10/3'
$uap5 = 'http://schemas.microsoft.com/appx/manifest/uap/windows10/5'
$com = 'http://schemas.microsoft.com/appx/manifest/com/windows10'
$rescap = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities'
$document = [Xml.XmlDocument]::new()
$document.XmlResolver = $null
function Add-Element($Parent, [string] $Name, [hashtable] $Attributes = @{}, [string] $Namespace = $foundation) {
    $element = $document.CreateElement($Name, $Namespace)
    foreach ($key in $Attributes.Keys) { $element.SetAttribute($key, [string] $Attributes[$key]) }
    $null = $Parent.AppendChild($element)
    return ,$element
}
function Add-Theme($Parent, $Configuration) {
    $icons = Add-Element $Parent 'Icons'
    $null = Add-Element $icons 'Icon' @{ Path = (Use-Image (Get-Text $Configuration 'icon' 2048) $true) }
    $screenshots = Add-Element $Parent 'Screenshots'
    $null = Add-Element $screenshots 'Screenshot' @{
        Path = (Use-Image (Get-Text $Configuration 'screenshot' 2048) $true)
        DisplayAltText = (Use-Label (Get-Text $Configuration 'altText' 1024))
    }
}
try {
    $inventory = Read-JSONFile (Join-Path $root.FullName 'distribution-inventory.json') 4194304
    $configuration = Read-JSONFile $ConfigurationPath 65536
    if ($inventory.schemaVersion -ne 1 -or $configuration.schemaVersion -ne 1 -or
        $inventory.architecture -cnotin @('x64', 'arm64')) { throw 'Unsupported inventory/configuration schema or architecture.' }
    if ($inventory.status -cnotin @('STAGED_UNVERIFIED', 'SIGNED_RUNTIME_UNVERIFIED')) { throw 'Unsupported distribution state.' }
    $entries = @($inventory.files)
    if ($entries.Count -lt 6 -or $entries.Count -gt 10000) { throw 'Invalid package inventory count.' }
    $null = Assert-CodexBarFirstPartyFiles $entries
    foreach ($entry in $entries) {
        $path = Get-RelativePath (Get-Text $entry 'path' 2048)
        [long] $size = 0
        if (-not [long]::TryParse([string] $entry.bytes, [ref] $size) -or $size -lt 0 -or $size -gt 536870912 -or
            [string] $entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $files.ContainsKey($path)) { throw 'Invalid package file record.' }
        $files.Add($path, $entry)
    }
    foreach ($required in @(
        @('CodexBarWindows.exe', 'application'), @('CodexBarCLI.exe', 'cli'),
        @('CodexBarWidgetHost.exe', 'application'), @('CodexBarWidgetBackend.dll', 'runtime'),
        @('Microsoft.Windows.Widgets.dll', 'runtime'), @('Microsoft.Windows.Widgets.winmd', 'resource'),
        @('licenses\windows-widget-host\Microsoft.WindowsAppSDK.Widgets.txt', 'license'),
        @('licenses\windows-widget-host\Microsoft.WindowsAppSDK.Base.txt', 'license'),
        @('licenses\windows-widget-host\Microsoft.Windows.CppWinRT.txt', 'license')
    )) { $null = Use-PackageFile $required[0] $required[1] }
    $fragmentPath = Use-PackageFile 'resources\windows-widget-host\Microsoft.WindowsAppSDK.Widgets.appxfragment' 'resource'
    # Original bytes from Microsoft.WindowsAppSDK.Widgets 2.0.5/runtimes-framework/package.appxfragment.
    # A package upgrade must deliberately update this registration contract instead of merging arbitrary XML.
    if ((Get-Hash $held[$fragmentPath]) -cne 'dc05acaa06f54cb75d2627fc1938049a20d398ceba6e470e61df78757091a052') {
        throw 'The Widgets SDK registration fragment does not match the pinned 2.0.5 source.'
    }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 65536
    $settings.CloseInput = $false
    $reader = [Xml.XmlReader]::Create($held[$fragmentPath], $settings)
    $fragment = [Xml.XmlDocument]::new()
    $fragment.XmlResolver = $null
    try { $fragment.Load($reader) } finally { $reader.Dispose() }
    if ($fragment.DocumentElement.LocalName -cne 'Fragment' -or $fragment.DocumentElement.NamespaceURI -cne $foundation) {
        throw 'Unexpected SDK fragment root.'
    }
    $identity = $configuration.identity
    $name = Get-Text $identity 'name' 50
    if ($name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$') { throw 'Invalid package identity name.' }
    $publisher = Get-Text $identity 'publisher' 8192
    $null = [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($publisher)
    $version = Get-Version (Get-Text $identity 'version')
    $minimum = Get-Version (Get-Text $configuration 'minimumWindowsVersion')
    $maximum = Get-Version (Get-Text $configuration 'maximumTestedWindowsVersion')
    if ($minimum -lt [version] '10.0.22000.0' -or $maximum -lt $minimum) { throw 'This widget host requires Windows 11 or later.' }
    $package = Add-Element $document 'Package' @{ IgnorableNamespaces = 'uap uap3 uap5 com rescap' }
    foreach ($pair in @(@('uap', $uap), @('uap3', $uap3), @('uap5', $uap5), @('com', $com), @('rescap', $rescap))) {
        $package.SetAttribute(('xmlns:' + $pair[0]), $pair[1])
    }
    $null = Add-Element $package 'Identity' @{ Name = $name; Publisher = $publisher; Version = $version.ToString(); ProcessorArchitecture = $inventory.architecture }
    $display = Use-Label (Get-Text $configuration 'displayName')
    $description = Use-Label (Get-Text $configuration 'description')
    $properties = Add-Element $package 'Properties'
    (Add-Element $properties 'DisplayName').InnerText = $display
    (Add-Element $properties 'PublisherDisplayName').InnerText = Use-Label (Get-Text $configuration 'publisherDisplayName')
    (Add-Element $properties 'Description').InnerText = $description
    (Add-Element $properties 'Logo').InnerText = Use-Image (Get-Text $configuration.visualAssets 'storeLogo' 2048)
    $resources = Add-Element $package 'Resources'
    $languages = @($configuration.languages)
    if ($languages.Count -lt 1 -or $languages.Count -gt 16) { throw 'Declare one to sixteen resource languages.' }
    $seenLanguages = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($language in $languages) {
        if ($language -isnot [string] -or $language -notmatch '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$' -or
            -not $seenLanguages.Add($language)) { throw 'Invalid or duplicate resource language.' }
        $null = Add-Element $resources 'Resource' @{ Language = $language }
    }
    $dependencies = Add-Element $package 'Dependencies'
    $null = Add-Element $dependencies 'TargetDeviceFamily' @{ Name = 'Windows.Desktop'; MinVersion = $minimum.ToString(); MaxVersionTested = $maximum.ToString() }
    $packageCapabilities = Add-Element $package 'Capabilities'
    $null = Add-Element $packageCapabilities 'Capability' @{ Name = 'internetClient' }
    $null = Add-Element $packageCapabilities 'rescap:Capability' @{ Name = 'runFullTrust' } $rescap
    # Package-level SDK registration includes its exact proxy/stub interfaces and in-process classes.
    $sdkExtensions = $fragment.DocumentElement.SelectSingleNode('*[local-name()="Extensions"]')
    if ($null -eq $sdkExtensions) { throw 'Missing SDK package extensions.' }
    $null = $package.AppendChild($document.ImportNode($sdkExtensions, $true))
    $applications = Add-Element $package 'Applications'
    $application = Add-Element $applications 'Application' @{ Id = 'CodexBar'; Executable = 'CodexBarWindows.exe'; EntryPoint = 'Windows.FullTrustApplication' }
    $null = Add-Element $application 'uap:VisualElements' @{
        DisplayName = $display; Description = $description; BackgroundColor = 'transparent'
        Square150x150Logo = (Use-Image (Get-Text $configuration.visualAssets 'square150Logo' 2048))
        Square44x44Logo = (Use-Image (Get-Text $configuration.visualAssets 'square44Logo' 2048))
    } $uap
    $extensions = Add-Element $application 'Extensions'
    $comExtension = Add-Element $extensions 'com:Extension' @{ Category = 'windows.comServer' } $com
    $server = Add-Element $comExtension 'com:ComServer' @{} $com
    $executable = Add-Element $server 'com:ExeServer' @{ Executable = 'CodexBarWidgetHost.exe'; DisplayName = 'CodexBar widget host' } $com
    # Windows/Widgets/Native/WidgetClassFactory.h owns this CLSID.
    $classID = '87b453c1-e69f-4cf4-a529-9e680ee69483'
    $null = Add-Element $executable 'com:Class' @{ Id = $classID; DisplayName = 'CodexBar widget provider' } $com
    $widgetExtension = Add-Element $extensions 'uap3:Extension' @{ Category = 'windows.appExtension' } $uap3
    $appExtension = Add-Element $widgetExtension 'uap3:AppExtension' @{
        Name = 'com.microsoft.windows.widgets'; DisplayName = $display; Id = 'CodexBarWidgets'; PublicFolder = 'WidgetAssets'
    } $uap3
    $widgetProperties = Add-Element $appExtension 'uap3:Properties' @{} $uap3
    $provider = Add-Element $widgetProperties 'WidgetProvider'
    $icons = Add-Element $provider 'ProviderIcons'
    $null = Add-Element $icons 'Icon' @{ Path = (Use-Image (Get-Text $configuration 'providerIcon' 2048) $true) }
    $activation = Add-Element $provider 'Activation'
    $null = Add-Element $activation 'CreateInstance' @{ ClassId = $classID }
    $definitions = Add-Element $provider 'Definitions'
    # Keep the original kind IDs and accepted sizes in WindowsWidgetHostDefinition.swift.
    $sizes = [ordered] @{
        CodexBarSwitcherWidget = @('small', 'medium', 'large'); CodexBarUsageWidget = @('small', 'medium', 'large')
        CodexBarHistoryWidget = @('medium', 'large'); CodexBarCompactWidget = @('small')
        CodexBarBurnDownWidget = @('medium'); CodexBarCombinedBurnDownWidget = @('medium')
    }
    $widgets = @($configuration.widgets)
    if ($widgets.Count -ne $sizes.Count) { throw 'All six widget definitions must be configured.' }
    $seenWidgets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($widget in $widgets) {
        $id = Get-Text $widget 'id'
        if ($id -cnotin @($sizes.Keys) -or -not $seenWidgets.Add($id)) { throw 'Unknown or duplicate widget definition.' }
        $definition = Add-Element $definitions 'Definition' @{
            Id = $id; DisplayName = (Use-Label (Get-Text $widget 'displayName'))
            Description = (Use-Label (Get-Text $widget 'description' 2048)); AllowMultiple = 'true'; IsCustomizable = 'true'
        }
        $capabilities = Add-Element $definition 'Capabilities'
        foreach ($size in $sizes[$id]) { $capability = Add-Element $capabilities 'Capability'; $null = Add-Element $capability 'Size' @{ Name = $size } }
        $theme = Add-Element $definition 'ThemeResources'
        Add-Theme $theme $widget
        foreach ($mode in @('DarkMode', 'LightMode')) {
            $property = $widget.PSObject.Properties[$mode]
            if ($null -ne $property) { Add-Theme (Add-Element $theme $mode) $property.Value }
        }
    }
    $startupTask = $configuration.startupTask
    if ($null -ne $startupTask) {
        $taskId = Get-Text $startupTask 'taskId' 64
        if ($taskId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Invalid startup task id.' }
        $enabledProperty = $startupTask.PSObject.Properties['enabled']
        if ($null -ne $enabledProperty -and $enabledProperty.Value -isnot [bool]) { throw 'Invalid startup task enabled flag.' }
        $startupEnabled = if ($null -ne $enabledProperty -and $enabledProperty.Value) { 'true' } else { 'false' }
        $startupExtension = Add-Element $extensions 'uap5:Extension' @{ Category = 'windows.startupTask' } $uap5
        $null = Add-Element $startupExtension 'uap5:StartupTask' @{
            TaskId = $taskId
            Enabled = $startupEnabled
            DisplayName = (Use-Label (Get-Text $startupTask 'displayName' 256))
        } $uap5
    }
    $output = [IO.Path]::GetFullPath($OutputManifest)
    if ([IO.Path]::GetFileName($output) -cne 'AppxManifest.xml') { throw 'Output must be named AppxManifest.xml.' }
    $buffer = [IO.MemoryStream]::new()
    $writerSettings = [Xml.XmlWriterSettings]::new()
    $writerSettings.Encoding = [Text.UTF8Encoding]::new($false)
    $writerSettings.Indent = $true
    $writer = [Xml.XmlWriter]::Create($buffer, $writerSettings)
    try { $document.Save($writer); $writer.Flush(); $bytes = $buffer.ToArray() }
    finally { $writer.Dispose(); $buffer.Dispose() }
    if ($bytes.Length -gt 1048576) { throw 'Generated manifest exceeds one MiB.' }
    if (-not $PSCmdlet.ShouldProcess('New MSIX manifest', 'Write widget and runtime registration declarations')) { return }
    $stream = [IO.File]::Open($output, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    [pscustomobject] @{ ManifestPath = $output; Status = 'MANIFEST_WRITTEN_UNVERIFIED'; Architecture = $inventory.architecture; RuntimeValidation = 'NOT_RUN' }
} finally {
    foreach ($stream in $held.Values) { $stream.Dispose() }
}
