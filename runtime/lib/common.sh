#!/usr/bin/env bash
# common.sh — runtime/*.sh 와 runtime/lib/*.sh 가 공유하는 헬퍼.
# source 만 되며 단독 실행되지 않는다.
[ -n "${_CWC_COMMON_LOADED:-}" ] && return 0
_CWC_COMMON_LOADED=1

# resolve_python — python3 / python / py -3 중 첫 번째를 echo.
# 찾지 못하면 비-0 반환.
resolve_python() {
    if command -v python3 >/dev/null 2>&1; then echo "python3"; return 0; fi
    if command -v python  >/dev/null 2>&1; then echo "python";  return 0; fi
    if command -v py      >/dev/null 2>&1; then echo "py -3";   return 0; fi
    return 1
}

# is_claude_session — Claude Code 세션 안에서 실행 중인지 휴리스틱.
# 감지된 환경변수 하나라도 비어있지 않으면 '세션 내부'로 간주.
#   - CLAUDECODE           : Claude Code가 항상 설정하는 신뢰 가능한 주(primary) 변수.
#   - CLAUDE_CODE_SESSION_ID: Claude Code가 세션 식별자로 설정하는 실제 변수.
#   - CLAUDE_CODE_SESSION   : 방어적 추가 (구버전/호환 대비).
#   - CLAUDE_CODE           : 방어적 추가.
is_claude_session() {
    [ -n "${CLAUDECODE:-}" ]              || \
    [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]  || \
    [ -n "${CLAUDE_CODE_SESSION:-}" ]     || \
    [ -n "${CLAUDE_CODE:-}" ]
}

# truthy — "1", "true", "yes" 를 참으로 판단.
truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}
