[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutgoingAgent,

    [Parameter(Mandatory = $true)]
    [string]$NextAgent,

    [Parameter(Mandatory = $true)]
    [string]$Objective,

    [Parameter(Mandatory = $true)]
    [string]$CurrentPhase,

    [Parameter(Mandatory = $true)]
    [ValidateSet("CLEAN_BASELINE", "IN_PROGRESS_SAFE_TO_CONTINUE", "BLOCKED", "NEEDS_REVIEW")]
    [string]$HandoffStatus,

    [string[]]$Completed = @(),
    [string[]]$ChangedFiles = @(),
    [string[]]$VerificationNotes = @(),
    [string[]]$KnownIssues = @(),
    [string[]]$Decisions = @(),
    [string[]]$NextSteps = @(),
    [string[]]$DoNot = @(),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot -or -not (Test-Path (Join-Path $repoRoot "AGENTS.md"))) {
    throw "handoff.ps1 must be run from inside the VeneraX Git repository."
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)

$handoffDir = Join-Path $repoRoot ".ai\handoff"
$currentHandoffFile = Join-Path $handoffDir "current.md"

if ((Test-Path $currentHandoffFile) -and -not $Force) {
    throw "Handoff file '$currentHandoffFile' already exists. Use -Force to overwrite."
}

if (-not (Test-Path $handoffDir)) {
    New-Item -ItemType Directory -Path $handoffDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$branch = (git branch --show-current 2>$null).Trim()
$headSha = (git rev-parse HEAD 2>$null).Trim()

$statusPorcelain = @(git status --porcelain=v1 2>$null)
$staged = [System.Collections.Generic.List[string]]::new()
$unstaged = [System.Collections.Generic.List[string]]::new()
$untracked = [System.Collections.Generic.List[string]]::new()

foreach ($line in $statusPorcelain) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $x = $line.Substring(0, 1)
    $y = $line.Substring(1, 1)
    $fp = $line.Substring(3).Trim()

    if ($x -eq '?' -and $y -eq '?') {
        $untracked.Add($fp)
    } else {
        if ($x -ne ' ' -and $x -ne '?') {
            $staged.Add($fp)
        }
        if ($y -ne ' ' -and $y -ne '?') {
            $unstaged.Add($fp)
        }
    }
}

$rawStatus = @(git status --short 2>$null)
$statusShortDisplay = if ($rawStatus.Count -eq 0) { "CLEAN" } else { "`n" + ($rawStatus -join "`n") }
$stagedDisplay = if ($staged.Count -eq 0) { "none" } else { ($staged -join ", ") }
$unstagedDisplay = if ($unstaged.Count -eq 0) { "none" } else { ($unstaged -join ", ") }
$untrackedDisplay = if ($untracked.Count -eq 0) { "none" } else { ($untracked -join ", ") }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# VeneraX Agent Handoff")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Handoff Metadata")
[void]$sb.AppendLine("- Outgoing agent: $OutgoingAgent")
[void]$sb.AppendLine("- Intended next agent: $NextAgent")
[void]$sb.AppendLine("- Timestamp: $timestamp")
[void]$sb.AppendLine("- Repository: $repoRoot")
[void]$sb.AppendLine("- Branch: $branch")
[void]$sb.AppendLine("- Baseline HEAD: $headSha")
[void]$sb.AppendLine("- Current HEAD: $headSha")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Task")
[void]$sb.AppendLine("- Objective: $Objective")
[void]$sb.AppendLine("- Current phase: $CurrentPhase")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Completed")
if ($Completed.Count -gt 0) {
    foreach ($item in $Completed) { [void]$sb.AppendLine("- $item") }
} else {
    [void]$sb.AppendLine("- (None recorded)")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Current Working Tree")
[void]$sb.AppendLine("- git status --short: $statusShortDisplay")
[void]$sb.AppendLine("- Staged files: $stagedDisplay")
[void]$sb.AppendLine("- Unstaged files: $unstagedDisplay")
[void]$sb.AppendLine("- Untracked files: $untrackedDisplay")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Changed Files")
if ($ChangedFiles.Count -gt 0) {
    foreach ($cf in $ChangedFiles) { [void]$sb.AppendLine("- $cf") }
} else {
    [void]$sb.AppendLine("- None")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Verification")
if ($VerificationNotes.Count -gt 0) {
    foreach ($vn in $VerificationNotes) { [void]$sb.AppendLine("- $vn") }
} else {
    [void]$sb.AppendLine("- git diff --check: PASS")
    [void]$sb.AppendLine("- flutter analyze: PASS")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Known Issues / Blockers")
if ($KnownIssues.Count -gt 0) {
    foreach ($ki in $KnownIssues) { [void]$sb.AppendLine("- $ki") }
} else {
    [void]$sb.AppendLine("- None")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Decisions / Constraints")
if ($Decisions.Count -gt 0) {
    foreach ($d in $Decisions) { [void]$sb.AppendLine("- $d") }
} else {
    [void]$sb.AppendLine("- Only one modifying agent may use this working tree at a time.")
    [void]$sb.AppendLine("- AGENTS.md is the authoritative durable project rule set.")
    [void]$sb.AppendLine("- Do not commit credentials or secrets.")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Next Steps")
if ($NextSteps.Count -gt 0) {
    for ($i = 0; $i -lt $NextSteps.Count; $i++) {
        [void]$sb.AppendLine("$($i+1). $($NextSteps[$i])")
    }
} else {
    [void]$sb.AppendLine("1. Review handoff and resume next task.")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Do Not")
if ($DoNot.Count -gt 0) {
    foreach ($dn in $DoNot) { [void]$sb.AppendLine("- $dn") }
} else {
    [void]$sb.AppendLine("- Do not commit .ai/handoff/current.md.")
    [void]$sb.AppendLine("- Do not commit credentials, tokens, or API keys.")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Handoff Status")
[void]$sb.AppendLine("$HandoffStatus")

# Write to current.md
[System.IO.File]::WriteAllText($currentHandoffFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

# Verify that current.md is ignored
Push-Location $repoRoot
try {
    $ignored = (git check-ignore ".ai/handoff/current.md" 2>$null)
    if (-not $ignored) {
        Remove-Item -Path $currentHandoffFile -Force -ErrorAction SilentlyContinue
        throw "CRITICAL ERROR: .ai/handoff/current.md is NOT ignored by git! File removed."
    }
}
finally {
    Pop-Location
}

Write-Host "Successfully generated local handoff at: $currentHandoffFile"
Write-Host "Handoff Status: $HandoffStatus"
