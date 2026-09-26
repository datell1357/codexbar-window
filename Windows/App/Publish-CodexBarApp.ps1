# Source-only implementation. Invoke on Windows only after build validation is authorized.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string] $DotNetPath,
    [Parameter(Mandatory)][string] $PackageLockFile,
    [Parameter(Mandatory)][string] $LicenseDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string] $SourceRevision,
    [Parameter(Mandatory)][string] $ProductVersion,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string] $Architecture,
    [Parameter(Mandatory)][string] $OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Packaging\Read-CodexBarBuildProvenance.ps1')
. (Join-Path $PSScriptRoot '..\Packaging\Read-CodexBarAppPayload.ps1')
. (Join-Path $PSScriptRoot '..\Packaging\Read-CodexBarPEImports.ps1')
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$null = Read-CodexBarBuildProvenance ([pscustomobject] @{
    repository = 'https://github.com/datell1357/codexbar-window'; revision = $SourceRevision
    version = $ProductVersion; status = 'DECLARED_NOT_ATTESTED'
})
if (-not [IO.Path]::IsPathRooted($DotNetPath)) { throw 'Specify the absolute trusted dotnet.exe path.' }
$dotnet = Get-Item -LiteralPath $DotNetPath -Force
if ($dotnet.PSIsContainer -or $dotnet.Name -ine 'dotnet.exe' -or
    ($dotnet.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Expected a regular dotnet.exe.' }
$lock = Get-Item -LiteralPath $PackageLockFile -Force
if ($lock.PSIsContainer -or ($lock.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
    $lock.Length -le 0 -or $lock.Length -gt 4194304) { throw 'Supply a reviewed packages.lock.json, at most 4 MiB.' }
$licenseRoot = Get-Item -LiteralPath $LicenseDirectory -Force
if (-not $licenseRoot.PSIsContainer -or ($licenseRoot.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Supply a regular directory containing the reviewed dependency licenses and THIRD-PARTY-NOTICES.txt.'
}
$runRoot = [IO.Path]::GetFullPath($OutputDirectory)
$sourceRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
if ((Test-Path -LiteralPath $runRoot) -or
    ($runRoot.TrimEnd('\') + '\').StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be a new directory outside the source project.'
}
$project = Join-Path $PSScriptRoot 'CodexBarApp.csproj'
foreach ($path in @($project, $runRoot)) {
    if ($path.IndexOfAny([char[]] ';%"') -ge 0) { throw 'Unsupported MSBuild property path characters.' }
}
# No clean/rebuild or reuse of output directories. Failed builds and downloaded packages are retained.
if (-not $PSCmdlet.ShouldProcess('New Windows app publish directory', 'Restore locked packages and publish WinUI')) { return }
$null = New-Item -ItemType Directory -Path $runRoot
$publish = Join-Path $runRoot 'publish'
$objects = Join-Path $runRoot 'obj'
$binary = Join-Path $runRoot 'bin'
$packages = Join-Path $runRoot 'packages'
foreach ($directory in @($publish, $objects, $binary, $packages)) { $null = New-Item -ItemType Directory -Path $directory }
$copiedLock = Join-Path $runRoot 'packages.lock.json'
[IO.File]::Copy($lock.FullName, $copiedLock, $false)
if ((Get-Item -LiteralPath $copiedLock).Length -gt 4194304) { throw 'Copied lock exceeds 4 MiB.' }
$lockHash = (Get-FileHash -LiteralPath $copiedLock -Algorithm SHA256).Hash.ToLowerInvariant()
$platform = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
$properties = @(
    "-p:Platform=$platform", '-p:Configuration=Release',
    "-p:Version=$ProductVersion",
    "-p:BaseIntermediateOutputPath=$($objects.Replace('\', '/'))/",
    "-p:MSBuildProjectExtensionsPath=$($objects.Replace('\', '/'))/",
    "-p:BaseOutputPath=$($binary.Replace('\', '/'))/",
    "-p:RestorePackagesPath=$($packages.Replace('\', '/'))",
    "-p:NuGetLockFilePath=$($copiedLock.Replace('\', '/'))",
    '-p:RestoreLockedMode=true', '-p:SelfContained=true', '-p:WindowsAppSDKSelfContained=true',
    '-p:PublishSingleFile=false', '-p:PublishTrimmed=false'
)
try {
    & $dotnet.FullName restore $project --runtime "win-$Architecture" --locked-mode --source 'https://api.nuget.org/v3/index.json' @properties
    if ($LASTEXITCODE -ne 0) { throw 'Windows app locked restore failed.' }
    & $dotnet.FullName publish $project --configuration Release --runtime "win-$Architecture" --no-restore --output $publish @properties
    if ($LASTEXITCODE -ne 0) { throw 'Windows app publish failed.' }
    if ((Get-FileHash -LiteralPath $copiedLock -Algorithm SHA256).Hash -ine $lockHash) { throw 'Dependency lock changed during publish.' }
    # Licenses are explicit inputs, not a claim that NuGet automatically supplied complete notices.
    $licenses = Join-Path $publish 'licenses'
    if (Test-Path -LiteralPath $licenses) { throw 'Publish output already contains the reserved licenses directory.' }
    $null = New-Item -ItemType Directory -Path $licenses
    $licenseQueue = [Collections.Generic.Queue[object]]::new()
    $licenseQueue.Enqueue([pscustomobject] @{ source = $licenseRoot.FullName; target = $licenses; depth = 0 })
    $licenseCount = 0
    while ($licenseQueue.Count -gt 0) {
        $node = $licenseQueue.Dequeue()
        if ($node.depth -gt 16) { throw 'License directory depth exceeded.' }
        foreach ($item in Get-ChildItem -LiteralPath $node.source -Force) {
            $licenseCount++
            if ($licenseCount -gt 4096 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Linked or excessive license inputs.'
            }
            $target = Join-Path $node.target $item.Name
            if ($item.PSIsContainer) {
                $null = New-Item -ItemType Directory -Path $target
                $licenseQueue.Enqueue([pscustomobject] @{ source = $item.FullName; target = $target; depth = $node.depth + 1 })
            } else {
                if ($item.Length -le 0 -or $item.Length -gt 16777216) { throw 'Unsupported license size.' }
                [IO.File]::Copy($item.FullName, $target, $false)
            }
        }
    }
    $files = [Collections.Generic.List[object]]::new()
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject] @{ path = $publish; prefix = 'App'; depth = 0 })
    $visited = 0
    $machine = if ($Architecture -eq 'x64') { 0x8664 } else { 0xAA64 }
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        if ($node.depth -gt 32) { throw 'Publish directory depth exceeded.' }
        foreach ($item in Get-ChildItem -LiteralPath $node.path -Force) {
            $visited++
            if ($visited -gt 8192 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Linked or excessive publish output.'
            }
            $relative = $node.prefix + '/' + $item.Name
            if ($item.PSIsContainer) {
                $queue.Enqueue([pscustomobject] @{ path = $item.FullName; prefix = $relative; depth = $node.depth + 1 })
                continue
            }
            $extension = $item.Extension.ToLowerInvariant()
            $kind = if ($extension -eq '.exe') { 'application' } elseif ($extension -eq '.dll') { 'runtime' }
                elseif ($relative.StartsWith('App/licenses/', [StringComparison]::OrdinalIgnoreCase)) { 'license' }
                else { 'resource' }
            if ($kind -in @('application', 'runtime')) {
                $null = Read-CodexBarPEImage $item.FullName $machine ($kind -eq 'runtime')
            }
            if ($item.Length -gt 536870912) { throw 'Publish file exceeds the payload size limit.' }
            $files.Add([pscustomobject] @{
                path = $relative; kind = $kind; bytes = $item.Length
                sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    $payload = [pscustomobject] @{ schemaVersion = 1; files = @($files.ToArray() | Sort-Object path) }
    $null = Read-CodexBarAppPayload $payload
    $receipt = [ordered] @{
        schemaVersion = 1; component = 'CodexBarApp'; architecture = $Architecture; configuration = 'Release'
        sourceRevision = $SourceRevision; productVersion = $ProductVersion; provenanceStatus = 'LOCAL_BUILD_NOT_ATTESTED'
        deployment = 'SELF_CONTAINED_WINUI'; packagesLockSHA256 = $lockHash; payload = $payload
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($receipt | ConvertTo-Json -Depth 8))
    if ($bytes.Length -gt 4194304) { throw 'App receipt exceeds 4 MiB.' }
    $stream = [IO.File]::Open((Join-Path $runRoot 'build-receipt.json'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    Write-Output 'Windows app published with a local byte receipt. Runtime, licensing completeness and release approval remain unverified.'
} catch {
    Write-Warning 'Publish failed. All partial output and downloaded packages were preserved; choose a new output directory.'
    throw
}
