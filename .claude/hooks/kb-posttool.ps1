# PostToolUse hook for Read|Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell|WebSearch|WebFetch.
# - Read of a KB file: recorded; when every required KB file has been read the session is marked KB-loaded.
# - Write/Edit outside KB: marks the session "dirty" (work done, not yet recorded in Memory).
# - Write/Edit of this session's Memory node: clears "dirty".
# - Non-read-only shell command, WebSearch, WebFetch: marks "dirty".
# - Skill tool invoking ponytail: marks the session "ponytail-loaded" (the PreToolUse hook gates Luau writes on it).
. (Join-Path $PSScriptRoot 'kb-common.ps1')

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
