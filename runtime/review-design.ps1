#Requires -Version 5.1
<#
.SYNOPSIS
    Codex 설계에 대한 Claude 읽기전용 2차 검토(cross-review) 러너 (task-005, P1).
    Bash review-design.sh 와 동작 패리티: 같은 precondition, 종료코드, provenance, JSON 판정.

.DESCRIPTION
    1. design.md 존재 + validator 통과를 precondition 으로 확인 (미통과 시 Claude 호출 안 함).
    2. design.claude_cross_check 프로필(fable-5/max + fallback opus-4-8)로 읽기전용 검토 요청.
    3. 결과를 kb/tasks/<id>/design-review.md 에 기록하고 manifest 에 provenance 를 남긴다.

    advisory: 검토가 우려를 지적해도 종료코드 0. non-zero 는 precondition/렌더/프로필/CLI/
    JSON 파싱/파일 쓰기 오류에만. design.md 는 읽기전용(전후 해시 비교). collab.md/done-gate 미접촉.

.EXAMPLE
    ./runtime/review-design.ps1 task-004
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

$TaskDir      = Join-Path $ProjectRoot "kb\tasks\$TaskId"
$DesignFile   = Join-Path $TaskDir "design.md"
$ReviewFile   = Join-Path $TaskDir "design-review.md"
$ManifestFile = Join-Path $TaskDir "manifest.md"
$ValidatorCli = Join-Path $ProjectRoot "runtime\validator\cli.py"
$RP           = Join-Path $ProjectRoot "runtime\render-prompt.py"

# --- precondition: design.md + manifest ---
if (-not (Test-Path $DesignFile)) {
    Write-Host "[ERROR] 설계 문서가 없습니다: $DesignFile" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $ManifestFile)) {
    Write-Host "[ERROR] manifest 가 없습니다: $ManifestFile (provenance 기록 대상)" -ForegroundColor Red
    exit 1
}

# --- precondition: validator 통과 ---
Write-Host "--- 설계 검증 (교차검토 전제) ---"
$code = [int](Invoke-Validator -File $DesignFile -ValidatorCli $ValidatorCli)
if ($code -ne 0) {
    Write-Host "[ERROR] 설계 검증 미통과 (rc=$code). 교차검토를 실행하지 않습니다." -ForegroundColor Red
    exit $code
}

# --- 재귀 가드 ---
if ((Test-ClaudeSession) -and (-not (Test-Truthy $env:CLAUDE_AUTO_FORCE))) {
    Write-Host "[WARN] Claude Code 세션 내부에서 자동 호출을 거부합니다 (재귀 방지)." -ForegroundColor Yellow
    Write-Host "       우회하려면 CLAUDE_AUTO_FORCE=1 을 설정하세요."
    Write-Host "       교차검토를 건너뜁니다 (design-review.md 를 만들지 않음)."
    exit 0
}

$claudeCmd = Get-Command claude.cmd -ErrorAction SilentlyContinue
if (-not $claudeCmd) { $claudeCmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue }
if (-not $claudeCmd) {
    Write-Host "[WARN] claude CLI를 찾을 수 없습니다. 교차검토를 건너뜁니다." -ForegroundColor Yellow
    exit 1
}

# --- 프로필 조회 (design.claude_cross_check) ---
$model = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("profile", "--phase", "design", "--cli", "claude", "--field", "model")
if ($model.Code -ne 0) { Write-Host "[ERROR] 프로필 해석 실패(model) — 교차검토 중단." -ForegroundColor Red; exit $model.Code }
$effort = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("profile", "--phase", "design", "--cli", "claude", "--field", "effort")
if ($effort.Code -ne 0) { Write-Host "[ERROR] 프로필 해석 실패(effort) — 교차검토 중단." -ForegroundColor Red; exit $effort.Code }
$fallback = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("profile", "--phase", "design", "--cli", "claude", "--field", "fallback_model")
if ($fallback.Code -ne 0) { Write-Host "[ERROR] 프로필 해석 실패(fallback_model) — 교차검토 중단." -ForegroundColor Red; exit $fallback.Code }

# --- CLI 버전 preflight ---
$verOut = (& $claudeCmd.Source --version 2>&1 | Out-String).Trim()
$ver = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("check-cli-version", "--phase", "design", "--cli", "claude", "--version-output", $verOut)
if ($ver.Code -ne 0) {
    Write-Host "[ERROR] claude CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $verOut)" -ForegroundColor Red
    exit 1
}

