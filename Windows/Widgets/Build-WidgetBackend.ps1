# Source-only implementation: invoke explicitly on Windows after build validation is authorized.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $MSBuildPath,
    [Parameter(Mandatory)][ValidatePattern('^10\.0\.[0-9]+\.[0-9]+$')][string] $WindowsSdkVersion,
    [ValidateSet('x64', 'ARM64')][string] $Architecture = 'x64',
    [ValidateSet('Debug', 'Release')][string] $Configuration = 'Release'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This build requires Windows.' }
if (-not [IO.Path]::IsPathRooted($MSBuildPath)) { throw 'Supply the absolute trusted MSBuild.exe path.' }
$buildTool = Get-Item -LiteralPath $MSBuildPath -ErrorAction Stop
if ($buildTool.PSIsContainer -or $buildTool.Name -ine 'MSBuild.exe') { throw 'Expected MSBuild.exe.' }
$project = Join-Path $PSScriptRoot 'Native\CodexBarWidgetBackend.vcxproj'
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) { throw 'Widget backend project is missing.' }
# Never clean/rebuild an existing directory or reuse a stale binary as a successful artifact.
$runID = [Guid]::NewGuid().ToString('N')
$runRoot = Join-Path $PSScriptRoot "Native\out\runs\$runID"
$binaryRoot = Join-Path $runRoot 'bin'
$objectRoot = Join-Path $runRoot 'obj'
# MSBuild treats semicolons/percent sequences/quotes as property syntax, not literal path characters.
foreach ($path in @($project, $runRoot)) {
    if ($path.IndexOfAny([char[]] ';%"') -ge 0) { throw 'Repository path contains unsupported MSBuild property characters.' }
}
[void][IO.Directory]::CreateDirectory($binaryRoot)
[void][IO.Directory]::CreateDirectory($objectRoot)
$buildArguments = @(
    $project, '/nologo', '/t:Build', '/m:1', '/nr:false',
    "/p:Configuration=$Configuration", "/p:Platform=$Architecture",
    "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion",
    # Forward slash avoids a terminal backslash escaping a native argument's closing quote.
    "/p:OutDir=$($binaryRoot.Replace('\', '/'))/", "/p:IntDir=$($objectRoot.Replace('\', '/'))/"
)
& $buildTool.FullName @buildArguments
if ($LASTEXITCODE -ne 0) { throw "Widget backend build failed with exit code $LASTEXITCODE. Output retained at $runRoot" }
$dll = Join-Path $binaryRoot 'CodexBarWidgetBackend.dll'
if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw 'MSBuild returned success without the expected DLL.' }
# Bind the receipt to the produced bytes while denying write/delete sharing during the read.
$artifact = Get-Item -LiteralPath $dll -Force
if (($artifact.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $artifact.Length -le 0 -or
    $artifact.Length -gt 536870912) { throw 'Expected a nonempty regular backend DLL no larger than 512 MiB.' }
$artifactStream = [IO.File]::Open($artifact.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $artifactSize = $artifactStream.Length
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $artifactHash = ([BitConverter]::ToString($sha.ComputeHash($artifactStream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
} finally { $artifactStream.Dispose() }
# Build receipt only: byte identity is not a signed attestation or tests/ABI/load/release approval.
$receipt = [ordered] @{
    schemaVersion = 1
    component = 'CodexBarWidgetBackend'
    architecture = $Architecture
    configuration = $Configuration
    windowsSdkVersion = $WindowsSdkVersion
    msbuildPath = $buildTool.FullName
    msbuildFileVersion = $buildTool.VersionInfo.FileVersion
    artifactPath = $dll
    artifactSize = $artifactSize
    artifactSHA256 = $artifactHash
    provenanceStatus = 'LOCAL_BUILD_NOT_ATTESTED' 
    buildFinishedUtc = [DateTime]::UtcNow.ToString('o')
    validation = 'NOT_RUN'
}
$receiptPath = Join-Path $runRoot 'build-receipt.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
[pscustomobject] @{ ArtifactPath = $dll; ReceiptPath = $receiptPath }
