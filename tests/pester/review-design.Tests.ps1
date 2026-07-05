#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 5 tests for runtime/review-design.ps1 — bats(review-design.bats) 미러 (task-005).

.DESCRIPTION
    bats 시나리오와 동일한 흐름을 검증한다:
      1. 인자 없음 (Mandatory TaskId 누락)      -> NON-ZERO
      2. design.md 없음                          -> exit 1
      3. draft/invalid design.md                 -> validator 실패, claude 미호출, exit 1
      4. 세션 내부 (FORCE 없음)                   -> 재귀 가드, exit 0, review 파일 없음
      5. good + fable 스텁                        -> exit 0, review 파일 + 강제 플래그 + provenance(fallback=false) + design.md 불변
      6. fallback(opus) 스텁                      -> exit 0, provenance fallback=true
      7. unknown model JSON                       -> exit 1, review 파일/ provenance 없음
      8. CLI 버전 미달                            -> preflight 실패
      9. 프로필 부재                              -> exit 1 (조용한 기본값 금지)
#>

BeforeAll {
    $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $script:Shell = $null
    $shellCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $shellCmd) { $shellCmd = Get-Command powershell -ErrorAction SilentlyContinue }
    if ($shellCmd) { $script:Shell = $shellCmd.Source }
    $script:IsWin = ($IsWindows -or ($env:OS -match "Windows"))

    function New-Workspace {
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("cwc-rv-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "runtime\config") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "kb\tasks") -Force | Out-Null
        Copy-Item (Join-Path $script:Repo "runtime\validator") (Join-Path $work "runtime\") -Recurse
        Copy-Item (Join-Path $script:Repo "runtime\lib")       (Join-Path $work "runtime\") -Recurse
        Copy-Item (Join-Path $script:Repo "runtime\review-design.ps1") (Join-Path $work "runtime\")
        Copy-Item (Join-Path $script:Repo "runtime\render-prompt.py")  (Join-Path $work "runtime\")
        Copy-Item (Join-Path $script:Repo "runtime\config\model-profiles.json") (Join-Path $work "runtime\config\")
        Copy-Item (Join-Path $script:Repo "templates") (Join-Path $work "templates") -Recurse
        # task-t: good design + manifest
        $td = Join-Path $work "kb\tasks\task-t"
        New-Item -ItemType Directory -Path $td -Force | Out-Null
        Copy-Item (Join-Path $script:Repo "tests\validator\fixtures\good.md") (Join-Path $td "design.md")
        $tpl = Get-Content (Join-Path $work "templates\manifest.md") -Raw
        [System.IO.File]::WriteAllText((Join-Path $td "manifest.md"),
            ($tpl -replace 'task-<NNN>', 'task-t'), [System.Text.UTF8Encoding]::new($false))
        return $work
    }

    # claude 스텁: --version 응답 + -p 호출 시 지정 JSON 을 stdout 으로. (JSON 은 ASCII 로 유지)
    function Install-ClaudeStub {
        param([string]$Work, [string]$Json, [string]$Version = "2.99.0", [string]$ArgsLog = "")
        $binDir = Join-Path $Work "bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        if ($script:IsWin) {
            $lines = @("@echo off", "if `"%~1`"==`"--version`" ( echo $Version & exit /b 0 )")
            if ($ArgsLog) { $lines += "echo %* >> `"$ArgsLog`"" }
            $lines += "echo $Json"
            $lines += "exit /b 0"
            Set-Content -Path (Join-Path $binDir "claude.cmd") -Value ($lines -join "`r`n") -Encoding ASCII
        } else {
            $lines = @('#!/usr/bin/env bash', ('if [ "${1:-}" = "--version" ]; then echo "' + $Version + '"; exit 0; fi'))
            if ($ArgsLog) { $lines += ('printf ''%s\n'' "$*" >> "' + $ArgsLog + '"') }
            $lines += ("echo '" + $Json + "'")
            $lines += 'exit 0'
            Set-Content -Path (Join-Path $binDir "claude") -Value ($lines -join "`n") -Encoding ASCII
            & chmod +x (Join-Path $binDir "claude") 2>$null | Out-Null
        }
        return $binDir
    }

    function Get-SystemPath {
        if ($script:IsWin) { return "$env:SystemRoot\System32;$env:SystemRoot" }
        return "/usr/bin:/bin"
    }

    function Invoke-Script {
        param([string]$ScriptPath, [string[]]$ScriptArgs = @(), [hashtable]$ExtraEnv = @{})
        $clear = @("CLAUDE_CODE_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDECODE", "CLAUDE_CODE", "CLAUDE_AUTO_FORCE")
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

Describe "review-design.ps1" -Skip:([string]::IsNullOrEmpty($script:Shell)) {

    BeforeEach {
        $script:Work = New-Workspace
        $script:ScriptPath = Join-Path $script:Work "runtime\review-design.ps1"
        $script:SysPath = Get-SystemPath
        $script:TaskDir = Join-Path $script:Work "kb\tasks\task-t"
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

    It "missing design.md -> exit 1" {
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-none") -ExtraEnv @{ PATH = $script:SysPath }
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "설계 문서가 없습니다"
    }

    It "draft design -> validator fails, claude not called, exit 1" {
        $tx = Join-Path $script:Work "kb\tasks\task-x"
        New-Item -ItemType Directory -Path $tx -Force | Out-Null
        $tpl = Get-Content (Join-Path $script:Work "templates\design.md") -Raw
        [System.IO.File]::WriteAllText((Join-Path $tx "design.md"), ($tpl -replace 'task-<NNN>', 'task-x'), [System.Text.UTF8Encoding]::new($false))
        $mtpl = Get-Content (Join-Path $script:Work "templates\manifest.md") -Raw
        [System.IO.File]::WriteAllText((Join-Path $tx "manifest.md"), ($mtpl -replace 'task-<NNN>', 'task-x'), [System.Text.UTF8Encoding]::new($false))
        $argsLog = Join-Path $script:Work "cargs.log"
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"x","model":"claude-fable-5"}' -ArgsLog $argsLog
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-x") -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        (Test-Path (Join-Path $tx "design-review.md")) | Should -BeFalse
        (Test-Path $argsLog) | Should -BeFalse
    }

    It "inside Claude session -> recursion guard, exit 0, no review file" {
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"x","model":"claude-fable-5"}'
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-t") -ExtraEnv @{ PATH = $pathWithStub; CLAUDE_CODE_SESSION = "1" }
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match "재귀 방지"
        (Test-Path (Join-Path $script:TaskDir "design-review.md")) | Should -BeFalse
    }

    It "good design + fable stub -> review file + pinned flags + provenance(false) + design unchanged" {
        $argsLog = Join-Path $script:Work "cargs.log"
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"review body","model":"claude-fable-5"}' -ArgsLog $argsLog
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $before = (Get-FileHash -Algorithm SHA256 (Join-Path $script:TaskDir "design.md")).Hash
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-t") -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Be 0
        (Test-Path (Join-Path $script:TaskDir "design-review.md")) | Should -BeTrue
        $stubArgs = Get-Content $argsLog -Raw
        $stubArgs | Should -Match "--model claude-fable-5"
        $stubArgs | Should -Match "--effort max"
        $stubArgs | Should -Match "--fallback-model claude-opus-4-8"
        $stubArgs | Should -Match "--output-format json"
        (Get-Content (Join-Path $script:TaskDir "manifest.md") -Raw) | Should -Match "cross_reviewed_by.*fallback=false"
        $after = (Get-FileHash -Algorithm SHA256 (Join-Path $script:TaskDir "design.md")).Hash
        $after | Should -Be $before
    }

    It "fallback (opus) stub -> exit 0, provenance fallback=true" {
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"review","model":"claude-opus-4-8"}'
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-t") -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Be 0
        (Get-Content (Join-Path $script:TaskDir "manifest.md") -Raw) | Should -Match "cross_reviewed_by.*fallback=true"
        $r.Output | Should -Match "fallback 발동"
    }

    It "unknown model JSON -> exit 1, no review file, no provenance" {
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"x","model":"claude-sonnet-5"}'
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-t") -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        (Test-Path (Join-Path $script:TaskDir "design-review.md")) | Should -BeFalse
        (Get-Content (Join-Path $script:TaskDir "manifest.md") -Raw) | Should -Not -Match "cross_reviewed_by"
    }

    It "CLI version below minimum -> preflight fail" {
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"x","model":"claude-fable-5"}' -Version "0.1.0"
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-t") -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match "버전"
    }

    It "profile missing -> exit 1 (no silent default)" {
        $binDir = Install-ClaudeStub -Work $script:Work -Json '{"result":"x","model":"claude-fable-5"}'
        Remove-Item (Join-Path $script:Work "runtime\config\model-profiles.json") -Force
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-t") -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match "프로필"
    }
}