# --- 프롬프트 렌더 ---
$prompt = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("render", "--phase", "design-review", "--task-id", $TaskId, "--design-file", $DesignFile, "--review-file", $ReviewFile, "--project-root", $ProjectRoot, "--model", $model.Value, "--effort", $effort.Value)
if ($prompt.Code -ne 0) { Write-Host "[ERROR] 프롬프트 렌더 실패 — 교차검토 중단." -ForegroundColor Red; exit 1 }

# --- design.md 읽기전용 보증: 실행 전 해시 ---
$beforeHash = (Get-FileHash -Algorithm SHA256 -Path $DesignFile).Hash

Write-Host "[INFO] Claude 교차검토 요청 중... (model=$($model.Value), effort=$($effort.Value), fallback=$($fallback.Value), cli=$($ver.Value))"
Write-Host ""
$tmpJson = [System.IO.Path]::GetTempFileName()
try {
    $raw = ($null | & $claudeCmd.Source -p $prompt.Value --model $model.Value --effort $effort.Value `
        --fallback-model $fallback.Value --output-format json 2>$null | Out-String)
    $claudeRc = [int]$LASTEXITCODE
    if ($claudeRc -ne 0) { Write-Host "[ERROR] claude 호출 실패 (exit $claudeRc)." -ForegroundColor Red; exit $claudeRc }
    [System.IO.File]::WriteAllText($tmpJson, $raw, [System.Text.UTF8Encoding]::new($false))

    # --- 실제 model / fallback / 본문 추출 (조용한 폴백 금지) ---
    $actual = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("detect-fallback", "--json-file", $tmpJson, "--requested-model", $model.Value, "--fallback-model", $fallback.Value, "--field", "actual_model")
    if ($actual.Code -ne 0) { Write-Host "[ERROR] fallback 판별 실패." -ForegroundColor Red; exit 1 }
    $fired = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("detect-fallback", "--json-file", $tmpJson, "--requested-model", $model.Value, "--fallback-model", $fallback.Value, "--field", "fallback")
    if ($fired.Code -ne 0) { Write-Host "[ERROR] fallback 판별 실패." -ForegroundColor Red; exit 1 }
    $body = Invoke-RenderPrompt -RenderPrompt $RP -Arguments @("detect-fallback", "--json-file", $tmpJson, "--requested-model", $model.Value, "--fallback-model", $fallback.Value, "--field", "response_text")
    if ($body.Code -ne 0) { Write-Host "[ERROR] 응답 본문 추출 실패." -ForegroundColor Red; exit 1 }
}
finally {
    Remove-Item $tmpJson -Force -ErrorAction SilentlyContinue
}

# --- design.md 읽기전용 보증: 실행 후 해시 비교 ---
$afterHash = (Get-FileHash -Algorithm SHA256 -Path $DesignFile).Hash
if ($beforeHash -ne $afterHash) {
    Write-Host "[ERROR] design.md 가 교차검토 중 변경되었습니다. 산출물을 기록하지 않고 실패합니다 (읽기전용 위반)." -ForegroundColor Red
    exit 1
}

# --- design-review.md 기록 (atomic-ish: temp write → move) ---
$today = Get-Date -Format 'yyyy-MM-dd'
$header = @"
# 설계 교차검토 — $TaskId

> **advisory** (구현 게이트 아님). Reviewer: Claude ($($actual.Value)/$($effort.Value)), $today. fallback=$($fired.Value)
> Target: $DesignFile (읽기전용). 이 문서는 runtime/review-design.ps1 가 생성했다.

"@
$tmpReview = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpReview, $header + $body.Value + "`n", [System.Text.UTF8Encoding]::new($false))
Move-Item -Force $tmpReview $ReviewFile
Write-Host "[OK] 교차검토 기록: $ReviewFile"

# --- manifest provenance ---
[System.IO.File]::AppendAllText($ManifestFile,
    "- **cross_reviewed_by**: claude $($actual.Value)/$($effort.Value) @claude $($ver.Value), $today (fallback=$($fired.Value))`n",
    [System.Text.UTF8Encoding]::new($false))
Write-Host "[OK] provenance 기록: $ManifestFile"

if (Test-Truthy $fired.Value) {
    Write-Host "[WARN] fallback 발동: $($model.Value) → $($actual.Value) (effort=$($effort.Value) 유지)." -ForegroundColor Yellow
}
