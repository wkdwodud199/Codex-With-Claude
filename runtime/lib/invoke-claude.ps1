#Requires -Version 5.1
<#
.SYNOPSIS
    Claude CLI 호출 로직 (PowerShell, codex-design 과 대칭).

.DESCRIPTION
    Dot-source 전용. 내보내는 함수:
      Invoke-ClaudeIfEnabled -TaskId -DesignFile -ImplNotes -AutoMode -ProjectRoot
        - 반환 0  : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
        - 반환 1  : --auto 인데 CLI 부재 또는 호출 실패.

    D2 정책:
      - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 0 반환.
      - --auto 인데 claude CLI 부재 → NON-ZERO.
      - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.

    재귀 가드 (중요):
      이미 Claude Code 세션 안에서 `claude -p` 를 호출하면 중첩 세션이 돼
      토큰이 폭증할 수 있으므로 기본 정책은 거부.
      세션 감지는 CLAUDECODE(주) / CLAUDE_CODE_SESSION_ID 등으로 한다 (common.ps1 참조).
      CLAUDE_AUTO_FORCE=1 이 명시된 경우에만 중첩 호출 허용.

    프롬프트 구성 원칙:
      - design.md 내용을 프롬프트에 인라인하지 않는다 (컨텍스트 절약).
      - 경로만 전달하고 Claude 측에서 읽도록 한다.
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

    Write-Host "[INFO] Claude에게 구현 요청 중... ($($claudeCmd.Source))"
    Write-Host ""
    $prompt = @"
$TaskId 의 설계 문서를 읽고 구현을 시작해주세요.

설계 문서: $DesignFile
구현 노트: $ImplNotes
프로젝트 루트: $ProjectRoot

CLAUDE.md 규약:
  1. design.md를 먼저 읽으세요 (필수 섹션 / Status 확인).
  2. 구현 중 결정이 설계와 달라지면 implementation-notes.md에 기록하세요.
  3. 완료 후 kb/artifacts/$TaskId-summary.md 를 작성하고 python3 runtime/generate-status.py 를 실행하세요.
"@
    # CLI stdout을 함수 출력 스트림에 흘리면 return 값이 배열로 오염된다.
    # Write-Host로 콘솔에 명시 출력하고, 함수는 스칼라 rc만 반환한다.
    & $claudeCmd.Source -p $prompt 2>&1 | ForEach-Object { Write-Host $_ }
    $rc = [int]$LASTEXITCODE
    Write-Host ""
    return $rc
}
