#Requires -Version 5.1
<#
.SYNOPSIS
    Codex 가 Claude 구현 결과를 리뷰하는 러너 (task-006, Phase D, opt-in).
    Bash codex-review.sh 와 동작 패리티.

.DESCRIPTION
    1. base 완료 전제 검증(--check-review-target): impl-notes(done)+summary(done)+manifest.
       approved-done 리뷰 게이트는 제외(재리뷰 순환 방지).
    2. review.codex 프로필(gpt-5.5/xhigh)로 codex 리뷰 요청 — staging 파일 하나만.
    3. staging 을 --check-review 로 검증한 뒤에만 reviews/<NNN>.md 로 승격.

.EXAMPLE
    ./runtime/codex-review.ps1 task-004
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TaskId
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

. "$ScriptDir\lib\common.ps1"
. "$ScriptDir\lib\invoke-codex.ps1"

$TaskDir         = Join-Path $ProjectRoot "kb\tasks\$TaskId"
$DesignFile      = Join-Path $TaskDir "design.md"
$ImplNotes       = Join-Path $TaskDir "implementation-notes.md"
$ArtifactSummary = Join-Path $ProjectRoot "kb\artifacts\$TaskId-summary.md"
$ReviewsDir      = Join-Path $TaskDir "reviews"
$Staging         = Join-Path $TaskDir ".review-staging.md"
$ReviewTemplate  = Join-Path $ProjectRoot "templates\review.md"
$ValidatorCli    = Join-Path $ProjectRoot "runtime\validator\cli.py"
$RP              = Join-Path $ProjectRoot "runtime\render-prompt.py"

$py = Resolve-Python
if (-not $py) {
    Write-Host "[ERROR] Python 3 을 찾을 수 없습니다." -ForegroundColor Red
    Write-Host "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
    exit 2
}
$exe = $py[0]
$prefix = if ($py.Count -gt 1) { $py[1..($py.Count - 1)] } else { @() }

function Invoke-ValidatorArgs {
    param([string[]]$Args)
    & $exe @prefix $ValidatorCli @Args 2>&1 | ForEach-Object { Write-Host $_ }
    return [int]$LASTEXITCODE
}

# --- base 완료 전제 (리뷰 게이트 제외) ---
Write-Host "--- 리뷰 전제 검증 (base done, 리뷰 게이트 제외) ---"
$targetRc = Invoke-ValidatorArgs -Args @("--check-review-target", $TaskId)
if ($targetRc -ne 0) {
    Write-Host "[ERROR] base 완료 전제 미충족 (rc=$targetRc). 구현이 done 상태여야 리뷰할 수 있습니다." -ForegroundColor Red
    exit $targetRc
}

# --- review.codex 프로필 조회 ---
$model = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("profile", "--phase", "review", "--cli", "codex", "--field", "model")
if ($model.Code -ne 0) { Write-Host "[ERROR] 프로필 해석 실패(model) — 리뷰 중단." -ForegroundColor Red; exit $model.Code }
$effort = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("profile", "--phase", "review", "--cli", "codex", "--field", "effort")
if ($effort.Code -ne 0) { Write-Host "[ERROR] 프로필 해석 실패(effort) — 리뷰 중단." -ForegroundColor Red; exit $effort.Code }

# --- CLI 버전 preflight (codex 존재 시에만) ---
$codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
if (-not $codexCmd) { $codexCmd = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue }
if ($codexCmd) {
    $verOut = (& $codexCmd.Source --version 2>&1 | Out-String).Trim()
    $ver = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("check-cli-version", "--phase", "review", "--cli", "codex", "--version-output", $verOut)
    if ($ver.Code -ne 0) {
        Write-Host "[ERROR] codex CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $verOut)" -ForegroundColor Red
        exit 1
    }
}

# --- 다음 리뷰 번호 (NNN) ---
$nextNum = 1
if (Test-Path $ReviewsDir) {
    Get-ChildItem -Path $ReviewsDir -Filter "*.md" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match '^[0-9]{3}$') {
            $n = [int]$_.BaseName
            if ($n -ge $nextNum) { $nextNum = $n + 1 }
        }
    }
}
$NNN = '{0:D3}' -f $nextNum
$ReviewFile = Join-Path $ReviewsDir "$NNN.md"

# --- 리뷰 프롬프트 렌더 (staging 경로) ---
if (Test-Path $Staging) { Remove-Item $Staging -Force }
$prompt = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("render", "--phase", "review", "--task-id", $TaskId, "--design-file", $DesignFile, "--impl-notes", $ImplNotes, "--artifact-summary", $ArtifactSummary, "--review-file", $Staging, "--review-template", $ReviewTemplate, "--project-root", $ProjectRoot, "--model", $model.Value, "--effort", $effort.Value)
if ($prompt.Code -ne 0) { Write-Host "[ERROR] 리뷰 프롬프트 렌더 실패 — 중단." -ForegroundColor Red; exit 1 }

# --- codex 리뷰 호출 ---
$invokeRc = [int](Invoke-CodexReview -ProjectRoot $ProjectRoot -Prompt $prompt.Value -Model $model.Value -Effort $effort.Value)
if ($invokeRc -ne 0) {
    Write-Host "[ERROR] codex 리뷰 호출 실패 (exit $invokeRc)." -ForegroundColor Red
    if (Test-Path $Staging) { Remove-Item $Staging -Force }
    exit $invokeRc
}
if (-not (Test-Path $Staging)) {
    Write-Host "[ERROR] codex 가 리뷰 파일을 쓰지 않았습니다: $Staging" -ForegroundColor Red
    exit 1
}

# --- staging 검증 (통과해야만 승격) ---
$reviewRc = Invoke-ValidatorArgs -Args @("--check-review", $Staging)
if ($reviewRc -ne 0) {
    Write-Host "[ERROR] 생성된 리뷰가 검증을 통과하지 못했습니다 (rc=$reviewRc). 승격하지 않습니다." -ForegroundColor Red
    Remove-Item $Staging -Force -ErrorAction SilentlyContinue
    exit $reviewRc
}

# --- 승격: reviews/NNN.md ---
if (-not (Test-Path $ReviewsDir)) { New-Item -ItemType Directory -Path $ReviewsDir -Force | Out-Null }
Move-Item -Force $Staging $ReviewFile
Write-Host "[OK] 리뷰 생성: $ReviewFile"

# --- 상태 안내 (no-auto-revert) ---
$latestJson = (& $exe @prefix $ValidatorCli "--latest-review" $TaskId "--json" 2>$null | Out-String)
$status = ""
try { $status = ($latestJson | ConvertFrom-Json).status } catch { $status = "" }
Write-Host "[INFO] 최신 리뷰 status: $(if ($status) { $status } else { '?' })"
if ($status -ne "approved") {
    Write-Host "[INFO] approved 가 아니므로 approved-done 게이트는 아직 통과하지 않습니다."
    Write-Host "       (no-auto-revert: 구현 상태는 자동으로 바뀌지 않습니다. 구현자가 다음 액션을 판단하세요.)"
}
