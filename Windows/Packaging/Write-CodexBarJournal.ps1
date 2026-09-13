# Callers own the operations lock and validate the containing managed directory.
function Write-CodexBarJournal {
    param([Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][object] $Record)
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.pending'
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Record | ConvertTo-Json -Depth 10))
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid journal destination.' }
        # Keep the previous generation; incomplete temporary files are also preserved on failure.
        [IO.File]::Replace($temporary, $Path, ($Path + '.' + [Guid]::NewGuid().ToString('N') + '.previous'))
    } else { [IO.File]::Move($temporary, $Path) }
}
