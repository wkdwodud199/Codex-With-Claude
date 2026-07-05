#Requires -Version 5.1
<#
.SYNOPSIS
    Codex CLI 호출 로직 (PowerShell).

.DESCRIPTION
    Dot-source 전용. 내보내는 함수:
      Invoke-CodexIfEnabled -TaskId -DesignFile -TaskDesc -AutoMode -ProjectRoot
        - 반환 0  : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
        - 반환 1  : --auto 인데 CLI 부재 / 버전 미달 / 정책 실패 / 호출 실패.
        - 반환 2  : 환경 오류 (python 부재, 프로필·프롬프트 IO/해석 오류).

    task-004 (bash invoke-codex.sh 와 동작 패리티):
      - 모델/effort 는 runtime/config/model-profiles.json(SSOT)에서 render-prompt.py 로
        얻어 항상 `-m <model> -c model_reasoning_effort=<effort>` 를 명시한다.
      - 프로필/렌더 실패 시 --auto 를 거부한다 (조용한 기본값 금지).
      - CLI 버전 preflight: min_cli_version 미달이면 호출하지 않고 실패.
      - 호출 성공 시 $script:CwcProvLine 에 provenance 를 남긴다 (러너가 기록).

    D2 정책:
      - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 0 반환.
      - --auto 인데 codex CLI 부재 → NON-ZERO.
      - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.

    Claude Code 세션 내부에서 Auto 요청 시 CODEX_AUTO_FORCE=1 없으면 거부.
#>

. "$PSScriptRoot\common.ps1"

