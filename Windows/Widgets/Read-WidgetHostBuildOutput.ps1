# Invoked by the explicit Windows build after MSBuild finishes; no program is launched here.
function Read-WidgetHostBuildOutput([string] $OutputDirectory) {
    $root = Get-Item -LiteralPath $OutputDirectory -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Widget host output must be a regular directory.'
    }
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject] @{ directory = $root.FullName; prefix = ''; depth = 0 })
    $files = [Collections.Generic.List[object]]::new()
    $visited = 0
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        if ($node.depth -gt 16) { throw 'Widget output tree is too deep.' }
        foreach ($item in Get-ChildItem -LiteralPath $node.directory -Force) {
            if (++$visited -gt 8192) { throw 'Widget output tree exceeds its entry limit.' }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked widget output is unsupported.' }
            $relative = $node.prefix + $item.Name
            if ($item.PSIsContainer) {
                $queue.Enqueue([pscustomobject] @{ directory = $item.FullName; prefix = $relative + '/'; depth = $node.depth + 1 })
                continue
            }
            # These are explicit build-only artifacts, not a catch-all extension exclusion.
            if ($relative -in @('CodexBarWidgetHost.pdb', 'CodexBarWidgetHost.ilk', 'CodexBarWidgetHost.lib', 'CodexBarWidgetHost.exp')) { continue }
            if ($files.Count -ge 4096) { throw 'Widget payload exceeds its file limit.' }
            $kind = if ($relative -ieq 'CodexBarWidgetHost.exe') { 'application' }
                elseif ($relative.StartsWith('licenses/windows-widget-host/', [StringComparison]::OrdinalIgnoreCase)) { 'license' }
                elseif ($item.Extension -ieq '.dll') { 'runtime' } else { 'resource' }
            $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $size = $stream.Length
                if ($size -gt 536870912) { throw 'Widget payload file exceeds 512 MiB.' }
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
                finally { $sha.Dispose() }
            } finally { $stream.Dispose() }
            $files.Add([pscustomobject] @{ path = $relative; kind = $kind; bytes = $size; sha256 = $hash })
        }
    }
    return [pscustomobject] @{ schemaVersion = 1; files = @($files.ToArray() | Sort-Object path) }
}
