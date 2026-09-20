# Volt KB hook helpers. Dot-sourced by every hook script in this folder.
# Target: Windows PowerShell 5.1. No external tools required.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$KbDir      = Join-Path $ProjectDir 'KB'
$StateDir   = Join-Path $ProjectDir '.claude\state'
$CoreFile   = Join-Path $KbDir 'Core.md'

# Paths injected in full at session start. They are also the required reads for the fallback gate.
$RequiredPaths = @('Decisions', 'Mistakes', 'Standards')

$AutoStart = '<!-- kb:auto-start -->'
$AutoEnd   = '<!-- kb:auto-end -->'

# ---------------------------------------------------------------- hook I/O

function Read-HookInput {
    $raw = ''
    try {
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
    } catch { $raw = '' }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Write-HookJson($obj) {
    $json = $obj | ConvertTo-Json -Depth 8 -Compress
    [Console]::Out.Write($json)
    [Console]::Out.Flush()
}

function Get-Prop($obj, $name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-SessionId($hookInput) {
    $sid = [string](Get-Prop $hookInput 'session_id')
    if ([string]::IsNullOrWhiteSpace($sid)) { $sid = 'unknown' }
    return $sid
}

function Get-SafeSid($sid) {
    $s = ([string]$sid) -replace '[^a-zA-Z0-9\-]', ''
    if ($s -eq '') { $s = 'unknown' }
    return $s
}

function Get-ShortSid($sid) {
    $clean = ([string]$sid) -replace '[^a-zA-Z0-9]', ''
    if ($clean.Length -eq 0) { return 'unknown' }
    if ($clean.Length -gt 8) { return $clean.Substring(0, 8) }
    return $clean
}

# ---------------------------------------------------------------- per-session state markers

function Ensure-StateDir {
    if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
}

function Get-StatePath($sid, $kind) {
    Ensure-StateDir
    return (Join-Path $StateDir ('{0}.{1}' -f (Get-SafeSid $sid), $kind))
}

function Write-State($sid, $kind, $text) {
    $p = Get-StatePath $sid $kind
    for ($i = 0; $i -lt 3; $i++) {
        try { [System.IO.File]::WriteAllText($p, [string]$text, $script:Utf8NoBom); return } catch { Start-Sleep -Milliseconds 60 }
    }
}

function Touch-State($sid, $kind) { Write-State $sid $kind (Get-Date -Format 'o') }

function Test-State($sid, $kind) { return (Test-Path -LiteralPath (Get-StatePath $sid $kind)) }

function Remove-State($sid, $kind) {
    $p = Get-StatePath $sid $kind
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
}

function Append-State($sid, $kind, $line) {
    $p = Get-StatePath $sid $kind
    for ($i = 0; $i -lt 3; $i++) {
        try { [System.IO.File]::AppendAllText($p, ([string]$line + "`n"), $script:Utf8NoBom); return } catch { Start-Sleep -Milliseconds 60 }
    }
}

function Read-StateLines($sid, $kind) {
    $p = Get-StatePath $sid $kind
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    return @([System.IO.File]::ReadAllLines($p) | Where-Object { $_.Trim() -ne '' })
}

function Read-StateText($sid, $kind) {
    $p = Get-StatePath $sid $kind
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $t = [System.IO.File]::ReadAllText($p).Trim()
    if ($t -eq '') { return $null }
    return $t
}

function Remove-OldState([int]$days) {
    Ensure-StateDir
    $cutoff = (Get-Date).AddDays(-$days)
    Get-ChildItem -LiteralPath $StateDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# The session's Memory node, relative to the project root. Fixed on first use so a
# session that crosses midnight keeps a single node.
function Get-SessionMemoryRel($sid) {
    $stored = Read-StateText $sid 'memory-file'
    if ($stored) { return $stored }
    $rel = 'KB/Memory/{0}-{1}.md' -f (Get-Date -Format 'yyyy-MM-dd'), (Get-ShortSid $sid)
    Write-State $sid 'memory-file' $rel
    return $rel
}

# ---------------------------------------------------------------- file helpers

function Read-Text($path) { return [System.IO.File]::ReadAllText($path) }
function Write-Text($path, $content) { [System.IO.File]::WriteAllText($path, [string]$content, $script:Utf8NoBom) }

function Resolve-ToolPath($p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    $p = ([string]$p) -replace '/', '\'
    try {
        if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $ProjectDir $p }
        return [System.IO.Path]::GetFullPath($p)
    } catch { return $null }
}

function Test-UnderDir($fullPath, $dir) {
    if ([string]::IsNullOrWhiteSpace($fullPath)) { return $false }
    $d = ([string]$dir).TrimEnd('\') + '\'
    return ([string]$fullPath).StartsWith($d, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelKbPath($fullPath) {
    if (-not (Test-UnderDir $fullPath $KbDir)) { return $null }
    $k = $KbDir.TrimEnd('\') + '\'
    return ([string]$fullPath).Substring($k.Length).Replace('\', '/')
}

# ---------------------------------------------------------------- KB structure

function Get-PathDirs {
    if (-not (Test-Path -LiteralPath $KbDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $KbDir -Directory | Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)
}

function Get-PathIndexFile($pathName) { return (Join-Path (Join-Path $KbDir $pathName) ($pathName + '.md')) }

function Get-Nodes($pathName) {
    $dir = Join-Path $KbDir $pathName
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File -Filter '*.md' | Where-Object { $_.Name -ine ($pathName + '.md') } | Sort-Object Name)
}

function Get-NodeMeta($file) {
    # Title: frontmatter title > first H1 > file basename. Description: frontmatter description.
    $title = $null; $desc = $null; $inFm = $false
    $lines = [System.IO.File]::ReadAllLines($file.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($i -eq 0 -and $l.Trim() -eq '---') { $inFm = $true; continue }
        if ($inFm) {
            if ($l.Trim() -eq '---') { $inFm = $false; continue }
            if ($l -match '^\s*description\s*:\s*(.+)$') { $desc = $matches[1].Trim().Trim('"').Trim("'") }
            elseif ($l -match '^\s*title\s*:\s*(.+)$') { $title = $matches[1].Trim().Trim('"').Trim("'") }
            continue
        }
        if (-not $title -and $l -match '^#\s+(.+)$') { $title = $matches[1].Trim(); break }
    }
    if (-not $title) { $title = $file.BaseName }
    return @{ Title = $title; Description = $desc }
}

function Get-RequiredKbReads {
    $req = @('Core.md')
    foreach ($p in $RequiredPaths) {
        if (Test-Path -LiteralPath (Get-PathIndexFile $p)) { $req += ('{0}/{0}.md' -f $p) }
        foreach ($n in (Get-Nodes $p)) { $req += ('{0}/{1}' -f $p, $n.Name) }
    }
    return $req
}

function Get-MissingKbReads($sid) {
    $read = @(Read-StateLines $sid 'kb-reads' | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $missing = @()
    foreach ($r in (Get-RequiredKbReads)) { if ($read -notcontains $r.ToLowerInvariant()) { $missing += $r } }
    return $missing
}

# ---------------------------------------------------------------- auto-maintained index sections

function Replace-AutoSection($content, $newBody) {
    $eol = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $body = ([string]$newBody) -replace "`r?`n", $eol
    $block = $AutoStart + $eol + $body + $eol + $AutoEnd
    $s = $content.IndexOf($AutoStart); $e = $content.IndexOf($AutoEnd)
    if ($s -ge 0 -and $e -gt $s) {
        return $content.Substring(0, $s) + $block + $content.Substring($e + $AutoEnd.Length)
    }
    return $content.TrimEnd() + $eol + $eol + $block + $eol
}

function Update-KbIndexes {
    $paths = Get-PathDirs
    if (Test-Path -LiteralPath $CoreFile) {
        $lines = @()
        foreach ($p in $paths) {
            $count = (Get-Nodes $p.Name).Count
            $word = if ($count -eq 1) { 'node' } else { 'nodes' }
            $desc = ''
            $idx = Get-PathIndexFile $p.Name
            if (Test-Path -LiteralPath $idx) {
                $m = Get-NodeMeta (Get-Item -LiteralPath $idx)
                if ($m.Description) { $desc = ' - ' + $m.Description }
            }
            $lines += ('- [[{0}/{0}|{0}]] ({1} {2}){3}' -f $p.Name, $count, $word, $desc)
        }
        if ($lines.Count -eq 0) { $lines = @('_No paths yet._') }
        $c = Read-Text $CoreFile
        $n = Replace-AutoSection $c ($lines -join "`n")
        if ($n -ne $c) { Write-Text $CoreFile $n }
    }
    foreach ($p in $paths) {
        $idx = Get-PathIndexFile $p.Name
        if (-not (Test-Path -LiteralPath $idx)) { continue }
        $lines = @()
        foreach ($node in (Get-Nodes $p.Name)) {
            $m = Get-NodeMeta $node
            $line = '- [[{0}/{1}|{2}]]' -f $p.Name, $node.BaseName, $m.Title
            if ($m.Description) { $line += ' - ' + $m.Description }
            $lines += $line
        }
        if ($lines.Count -eq 0) { $lines = @('_No nodes yet._') }
        $c = Read-Text $idx
        $n = Replace-AutoSection $c ($lines -join "`n")
        if ($n -ne $c) { Write-Text $idx $n }
    }
}
