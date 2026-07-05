#!/usr/bin/env bash
# invoke-codex.sh — Codex CLI 호출 로직.
#
# source 전용. 내보내는 함수:
#   invoke_codex_if_enabled <task-id> <design-file> <task-desc> <auto-mode> <project-root>
#     - return 0  : 호출 성공 또는 의도된 스킵 (수동 모드 / 재귀 가드 스킵).
#     - return 1  : --auto 인데 CLI 부재 / 버전 미달 / 정책 실패 / 호출 실패.
#     - return 2  : 환경 오류 (python 부재, 프로필·프롬프트 IO/해석 오류).
#
#   task-004 (2층 라우팅 + 프롬프트 SSOT):
#     - 모델/effort 는 runtime/config/model-profiles.json 에서 render-prompt.py 로 얻어
#       항상 `-m <model> -c model_reasoning_effort=<effort>` 를 명시한다
#       (사용자 전역 ~/.codex/config.toml 에 의존하지 않는다).
#     - 프로필/렌더 실패 시 --auto 를 거부한다 (조용한 기본값 금지).
#     - CLI 버전 preflight: 프로필의 min_cli_version 미달이면 호출하지 않고 실패.
#     - 호출 성공 시 CWC_PROV_LINE 전역에 provenance 를 남긴다.
#       러너가 검증 통과 후 manifest 에 기록한다.
#
# D2 정책:
#   - 수동 모드 스킵 / 재귀 가드 스킵은 의도된 동작이므로 exit 0.
#   - --auto 인데 codex CLI 부재 → NON-ZERO.
#   - --auto 로 호출했으나 CLI가 non-zero 반환 → 그 코드를 그대로 전파.
#
# 재귀 가드:
#   Claude Code 세션 내부에서 auto=1 요청 시 CODEX_AUTO_FORCE=1 없으면 거부.
#   세션 감지는 CLAUDECODE(주)/CLAUDE_CODE_SESSION_ID 등으로 한다 (common.sh 참조).

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runtime/lib/common.sh
. "$_LIB_DIR/common.sh"

invoke_codex_if_enabled() {
    local task_id="$1"
    local design_file="$2"
    local task_desc="$3"
    local auto_mode="$4"
    local project_root="$5"
    CWC_PROV_LINE=""

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
    if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[WARN] git 저장소가 아닙니다: $project_root"
        echo "       codex 자동 설계는 git 저장소 안에서만 실행합니다 (안전망)."
        return 1
    fi

    # --- 프로필/렌더러 (task-004): python 필요 ---
    local py
    if ! py=$(resolve_python); then
        echo "[ERROR] Python 3 을 찾을 수 없습니다 (프로필/프롬프트 해석에 필요)."
        echo "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        return 2
    fi
    local rp="$project_root/runtime/render-prompt.py"

    local model effort rc
    # shellcheck disable=SC2086
    model=$($py "$rp" profile --phase design --cli codex --field model); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] 프로필 해석 실패(model) — --auto 를 중단합니다 (조용한 기본값 금지)."
        return "$rc"
    fi
    # shellcheck disable=SC2086
    effort=$($py "$rp" profile --phase design --cli codex --field effort); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] 프로필 해석 실패(effort) — --auto 를 중단합니다."
        return "$rc"
    fi

    # --- CLI 버전 preflight ---
    local ver_out cli_ver
    ver_out=$(codex --version 2>&1 || true)
    # shellcheck disable=SC2086
    cli_ver=$($py "$rp" check-cli-version --phase design --cli codex --version-output "$ver_out"); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] codex CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $(printf '%s' "$ver_out" | head -n1))"
        return "$rc"
    fi

    # --- 프롬프트 렌더 (SSOT: templates/prompts/design.md + schema.json) ---
    local prompt
    # shellcheck disable=SC2086
    prompt=$($py "$rp" render --phase design --task-id "$task_id" --design-file "$design_file" \
        --task-desc "$task_desc" --project-root "$project_root"); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[ERROR] 프롬프트 렌더 실패 — --auto 를 중단합니다."
        return "$rc"
    fi

    echo "[INFO] Codex에게 설계 요청 중... (model=$model, effort=$effort, cli=$cli_ver)"
    echo ""
    # codex 0.142+: 제약된 샌드박스(workspace-write) + 명시적 모델/effort 강제.
    # --skip-git-repo-check 는 사용하지 않는다 (git 안전망 유지).
    codex exec --sandbox workspace-write -C "$project_root" \
        -m "$model" -c "model_reasoning_effort=$effort" "$prompt" < /dev/null
    rc=$?
    echo ""
    if [ "$rc" -eq 0 ]; then
        CWC_PROV_LINE="design=codex $model/$effort @codex $cli_ver, $(date +%Y-%m-%d) (fallback=none)"
    fi
    return "$rc"
}

# invoke_codex_review — Phase D 구현 리뷰용 codex 호출 (task-006).
#   invoke_codex_review <project-root> <prompt> <model> <effort>
#   - 재귀 가드 / codex 존재 / git preflight 를 design 호출과 같은 의미로 적용.
#   - codex exec --sandbox workspace-write -m <model> -c model_reasoning_effort=<effort>.
#     --skip-git-repo-check 는 쓰지 않는다.
#   - return 0: 호출 성공. 1: 가드/부재/preflight 실패. codex non-zero 는 그대로 전파.
#   재귀 가드가 막으면 리뷰 생성 자체가 목적이므로 false success 를 내지 않고 NON-ZERO(1) 로 종료한다.
invoke_codex_review() {
    local project_root="$1" prompt="$2" model="$3" effort="$4"

    if is_claude_session && ! truthy "${CODEX_AUTO_FORCE:-}"; then
        echo "[WARN] 세션 내부에서 codex 자동 호출을 거부합니다 (재귀 방지). CODEX_AUTO_FORCE=1 로 우회."
        echo "       리뷰를 생성하지 못했으므로 실패로 종료합니다."
        return 1
    fi
    if ! command -v codex >/dev/null 2>&1; then
        echo "[WARN] codex CLI를 찾을 수 없습니다. 리뷰를 생성할 수 없습니다."
        return 1
    fi
    if ! git -C "$project_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[WARN] git 저장소가 아닙니다: $project_root (codex 리뷰는 git 저장소 안에서만)."
        return 1
    fi

    echo "[INFO] Codex 리뷰 요청 중... (model=$model, effort=$effort)"
    echo ""
    echo "" | codex exec --sandbox workspace-write -C "$project_root" \
        -m "$model" -c "model_reasoning_effort=$effort" "$prompt" < /dev/null
    local rc=$?
    echo ""
    return "$rc"
}
