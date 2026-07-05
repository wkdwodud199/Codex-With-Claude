#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 5 tests for runtime/codex-design.ps1 — bats(codex-design.bats) 미러.

.DESCRIPTION
    bats 시나리오와 동일한 흐름을 PowerShell에서 검증한다:
      1. 인자 없음 (Mandatory 파라미터 누락)        -> NON-ZERO
      2. codex 부재 + 원시 템플릿 (수동 모드)        -> exit 1 (후검증 실패)
      3. 기존 design.md 존재                          -> exit 1 (덮어쓰기 가드)
      4. --auto + codex 스텁(exit 0) + 미완성 초안    -> 스텁 호출 후 후검증 실패 (exit 1)
      5. 기본(no --auto) + codex 스텁                 -> 스텁 스킵, 수동 모드 배너, exit 1
      6. 새 task 생성                                  -> manifest.md 자동 생성 (Phase A)
      7. --auto + 유효 design + codex 비정상 종료      -> 실패 전파 (D2)

    참고: 로컬에 Pester가 없어도 무방하다. CI(smoke-powershell job)에서
    Invoke-Pester 로 실행하도록 배선하는 것을 권장한다 (notes 참조).
#>

BeforeAll {
    $script:Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    # pwsh(우선) 또는 powershell 실행 파일을 찾는다. (PS 5.1 호환 — ?. 미사용)
    $script:Shell = $null
    $shellCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $shellCmd) { $shellCmd = Get-Command powershell -ErrorAction SilentlyContinue }
    if ($shellCmd) { $script:Shell = $shellCmd.Source }
    $script:IsWin = ($IsWindows -or ($env:OS -match "Windows"))

    function New-Workspace {
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("cwc-codex-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "runtime") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "templates") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $work "kb\tasks") -Force | Out-Null
        Copy-Item (Join-Path $script:Repo "runtime\validator") (Join-Path $work "runtime\") -Recurse
        Copy-Item (Join-Path $script:Repo "runtime\lib")       (Join-Path $work "runtime\") -Recurse
        Copy-Item (Join-Path $script:Repo "runtime\claude-implement.ps1") (Join-Path $work "runtime\")
        Copy-Item (Join-Path $script:Repo "runtime\codex-design.ps1")     (Join-Path $work "runtime\")
        Copy-Item (Join-Path $script:Repo "runtime\render-prompt.py")     (Join-Path $work "runtime\")
        New-Item -ItemType Directory -Path (Join-Path $work "runtime\config") -Force | Out-Null
        Copy-Item (Join-Path $script:Repo "runtime\config\model-profiles.json") (Join-Path $work "runtime\config\")
        # templates/prompts/ 하위 디렉터리 포함 복사 (task-004)
        Copy-Item (Join-Path $script:Repo "templates\*") (Join-Path $work "templates\") -Recurse
        # git preflight(D3)가 통과하도록 작업 디렉터리를 git 저장소로 만든다.
        & git init -q $work 2>$null | Out-Null
        return $work
    }

    # codex 스텁을 bin 디렉터리에 설치하고 그 경로를 돌려준다.
    # task-004: 러너의 --version preflight 에 응답해야 한다 (버전 주입 가능).
    function Install-CodexStub {
        param([string]$Work, [string]$Version = "99.0.0")
        $binDir = Join-Path $Work "bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        if ($script:IsWin) {
            # PowerShell이 codex.cmd / codex 를 Application 으로 찾도록 .cmd 스텁 생성.
            $cmd = "@echo off`r`nif `"%~1`"==`"--version`" ( echo codex-cli $Version & exit /b 0 )`r`nexit /b 0"
            Set-Content -Path (Join-Path $binDir "codex.cmd") -Value $cmd -Encoding ASCII
        } else {
            $stub = Join-Path $binDir "codex"
            $body = "#!/usr/bin/env bash`nif [ `"`${1:-}`" = `"--version`" ]; then echo `"codex-cli $Version`"; exit 0; fi`nexit 0"
            Set-Content -Path $stub -Value $body -Encoding ASCII
            & chmod +x $stub 2>$null | Out-Null
        }
        return $binDir
    }

    function Get-SystemPath {
        if ($script:IsWin) { return "$env:SystemRoot\System32;$env:SystemRoot" }
        return "/usr/bin:/bin"
    }

    function Invoke-Script {
        param(
            [string]$ScriptPath,
            [string[]]$ScriptArgs = @(),
            [hashtable]$ExtraEnv = @{}
        )
        $clear = @("CLAUDE_CODE_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDECODE",
                   "CLAUDE_CODE", "CODEX_AUTO", "CODEX_AUTO_FORCE")
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

Describe "codex-design.ps1" -Skip:([string]::IsNullOrEmpty($script:Shell)) {

    BeforeEach {
        $script:Work = New-Workspace
        $script:ScriptPath = Join-Path $script:Work "runtime\codex-design.ps1"
        $script:GoodFixture = Join-Path $script:Repo "tests\validator\fixtures\good.md"
        $script:SysPath = Get-SystemPath
    }

    AfterEach {
        if ($script:Work -and (Test-Path $script:Work)) {
            Remove-Item $script:Work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "no args (Mandatory params missing) -> NON-ZERO" {
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @()
        $r.ExitCode | Should -Not -Be 0
    }

    It "codex missing, raw draft (manual) -> post-validation fails (exit 1)" {
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-a", "sample") `
            -ExtraEnv @{ PATH = $script:SysPath }
        $r.ExitCode | Should -Be 1
        (Test-Path (Join-Path $script:Work "kb\tasks\task-a\design.md")) | Should -BeTrue
        ($r.Output -match "보완 필요" -or $r.Output -match "FAIL") | Should -BeTrue
    }

    It "existing design.md -> refuses to overwrite (exit 1)" {
        $taskDir = Join-Path $script:Work "kb\tasks\task-b"
        New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
        Copy-Item $script:GoodFixture (Join-Path $taskDir "design.md")
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-b", "sample") `
            -ExtraEnv @{ PATH = $script:SysPath }
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "이미 존재"
    }

    It "-Auto + codex stub -> stub invoked, post-validation fails (exit 1)" {
        $binDir = Install-CodexStub -Work $script:Work
        # 스텁(bin)을 PATH 앞에 둔다 — git preflight 용 시스템 경로도 포함.
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-c", "sample", "-Auto") `
            -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Be 1
        (Test-Path (Join-Path $script:Work "kb\tasks\task-c\design.md")) | Should -BeTrue
        $r.Output | Should -Match "Codex"
    }

    It "default (no -Auto) + codex stub -> stub skipped, manual banner (exit 1)" {
        $binDir = Install-CodexStub -Work $script:Work
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-d", "sample") `
            -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match "수동 모드"
    }

    # C-1: bats 미러 — Phase A manifest 자동생성
    It "new task -> manifest.md auto-generated (Phase A, C-1)" {
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-a", "sample") `
            -ExtraEnv @{ PATH = $script:SysPath }
        $manifest = Join-Path $script:Work "kb\tasks\task-a\manifest.md"
        (Test-Path $manifest) | Should -BeTrue
        (Get-Content $manifest -Raw) | Should -Match "task-a"
    }

    # C-1: bats 미러 — D2 전파 (유효 design 작성 후 codex 비정상 종료)
    It "-Auto + codex wrote valid design but exited non-zero -> propagate (D2, C-1)" {
        $binDir = Join-Path $script:Work "bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        $taskDir = Join-Path $script:Work "kb\tasks\task-e"
        if ($script:IsWin) {
            # Windows: codex.cmd 스텁이 --version 응답 후, 유효 design 을 복사하고 exit 7
            $cmd = "@echo off`r`nif `"%~1`"==`"--version`" ( echo codex-cli 99.0.0 & exit /b 0 )`r`nmkdir `"$taskDir`" 2>nul`r`ncopy /y `"$($script:GoodFixture)`" `"$taskDir\design.md`" >nul`r`nexit /b 7"
            Set-Content -Path (Join-Path $binDir "codex.cmd") -Value $cmd -Encoding ASCII
        } else {
            $stub = Join-Path $binDir "codex"
            $body = "#!/usr/bin/env bash`nif [ `"`${1:-}`" = `"--version`" ]; then echo `"codex-cli 99.0.0`"; exit 0; fi`nmkdir -p '$taskDir'`ncp '$($script:GoodFixture)' '$taskDir/design.md'`nexit 7"
            Set-Content -Path $stub -Value $body -Encoding ASCII
            & chmod +x $stub 2>$null | Out-Null
        }
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-e", "sample", "-Auto") `
            -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match "codex 자동 호출이 실패"
    }

    # task-004: 강제 플래그(-m/-c) 전달 + --skip-git-repo-check 부재 + provenance 기록
    It "-Auto full pass -> pinned flags (-m/-c) + provenance recorded (task-004)" {
        $binDir = Join-Path $script:Work "bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        $taskDir = Join-Path $script:Work "kb\tasks\task-f"
        $argsLog = Join-Path $script:Work "codex-args.log"
        if ($script:IsWin) {
            $cmd = "@echo off`r`nif `"%~1`"==`"--version`" ( echo codex-cli 99.0.0 & exit /b 0 )`r`necho %* >> `"$argsLog`"`r`nmkdir `"$taskDir`" 2>nul`r`ncopy /y `"$($script:GoodFixture)`" `"$taskDir\design.md`" >nul`r`nexit /b 0"
            Set-Content -Path (Join-Path $binDir "codex.cmd") -Value $cmd -Encoding ASCII
        } else {
            $stub = Join-Path $binDir "codex"
            $body = "#!/usr/bin/env bash`nif [ `"`${1:-}`" = `"--version`" ]; then echo `"codex-cli 99.0.0`"; exit 0; fi`nprintf '%s\n' `"`$*`" >> '$argsLog'`nmkdir -p '$taskDir'`ncp '$($script:GoodFixture)' '$taskDir/design.md'`nexit 0"
            Set-Content -Path $stub -Value $body -Encoding ASCII
            & chmod +x $stub 2>$null | Out-Null
        }
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-f", "sample", "-Auto") `
            -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Be 0
        $stubArgs = Get-Content $argsLog -Raw
        $stubArgs | Should -Match "-m gpt-5\.5"
        $stubArgs | Should -Match "model_reasoning_effort=xhigh"
        $stubArgs | Should -Match "--sandbox workspace-write"
        $stubArgs | Should -Not -Match "--skip-git-repo-check"
        (Get-Content (Join-Path $taskDir "manifest.md") -Raw) | Should -Match "design=codex gpt-5\.5/xhigh"
    }

    # task-004: 프로필 부재 -> --auto 거부 (조용한 기본값 금지)
    It "profile missing -> -Auto refused (no silent default) (task-004)" {
        $binDir = Install-CodexStub -Work $script:Work
        Remove-Item (Join-Path $script:Work "runtime\config\model-profiles.json") -Force
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-g", "sample", "-Auto") `
            -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match "프로필"
    }

    # task-004: 최소 CLI 버전 미달 -> 호출 전 preflight 실패
    It "codex CLI version below minimum -> preflight fail (task-004)" {
        $binDir = Install-CodexStub -Work $script:Work -Version "0.1.0"
        $pathWithStub = "$binDir$([IO.Path]::PathSeparator)$($script:SysPath)"
        $r = Invoke-Script -ScriptPath $script:ScriptPath -ScriptArgs @("task-h", "sample", "-Auto") `
            -ExtraEnv @{ PATH = $pathWithStub }
        $r.ExitCode | Should -Not -Be 0
        $r.Output | Should -Match "버전"
    }
}
