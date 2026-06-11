#!/usr/bin/env bash
# invoke-claude.sh — Claude CLI 호출 로직 (codex-design 과 대칭).
#
# source 전용. 내보내는 함수:
#   invoke_claude_if_enabled <task-id> <design-file> <impl-notes> <auto-mode> <project-root>
#     - auto-mode  : "1" 이면 자동 호출 시도, 아니면 안내만.
#     - return 0   : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
#     - return 1   : --auto 인데 CLI 부재 또는 호출 실패 (요청한 자동 작업 미수행).
#
#   D2 정책:
#     - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 exit 0.
#     - --auto 인데 claude CLI 부재 → 요청한 자동 작업을 못 했으므로 NON-ZERO.
#     - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.
#
# 재귀 가드 (중요):
#   이미 Claude Code 세션 안에서 `claude -p` 를 호출하면 중첩 세션이 돼
#   토큰이 폭증할 수 있으므로, 기본 정책은 거부.
#   세션 감지는 CLAUDECODE(주) / CLAUDE_CODE_SESSION_ID 등으로 한다 (common.sh 참조).
#   CLAUDE_AUTO_FORCE=1 이 명시된 경우에만 중첩 호출을 허용한다.
#
# 프롬프트 구성 원칙:
#   - design.md 내용을 그대로 인라인하지 않는다 (컨텍스트 절약).
#   - 경로만 전달하고 Claude 측에서 읽도록 한다.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime/lib/common.sh
. "$_LIB_DIR/common.sh"

invoke_claude_if_enabled() {
    local task_id="$1"
    local design_file="$2"
    local impl_notes="$3"
    local auto_mode="$4"
    local project_root="$5"

    if ! truthy "$auto_mode"; then
        echo "[INFO] 수동 모드입니다. Claude 자동 호출을 건너뜁니다."
        echo "       자동 호출을 원하면 --auto 또는 CLAUDE_AUTO=1 을 지정하세요."
        return 0
    fi

    if is_claude_session && ! truthy "${CLAUDE_AUTO_FORCE:-}"; then
        echo "[WARN] Claude Code 세션 내부에서 자동 호출을 거부합니다 (재귀 방지)."
        echo "       우회하려면 CLAUDE_AUTO_FORCE=1 을 설정하세요."
        return 0
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "[WARN] claude CLI를 찾을 수 없습니다."
        echo "       수동으로 구현하거나 claude CLI를 설치하세요."
        return 1
    fi

    echo "[INFO] Claude에게 구현 요청 중..."
    echo ""
    local prompt
    prompt=$(cat <<EOF
$task_id 의 설계 문서를 읽고 구현을 시작해주세요.

설계 문서: $design_file
구현 노트: $impl_notes
프로젝트 루트: $project_root

CLAUDE.md 규약:
  1. design.md를 먼저 읽으세요 (필수 섹션 / Status 확인).
  2. 구현 중 결정이 설계와 달라지면 implementation-notes.md 에 기록하세요.
  3. 완료 후 kb/artifacts/${task_id}-summary.md 를 작성하고 python3 runtime/generate-status.py 를 실행하세요.
EOF
)
    claude -p "$prompt" < /dev/null
    local rc=$?
    echo ""
    return $rc
}
