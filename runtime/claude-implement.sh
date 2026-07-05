#!/usr/bin/env bash
# claude-implement.sh — Claude에게 설계 기반 구현을 시작하도록 안내하는 래퍼
#
# 사용법:
#   ./runtime/claude-implement.sh [--auto] <task-id>
#
# 환경변수:
#   CLAUDE_AUTO=1        — --auto 와 동일 (Claude CLI 자동 호출 시도)
#   CLAUDE_AUTO_FORCE=1  — Claude Code 세션 안에서도 자동 호출 허용 (재귀 가드 우회)
#
# 전제 조건:
#   - Python 3.8+ 이 PATH에 존재 (python3 / python / py -3)
#   - design.md가 Codex에 의해 완성되어 있어야 한다 (Status: ready 이상)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=runtime/lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=runtime/lib/invoke-claude.sh
. "$SCRIPT_DIR/lib/invoke-claude.sh"

# --- 인자 파싱 ---
AUTO_MODE="0"
DONE_MODE="0"
POS=()
for arg in "$@"; do
    case "$arg" in
        --auto) AUTO_MODE="1" ;;
        --done) DONE_MODE="1" ;;
        --help|-h)
            echo "사용법: $0 [--auto] [--done] <task-id>"
            echo "  --done : 구현 완료 후 산출물 계약(impl-notes + artifact) 검증 (done-gate)"
            exit 0
            ;;
        *) POS+=("$arg") ;;
    esac
done
if truthy "${CLAUDE_AUTO:-}"; then AUTO_MODE="1"; fi

if [ "${#POS[@]}" -lt 1 ]; then
    echo "사용법: $0 [--auto] [--done] <task-id>"
    echo "예시:  $0 task-001"
    exit 1
fi

TASK_ID="${POS[0]}"
TASK_DIR="$PROJECT_ROOT/kb/tasks/$TASK_ID"
DESIGN_FILE="$TASK_DIR/design.md"
IMPL_NOTES="$TASK_DIR/implementation-notes.md"
IMPL_TEMPLATE="$PROJECT_ROOT/templates/implementation-notes.md"
VALIDATOR_CLI="$PROJECT_ROOT/runtime/validator/cli.py"

run_validator() {
    local file="$1"
    local py
    if ! py=$(resolve_python); then
        echo "[ERROR] Python 3 을 찾을 수 없습니다."
        echo "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        return 2
    fi
    # shellcheck disable=SC2086
    $py "$VALIDATOR_CLI" "$file"
}

# --- --done: 완료 검증 모드 (구현 후 산출물 계약 확인; done-gate) ---
# 구현 시작 흐름과 분리된 독립 모드. cli.py --check-done 으로 impl-notes + artifact 를 검사.
if truthy "$DONE_MODE"; then
    if ! py=$(resolve_python); then
        echo "[ERROR] Python 3 을 찾을 수 없습니다."
        echo "        Python 3.8+ 을 설치하세요: https://www.python.org/downloads/"
        exit 2
    fi
    # shellcheck disable=SC2086
    $py "$VALIDATOR_CLI" --check-done "$TASK_ID"
    exit $?
fi

# --- design.md 존재 확인 ---
if [ ! -f "$DESIGN_FILE" ]; then
    echo "[ERROR] 설계 문서가 없습니다: $DESIGN_FILE"
    echo "        먼저 Codex에게 설계를 요청하세요:"
    echo "        ./runtime/codex-design.sh $TASK_ID \"<작업 설명>\""
    exit 1
fi

echo "[OK] 설계 문서 확인: $DESIGN_FILE"

# --- 종합 검증 ---
# cli.py / run_validator 종료 코드:
#   0  = 통과
#   1  = 설계 검증 실패 (보완 필요)
#   2+ = 환경 오류 (Python 미설치 / IO / 디코딩 오류 등)
set +e
run_validator "$DESIGN_FILE"
validator_rc=$?
set -e
if [ "$validator_rc" -eq 1 ]; then
    echo ""
    echo "설계 문서 검증 실패. 구현을 시작하지 않습니다 (CLAUDE.md 규약에 따름)."
    exit 1
elif [ "$validator_rc" -ge 2 ]; then
    echo ""
    echo "환경 오류 (Python 미설치/IO 오류 등). 검증을 수행할 수 없어 구현을 시작하지 않습니다."
    exit "$validator_rc"
fi

# --- implementation-notes.md 초안 생성 ---
if [ ! -f "$IMPL_NOTES" ]; then
    if [ -f "$IMPL_TEMPLATE" ]; then
        sed "s|task-<NNN>|$TASK_ID|g" "$IMPL_TEMPLATE" > "$IMPL_NOTES"
        echo "[OK] 구현 노트 초안 생성: $IMPL_NOTES"
    else
        echo "[WARN] 구현 노트 템플릿 없음. 빈 파일을 생성합니다."
        echo "# 구현 노트 — $TASK_ID" > "$IMPL_NOTES"
    fi
else
    echo "[INFO] 구현 노트 이미 존재: $IMPL_NOTES"
fi

# --- Claude 호출 (라이브러리 위임, 수동이 기본) ---
# D2: --auto 인데 CLI 부재/호출 실패면 invoke_claude_if_enabled 가 NON-ZERO 를
#     반환한다. 그 경우 전체 러너도 NON-ZERO 로 종료한다 (요청한 자동 작업 실패).
#     수동 모드 / 재귀 가드 스킵은 0 을 반환하므로 정상 종료.
echo ""
set +e
invoke_claude_if_enabled "$TASK_ID" "$DESIGN_FILE" "$IMPL_NOTES" "$AUTO_MODE" "$PROJECT_ROOT"
invoke_rc=$?
set -e

# provenance (task-004): 자동 호출이 실제 성공했을 때만 manifest 에 기록.
MANIFEST_FILE="$TASK_DIR/manifest.md"
if [ "$invoke_rc" -eq 0 ] && [ -n "${CWC_PROV_LINE:-}" ]; then
    if [ -f "$MANIFEST_FILE" ]; then
        printf -- '- **generated_by**: %s\n' "$CWC_PROV_LINE" >> "$MANIFEST_FILE"
        echo "[OK] provenance 기록: $MANIFEST_FILE"
    else
        echo "[WARN] manifest 없음 — provenance 기록 건너뜀: $MANIFEST_FILE"
    fi
fi

# --- 구현 안내 출력 ---
echo ""
echo "============================================"
echo " Claude 구현 준비 완료: $TASK_ID"
echo "============================================"
echo ""
echo "Claude에게 다음과 같이 요청하세요:"
echo ""
echo "  $TASK_ID 의 설계 문서를 읽고 구현을 시작해주세요."
echo "  설계 문서: $DESIGN_FILE"
echo "  구현 노트: $IMPL_NOTES"
echo ""
echo "Claude는 CLAUDE.md 규약에 따라:"
echo "  1. design.md를 먼저 읽습니다."
echo "  2. 구현 중 변경이 생기면 implementation-notes.md에 기록합니다."
echo "  3. 완료 후 kb/artifacts/${TASK_ID}-summary.md를 생성합니다."
echo "  4. kb/index/status.md를 갱신합니다."

# D2: 자동 호출 실패 시 러너도 실패로 종료.
exit "$invoke_rc"
