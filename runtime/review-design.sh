#!/usr/bin/env bash
# review-design.sh — Codex 설계에 대한 Claude 읽기전용 2차 검토(cross-review) 러너 (task-005, P1)
#
# 사용법:
#   ./runtime/review-design.sh <task-id>
#
# 동작:
#   1. design.md 존재 + validator 통과를 precondition 으로 확인 (미통과 시 Claude 호출 안 함).
#   2. design.claude_cross_check 프로필(fable-5/max + fallback opus-4-8)로 읽기전용 검토를 요청.
#   3. 결과를 kb/tasks/<id>/design-review.md 에 기록하고 manifest 에 provenance 를 남긴다.
#
# 성격:
#   - advisory: 검토가 우려를 지적해도 종료코드는 0. non-zero 는 precondition/렌더/프로필/CLI/
#     JSON 파싱/파일 쓰기 오류에만 쓴다 (설계 게이트가 아니다).
#   - design.md 는 읽기전용: 실행 전후 해시가 다르면 아무것도 쓰지 않고 실패한다.
#   - collab.md / done-gate / reviews/ 는 건드리지 않는다 (task-006 소관).
#
# 환경변수:
#   CLAUDE_AUTO_FORCE=1 — Claude Code 세션 내부에서도 호출 허용 (재귀 가드 우회)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=runtime/lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

for arg in "$@"; do
    case "$arg" in
        --help|-h) echo "사용법: $0 <task-id>"; exit 0 ;;
    esac
done

if [ "$#" -lt 1 ]; then
    echo "사용법: $0 <task-id>"
    echo "예시:  $0 task-004"
    exit 1
fi

TASK_ID="$1"
TASK_DIR="$PROJECT_ROOT/kb/tasks/$TASK_ID"
DESIGN_FILE="$TASK_DIR/design.md"
REVIEW_FILE="$TASK_DIR/design-review.md"
MANIFEST_FILE="$TASK_DIR/manifest.md"
VALIDATOR_CLI="$PROJECT_ROOT/runtime/validator/cli.py"
RP="$PROJECT_ROOT/runtime/render-prompt.py"

# sha256 해시 (macOS shasum / Linux sha256sum 모두 대응).
file_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
    else echo "[ERROR] sha256 도구(sha256sum/shasum)를 찾을 수 없습니다." >&2; return 2; fi
}

py=""
resolve_py() {
    if ! py=$(resolve_python); then
        echo "[ERROR] Python 3 을 찾을 수 없습니다 (프로필/렌더/JSON 해석에 필요)."
        echo "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        return 2
    fi
}

# --- precondition: design.md 존재 ---
if [ ! -f "$DESIGN_FILE" ]; then
    echo "[ERROR] 설계 문서가 없습니다: $DESIGN_FILE"
    exit 1
fi
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "[ERROR] manifest 가 없습니다: $MANIFEST_FILE (provenance 기록 대상)"
    exit 1
fi

resolve_py || exit $?

# --- precondition: validator 통과 (미통과면 Claude 호출 안 함) ---
echo "--- 설계 검증 (교차검토 전제) ---"
set +e
# shellcheck disable=SC2086
$py "$VALIDATOR_CLI" "$DESIGN_FILE"
validator_rc=$?
set -e
if [ "$validator_rc" -ne 0 ]; then
    echo "[ERROR] 설계 검증 미통과 (rc=$validator_rc). 교차검토를 실행하지 않습니다."
    exit "$validator_rc"
fi

# --- 재귀 가드 ---
if is_claude_session && ! truthy "${CLAUDE_AUTO_FORCE:-}"; then
    echo "[WARN] Claude Code 세션 내부에서 자동 호출을 거부합니다 (재귀 방지)."
    echo "       우회하려면 CLAUDE_AUTO_FORCE=1 을 설정하세요."
    echo "       교차검토를 건너뜁니다 (design-review.md 를 만들지 않음)."
    exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "[WARN] claude CLI를 찾을 수 없습니다. 교차검토를 건너뜁니다."
    exit 1
fi

