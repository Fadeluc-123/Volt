# Stop hook. Regenerates the KB index lists, then refuses to end a turn that did work (session is
# "dirty") until this session's Memory node has been created or updated. Blocks at most twice per
# stop cycle so a misbehaving session cannot loop forever; after that it lets the turn end with a warning.
. (Join-Path $PSScriptRoot 'kb-common.ps1')

try {
    $hookInput = Read-HookInput
    $sid    = Get-SessionId $hookInput
    $active = $false
    $a = Get-Prop $hookInput 'stop_hook_active'
    if ($null -ne $a) { $active = [bool]$a }

    try { Update-KbIndexes } catch { }

    if (-not (Test-State $sid 'dirty')) { exit 0 }

    if (-not $active) { Remove-State $sid 'stop-retries' }
    $tries = (Read-StateLines $sid 'stop-retries').Count
    if ($tries -ge 2) {
        Remove-State $sid 'stop-retries'
        Write-HookJson @{ systemMessage = 'KB WARNING: work was done this turn but the session Memory node was not written after two reminders. Ask Claude to update KB/Memory, or do it by hand.' }
        exit 0
    }
    Append-State $sid 'stop-retries' (Get-Date -Format 'o')

    $memRel    = Get-SessionMemoryRel $sid
    $memExists = Test-Path -LiteralPath (Resolve-ToolPath $memRel)
    $research  = Read-StateLines $sid 'research'

    $step1 = if ($memExists) {
        ('UPDATE the existing session Memory node {0} with the Edit tool so it reflects everything done in this session so far.' -f $memRel)
    } else {
        ('CREATE the session Memory node {0} with the Write tool, using the template in KB/Memory/Memory.md.' -f $memRel)
    }
    $researchNote = ''
    if ($research.Count -gt 0) { $researchNote = (' Web research detected this session ({0} call(s)); make sure the findings are recorded.' -f $research.Count) }

    $reason = @(
        'KB UPDATE REQUIRED before this turn can end (enforced by .claude/hooks/kb-stop.ps1). Work was done that is not yet recorded in the knowledge base. Do the following, then stop again:',
        ('1. ' + $step1 + ' Content: what was done, why, how, outcome (what is verified and what is not), open threads. Keep it compact, aim for under 25 lines. It is a summary, not a session log.'),
        '2. If any mistake was made and corrected in this session (wrong assumption, broken build, misread requirement, tool misuse, rule broken), add ONE node PER mistake to KB/Mistakes using the template in KB/Mistakes/Mistakes.md. Skip if none.',
        ('3. If research was done (web searches, documentation reading, investigation that produced reusable knowledge), add ONE node PER topic to KB/Research using the template in KB/Research/Research.md. Skip if none.' + $researchNote),
        '4. If a new convention or rule was agreed with the user, add ONE node to KB/Standards using its template. Skip if none.',
        '5. If a plan was made or progressed, create or update its node in KB/Planning. Skip if none.',
        'Rules: one node per thing, never merge two things into one node; never edit or delete another session''s Memory node; use Write or Edit for KB files, not shell commands; do not run git commit or git push.'
    ) -join "`n"

    Write-HookJson @{ decision = 'block'; reason = $reason }
    exit 0
} catch {
    exit 0
}
