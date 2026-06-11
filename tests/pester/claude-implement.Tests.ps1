#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 5 tests for runtime/claude-implement.ps1 — bats(claude-implement.bats) 미러.

.DESCRIPTION
    bats 시나리오와 동일한 흐름을 PowerShell에서 검증한다:
      1. 인자 없음 (Mandatory 파라미터 누락)   -> NON-ZERO
      2. design.md 없음                         -> exit 1 + 안내
      3. draft/placeholder design.md            -> exit 1 (validator 거부)
      4. good design (기본 수동 모드)           -> exit 0 + impl-notes 생성 + 수동 모드 배너
      5. good design + --auto + 세션 안          -> exit 0 + 재귀 방지 배너
      6. good design + --auto + claude CLI 부재  -> NON-ZERO + no-CLI 경고 (D2)

    참고: 로컬에 Pester가 없어도 무방하다. CI(smoke-powershell job)에서
    Invoke-Pester 로 실행하도록 배선하는 것을 권장한다 (notes 참조).

    pwsh를 별도 프로세스로 실행해 exit code를 정확히 관측한다.
#>

BeforeAll {
    $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    # pwsh(우선) 또는 powershell 실행 파일을 찾는다. (PS 5.1 호환 — ?. 미사용)
    $script:Shell = $null
    $shellCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $shellCmd) { $shellCmd = Get-Command powershell -ErrorAction SilentlyContinue }
    if ($shellCmd) { $script:Shell = $shellCmd.Source }

    function New-Workspace {
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("cwc-impl-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "runtime") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "templates") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "kb\tasks") -Force | Out-Null
        Copy-Item (Join-Path $script:Repo "runtime\validator") (Join-Path $work "runtime\") -Recurse
        Copy-Item (Join-Path $script:Repo "runtime\lib")       (Join-Path $work "runtime\") -Recurse
        Copy-Item (Join-Path $script:Repo "runtime\claude-implement.ps1") (Join-Path $work "runtime\")
        Copy-Item (Join-Path $script:Repo "runtime\codex-design.ps1")     (Join-Path $work "runtime\")
        Copy-Item (Join-Path $script:Repo "templates\*") (Join-Path $work "templates\")
        # git preflight(D3) 대비 — 작업 디렉터리를 git 저장소로 만든다.
        & git init -q $work 2>$null | Out-Null
        return $work
    }

    # 스크립트를 별도 셸 프로세스로 실행하고 exit code + 출력을 돌려준다.
    # extraEnv: 호출 동안만 적용할 환경변수 해시테이블.
    function Invoke-Script {
        param(
            [string]$ScriptPath,
            [string[]]$ScriptArgs = @(),
            [hashtable]$ExtraEnv = @{}
        )
        # 세션 변수를 깨끗이 제거 (is_claude_session 이 검사하는 전부).
        $clear = @("CLAUDE_CODE_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDECODE",
                   "CLAUDE_CODE", "CLAUDE_AUTO", "CLAUDE_AUTO_FORCE")
        $saved = @{}
        foreach ($k in $clear) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $null) }
        $savedExtra = @{}
        foreach ($k in $ExtraEnv.Keys) { $savedExtra[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $ExtraEnv[$k]) }
        try {
            $argList = @("-NoProfile", "-NonInteractive", "-File", $ScriptPath) + $ScriptArgs
            $out = & $script:Shell @argList 2>&1 | Out-String
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
        }
        finally {
            foreach ($k in $ExtraEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedExtra[$k]) }
            foreach ($k in $clear) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
        }
    }
}

Describe "claude-implement.ps1" -Skip:([string]::IsNullOrEmpty($script:Shell)) {

    BeforeEach {
        $script:Work = New-Workspace
        $script:ScriptPath = Join-Path $script:Work "runtime\claude-implement.ps1"
        $script:GoodFixture = Join-Path $script:Repo "tests\validator\fixtures\good.md"
    }

    AfterEach {
        if ($script:Work -and (Test-Path $script:Work)) {
            Remove-Item $script:Work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "no args (Mandatory TaskId missing) -> NON-ZERO" {
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @()
        $r.ExitCode | Should -Not -Be 0
    }

    It "missing design.md -> exit 1 with hint" {
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-missing")
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "설계 문서가 없습니다"
        $r.Output | Should -Match "codex-design.ps1"
    }

    It "draft design -> validator rejects (exit 1)" {
        $taskDir = Join-Path $script:Work "kb\tasks\task-x"
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
        $tpl = Get-Content (Join-Path $script:Work "templates\design.md") -Raw
        ($tpl -replace 'task-<NNN>', 'task-x') | Set-Content (Join-Path $taskDir "design.md") -Encoding UTF8
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-x")
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "FAIL"
    }

    It "good design (default manual) -> exit 0 + impl-notes + manual banner" {
        $taskDir = Join-Path $script:Work "kb\tasks\task-y"
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
        Copy-Item $script:GoodFixture (Join-Path $taskDir "design.md")
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-y")
        $r.ExitCode | Should -Be 0
        (Test-Path (Join-Path $taskDir "implementation-notes.md")) | Should -BeTrue
        $r.Output | Should -Match "수동 모드"
        $r.Output | Should -Match "구현 준비 완료"
    }

    It "good design + -Auto in Claude session -> recursion guard (exit 0)" {
        $taskDir = Join-Path $script:Work "kb\tasks\task-y2"
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
        Copy-Item $script:GoodFixture (Join-Path $taskDir "design.md")
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-y2", "-Auto") `
            -ExtraEnv @{ CLAUDE_CODE_SESSION_ID = "1" }
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match "재귀 방지"
    }

    It "good design + -Auto, no claude CLI -> warn, NON-ZERO (D2)" {
        $taskDir = Join-Path $script:Work "kb\tasks\task-y3"
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
        Copy-Item $script:GoodFixture (Join-Path $taskDir "design.md")
        # claude 미설치를 보장하기 위해 PATH를 시스템 디렉터리로 제한한다.
        $restricted = if ($IsWindows -or $env:OS -match "Windows") {
            "$env:SystemRoot\System32;$env:SystemRoot"
        } else { "/usr/bin:/bin" }
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-y3", "-Auto") `
            -ExtraEnv @{ PATH = $restricted }
        # --auto 인데 claude CLI 부재 → 요청한 자동 작업 실패 → NON-ZERO.
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match "claude CLI를 찾을 수 없습니다"
    }
}
