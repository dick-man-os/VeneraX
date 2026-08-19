[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot -or -not (Test-Path (Join-Path $repoRoot "AGENTS.md"))) {
    throw "status.ps1 must be run from inside the VeneraX Git repository."
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)

$branch = (git branch --show-current 2>$null).Trim()
$headSha = (git rev-parse HEAD 2>$null).Trim()
$upstream = (git rev-parse --abbrev-ref '@{upstream}' 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstream)) {
    $upstream = "none"
} else {
    $upstream = $upstream.Trim()
}

$statusLines = @(git status --porcelain=v1 2>$null)
$stagedFiles = [System.Collections.Generic.List[string]]::new()
$unstagedFiles = [System.Collections.Generic.List[string]]::new()
$untrackedFiles = [System.Collections.Generic.List[string]]::new()

foreach ($line in $statusLines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $x = $line.Substring(0, 1)
    $y = $line.Substring(1, 1)
    $filePath = $line.Substring(3).Trim()

    if ($x -eq '?' -and $y -eq '?') {
        $untrackedFiles.Add($filePath)
    } else {
        if ($x -ne ' ' -and $x -ne '?') {
            $stagedFiles.Add($filePath)
        }
        if ($y -ne ' ' -and $y -ne '?') {
            $unstagedFiles.Add($filePath)
        }
    }
}

$currentHandoffPath = Join-Path $repoRoot ".ai\handoff\current.md"
$handoffExists = Test-Path $currentHandoffPath
$handoffStatus = "NONE"

if ($handoffExists) {
    $content = Get-Content $currentHandoffPath
    $inStatusSection = $false
    foreach ($cLine in $content) {
        $trimmed = $cLine.Trim()
        if ($trimmed -eq "## Handoff Status") {
            $inStatusSection = $true
            continue
        }
        if ($inStatusSection) {
            if ($trimmed.StartsWith("##")) {
                break
            }
            if ($trimmed -match '^(CLEAN_BASELINE|IN_PROGRESS_SAFE_TO_CONTINUE|BLOCKED|NEEDS_REVIEW)$') {
                $handoffStatus = $matches[1]
                break
            }
            if ($trimmed -match '^[A-Z_]+$' -and -not $trimmed.StartsWith("<!--")) {
                $handoffStatus = $trimmed
                break
            }
        }
    }
}

Write-Host "=== VeneraX Multi-Agent Status ==="
Write-Host "Repository Root: $repoRoot"
Write-Host "Branch:          $branch"
Write-Host "HEAD SHA:        $headSha"
Write-Host "Upstream:        $upstream"
Write-Host "Handoff Exists:  $handoffExists"
Write-Host "Handoff Status:  $handoffStatus"
Write-Host ""
Write-Host "--- Git Working Tree Status ---"
if ($statusLines.Count -eq 0) {
    Write-Host "Working tree is CLEAN."
} else {
    Write-Host "Staged Files ($($stagedFiles.Count)):"
    if ($stagedFiles.Count -eq 0) {
        Write-Host "  (none)"
    } else {
        foreach ($f in $stagedFiles) { Write-Host "  [staged]   $f" }
    }

    Write-Host "Unstaged Files ($($unstagedFiles.Count)):"
    if ($unstagedFiles.Count -eq 0) {
        Write-Host "  (none)"
    } else {
        foreach ($f in $unstagedFiles) { Write-Host "  [unstaged] $f" }
    }

    Write-Host "Untracked Files ($($untrackedFiles.Count)):"
    if ($untrackedFiles.Count -eq 0) {
        Write-Host "  (none)"
    } else {
        foreach ($f in $untrackedFiles) { Write-Host "  [untracked] $f" }
    }
}
