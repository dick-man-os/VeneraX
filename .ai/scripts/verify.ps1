[CmdletBinding()]
param(
    [string[]]$TestPath = @(),
    [switch]$QuickJs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot -or -not (Test-Path (Join-Path $repoRoot "AGENTS.md"))) {
    throw "verify.ps1 must be run from inside the VeneraX Git repository."
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)
Push-Location $repoRoot

try {
    Write-Host "=== Step 1: Checking whitespace and conflict markers (git diff --check) ==="
    git diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed with exit code $LASTEXITCODE"
    }
    Write-Host "git diff --check PASS`n"

    Write-Host "=== Step 2: Running static analysis (flutter analyze) ==="
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        throw "flutter analyze failed with exit code $LASTEXITCODE"
    }
    Write-Host "flutter analyze PASS`n"

    if ($TestPath -and $TestPath.Count -gt 0) {
        Write-Host "=== Step 3: Running targeted tests ==="

        $origPath = $env:PATH
        try {
            if ($QuickJs) {
                $quickJsPath = Join-Path $repoRoot "build\windows\x64\runner\Debug"
                Write-Host "Prepending QuickJS DLL path to local process PATH: $quickJsPath"
                $env:PATH = "$quickJsPath;$origPath"
            }

            foreach ($tp in $TestPath) {
                Write-Host "Running: flutter test $tp"
                flutter test $tp
                if ($LASTEXITCODE -ne 0) {
                    throw "flutter test $tp failed with exit code $LASTEXITCODE"
                }
            }
            Write-Host "Targeted tests PASS`n"
        }
        finally {
            $env:PATH = $origPath
        }
    }

    Write-Host "=== Step 4: Git working tree status (git status --short) ==="
    git status --short
    Write-Host "`n=== Verification Complete: ALL CHECKS PASSED ==="
}
finally {
    Pop-Location
}
