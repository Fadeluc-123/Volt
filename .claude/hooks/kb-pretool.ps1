# PreToolUse hook for Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell|Agent|WebSearch|WebFetch.
# 1. Denies git commit / push / merge / rebase / cherry-pick / revert and gh pr create / merge.
# 2. Denies every work tool until the session is marked KB-loaded (by SessionStart, or by reading
#    every required KB file with the Read tool, which the PostToolUse hook tracks).
# 3. Denies Write/Edit of any .lua or .luau file outside KB/ until the ponytail skill has been invoked
#    this session (the PostToolUse hook records the Skill call as the "ponytail-loaded" marker).
. (Join-Path $PSScriptRoot 'kb-common.ps1')

function Deny($reason) {
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
    }
    exit 0
}

try {
    $hookInput = Read-HookInput
    if ($null -eq $hookInput) { exit 0 }
    $sid  = Get-SessionId $hookInput
    $tool = [string](Get-Prop $hookInput 'tool_name')
    $ti   = Get-Prop $hookInput 'tool_input'

    # ---- 1. git guard -------------------------------------------------------------------------
    if ($tool -eq 'Bash' -or $tool -eq 'PowerShell') {
        $cmd = [string](Get-Prop $ti 'command')
        $prefix = '(?im)(^|[\s;&|(`{"''])'
        $gitRe  = $prefix + 'git(?:\.exe)?(?:\s+-\S+(?:\s+\S+)?)*\s+(commit|push|merge|rebase|cherry-pick|revert)\b'
        $ghRe   = $prefix + 'gh(?:\.exe)?\s+pr\s+(create|merge)\b'
        if ($cmd -match $gitRe -or $cmd -match $ghRe) {
            Deny 'BLOCKED by KB policy (KB/Standards/git-commits-are-manual.md): git commit, push, merge, rebase, cherry-pick, revert and PR creation are done by the user after reviewing the code. Leave the changes in the working tree, summarise what changed, and tell the user it is ready to review and commit.'
        }
    }

    # ---- 2. KB gate ---------------------------------------------------------------------------
    if (-not (Test-State $sid 'kb-loaded')) {
        $missing = Get-MissingKbReads $sid
        if ($missing.Count -eq 0) {
            # Everything was read but the marker was not set (for example the PostToolUse hook was skipped).
            Touch-State $sid 'kb-loaded'
        } else {
            $list = ($missing | ForEach-Object { 'KB/' + $_ }) -join ', '
            Deny ('BLOCKED: the Volt knowledge base has not been loaded in this session and no work may start before it is read (KB/Standards/kb-read-before-work.md). Use the Read tool on each of these files now; the gate opens automatically after the last one: ' + $list)
        }
    }

    # ---- 3. ponytail gate for Luau writes ---------------------------------------------------------
    if ($tool -match '^(Write|Edit|MultiEdit|NotebookEdit)$') {
        $fp   = Get-Prop $ti 'file_path'
        if (-not $fp) { $fp = Get-Prop $ti 'notebook_path' }
        $full = Resolve-ToolPath $fp
        if ($full -and ($full -match '(?i)\.luau?$') -and -not (Test-UnderDir $full $KbDir) -and -not (Test-State $sid 'ponytail-loaded')) {
            Deny 'BLOCKED by KB policy (KB/Standards/invoke-ponytail-before-writing-code.md): Volt code is written with the ponytail skill active. Invoke it now with the Skill tool (skill "ponytail:ponytail"), then retry this write. One invocation per session is enough.'
        }
    }
    exit 0
} catch {
    Write-HookJson @{ systemMessage = ('KB PreToolUse hook error, call allowed through: ' + $_.Exception.Message) }
    exit 0
}
