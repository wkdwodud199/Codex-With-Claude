#!/usr/bin/env bash
# invoke-claude.sh — Claude CLI 호출 로직 (codex-design 과 대칭).
#
# source 전용. 내보내는 함수:
#   invoke_claude_if_enabled <task-id> <design-file> <impl-notes> <auto-mode> <project-root>
#     - return 0  : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
#     - return 1  : --auto 인데 CLI 부재 / 버전 미달 / 라우팅 실패 / 호출 실패.
#     - return 2  : 환경 오류 (python 부재, 프로필·프롬프트 IO/해석 오류).
#
#   task-004 (설계 주도 라우팅):
#     - implement 의 model/effort 는 정적 강제가 아니라 design.md 의
#       "실행 계획 (Execution Plan)" 이 지정한다 (render-prompt.py route-implement).
#     - 실행 계획 부재는 legacy(task-001~003) 만 허용 — 프로필 기본값으로
#       라우팅하며 [WARN] 로그 + provenance(route=default) 를 남긴다.
#     - 항상 `claude -p --model <m> --effort <e>` 를 명시한다.
#     - 호출 성공 시 CWC_PROV_LINE 전역에 provenance 를 남긴다 (러너가 기록).
#
# D2 정책:
#   - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 exit 0.
#   - --auto 인데 claude CLI 부재 → NON-ZERO.
#   - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.
#
# 재귀 가드 (중요):
#   이미 Claude Code 세션 안에서 `claude -p` 를 호출하면 중첩 세션이 돼
#   토큰이 폭증할 수 있으므로, 기본 정책은 거부 (CLAUDE_AUTO_FORCE=1 로만 우회).
#
# 프롬프트 구성 원칙:
#   - design.md 내용을 인라인하지 않는다 (경로만 전달 — 컨텍스트 절약).
#   - 프롬프트 본문은 templates/prompts/implement.md 가 단일 원천이다.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime/lib/common.sh
. "$_LIB_DIR/common.sh"

invoke_claude_if_enabled() {
    local task_id="$1"
    local design_file="$2"
    local impl_notes="$3"
    local auto_mode="$4"
    local project_root="$5"
    CWC_PROV_LINE=""

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

    local py
    if ! py=$(resolve_python); then
        echo "[ERROR] Python 3 을 찾을 수 없습니다 (라우팅/프롬프트 해석에 필요)."
        echo "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        return 2
    fi
    local rp="$project_root/runtime/render-prompt.py"

    # --- 설계 주도 라우팅 (실행 계획 → model/effort) ---
    local model effort route rc
    # shellcheck disable=SC2086
    model=$($py "$rp" route-implement --design-file "$design_file" --task-id "$task_id" --field model); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] implement 라우팅 실패(model) — --auto 를 중단합니다."
        return "$rc"
    fi
    # shellcheck disable=SC2086
    effort=$($py "$rp" route-implement --design-file "$design_file" --task-id "$task_id" --field effort); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] implement 라우팅 실패(effort) — --auto 를 중단합니다."
        return "$rc"
    fi
    # shellcheck disable=SC2086
    route=$($py "$rp" route-implement --design-file "$design_file" --task-id "$task_id" --field route); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] implement 라우팅 실패(route) — --auto 를 중단합니다."
        return "$rc"
    fi
    if [ "$route" = "default" ]; then
        echo "[WARN] 실행 계획 없음(legacy) — 프로필 기본값으로 라우팅합니다: $model/$effort"
    fi

    # --- CLI 버전 preflight ---
    local ver_out cli_ver
    ver_out=$(claude --version 2>&1 || true)
    # shellcheck disable=SC2086
    cli_ver=$($py "$rp" check-cli-version --phase implement --cli claude --version-output "$ver_out"); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] claude CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $(printf '%s' "$ver_out" | head -n1))"
        return "$rc"
    fi

    # --- 프롬프트 렌더 (SSOT: templates/prompts/implement.md) ---
    local prompt
    # shellcheck disable=SC2086
    prompt=$($py "$rp" render --phase implement --task-id "$task_id" --design-file "$design_file" \
        --impl-notes "$impl_notes" --project-root "$project_root" --model "$model" --effort "$effort"); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] 프롬프트 렌더 실패 — --auto 를 중단합니다."
        return "$rc"
    fi

    echo "[INFO] Claude에게 구현 요청 중... (model=$model, effort=$effort, route=$route)"
    echo ""
    claude -p "$prompt" --model "$model" --effort "$effort" < /dev/null
    rc=$?
    echo ""
    if [ "$rc" -eq 0 ]; then
        CWC_PROV_LINE="implement=claude $model/$effort @claude $cli_ver, $(date +%Y-%m-%d) (route=$route)"
    fi
    return "$rc"
}
