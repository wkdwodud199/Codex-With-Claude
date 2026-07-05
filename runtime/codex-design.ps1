#Requires -Version 5.1
<#
.SYNOPSIS
    Codex에게 설계 문서 생성을 요청하는 래퍼 (Windows PowerShell 진입점)

.DESCRIPTION
    1. kb/tasks/<task-id>/ 디렉터리 생성
    2. 템플릿으로부터 design.md 초안 생성
    3. (옵션) Codex에게 설계 작성을 요청 — -Auto 또는 CODEX_AUTO=1 일 때만
    4. Python 검증기로 설계 완성 여부를 후검증

.EXAMPLE
    ./runtime/codex-design.ps1 task-002 "사용자 인증 모듈 설계"
    ./runtime/codex-design.ps1 task-002 "사용자 인증 모듈 설계" -Auto
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TaskId,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$TaskDesc,

    [switch]$Auto
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

. "$ScriptDir\lib\common.ps1"
. "$ScriptDir\lib\invoke-codex.ps1"

$TaskDir = Join-Path $ProjectRoot "kb\tasks\$TaskId"
$DesignFile = Join-Path $TaskDir "design.md"
$Template = Join-Path $ProjectRoot "templates\design.md"
$ValidatorCli = Join-Path $ProjectRoot "runtime\validator\cli.py"

$AutoMode = $Auto.IsPresent -or (Test-Truthy $env:CODEX_AUTO)

# --- 디렉터리 생성 ---
if (Test-Path $TaskDir) {
    Write-Host "[INFO] 디렉터리 이미 존재: $TaskDir"
} else {
    New-Item -ItemType Directory -Path $TaskDir -Force | Out-Null
    Write-Host "[OK] 디렉터리 생성: $TaskDir"
}

# --- 설계 문서 초안 생성 ---
if (Test-Path $DesignFile) {
    Write-Host "[WARN] 설계 문서 이미 존재: $DesignFile" -ForegroundColor Yellow
    Write-Host "       덮어쓰려면 기존 파일을 먼저 삭제하세요."
    exit 1
}

if (Test-Path $Template) {
    $templateContent = Get-Content $Template -Raw -Encoding UTF8
    $designContent = $templateContent -replace 'task-<NNN>', $TaskId
    [System.IO.File]::WriteAllText($DesignFile, $designContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[OK] 설계 문서 초안 생성: $DesignFile"
} else {
    Write-Host "[ERROR] 템플릿 파일 없음: $Template" -ForegroundColor Red
    exit 1
}

# --- manifest 초안 생성 (Phase A: 기본 로드 세트 최소화) ---
$ManifestFile = Join-Path $TaskDir "manifest.md"
$ManifestTemplate = Join-Path $ProjectRoot "templates\manifest.md"
if (Test-Path $ManifestFile) {
    Write-Host "[INFO] manifest 이미 존재: $ManifestFile"
} elseif (Test-Path $ManifestTemplate) {
    $manifestContent = (Get-Content $ManifestTemplate -Raw -Encoding UTF8) -replace 'task-<NNN>', $TaskId
    [System.IO.File]::WriteAllText($ManifestFile, $manifestContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[OK] manifest 초안 생성: $ManifestFile"
} else {
    Write-Host "[WARN] manifest 템플릿 없음: $ManifestTemplate (건너뜀)" -ForegroundColor Yellow
}

# --- Codex 호출 (라이브러리 위임) ---
# D2: --auto 인데 codex CLI 부재/호출 실패면 NON-ZERO 를 반환한다.
#     그 코드를 기억해 두었다가 최종 종료에 반영한다.
$invokeRc = [int](Invoke-CodexIfEnabled -TaskId $TaskId -DesignFile $DesignFile -TaskDesc $TaskDesc `
    -AutoMode $AutoMode -ProjectRoot $ProjectRoot)

# --- 후검증 ---
# Invoke-Validator / cli.py 종료 코드:
#   0  = 통과
#   1  = 설계 검증 실패 (보완 필요)
#   2+ = 환경 오류 (Python 미설치 / IO / 디코딩 오류 등)
Write-Host ""
Write-Host "--- 설계 완성 검증 ---"
$code = [int](Invoke-Validator -File $DesignFile -ValidatorCli $ValidatorCli)
if ($code -ge 2) {
    Write-Host ""
    Write-Host "환경 오류 (Python 미설치/IO 오류 등). 설계 검증을 수행할 수 없습니다." -ForegroundColor Red
    exit $code
} elseif ($code -eq 0) {
    # provenance (task-004): --auto 호출 성공 + 검증 통과 시에만 manifest 에 기록.
    if ($invokeRc -eq 0 -and $script:CwcProvLine) {
        if (Test-Path $ManifestFile) {
            [System.IO.File]::AppendAllText($ManifestFile,
                "- **generated_by**: $($script:CwcProvLine)`n", [System.Text.UTF8Encoding]::new($false))
            Write-Host "[OK] provenance 기록: $ManifestFile"
        } else {
            Write-Host "[WARN] manifest 없음 — provenance 기록 건너뜀: $ManifestFile" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "--- 다음 단계 ---"
    Write-Host "1. 설계 내용을 최종 검토하세요."
    Write-Host "2. Claude에게 구현을 요청하세요:"
    Write-Host "   ./runtime/claude-implement.ps1 $TaskId"
    # 검증은 통과했지만 --auto codex 호출이 실패했다면 그 실패를 전파한다 (D2).
    if ($invokeRc -ne 0) {
        Write-Host ""
        Write-Host "[WARN] 단, codex 자동 호출이 실패했습니다 (exit $invokeRc)." -ForegroundColor Yellow
        exit $invokeRc
    }
} else {
    Write-Host ""
    Write-Host "--- 보완 필요 ---"
    Write-Host "1. 설계 문서를 열어 누락된 부분을 채우세요."
    Write-Host "2. Status를 ready로 변경하세요."
    Write-Host "3. 모든 placeholder를 실제 내용으로 교체하세요."
    Write-Host "4. 완성 후: ./runtime/claude-implement.ps1 $TaskId"
    exit 1
}
