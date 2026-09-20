# PostToolUse hook for Read|Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell|WebSearch|WebFetch.
# - Read of a KB file: recorded; when every required KB file has been read the session is marked KB-loaded.
# - Write/Edit outside KB: marks the session "dirty" (work done, not yet recorded in Memory).
# - Write/Edit of this session's Memory node: clears "dirty".
# - Non-read-only shell command, WebSearch, WebFetch: marks "dirty".
# - Skill tool invoking ponytail: marks the session "ponytail-loaded" (the PreToolUse hook gates Luau writes on it).
. (Join-Path $PSScriptRoot 'kb-common.ps1')

function Test-ReadOnlyCommand($cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $true }
    $ro = @('ls', 'dir', 'cat', 'type', 'echo', 'pwd', 'cd', 'tree', 'head', 'tail', 'wc', 'grep', 'rg', 'find', 'findstr', 'where', 'which',
            'whoami', 'hostname', 'get-childitem', 'gci', 'get-content', 'gc', 'get-location', 'get-item', 'gi', 'get-command', 'gcm',
            'test-path', 'select-string', 'sls', 'resolve-path', 'rvpa', 'where-object', 'select-object', 'sort-object', 'format-table',
            'format-list', 'out-string', 'measure-object', 'get-date', 'get-process', 'get-help', 'get-member', 'write-output',
            'write-host', 'set-location', 'sl', 'gm', 'select', 'sort', 'ft', 'fl', 'measure', 'get-filehash', 'get-itemproperty', 'gp')
    $roGit = @('status', 'log', 'diff', 'show', 'branch', 'remote', 'rev-parse', 'ls-files', 'blame', 'describe', 'config', 'shortlog', 'reflog', 'stash')
    $segments = [regex]::Split($cmd, '(?:\|\||&&|;|\||\r?\n)')
    foreach ($seg in $segments) {
        $s = $seg.Trim().TrimStart('&', '(', ' ')
        if ($s -eq '') { continue }
        if ($s -match '^\$\w+\s*=\s*(.*)$') { $s = $matches[1].Trim() }
        if ($s -match '^\(?\s*([\w\.\-]+)(?:\s+(\S+))?') {
            $first  = $matches[1].ToLowerInvariant()
            $second = if ($matches[2]) { $matches[2].ToLowerInvariant() } else { '' }
        } else { return $false }
        if ($first -eq 'git' -or $first -eq 'git.exe') {
            if ($roGit -notcontains $second) { return $false }
            if ($second -eq 'stash' -and $s -notmatch '^\S+\s+stash\s+(list|show)\b') { return $false }
            continue
        }
        if ($ro -notcontains $first) { return $false }
    }
    return $true
}

try {
    $hookInput = Read-HookInput
    if ($null -eq $hookInput) { exit 0 }
    $sid  = Get-SessionId $hookInput
    $tool = [string](Get-Prop $hookInput 'tool_name')
    $ti   = Get-Prop $hookInput 'tool_input'
    $fp   = Get-Prop $ti 'file_path'
    if (-not $fp) { $fp = Get-Prop $ti 'notebook_path' }
    $full = Resolve-ToolPath $fp

    switch -Regex ($tool) {
        '^Read$' {
            if ($full -and (Test-UnderDir $full $KbDir)) {
                $rel = Get-RelKbPath $full
                if ($rel -and $rel.ToLowerInvariant().EndsWith('.md')) { Append-State $sid 'kb-reads' $rel }
                if (-not (Test-State $sid 'kb-loaded')) {
                    $missing = Get-MissingKbReads $sid
                    if ($missing.Count -eq 0) {
                        Touch-State $sid 'kb-loaded'
                        $memRel = Get-SessionMemoryRel $sid
                        Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = ("KB fully read. Write, Edit, shell, Agent and web tools are now unlocked for this session. This session's Memory node: {0} (create or update it before ending any turn that does work). One node per thing." -f $memRel) } }
                    } else {
                        Write-HookJson @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = ('KB gate: still unread: ' + (($missing | ForEach-Object { 'KB/' + $_ }) -join ', ')) } }
                    }
                }
            }
        }
        '^(Write|Edit|MultiEdit|NotebookEdit)$' {
            if (-not $full) { break }
            if (Test-UnderDir $full $StateDir) { break }
            if (Test-UnderDir $full $KbDir) {
                $memFull = Resolve-ToolPath (Get-SessionMemoryRel $sid)
                if ($full -ieq $memFull) {
                    Remove-State $sid 'dirty'
                    Touch-State $sid 'memory-written'
                }
            } else {
                Touch-State $sid 'dirty'
            }
        }
        '^(Bash|PowerShell)$' {
            $cmd = [string](Get-Prop $ti 'command')
            if (-not (Test-ReadOnlyCommand $cmd)) { Touch-State $sid 'dirty' }
        }
        '^(WebSearch|WebFetch)$' {
            $q = [string](Get-Prop $ti 'query'); if (-not $q) { $q = [string](Get-Prop $ti 'url') }
            Append-State $sid 'research' ($tool + ': ' + $q)
            Touch-State $sid 'dirty'
        }
        '^Skill$' {
            $skill = ''
            foreach ($k in @('skill', 'skill_name', 'name', 'command')) {
                $v = [string](Get-Prop $ti $k)
                if ($v) { $skill = $v; break }
            }
            if ($skill -match '(?i)(^|[:/])ponytail$') { Touch-State $sid 'ponytail-loaded' }
        }
    }
    exit 0
} catch {
    exit 0
}