function Invoke-CodexIfEnabled {
    param(
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)][string]$DesignFile,
        [Parameter(Mandatory=$true)][string]$TaskDesc,
        [Parameter(Mandatory=$true)][bool]$AutoMode,
        [Parameter(Mandatory=$true)][string]$ProjectRoot
    )
    $script:CwcProvLine = ""

    if (-not $AutoMode) {
        Write-Host "[INFO] 수동 모드입니다. Codex 자동 호출을 건너뜁니다."
        Write-Host "       자동 호출을 원하면 -Auto 또는 CODEX_AUTO=1 을 지정하세요."
        Write-Host "       설계 문서 초안: $DesignFile"
        return 0
    }

    if ((Test-ClaudeSession) -and (-not (Test-Truthy $env:CODEX_AUTO_FORCE))) {
        Write-Host "[WARN] Claude Code 세션 내부에서 자동 호출을 거부합니다 (재귀 방지)." -ForegroundColor Yellow
        Write-Host "       우회하려면 CODEX_AUTO_FORCE=1 을 설정하세요."
        return 0
    }

    $codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
    if (-not $codexCmd) {
        $codexCmd = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue
    }
    if (-not $codexCmd) {
        Write-Host "[WARN] codex CLI를 찾을 수 없습니다." -ForegroundColor Yellow
        Write-Host "       수동으로 설계 문서를 작성하거나 codex를 설치하세요."
        return 1
    }

    # --- preflight: git 저장소 안에서만 자동 호출 (git 안전망 복원) ---
    $gitCmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    $insideRepo = $false
    if ($gitCmd) {
        & $gitCmd.Source -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
        $insideRepo = ($LASTEXITCODE -eq 0)
    }
    if (-not $insideRepo) {
        Write-Host "[WARN] git 저장소가 아닙니다(또는 git 미설치): $ProjectRoot" -ForegroundColor Yellow
        Write-Host "       codex 자동 설계는 git 저장소 안에서만 실행합니다 (안전망)."
        return 1
    }

    # --- 프로필 강제 (task-004): 실패 시 --auto 거부 ---
    $rp = Join-Path $ProjectRoot "runtime\render-prompt.py"
    $model = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("profile", "--phase", "design", "--cli", "codex", "--field", "model")
    if ($model.Code -ne 0) {
        Write-Host "[ERROR] 프로필 해석 실패(model) — --auto 를 중단합니다 (조용한 기본값 금지)." -ForegroundColor Red
        return $model.Code
    }
    $effort = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("profile", "--phase", "design", "--cli", "codex", "--field", "effort")
    if ($effort.Code -ne 0) {
        Write-Host "[ERROR] 프로필 해석 실패(effort) — --auto 를 중단합니다." -ForegroundColor Red
        return $effort.Code
    }

    # --- CLI 버전 preflight ---
    $verOut = (& $codexCmd.Source --version 2>&1 | Out-String).Trim()
    $ver = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("check-cli-version", "--phase", "design", "--cli", "codex", "--version-output", $verOut)
    if ($ver.Code -ne 0) {
        Write-Host "[ERROR] codex CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $verOut)" -ForegroundColor Red
        return $ver.Code
    }

    # --- 프롬프트 렌더 (SSOT: templates/prompts/design.md + schema.json) ---
    $prompt = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("render", "--phase", "design", "--task-id", $TaskId, "--design-file", $DesignFile, "--task-desc", $TaskDesc, "--project-root", $ProjectRoot)
    if ($prompt.Code -ne 0) {
        Write-Host "[ERROR] 프롬프트 렌더 실패 — --auto 를 중단합니다." -ForegroundColor Red
        return $prompt.Code
    }

    Write-Host "[INFO] Codex에게 설계 요청 중... (model=$($model.Value), effort=$($effort.Value), cli=$($ver.Value))"
    Write-Host ""
    # 제약된 샌드박스 + 명시적 모델/effort 강제. --skip-git-repo-check 금지.
    # CLI stdout을 함수 출력 스트림에 흘리면 return 값이 배열로 오염된다 →
    # Write-Host 로 콘솔에 명시 출력하고, 함수는 스칼라 rc만 반환한다.
    $null | & $codexCmd.Source exec --sandbox workspace-write -C $ProjectRoot `
        -m $model.Value -c "model_reasoning_effort=$($effort.Value)" $prompt.Value 2>&1 |
        ForEach-Object { Write-Host $_ }
    $rc = [int]$LASTEXITCODE
    Write-Host ""
    if ($rc -eq 0) {
        $today = Get-Date -Format 'yyyy-MM-dd'
        $script:CwcProvLine = "design=codex $($model.Value)/$($effort.Value) @codex $($ver.Value), $today (fallback=none)"
    }
    return $rc
}

# Invoke-CodexReview — Phase D 구현 리뷰용 codex 호출 (task-006). Bash invoke_codex_review 패리티.
#   반환 0: 호출 성공. 1: 가드/부재/preflight 실패. codex non-zero 는 그대로 전파.
#   재귀 가드가 막으면 리뷰 생성이 목적이므로 false success 를 내지 않고 NON-ZERO(1) 로 종료.
function Invoke-CodexReview {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][string]$Model,
        [Parameter(Mandatory=$true)][string]$Effort
    )
    if ((Test-ClaudeSession) -and (-not (Test-Truthy $env:CODEX_AUTO_FORCE))) {
        Write-Host "[WARN] 세션 내부에서 codex 자동 호출을 거부합니다 (재귀 방지). CODEX_AUTO_FORCE=1 로 우회." -ForegroundColor Yellow
        Write-Host "       리뷰를 생성하지 못했으므로 실패로 종료합니다."
        return 1
    }
    $codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
    if (-not $codexCmd) { $codexCmd = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue }
    if (-not $codexCmd) {
        Write-Host "[WARN] codex CLI를 찾을 수 없습니다. 리뷰를 생성할 수 없습니다." -ForegroundColor Yellow
        return 1
    }
    $gitCmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    $insideRepo = $false
    if ($gitCmd) {
        & $gitCmd.Source -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
        $insideRepo = ($LASTEXITCODE -eq 0)
    }
    if (-not $insideRepo) {
        Write-Host "[WARN] git 저장소가 아닙니다: $ProjectRoot (codex 리뷰는 git 저장소 안에서만)." -ForegroundColor Yellow
        return 1
    }

    Write-Host "[INFO] Codex 리뷰 요청 중... (model=$Model, effort=$Effort)"
    Write-Host ""
    $null | & $codexCmd.Source exec --sandbox workspace-write -C $ProjectRoot `
        -m $Model -c "model_reasoning_effort=$Effort" $Prompt 2>&1 |
        ForEach-Object { Write-Host $_ }
    $rc = [int]$LASTEXITCODE
    Write-Host ""
    return $rc
}
