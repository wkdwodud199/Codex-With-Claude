#Requires -Version 5.1
<#
.SYNOPSIS
    Codex에게 설계 문서 생성을 요청하는 래퍼 (Windows PowerShell 진입점)

.DESCRIPTION
    1. kb/tasks/<task-id>/ 디렉터리 생성
    2. 템플릿으로부터 design.md 초안 생성
    3. Codex에게 설계 작성을 요청 (codex.cmd CLI 사용)
    4. claude-implement와 동일한 수준으로 설계 완성 여부를 후검증

.EXAMPLE
    ./runtime/codex-design.ps1 task-002 "사용자 인증 모듈 설계"
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TaskId,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$TaskDesc
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$TaskDir = Join-Path $ProjectRoot "kb\tasks\$TaskId"
$DesignFile = Join-Path $TaskDir "design.md"
$Template = Join-Path $ProjectRoot "templates\design.md"

# =============================================================================
# 설계 문서 종합 검증 (claude-implement.ps1과 동일 로직)
# =============================================================================
function Test-DesignFile {
    param([string]$File)

    $errors = @()
    $content = Get-Content $File -Raw -Encoding UTF8
    $lines = Get-Content $File -Encoding UTF8

    # --- 1. 필수 섹션 존재 검사 ---
    $requiredSections = @(
        "목표 (Objective)",
        "범위 (Scope)",
        "제약 (Constraints)",
        "구현 단계 (Implementation Steps)",
        "파일/모듈 영향 (Affected Files/Modules)",
        "테스트 기준 (Test Criteria)",
        "오픈 이슈 (Open Issues)"
    )

    foreach ($section in $requiredSections) {
        if (-not $content.Contains($section)) {
            $errors += "[섹션 누락] $section"
        }
    }

    # --- 2. Status 검사 (ready 또는 done만 허용) ---
    $statusLine = $lines | Where-Object { $_ -match '^> Status:' } | Select-Object -First 1
    if ($statusLine) {
        $statusValue = ($statusLine -replace '^> Status:\s*', '').Trim()
        switch ($statusValue) {
            'ready'       { <# pass #> }
            'done'        { <# pass #> }
            'draft'       { $errors += "[상태 차단] Status: draft" }
            'blocked'     { $errors += "[상태 차단] Status: blocked" }
            'in-progress' { $errors += "[상태 차단] Status: in-progress" }
            default       { $errors += "[상태 오류] Status: '$statusValue'" }
        }
    } else {
        $errors += "[상태 누락] '> Status:' 필드가 없습니다."
    }

    # --- 3. 템플릿 placeholder 잔존 검사 ---
    $placeholders = @(
        "(이 작업이 달성하려는 것을 1-2문장으로 기술)",
        "(이 작업에 포함되는 것과 포함되지 않는 것을 명시)",
        "(기술적, 시간적, 또는 기타 제약 조건)",
        "(설계 시점에 해결되지 않은 질문이나 리스크)",
        "task-<NNN>",
        "(이 설계가 의존하는 입력 나열)",
        "(이 설계가 생성할 산출물 나열)",
        "(구현 완료 후 다음 단계 기술)"
    )

    foreach ($ph in $placeholders) {
        if ($content.Contains($ph)) {
            $errors += "[placeholder 잔존] '$ph'"
        }
    }

    # --- 4. 빈 표/빈 리스트 검사 ---
    if ($content -match '\|\s*\|\s*create / modify / delete\s*\|') {
        $errors += "[빈 내용] 파일/모듈 영향 테이블이 비어 있습니다."
    }

    foreach ($line in $lines) {
        if ($line -match '^\- \[ \]\s*$') {
            $errors += "[빈 내용] 빈 체크박스가 있습니다."
            break
        }
    }

    # --- 5. 필수 메타 필드 존재 및 빈 값 검사 ---
    foreach ($field in @("Inputs", "Outputs", "Next step")) {
        $fieldLine = $lines | Where-Object { $_ -match "^> ${field}:" } | Select-Object -First 1
        if ($fieldLine) {
            $val = ($fieldLine -replace "^> ${field}:\s*", '').Trim()
            if ([string]::IsNullOrEmpty($val) -or $val -eq "()") {
                $errors += "[빈 필드] ${field}"
            }
        } else {
            $errors += "[필드 누락] '> ${field}:'"
        }
    }

    # --- 결과 출력 ---
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "[FAIL] 설계 문서 검증 실패 ($($errors.Count)건):" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  - $err" -ForegroundColor Red
        }
        return $false
    }
    return $true
}

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
    [System.IO.File]::WriteAllText($DesignFile, $designContent, [System.Text.Encoding]::UTF8)
    Write-Host "[OK] 설계 문서 초안 생성: $DesignFile"
} else {
    Write-Host "[ERROR] 템플릿 파일 없음: $Template" -ForegroundColor Red
    exit 1
}

# --- Codex 호출 (Windows: codex.cmd 사용) ---
$codexCalled = $false
$codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
if (-not $codexCmd) {
    $codexCmd = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue
}

if ($codexCmd) {
    Write-Host "[INFO] Codex에게 설계 요청 중... ($($codexCmd.Source))"
    Write-Host ""
    $prompt = "다음 작업에 대한 설계 문서를 작성해주세요. " +
        "작업: $TaskDesc. " +
        "설계 문서 경로: $DesignFile. " +
        "참조할 기존 문서: $ProjectRoot\kb\concepts\. " +
        "중요 규칙: 템플릿의 모든 필수 섹션을 빠짐없이 채우세요. " +
        "모든 placeholder 안내문을 실제 내용으로 교체하세요. " +
        "완성 후 문서 상단의 Status를 ready로 변경하세요. " +
        "Inputs, Outputs, Next step 필드를 구체적으로 채우세요. " +
        "파일/모듈 영향 테이블과 테스트 기준 체크박스에 실제 항목을 기입하세요."
    $null | & $codexCmd.Source exec --full-auto --skip-git-repo-check -C $ProjectRoot $prompt
    Write-Host ""
    $codexCalled = $true
} else {
    Write-Host "[WARN] codex CLI를 찾을 수 없습니다." -ForegroundColor Yellow
    Write-Host "       수동으로 설계 문서를 작성하거나 codex를 설치하세요."
    Write-Host "       설계 문서 초안 위치: $DesignFile"
}

# --- 후검증 (claude-implement와 동일 수준) ---
Write-Host ""
Write-Host "--- 설계 완성 검증 ---"
if (Test-DesignFile -File $DesignFile) {
    Write-Host "[OK] 설계 문서가 완성 상태입니다." -ForegroundColor Green
    Write-Host ""
    Write-Host "--- 다음 단계 ---"
    Write-Host "1. 설계 내용을 최종 검토하세요."
    Write-Host "2. Claude에게 구현을 요청하세요:"
    Write-Host "   ./runtime/claude-implement.ps1 $TaskId"
} else {
    Write-Host ""
    if ($codexCalled) {
        Write-Host "[INFO] Codex가 설계를 생성했지만 완성 기준을 충족하지 않습니다."
    }
    Write-Host ""
    Write-Host "--- 보완 필요 ---"
    Write-Host "1. 설계 문서를 열어 누락된 부분을 채우세요."
    Write-Host "2. Status를 ready로 변경하세요."
    Write-Host "3. 모든 placeholder를 실제 내용으로 교체하세요."
    Write-Host "4. 완성 후: ./runtime/claude-implement.ps1 $TaskId"
    exit 1
}
