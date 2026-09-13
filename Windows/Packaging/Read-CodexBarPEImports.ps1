# Dot-sourced helper; reads PE32+ metadata without loading the image.
function Read-CodexBarPEImports([string] $Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        function Read-U16([long] $Offset) {
            if ($Offset -lt 0 -or $Offset -gt $stream.Length - 2) { throw 'PE read outside file.' }
            $stream.Position = $Offset
            return $reader.ReadUInt16()
        }
        function Read-U32([long] $Offset) {
            if ($Offset -lt 0 -or $Offset -gt $stream.Length - 4) { throw 'PE read outside file.' }
            $stream.Position = $Offset
            return $reader.ReadUInt32()
        }
        if ((Read-U16 0) -ne 0x5A4D) { throw 'Missing DOS signature.' }
        [long] $pe = Read-U32 0x3C
        if ($pe -lt 64 -or $pe -gt 1048576 -or (Read-U32 $pe) -ne 0x4550) { throw 'Invalid PE signature.' }
        $sectionCount = Read-U16 ($pe + 6)
        $optionalSize = Read-U16 ($pe + 20)
        $optional = $pe + 24
        if ($sectionCount -lt 1 -or $sectionCount -gt 96 -or $optionalSize -lt 112 -or
            (Read-U16 $optional) -ne 0x20B) { throw 'Only bounded PE32+ images are supported.' }
        $directoryCount = Read-U32 ($optional + 108)
        if ($directoryCount -gt 16 -or 112 + 8 * $directoryCount -gt $optionalSize) {
            throw 'Unsupported PE directory table.'
        }
        $headerSize = Read-U32 ($optional + 60)
        $sections = [Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $base = $optional + $optionalSize + 40 * $index
            $sections.Add([pscustomobject] @{
                rva = [long](Read-U32 ($base + 12))
                size = [long](Read-U32 ($base + 16))
                offset = [long](Read-U32 ($base + 20))
            })
        }
        function Resolve-Rva([long] $Rva, [long] $Size) {
            $matches = [Collections.Generic.List[long]]::new()
            if ($Rva -ge 0 -and $Rva + $Size -le $headerSize -and $Rva + $Size -le $stream.Length) {
                $matches.Add($Rva)
            }
            foreach ($section in $sections) {
                $delta = $Rva - $section.rva
                if ($delta -ge 0 -and $delta + $Size -le $section.size -and
                    $section.offset + $delta + $Size -le $stream.Length) {
                    $matches.Add($section.offset + $delta)
                }
            }
            if ($matches.Count -ne 1) { throw 'Unmapped or ambiguous PE RVA.' }
            return $matches[0]
        }
        function Read-DllName([long] $Rva) {
            $bytes = [Collections.Generic.List[byte]]::new()
            for ($index = 0; $index -lt 260; $index++) {
                $stream.Position = Resolve-Rva ($Rva + $index) 1
                $byte = $reader.ReadByte()
                if ($byte -eq 0) {
                    $name = [Text.Encoding]::ASCII.GetString($bytes.ToArray())
                    if ($name -notmatch '^[A-Za-z0-9_.+-]+\.dll$') { throw 'Unsupported import library name.' }
                    return $name.ToLowerInvariant()
                }
                if ($byte -lt 0x21 -or $byte -gt 0x7E) { throw 'Invalid import library name.' }
                $bytes.Add($byte)
            }
            throw 'Unterminated import library name.'
        }
        $imports = [Collections.Generic.List[object]]::new()
        foreach ($directory in @(@{ index = 1; stride = 20; name = 12; kind = 'import' },
                                  @{ index = 13; stride = 32; name = 4; kind = 'delayImport' })) {
            if ($directoryCount -le $directory.index) { continue }
            $entry = $optional + 112 + 8 * $directory.index
            [long] $rva = Read-U32 $entry
            [long] $size = Read-U32 ($entry + 4)
            if ($rva -eq 0 -and $size -eq 0) { continue }
            if ($rva -eq 0 -or $size -lt $directory.stride -or $size -gt 1048576) { throw 'Invalid import directory size.' }
            $terminated = $false
            for ($index = 0; $index -lt 4096 -and ($index + 1) * $directory.stride -le $size; $index++) {
                $offset = Resolve-Rva ($rva + $index * $directory.stride) $directory.stride
                $nonzero = $false
                for ($field = 0; $field -lt $directory.stride; $field += 4) {
                    if ((Read-U32 ($offset + $field)) -ne 0) { $nonzero = $true }
                }
                if (-not $nonzero) { $terminated = $true; break }
                if ($directory.kind -eq 'delayImport' -and (Read-U32 $offset) -ne 1) {
                    throw 'Only RVA-based delay import descriptors are supported.'
                }
                $nameRva = Read-U32 ($offset + $directory.name)
                if ($nameRva -eq 0) { throw 'Missing import DLL name.' }
                $imports.Add([pscustomobject] @{ name = (Read-DllName $nameRva); kind = $directory.kind })
            }
            if (-not $terminated) { throw 'Import directory terminator missing or limit exceeded.' }
        }
        return $imports.ToArray()
    } finally { $reader.Dispose() }
}
