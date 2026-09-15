# Source-only implementation. Run explicitly on Windows after build validation is authorized.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $MSBuildPath,
    [Parameter(Mandatory)][string] $NuGetPath,
    [Parameter(Mandatory)][string] $CallerPolicyPath,
    [Parameter(Mandatory)][ValidatePattern('^10\.0\.[0-9]+\.[0-9]+$')][string] $WindowsSdkVersion,
    [ValidateSet('x64', 'ARM64')][string] $Architecture = 'x64',
    [ValidateSet('Debug', 'Release')][string] $Configuration = 'Release'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This build requires Windows.' }
if ([version] $WindowsSdkVersion -lt [version] '10.0.22000.0') { throw 'The host targets Windows 11 or later.' }
function Get-BuildTool([string] $Path, [string] $Name) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "Supply the absolute trusted $Name path." }
    $tool = Get-Item -LiteralPath $Path -Force
    if ($tool.PSIsContainer -or $tool.Name -ine $Name -or ($tool.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular $Name file."
    }
    return $tool
}
function Get-BytesHash([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
$buildTool = Get-BuildTool $MSBuildPath 'MSBuild.exe'
$nugetTool = Get-BuildTool $NuGetPath 'NuGet.exe'
$policyFile = Get-Item -LiteralPath $CallerPolicyPath -Force
if ($policyFile.PSIsContainer -or ($policyFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    $policyFile.Length -le 0 -or $policyFile.Length -gt 8192) { throw 'Expected a caller policy JSON of at most 8 KiB.' }
$policyStream = [IO.File]::Open($policyFile.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    if ($policyStream.Length -le 0 -or $policyStream.Length -gt 8192) { throw 'Caller policy size changed.' }
    $policyBytes = New-Object byte[] ([int] $policyStream.Length)
    $offset = 0
    while ($offset -lt $policyBytes.Length) {
        $received = $policyStream.Read($policyBytes, $offset, $policyBytes.Length - $offset)
        if ($received -eq 0) { throw 'Caller policy ended before its declared size.' }
        $offset += $received
    }
} finally { $policyStream.Dispose() }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$policy = $utf8.GetString($policyBytes) | ConvertFrom-Json
if ($null -eq $policy -or @($policy.PSObject.Properties).Count -ne 3) { throw 'Unsupported caller policy schema.' }
foreach ($name in @('schemaVersion', 'packageFamily', 'executableNames')) {
    if ($null -eq $policy.PSObject.Properties[$name]) { throw 'Missing caller policy field.' }
}
if (($policy.schemaVersion -isnot [int] -and $policy.schemaVersion -isnot [long]) -or
    $policy.schemaVersion -ne 1 -or $policy.packageFamily -isnot [string] -or
    $policy.packageFamily -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,200}_[A-Za-z0-9]{1,20}$') {
    throw 'Caller policy must name one exact installed package family.'
}
if ($policy.executableNames -isnot [Array] -or $policy.executableNames.Count -lt 1 -or
    $policy.executableNames.Count -gt 8) { throw 'Caller policy requires one to eight executable names.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in $policy.executableNames) {
    if ($name -isnot [string] -or $name -inotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,249}\.exe$' -or -not $seen.Add($name)) {
        throw 'Caller policy contains an invalid or duplicate executable name.'
    }
}
$project = Join-Path $PSScriptRoot 'Native\Host\CodexBarWidgetHost.vcxproj'
$packages = Join-Path $PSScriptRoot 'Native\Host\packages.config'
$runRoot = Join-Path $PSScriptRoot ('Native\out\host-runs\' + [Guid]::NewGuid().ToString('N'))
$binaryRoot = Join-Path $runRoot 'bin'
$objectRoot = Join-Path $runRoot 'obj'
$packageRoot = Join-Path $runRoot 'packages'
$policyRoot = Join-Path $runRoot 'policy'
foreach ($path in @($project, $runRoot)) {
    if ($path.IndexOfAny([char[]] ';%"') -ge 0) { throw 'Repository path contains unsupported MSBuild property characters.' }
}
# Never clean, rebuild over, or fall back to an existing output. Preserve failed output and restored packages.
foreach ($directory in @($binaryRoot, $objectRoot, $packageRoot, $policyRoot)) {
    [void][IO.Directory]::CreateDirectory($directory)
}
$quotedNames = ($policy.executableNames | ForEach-Object { 'L"' + $_ + '"' }) -join ', '
$header = @"
#pragma once
#include <string>
#include <vector>
namespace CodexBar::Widgets::InstalledCallerPolicy {
inline constexpr wchar_t PackageFamily[] = L"$($policy.packageFamily)";
inline std::vector<std::wstring> ExecutableNames() { return {$quotedNames}; }
}
"@
[IO.File]::WriteAllText((Join-Path $policyRoot 'CodexBarWidgetCallerPolicy.h'), $header, $utf8)
[IO.File]::WriteAllBytes((Join-Path $policyRoot 'caller-policy.json'), $policyBytes)
# Exact versions, including transitive packages, are recorded in packages.config. No install scripts run.
& $nugetTool.FullName restore $packages -PackagesDirectory $packageRoot -Source 'https://api.nuget.org/v3/index.json' -NonInteractive -NoCache -DisableParallelProcessing
if ($LASTEXITCODE -ne 0) { throw "Widget host package restore failed. Output retained at $runRoot" }
$buildArguments = @(
    $project, '/nologo', '/t:Build', '/m:1', '/nr:false',
    "/p:Configuration=$Configuration", "/p:Platform=$Architecture",
    "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion",
    "/p:CodexBarNuGetPackagesDir=$($packageRoot.Replace('\', '/'))/",
    "/p:CodexBarWidgetPolicyDirectory=$($policyRoot.Replace('\', '/'))",
    "/p:OutDir=$($binaryRoot.Replace('\', '/'))/", "/p:IntDir=$($objectRoot.Replace('\', '/'))/"
)
& $buildTool.FullName @buildArguments
if ($LASTEXITCODE -ne 0) { throw "Widget host build failed with exit code $LASTEXITCODE. Output retained at $runRoot" }
$exe = Get-Item -LiteralPath (Join-Path $binaryRoot 'CodexBarWidgetHost.exe') -Force
if ($exe.PSIsContainer -or ($exe.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Expected a regular host executable.' }
$stream = [IO.File]::Open($exe.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $size = $stream.Length
    if ($size -le 0 -or $size -gt 536870912) { throw 'Expected a nonempty host executable of at most 512 MiB.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
} finally { $stream.Dispose() }
$receipt = [ordered] @{
    schemaVersion = 1
    component = 'CodexBarWidgetHost'
    architecture = $Architecture
    configuration = $Configuration
    windowsSdkVersion = $WindowsSdkVersion
    msbuildPath = $buildTool.FullName
    msbuildFileVersion = $buildTool.VersionInfo.FileVersion
    nugetFileVersion = $nugetTool.VersionInfo.FileVersion
    packagesConfigSHA256 = Get-BytesHash ([IO.File]::ReadAllBytes($packages))
    callerPolicySHA256 = Get-BytesHash $policyBytes
    callerPackageFamily = $policy.packageFamily
    callerExecutableNames = @($policy.executableNames)
    artifactPath = $exe.FullName
    artifactSize = $size
    artifactSHA256 = $hash
    outputDirectory = $binaryRoot
    deployment = 'SELF_CONTAINED_COMPONENTS_PACKAGE_REGISTRATION_REQUIRED'
    provenanceStatus = 'LOCAL_BUILD_NOT_ATTESTED'
    buildFinishedUtc = [DateTime]::UtcNow.ToString('o')
    validation = 'NOT_RUN'
}
$receiptPath = Join-Path $runRoot 'build-receipt.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 4), $utf8)
[pscustomobject] @{ ArtifactPath = $exe.FullName; OutputDirectory = $binaryRoot; ReceiptPath = $receiptPath }
