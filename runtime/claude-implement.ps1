#Requires -Version 5.1
<#
.SYNOPSIS
    Claude에게 설계 기반 구현을 시작하도록 안내하는 래퍼 (Windows PowerShell 진입점)

.DESCRIPTION
    1. design.md 존재 여부 확인
    2. Python 검증기 (runtime/validator/cli.py) 호출
    3. 검증 통과 시 implementation-notes.md 초안 생성
    4. (옵션) Claude CLI에 구현 요청 — -Auto 또는 CLAUDE_AUTO=1 일 때만
    5. 구현 안내 출력

.EXAMPLE
    ./runtime/claude-implement.ps1 task-001
    ./runtime/claude-implement.ps1 task-001 -Auto
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TaskId,

    [switch]$Auto,
    [switch]$Done
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

. "$ScriptDir\lib\common.ps1"
. "$ScriptDir\lib\invoke-claude.ps1"

$TaskDir = Join-Path $ProjectRoot "kb\tasks\$TaskId"
$DesignFile = Join-Path $TaskDir "design.md"
$ImplNotes = Join-Path $TaskDir "implementation-notes.md"
$ImplTemplate = Join-Path $ProjectRoot "templates\implementation-notes.md"
$ValidatorCli = Join-Path $ProjectRoot "runtime\validator\cli.py"

$AutoMode = $Auto.IsPresent -or (Test-Truthy $env:CLAUDE_AUTO)

# --- -Done: 완료 검증 모드 (구현 후 산출물 계약 확인; done-gate) ---
if ($Done.IsPresent) {
    $py = Resolve-Python
    if (-not $py) {
        Write-Host "[ERROR] Python 3 을 찾을 수 없습니다." -ForegroundColor Red
        Write-Host "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        exit 2
    }
    $exe = $py[0]
    $prefix = if ($py.Count -gt 1) { $py[1..($py.Count - 1)] } else { @() }
    & $exe @prefix $ValidatorCli "--check-done" $TaskId
    exit $LASTEXITCODE
}

# --- design.md 존재 확인 ---
if (-not (Test-Path $DesignFile)) {
    Write-Host "[ERROR] 설계 문서가 없습니다: $DesignFile" -ForegroundColor Red
    Write-Host "        먼저 Codex에게 설계를 요청하세요:"
    Write-Host "        ./runtime/codex-design.ps1 $TaskId '<작업 설명>'"
    exit 1
}

Write-Host "[OK] 설계 문서 확인: $DesignFile"

# --- 종합 검증 ---
# Invoke-Validator / cli.py 종료 코드:
#   0  = 통과
#   1  = 설계 검증 실패 (보완 필요)
#   2+ = 환경 오류 (Python 미설치 / IO / 디코딩 오류 등)
$code = [int](Invoke-Validator -File $DesignFile -ValidatorCli $ValidatorCli)
if ($code -eq 1) {
    Write-Host ""
    Write-Host "설계 문서 검증 실패. 구현을 시작하지 않습니다 (CLAUDE.md 규약에 따름)." -ForegroundColor Red
    exit 1
} elseif ($code -ge 2) {
    Write-Host ""
    Write-Host "환경 오류 (Python 미설치/IO 오류 등). 검증을 수행할 수 없어 구현을 시작하지 않습니다." -ForegroundColor Red
    exit $code
}

# --- implementation-notes.md 초안 생성 ---
if (-not (Test-Path $ImplNotes)) {
    if (Test-Path $ImplTemplate) {
        $templateContent = Get-Content $ImplTemplate -Raw -Encoding UTF8
        $notesContent = $templateContent -replace 'task-<NNN>', $TaskId
        [System.IO.File]::WriteAllText($ImplNotes, $notesContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] 구현 노트 초안 생성: $ImplNotes"
    } else {
        [System.IO.File]::WriteAllText($ImplNotes, "# 구현 노트 - $TaskId`n", [System.Text.UTF8Encoding]::new($false))
        Write-Host "[WARN] 구현 노트 템플릿 없음." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] 구현 노트 이미 존재: $ImplNotes"
}

# --- Claude 호출 (라이브러리 위임, 수동이 기본) ---
# D2: --auto 인데 CLI 부재/호출 실패면 NON-ZERO 를 반환한다. 그 코드를 기억해
#     두었다가 러너 종료에 반영한다. 수동/재귀가드 스킵은 0 이므로 정상 종료.
Write-Host ""
$invokeRc = [int](Invoke-ClaudeIfEnabled -TaskId $TaskId -DesignFile $DesignFile -ImplNotes $ImplNotes `
    -AutoMode $AutoMode -ProjectRoot $ProjectRoot)

# provenance (task-004): 자동 호출이 실제 성공했을 때만 manifest 에 기록.
$ManifestFile = Join-Path $TaskDir "manifest.md"
if ($invokeRc -eq 0 -and $script:CwcProvLine) {
    if (Test-Path $ManifestFile) {
        [System.IO.File]::AppendAllText($ManifestFile,
            "- **generated_by**: $($script:CwcProvLine)`n", [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] provenance 기록: $ManifestFile"
    } else {
        Write-Host "[WARN] manifest 없음 — provenance 기록 건너뜀: $ManifestFile" -ForegroundColor Yellow
    }
}

# --- 구현 안내 출력 ---
Write-Host ""
Write-Host "============================================"
Write-Host " Claude 구현 준비 완료: $TaskId"
Write-Host "============================================"
Write-Host ""
Write-Host "Claude에게 다음과 같이 요청하세요:"
Write-Host ""
Write-Host "  $TaskId 의 설계 문서를 읽고 구현을 시작해주세요."
Write-Host "  설계 문서: $DesignFile"
Write-Host "  구현 노트: $ImplNotes"
Write-Host ""
Write-Host "Claude는 CLAUDE.md 규약에 따라:"
Write-Host "  1. design.md를 먼저 읽습니다."
Write-Host "  2. 구현 중 변경이 생기면 implementation-notes.md에 기록합니다."
Write-Host "  3. 완료 후 kb/artifacts/$TaskId-summary.md를 생성합니다."
Write-Host "  4. kb/index/status.md를 갱신합니다."

# D2: 자동 호출 실패 시 러너도 실패로 종료.
exit $invokeRc
