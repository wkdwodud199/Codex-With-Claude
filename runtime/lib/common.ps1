#Requires -Version 5.1
<#
.SYNOPSIS
    runtime/*.ps1 와 runtime/lib/*.ps1 가 공유하는 PowerShell 헬퍼.
    Dot-source 전용: `. "$PSScriptRoot\lib\common.ps1"` 형태로 로드.
#>
if ($script:CwcCommonLoaded) { return }
$script:CwcCommonLoaded = $true

function Resolve-Python {
    foreach ($cmd in @("python3", "python")) {
        $found = Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue
        # 단일 원소 배열은 PS 가 문자열로 언랩해 $py[0] 이 첫 글자('p')가 된다 —
        # 콤마 연산자로 배열을 보존한다 (CI windows 첫 실행에서 발견된 잠복 버그).
        if ($found) { return ,@($cmd) }
    }
    $py = Get-Command "py" -CommandType Application -ErrorAction SilentlyContinue
    if ($py) { return @("py", "-3") }
    return $null
}

function Invoke-Validator {
    param(
        [Parameter(Mandatory=$true)][string]$File,
        [Parameter(Mandatory=$true)][string]$ValidatorCli
    )
    $py = Resolve-Python
    if (-not $py) {
        Write-Host "[ERROR] Python 3 을 찾을 수 없습니다." -ForegroundColor Red
        Write-Host "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        return 2
    }
    $exe = $py[0]
    $prefix = if ($py.Count -gt 1) { $py[1..($py.Count - 1)] } else { @() }
    # cli.py가 출력한 내용을 함수 출력 스트림으로 흘려보내면 호출자에서
    # @('[OK]...', 0) 같은 배열로 오염되어 'if ($code -ne 0)'가 PASS인데도
    # truthy가 된다. 출력은 Write-Host로 콘솔에 명시적으로 흘려보내고,
    # 함수는 오직 스칼라 $LASTEXITCODE만 반환한다.
    & $exe @prefix $ValidatorCli $File 2>&1 | ForEach-Object { Write-Host $_ }
    return [int]$LASTEXITCODE
}

function Invoke-RenderPrompt {
    <#
        render-prompt.py 를 실행해 stdout 값과 종료 코드를 돌려준다 (task-004).
        출력 스트림 오염을 피하기 위해 실패 메시지는 Write-Host 로 흘리고
        [pscustomobject]@{ Code; Value } 만 반환한다.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$RenderPrompt,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )
    $py = Resolve-Python
    if (-not $py) {
        Write-Host "[ERROR] Python 3 을 찾을 수 없습니다 (프로필/프롬프트 해석에 필요)." -ForegroundColor Red
        Write-Host "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        return [pscustomobject]@{ Code = 2; Value = "" }
    }
    $exe = $py[0]
    $prefix = if ($py.Count -gt 1) { $py[1..($py.Count - 1)] } else { @() }
    $out = (& $exe @prefix $RenderPrompt @Arguments 2>&1 | Out-String)
    $rc = [int]$LASTEXITCODE
    $value = $out.Trim()
    if ($rc -ne 0 -and $value) { Write-Host $value }
    return [pscustomobject]@{ Code = $rc; Value = $value }
}

function Test-ClaudeSession {
    # CLAUDECODE가 Claude Code가 항상 설정하는 신뢰 가능한 주(primary) 변수다.
    # CLAUDE_CODE_SESSION_ID는 세션 식별자로 실제 설정되는 변수다.
    # CLAUDE_CODE_SESSION / CLAUDE_CODE는 방어적 추가 (구버전/호환 대비).
    if ($env:CLAUDECODE)             { return $true }
    if ($env:CLAUDE_CODE_SESSION_ID) { return $true }
    if ($env:CLAUDE_CODE_SESSION)    { return $true }
    if ($env:CLAUDE_CODE)            { return $true }
    return $false
}

function Test-Truthy {
    param([string]$Value)
    if (-not $Value) { return $false }
    return @("1", "true", "TRUE", "yes", "YES", "on", "ON") -contains $Value
}
