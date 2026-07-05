#Requires -Version 5.1
<#
.SYNOPSIS
    Claude CLI 호출 로직 (PowerShell, codex-design 과 대칭).

.DESCRIPTION
    Dot-source 전용. 내보내는 함수:
      Invoke-ClaudeIfEnabled -TaskId -DesignFile -ImplNotes -AutoMode -ProjectRoot
        - 반환 0  : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
        - 반환 1  : --auto 인데 CLI 부재 / 버전 미달 / 라우팅 실패 / 호출 실패.
        - 반환 2  : 환경 오류 (python 부재, 프로필·프롬프트 IO/해석 오류).

    task-004 (bash invoke-claude.sh 와 동작 패리티 — 설계 주도 라우팅):
      - implement 의 model/effort 는 design.md 의 "실행 계획 (Execution Plan)" 이
        지정한다 (render-prompt.py route-implement).
      - 실행 계획 부재는 legacy(task-001~003)만 허용 — 프로필 기본값으로 라우팅하며
        [WARN] 로그 + provenance(route=default) 를 남긴다.
      - 항상 `claude -p --model <m> --effort <e>` 를 명시한다.
      - 호출 성공 시 $script:CwcProvLine 에 provenance 를 남긴다 (러너가 기록).

    D2 정책:
      - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 0 반환.
      - --auto 인데 claude CLI 부재 → NON-ZERO.
      - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.

    재귀 가드: 세션 내 `claude -p` 는 중첩 세션이 되므로 기본 거부
    (CLAUDE_AUTO_FORCE=1 로만 우회). 프롬프트는 design.md 를 인라인하지 않고
    경로만 전달한다 (templates/prompts/implement.md 가 단일 원천).
#>

. "$PSScriptRoot\common.ps1"

function Invoke-ClaudeIfEnabled {
    param(
        [Parameter(Mandatory=$true)][string]$TaskId,
        [Parameter(Mandatory=$true)][string]$DesignFile,
        [Parameter(Mandatory=$true)][string]$ImplNotes,
        [Parameter(Mandatory=$true)][bool]$AutoMode,
        [Parameter(Mandatory=$true)][string]$ProjectRoot
    )
    $script:CwcProvLine = ""

    if (-not $AutoMode) {
        Write-Host "[INFO] 수동 모드입니다. Claude 자동 호출을 건너뜁니다."
        Write-Host "       자동 호출을 원하면 -Auto 또는 CLAUDE_AUTO=1 을 지정하세요."
        return 0
    }

    if ((Test-ClaudeSession) -and (-not (Test-Truthy $env:CLAUDE_AUTO_FORCE))) {
        Write-Host "[WARN] Claude Code 세션 내부에서 자동 호출을 거부합니다 (재귀 방지)." -ForegroundColor Yellow
        Write-Host "       우회하려면 CLAUDE_AUTO_FORCE=1 을 설정하세요."
        return 0
    }

    $claudeCmd = Get-Command claude.cmd -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        $claudeCmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue
    }
    if (-not $claudeCmd) {
        Write-Host "[WARN] claude CLI를 찾을 수 없습니다." -ForegroundColor Yellow
        Write-Host "       수동으로 구현하거나 claude CLI를 설치하세요."
        return 1
    }

    # --- 설계 주도 라우팅 (실행 계획 → model/effort) ---
    $rp = Join-Path $ProjectRoot "runtime\render-prompt.py"
    $model = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("route-implement", "--design-file", $DesignFile, "--task-id", $TaskId, "--field", "model")
    if ($model.Code -ne 0) {
        Write-Host "[ERROR] implement 라우팅 실패(model) — --auto 를 중단합니다." -ForegroundColor Red
        return $model.Code
    }
    $effort = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("route-implement", "--design-file", $DesignFile, "--task-id", $TaskId, "--field", "effort")
    if ($effort.Code -ne 0) {
        Write-Host "[ERROR] implement 라우팅 실패(effort) — --auto 를 중단합니다." -ForegroundColor Red
        return $effort.Code
    }
    $route = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("route-implement", "--design-file", $DesignFile, "--task-id", $TaskId, "--field", "route")
    if ($route.Code -ne 0) {
        Write-Host "[ERROR] implement 라우팅 실패(route) — --auto 를 중단합니다." -ForegroundColor Red
        return $route.Code
    }
    if ($route.Value -eq "default") {
        Write-Host "[WARN] 실행 계획 없음(legacy) — 프로필 기본값으로 라우팅합니다: $($model.Value)/$($effort.Value)" -ForegroundColor Yellow
    }

    # --- CLI 버전 preflight ---
    $verOut = (& $claudeCmd.Source --version 2>&1 | Out-String).Trim()
    $ver = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("check-cli-version", "--phase", "implement", "--cli", "claude", "--version-output", $verOut)
    if ($ver.Code -ne 0) {
        Write-Host "[ERROR] claude CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $verOut)" -ForegroundColor Red
        return $ver.Code
    }

    # --- 프롬프트 렌더 (SSOT: templates/prompts/implement.md) ---
    $prompt = Invoke-RenderPrompt -RenderPrompt $rp -Arguments @("render", "--phase", "implement", "--task-id", $TaskId, "--design-file", $DesignFile, "--impl-notes", $ImplNotes, "--project-root", $ProjectRoot, "--model", $model.Value, "--effort", $effort.Value)
    if ($prompt.Code -ne 0) {
        Write-Host "[ERROR] 프롬프트 렌더 실패 — --auto 를 중단합니다." -ForegroundColor Red
        return $prompt.Code
    }

    Write-Host "[INFO] Claude에게 구현 요청 중... (model=$($model.Value), effort=$($effort.Value), route=$($route.Value))"
    Write-Host ""
    # CLI stdout 오염 방지 — Write-Host 로 출력, 함수는 스칼라 rc만 반환.
    & $claudeCmd.Source -p $prompt.Value --model $model.Value --effort $effort.Value 2>&1 |
        ForEach-Object { Write-Host $_ }
    $rc = [int]$LASTEXITCODE
    Write-Host ""
    if ($rc -eq 0) {
        $today = Get-Date -Format 'yyyy-MM-dd'
        $script:CwcProvLine = "implement=claude $($model.Value)/$($effort.Value) @claude $($ver.Value), $today (route=$($route.Value))"
    }
    return $rc
}
