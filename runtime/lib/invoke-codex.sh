#!/usr/bin/env bash
# invoke-codex.sh — Codex CLI 호출 로직.
#
# source 전용. 내보내는 함수:
#   invoke_codex_if_enabled <task-id> <design-file> <task-desc> <auto-mode> <project-root>
#     - auto-mode  : "1" 이면 자동 호출 시도, 아니면 안내만.
#     - return 0   : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
#     - return 1   : --auto 인데 CLI 부재 또는 호출 실패.
#
#   D2 정책:
#     - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 exit 0.
#     - --auto 인데 codex CLI 부재 → NON-ZERO.
#     - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.
#
# 재귀 가드:
#   Claude Code 세션 내부에서 auto=1 요청 시 CODEX_AUTO_FORCE=1 없으면 거부.
#   세션 감지는 CLAUDECODE(주) / CLAUDE_CODE_SESSION_ID 등으로 한다 (common.sh 참조).
#   (Codex 호출 자체는 Claude 세션을 중첩하지 않지만 대칭성 위해 동일 규칙 유지.)

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime/lib/common.sh
. "$_LIB_DIR/common.sh"

invoke_codex_if_enabled() {
    local task_id="$1"
    local design_file="$2"
    local task_desc="$3"
    local auto_mode="$4"
    local project_root="$5"

    if ! truthy "$auto_mode"; then
        echo "[INFO] 수동 모드입니다. Codex 자동 호출을 건너뜁니다."
        echo "       자동 호출을 원하면 --auto 또는 CODEX_AUTO=1 을 지정하세요."
        echo "       설계 문서 초안: $design_file"
        return 0
    fi

    if is_claude_session && ! truthy "${CODEX_AUTO_FORCE:-}"; then
        echo "[WARN] Claude Code 세션 내부에서 자동 호출을 거부합니다 (재귀 방지)."
        echo "       우회하려면 CODEX_AUTO_FORCE=1 을 설정하세요."
        return 0
    fi

    if ! command -v codex >/dev/null 2>&1; then
        echo "[WARN] codex CLI를 찾을 수 없습니다."
        echo "       수동으로 설계 문서를 작성하거나 codex를 설치하세요."
        return 1
    fi

    # --- preflight: git 저장소 안에서만 자동 호출 (git 안전망 복원) ---
    # --skip-git-repo-check 제거에 따라, codex가 거부하기 전에 먼저 확인한다.
    if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[WARN] git 저장소가 아닙니다: $project_root"
        echo "       codex 자동 설계는 git 저장소 안에서만 실행합니다 (안전망)."
        return 1
    fi

    echo "[INFO] Codex에게 설계 요청 중..."
    echo ""
    local prompt
    prompt=$(cat <<EOF
다음 작업에 대한 설계 문서를 작성해주세요.
작업: $task_desc
설계 문서 경로: $design_file
참조할 기존 문서: $project_root/kb/concepts/

중요 규칙:
- 템플릿의 모든 필수 섹션(목표, 범위, 제약, 구현 단계, 파일/모듈 영향, 테스트 기준, 오픈 이슈)을 빠짐없이 채우세요.
- 모든 placeholder 안내문을 실제 내용으로 교체하세요.
- 완성 후 문서 상단의 Status를 ready로 변경하세요.
- Inputs, Outputs, Next step 필드를 구체적으로 채우세요.
- 파일/모듈 영향 테이블과 테스트 기준 체크박스에 실제 항목을 기입하세요.
EOF
)
    # codex 0.137: 제약된 샌드박스(workspace-write)로 비대화형 실행.
    # 설계 생성기는 kb/tasks/<id>/ 아래 한 파일만 쓰면 되므로 full-auto 불필요.
    # --skip-git-repo-check 제거로 codex의 git 안전망을 복원한다.
    echo "" | codex exec --sandbox workspace-write -C "$project_root" "$prompt" < /dev/null
    local rc=$?
    echo ""
    return $rc
}
