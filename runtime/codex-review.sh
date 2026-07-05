#!/usr/bin/env bash
# codex-review.sh — Codex 가 Claude 구현 결과를 리뷰하는 러너 (task-006, Phase D, opt-in)
#
# 사용법:
#   ./runtime/codex-review.sh <task-id>
#
# 동작:
#   1. base 완료 전제 검증 (--check-review-target): impl-notes(done) + artifact summary(done) + manifest.
#      (approved-done 리뷰 게이트는 제외 — 재리뷰 순환을 막기 위함.)
#   2. review.codex 프로필(gpt-5.5/xhigh)로 codex 에게 리뷰를 요청. codex 는 staging 파일 하나만 쓴다.
#   3. staging 리뷰를 검증(--check-review)한 뒤에만 reviews/<NNN>.md 로 승격(move)한다.
#      → 부분/오류 리뷰가 approved-done 게이트를 오염시키지 않는다.
#
# 환경변수:
#   CODEX_AUTO_FORCE=1 — 세션 내부에서도 codex 호출 허용 (재귀 가드 우회)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=runtime/lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=runtime/lib/invoke-codex.sh
. "$SCRIPT_DIR/lib/invoke-codex.sh"

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
IMPL_NOTES="$TASK_DIR/implementation-notes.md"
ARTIFACT_SUMMARY="$PROJECT_ROOT/kb/artifacts/$TASK_ID-summary.md"
REVIEWS_DIR="$TASK_DIR/reviews"
STAGING="$TASK_DIR/.review-staging.md"
REVIEW_TEMPLATE="$PROJECT_ROOT/templates/review.md"
VALIDATOR_CLI="$PROJECT_ROOT/runtime/validator/cli.py"
RP="$PROJECT_ROOT/runtime/render-prompt.py"

py=""
if ! py=$(resolve_python); then
    echo "[ERROR] Python 3 을 찾을 수 없습니다."
    echo "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
    exit 2
fi

# --- base 완료 전제 (리뷰 게이트 제외) ---
echo "--- 리뷰 전제 검증 (base done, 리뷰 게이트 제외) ---"
set +e
# shellcheck disable=SC2086
$py "$VALIDATOR_CLI" --check-review-target "$TASK_ID"
target_rc=$?
set -e
if [ "$target_rc" -ne 0 ]; then
    echo "[ERROR] base 완료 전제 미충족 (rc=$target_rc). 구현이 done 상태여야 리뷰할 수 있습니다."
    exit "$target_rc"
fi

# --- review.codex 프로필 조회 ---
rp_get() { # <field>
    local v rc
    # shellcheck disable=SC2086
    v=$($py "$RP" profile --phase review --cli codex --field "$1"); rc=$?
    if [ "$rc" -ne 0 ]; then echo "[ERROR] 프로필 해석 실패($1) — 리뷰 중단." >&2; return "$rc"; fi
    printf '%s' "$v"
}
model=$(rp_get model)
effort=$(rp_get effort)

# --- CLI 버전 preflight (codex 존재 시에만; 부재는 invoke 헬퍼가 처리) ---
if command -v codex >/dev/null 2>&1; then
    ver_out=$(codex --version 2>&1 || true)
    # shellcheck disable=SC2086
    $py "$RP" check-cli-version --phase review --cli codex --version-output "$ver_out" >/dev/null || {
        echo "[ERROR] codex CLI 버전 preflight 실패 — 호출하지 않습니다. (감지: $(printf '%s' "$ver_out" | head -n1))"; exit 1;
    }
fi

# --- 다음 리뷰 번호 (NNN) ---
next_num=1
if [ -d "$REVIEWS_DIR" ]; then
    for f in "$REVIEWS_DIR"/[0-9][0-9][0-9].md; do
        [ -e "$f" ] || continue
        n=$(basename "$f" .md)
        n=$((10#$n))
        [ "$n" -ge "$next_num" ] && next_num=$((n + 1))
    done
fi
NNN=$(printf '%03d' "$next_num")
REVIEW_FILE="$REVIEWS_DIR/$NNN.md"

# --- 리뷰 프롬프트 렌더 (staging 경로로 지시) ---
rm -f "$STAGING"
# shellcheck disable=SC2086
prompt=$($py "$RP" render --phase review --task-id "$TASK_ID" --design-file "$DESIGN_FILE" \
    --impl-notes "$IMPL_NOTES" --artifact-summary "$ARTIFACT_SUMMARY" --review-file "$STAGING" \
    --review-template "$REVIEW_TEMPLATE" --project-root "$PROJECT_ROOT" --model "$model" --effort "$effort") || {
    echo "[ERROR] 리뷰 프롬프트 렌더 실패 — 중단."; exit 1;
}

# --- codex 리뷰 호출 (staging 파일 하나만 쓰도록 지시) ---
set +e
invoke_codex_review "$PROJECT_ROOT" "$prompt" "$model" "$effort"
invoke_rc=$?
set -e
if [ "$invoke_rc" -ne 0 ]; then
    echo "[ERROR] codex 리뷰 호출 실패 (exit $invoke_rc)."
    rm -f "$STAGING"
    exit "$invoke_rc"
fi

if [ ! -f "$STAGING" ]; then
    echo "[ERROR] codex 가 리뷰 파일을 쓰지 않았습니다: $STAGING"
    exit 1
fi

# --- staging 리뷰 검증 (통과해야만 승격) ---
set +e
# shellcheck disable=SC2086
$py "$VALIDATOR_CLI" --check-review "$STAGING"
review_rc=$?
set -e
if [ "$review_rc" -ne 0 ]; then
    echo "[ERROR] 생성된 리뷰가 검증을 통과하지 못했습니다 (rc=$review_rc). reviews/ 로 승격하지 않습니다."
    rm -f "$STAGING"
    exit "$review_rc"
fi

# --- 승격: reviews/NNN.md ---
mkdir -p "$REVIEWS_DIR"
mv "$STAGING" "$REVIEW_FILE"
echo "[OK] 리뷰 생성: $REVIEW_FILE"

# --- 상태 안내 (no-auto-revert) ---
status=$($py "$VALIDATOR_CLI" --latest-review "$TASK_ID" --json 2>/dev/null \
    | $py -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
echo "[INFO] 최신 리뷰 status: ${status:-?}"
if [ "$status" != "approved" ]; then
    echo "[INFO] approved 가 아니므로 approved-done 게이트는 아직 통과하지 않습니다."
    echo "       (no-auto-revert: 구현 상태는 자동으로 바뀌지 않습니다. 구현자가 다음 액션을 판단하세요.)"
fi
