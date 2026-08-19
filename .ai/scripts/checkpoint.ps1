[CmdletBinding()]
param(
    [string]$CheckpointDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot -or -not (Test-Path (Join-Path $repoRoot "AGENTS.md"))) {
    throw "checkpoint.ps1 must be run from inside the VeneraX Git repository."
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)

if ([string]::IsNullOrWhiteSpace($CheckpointDir)) {
    $parentDir = Split-Path -Parent $repoRoot
    $checkpointRoot = Join-Path $parentDir "_checkpoints"
} else {
    $checkpointRoot = [System.IO.Path]::GetFullPath($CheckpointDir)
}

# Ensure checkpoint location is outside the repo
if ($checkpointRoot.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Checkpoint directory must be located OUTSIDE the Git repository. Target: $checkpointRoot"
}

$timestampFolder = "VeneraX-" + (Get-Date -Format "yyyyMMdd-HHmmss")
$targetFolder = Join-Path $checkpointRoot $timestampFolder

if (-not (Test-Path $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
}

Push-Location $repoRoot
try {
    # 1. branch.txt
    $branch = (git branch --show-current 2>$null)
    if ($null -eq $branch) { $branch = "" } else { $branch = $branch.Trim() }
    Set-Content -Path (Join-Path $targetFolder "branch.txt") -Value $branch -Encoding UTF8

    # 2. head.txt
    $headSha = (git rev-parse HEAD 2>$null)
    if ($null -eq $headSha) { $headSha = "" } else { $headSha = $headSha.Trim() }
    Set-Content -Path (Join-Path $targetFolder "head.txt") -Value $headSha -Encoding UTF8

    # 3. git-status.txt
    $gitStatus = @(git status 2>$null)
    Set-Content -Path (Join-Path $targetFolder "git-status.txt") -Value $gitStatus -Encoding UTF8

    # 4. working-tree.patch (git diff --binary)
    $workingTreeDiff = @(git diff --binary 2>$null)
    Set-Content -Path (Join-Path $targetFolder "working-tree.patch") -Value $workingTreeDiff -Encoding UTF8

    # 5. staged.patch (git diff --cached --binary)
    $stagedDiff = @(git diff --cached --binary 2>$null)
    Set-Content -Path (Join-Path $targetFolder "staged.patch") -Value $stagedDiff -Encoding UTF8

    # 6. untracked-files.txt (NAMES ONLY)
    $untracked = @(git ls-files --others --exclude-standard 2>$null)
    Set-Content -Path (Join-Path $targetFolder "untracked-files.txt") -Value $untracked -Encoding UTF8

    # 7. handoff-current.md (if current.md exists)
    $currentHandoff = Join-Path $repoRoot ".ai\handoff\current.md"
    if (Test-Path $currentHandoff) {
        Copy-Item -Path $currentHandoff -Destination (Join-Path $targetFolder "handoff-current.md") -Force
    }

    # 8. README.txt
    $readmeContent = @"
VeneraX Multi-Agent Checkpoint
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
Repository: $repoRoot
Branch: $branch
HEAD: $headSha

INCLUDED IN THIS CHECKPOINT:
- Current branch name (branch.txt)
- HEAD commit SHA (head.txt)
- Complete git status output (git-status.txt)
- Binary patch of unstaged working tree changes (working-tree.patch)
- Binary patch of staged index changes (staged.patch)
- List of untracked file names (untracked-files.txt)
- Local handoff state if present (handoff-current.md)

IMPORTANT NOTICE / WHAT WAS NOT BACKED UP:
- Untracked file contents are NOT included in this checkpoint (names only).
- Ignored files (.env, credentials, auth tokens, build artifacts, etc.) are NOT included.
- No secrets, tokens, or local environment credentials were saved.
"@
    Set-Content -Path (Join-Path $targetFolder "README.txt") -Value $readmeContent -Encoding UTF8
}
finally {
    Pop-Location
}

Write-Host "Checkpoint created successfully at:"
Write-Host "  $targetFolder"
