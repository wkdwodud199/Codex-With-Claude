#Requires -Version 5.1
<#
.SYNOPSIS
    Codex CLI 호출 로직 (PowerShell).

.DESCRIPTION
    Dot-source 전용. 내보내는 함수:
      Invoke-CodexIfEnabled -TaskId -DesignFile -TaskDesc -AutoMode -ProjectRoot
        - AutoMode    : $true 면 자동 호출 시도, 아니면 안내만 출력.
        - 반환 0      : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
        - 반환 1      : --auto 인데 CLI 부재 또는 호출 실패.

    D2 정책:
      - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 0 반환.
      - --auto 인데 codex CLI 부재 → NON-ZERO.
      - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.

    Claude Code 세션 내부에서 Auto 요청 시 CODEX_AUTO_FORCE=1 없으면 거부.
    세션 감지는 CLAUDECODE(주) / CLAUDE_CODE_SESSION_ID 등으로 한다 (common.ps1 참조).
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
    # --skip-git-repo-check 제거에 따라, codex가 거부하기 전에 먼저 확인한다.
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

    Write-Host "[INFO] Codex에게 설계 요청 중... ($($codexCmd.Source))"
    Write-Host ""
    $prompt = @"
다음 작업에 대한 설계 문서를 작성해주세요.
작업: $TaskDesc
설계 문서 경로: $DesignFile
참조할 기존 문서: $ProjectRoot\kb\concepts\

중요 규칙:
  - 템플릿의 모든 필수 섹션(목표, 범위, 제약, 구현 단계, 파일/모듈 영향, 테스트 기준, 오픈 이슈)을 빠짐없이 채우세요.
  - 모든 placeholder 안내문을 실제 내용으로 교체하세요.
  - 완성 후 문서 상단의 Status를 ready로 변경하세요.
  - Inputs, Outputs, Next step 필드를 구체적으로 채우세요.
  - 파일/모듈 영향 테이블과 테스트 기준 체크박스에 실제 항목을 기입하세요.
"@
    # codex 0.137: 제약된 샌드박스(workspace-write)로 비대화형 실행.
    # 설계 생성기는 kb/tasks/<id>/ 아래 한 파일만 쓰면 되므로 full-auto 불필요.
    # --skip-git-repo-check 제거로 codex의 git 안전망을 복원한다.
    # CLI stdout을 함수 출력 스트림에 흘리면 return 값이 배열로 오염된다.
    # Write-Host로 콘솔에 명시 출력하고, 함수는 스칼라 rc만 반환한다.
    $null | & $codexCmd.Source exec --sandbox workspace-write -C $ProjectRoot $prompt 2>&1 |
        ForEach-Object { Write-Host $_ }
    $rc = [int]$LASTEXITCODE
    Write-Host ""
    return $rc
}
