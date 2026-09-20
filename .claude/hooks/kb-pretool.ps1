# PreToolUse hook for Write|Edit|MultiEdit|NotebookEdit|Bash|PowerShell|Agent|WebSearch|WebFetch.
# 1. Denies git commit / push / merge / rebase / cherry-pick / revert and gh pr create / merge.
# 2. Denies every work tool until the session is marked KB-loaded (by SessionStart, or by reading
#    every required KB file with the Read tool, which the PostToolUse hook tracks).
# 3. Denies Write/Edit of any .lua or .luau file outside KB/ until the ponytail skill has been invoked
#    this session (the PostToolUse hook records the Skill call as the "ponytail-loaded" marker).
# 4. Denies Write/Edit of any non-ignored repository file, and any shell command that is not read-only
#    or a branch switch, while the working tree is on main. Nothing is written on main.
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

# True when every segment of the command is read-only or a branch switch (git switch -c x, git switch x,
# git checkout -b x, git checkout x): all a session may run while the working tree is on main.
function Test-MainSafeCommand($cmd) {
    $branchRe = '(?i)^git(?:\.exe)?(?:\s+-\S+(?:\s+\S+)?)*\s+(checkout|switch)\s+(?:(?:-b|-c|--create)\s+)?[^\s-]\S*$'
    foreach ($seg in [regex]::Split([string]$cmd, '(?:\|\||&&|;|\||\r?\n)')) {
        $s = $seg.Trim().TrimStart('&', '(', ' ').Trim()
        if ($s -eq '' -or $s -match $branchRe -or (Test-ReadOnlyCommand $s)) { continue }
        return $false
    }
    return $true
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
    $isWrite = $tool -match '^(Write|Edit|MultiEdit|NotebookEdit)$'
    $fp   = Get-Prop $ti 'file_path'
    if (-not $fp) { $fp = Get-Prop $ti 'notebook_path' }
    $full = Resolve-ToolPath $fp
    if ($isWrite -and $full -and ($full -match '(?i)\.luau?$') -and -not (Test-UnderDir $full $KbDir) -and -not (Test-State $sid 'ponytail-loaded')) {
        Deny 'BLOCKED by KB policy (KB/Standards/invoke-ponytail-before-writing-code.md): Volt code is written with the ponytail skill active. Invoke it now with the Skill tool (skill "ponytail:ponytail"), then retry this write. One invocation per session is enough.'
    }

    # ---- 4. branch guard: nothing is written on main ----------------------------------------------
    $switchHelp = 'the working tree is on main and nothing is written on main (KB/Standards/never-write-on-main.md). Switch to a branch first with one command on its own, git switch -c <name>, named by KB/Standards/code-style-tooling-config-conventions.md 11.8: feature/<system>, fix/<x>, docs/<x>, or CU-<taskid>_<compactname>_<author>. Uncommitted changes carry over to the new branch. Then retry.'
    if ($isWrite -and $full -and (Test-UnderDir $full $ProjectDir) -and ((Get-GitBranch) -eq 'main') -and -not (Test-GitIgnored $full)) {
        Deny ('BLOCKED by KB policy: ' + $switchHelp)
    }
    if (($tool -eq 'Bash' -or $tool -eq 'PowerShell') -and -not (Test-MainSafeCommand $cmd) -and ((Get-GitBranch) -eq 'main')) {
        Deny ('BLOCKED by KB policy: this shell command is not read-only, and ' + $switchHelp + ' If it only reads, use plain read-only commands (cat, ls, grep, git status/diff/log) with no variable assignments.')
    }
    exit 0
} catch {
    Write-HookJson @{ systemMessage = ('KB PreToolUse hook error, call allowed through: ' + $_.Exception.Message) }
    exit 0
}
