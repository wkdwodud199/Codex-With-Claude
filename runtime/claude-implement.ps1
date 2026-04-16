#Requires -Version 5.1
<#
.SYNOPSIS
    Claude에게 설계 기반 구현을 시작하도록 안내하는 래퍼 (Windows PowerShell 진입점)

.DESCRIPTION
    1. design.md 존재 여부 확인
    2. 필수 섹션 검증
    3. placeholder/draft 상태 차단
    4. 필수 메타 필드 존재 및 내용 검증
    5. 검증 통과 시 Claude에게 구현 컨텍스트 제공

.EXAMPLE
    ./runtime/claude-implement.ps1 task-001
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TaskId
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$TaskDir = Join-Path $ProjectRoot "kb\tasks\$TaskId"
$DesignFile = Join-Path $TaskDir "design.md"
$ImplNotes = Join-Path $TaskDir "implementation-notes.md"
$ImplTemplate = Join-Path $ProjectRoot "templates\implementation-notes.md"

# =============================================================================
# 설계 문서 종합 검증 (codex-design.ps1과 동일 로직)
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
        Write-Host ""
        Write-Host "설계 문서를 보완한 후 다시 실행하세요."
        return $false
    }
    return $true
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
if (-not (Test-DesignFile -File $DesignFile)) {
    exit 1
}

Write-Host "[OK] 설계 문서 검증 통과 (섹션, 상태, placeholder, 내용)" -ForegroundColor Green

# --- implementation-notes.md 초안 생성 ---
if (-not (Test-Path $ImplNotes)) {
    if (Test-Path $ImplTemplate) {
        $templateContent = Get-Content $ImplTemplate -Raw -Encoding UTF8
        $notesContent = $templateContent -replace 'task-<NNN>', $TaskId
        [System.IO.File]::WriteAllText($ImplNotes, $notesContent, [System.Text.Encoding]::UTF8)
        Write-Host "[OK] 구현 노트 초안 생성: $ImplNotes"
    } else {
        "# 구현 노트 - $TaskId" | Out-File -FilePath $ImplNotes -Encoding UTF8
        Write-Host "[WARN] 구현 노트 템플릿 없음." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] 구현 노트 이미 존재: $ImplNotes"
}

# --- Claude 구현 안내 출력 ---
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