# --- 프로필 조회 (design.claude_cross_check) ---
rp_get() { # <field>
    local v rc
    # shellcheck disable=SC2086
    v=$($py "$RP" profile --phase design --cli claude --field "$1"); rc=$?
    if [ "$rc" -ne 0 ]; then echo "[ERROR] 프로필 해석 실패($1) — 교차검토 중단." >&2; return "$rc"; fi
    printf '%s' "$v"
}
model=$(rp_get model)
effort=$(rp_get effort)
fallback_model=$(rp_get fallback_model)

# --- CLI 버전 preflight ---
ver_out=$(claude --version 2>&1 || true)
# shellcheck disable=SC2086
cli_ver=$($py "$RP" check-cli-version --phase design --cli claude --version-output "$ver_out") || {
    echo "[ERROR] claude CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $(printf '%s' "$ver_out" | head -n1))"; exit 1;
}

# --- 프롬프트 렌더 ---
# shellcheck disable=SC2086
prompt=$($py "$RP" render --phase design-review --task-id "$TASK_ID" --design-file "$DESIGN_FILE" \
    --review-file "$REVIEW_FILE" --project-root "$PROJECT_ROOT" --model "$model" --effort "$effort") || {
    echo "[ERROR] 프롬프트 렌더 실패 — 교차검토 중단."; exit 1;
}

# --- design.md 읽기전용 보증: 실행 전 해시 ---
before_hash=$(file_hash "$DESIGN_FILE") || exit $?

echo "[INFO] Claude 교차검토 요청 중... (model=$model, effort=$effort, fallback=$fallback_model, cli=$cli_ver)"
echo ""
tmp_json="$(mktemp)"
trap 'rm -f "$tmp_json"' EXIT
set +e
claude -p "$prompt" --model "$model" --effort "$effort" --fallback-model "$fallback_model" \
    --output-format json < /dev/null > "$tmp_json"
claude_rc=$?
set -e
if [ "$claude_rc" -ne 0 ]; then
    echo "[ERROR] claude 호출 실패 (exit $claude_rc)."
    exit "$claude_rc"
fi

# --- 실제 model / fallback / 본문 추출 (조용한 폴백 금지) ---
actual_model=$($py "$RP" detect-fallback --json-file "$tmp_json" --requested-model "$model" \
    --fallback-model "$fallback_model" --field actual_model) || { echo "[ERROR] fallback 판별 실패."; exit 1; }
fallback_fired=$($py "$RP" detect-fallback --json-file "$tmp_json" --requested-model "$model" \
    --fallback-model "$fallback_model" --field fallback) || { echo "[ERROR] fallback 판별 실패."; exit 1; }
review_body=$($py "$RP" detect-fallback --json-file "$tmp_json" --requested-model "$model" \
    --fallback-model "$fallback_model" --field response_text) || { echo "[ERROR] 응답 본문 추출 실패."; exit 1; }

# --- design.md 읽기전용 보증: 실행 후 해시 비교 ---
after_hash=$(file_hash "$DESIGN_FILE") || exit $?
if [ "$before_hash" != "$after_hash" ]; then
    echo "[ERROR] design.md 가 교차검토 중 변경되었습니다. 산출물을 기록하지 않고 실패합니다 (읽기전용 위반)."
    exit 1
fi

# --- design-review.md 기록 (atomic) ---
today=$(date +%Y-%m-%d)
tmp_review="$(mktemp)"
{
    echo "# 설계 교차검토 — $TASK_ID"
    echo ""
    echo "> **advisory** (구현 게이트 아님). Reviewer: Claude ($actual_model/$effort), $today. fallback=$fallback_fired"
    echo "> Target: $DESIGN_FILE (읽기전용). 이 문서는 runtime/review-design.sh 가 생성했다."
    echo ""
    printf '%s\n' "$review_body"
} > "$tmp_review"
mv "$tmp_review" "$REVIEW_FILE"
echo "[OK] 교차검토 기록: $REVIEW_FILE"

# --- manifest provenance ---
printf -- '- **cross_reviewed_by**: claude %s/%s @claude %s, %s (fallback=%s)\n' \
    "$actual_model" "$effort" "$cli_ver" "$today" "$fallback_fired" >> "$MANIFEST_FILE"
echo "[OK] provenance 기록: $MANIFEST_FILE"

if truthy "$fallback_fired"; then
    echo "[WARN] fallback 발동: $model → $actual_model (effort=$effort 유지)."
fi
