#!/usr/bin/env bash
# codex-design.sh — Codex에게 설계 문서 생성을 요청하는 래퍼
#
# 사용법:
#   ./runtime/codex-design.sh [--auto] <task-id> "<작업 설명>"
#
# 환경변수:
#   CODEX_AUTO=1        — --auto 와 동일 (자동 호출 시도)
#   CODEX_AUTO_FORCE=1  — Claude Code 세션 안에서도 자동 호출 허용 (재귀 가드 우회)
#
# 전제 조건:
#   - Python 3.8+ 이 PATH에 존재 (python3 / python / py -3)
#   - codex CLI는 선택 — 미설치 시 수동 작성 안내로 전환

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=runtime/lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=runtime/lib/invoke-codex.sh
. "$SCRIPT_DIR/lib/invoke-codex.sh"

# --- 인자 파싱 (--auto 어디든 허용) ---
AUTO_MODE="0"
POS=()
for arg in "$@"; do
    case "$arg" in
        --auto) AUTO_MODE="1" ;;
        --help|-h)
            echo "사용법: $0 [--auto] <task-id> <작업 설명>"
            exit 0
            ;;
        *) POS+=("$arg") ;;
    esac
done
if truthy "${CODEX_AUTO:-}"; then AUTO_MODE="1"; fi

if [ "${#POS[@]}" -lt 2 ]; then
    echo "사용법: $0 [--auto] <task-id> <작업 설명>"
    echo "예시:  $0 task-001 \"사용자 인증 모듈 설계\""
    exit 1
fi

TASK_ID="${POS[0]}"
TASK_DESC="${POS[1]}"
TASK_DIR="$PROJECT_ROOT/kb/tasks/$TASK_ID"
DESIGN_FILE="$TASK_DIR/design.md"
TEMPLATE="$PROJECT_ROOT/templates/design.md"
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

# --- 디렉터리 생성 ---
if [ -d "$TASK_DIR" ]; then
    echo "[INFO] 디렉터리 이미 존재: $TASK_DIR"
else
    mkdir -p "$TASK_DIR"
    echo "[OK] 디렉터리 생성: $TASK_DIR"
fi

# --- 설계 문서 초안 생성 ---
if [ -f "$DESIGN_FILE" ]; then
    echo "[WARN] 설계 문서 이미 존재: $DESIGN_FILE"
    echo "       덮어쓰려면 기존 파일을 먼저 삭제하세요."
    exit 1
fi

if [ -f "$TEMPLATE" ]; then
    sed "s|task-<NNN>|$TASK_ID|g" "$TEMPLATE" > "$DESIGN_FILE"
    echo "[OK] 설계 문서 초안 생성: $DESIGN_FILE"
else
    echo "[ERROR] 템플릿 파일 없음: $TEMPLATE"
    exit 1
fi

# --- manifest 초안 생성 (Phase A: 기본 로드 세트 최소화) ---
MANIFEST_FILE="$TASK_DIR/manifest.md"
MANIFEST_TEMPLATE="$PROJECT_ROOT/templates/manifest.md"
if [ -f "$MANIFEST_FILE" ]; then
    echo "[INFO] manifest 이미 존재: $MANIFEST_FILE"
elif [ -f "$MANIFEST_TEMPLATE" ]; then
    sed "s|task-<NNN>|$TASK_ID|g" "$MANIFEST_TEMPLATE" > "$MANIFEST_FILE"
    echo "[OK] manifest 초안 생성: $MANIFEST_FILE"
else
    echo "[WARN] manifest 템플릿 없음: $MANIFEST_TEMPLATE (건너뜀)"
fi

# --- Codex 호출 (라이브러리 위임) ---
# D2: --auto 인데 codex CLI 부재/호출 실패면 invoke_codex_if_enabled 가
#     NON-ZERO 를 반환한다. 그 코드를 기억해 두었다가 최종 종료에 반영한다.
set +e
invoke_codex_if_enabled "$TASK_ID" "$DESIGN_FILE" "$TASK_DESC" "$AUTO_MODE" "$PROJECT_ROOT"
invoke_rc=$?
set -e

# --- 후검증 ---
# cli.py / run_validator 종료 코드:
#   0  = 통과
#   1  = 설계 검증 실패 (보완 필요)
#   2+ = 환경 오류 (Python 미설치 / IO / 디코딩 오류 등)
echo ""
echo "--- 설계 완성 검증 ---"
set +e
run_validator "$DESIGN_FILE"
validator_rc=$?
set -e

if [ "$validator_rc" -ge 2 ]; then
    echo ""
    echo "환경 오류 (Python 미설치/IO 오류 등). 설계 검증을 수행할 수 없습니다."
    exit "$validator_rc"
elif [ "$validator_rc" -eq 0 ]; then
    # provenance (task-004): --auto 호출 성공 + 검증 통과 시에만 manifest 에 기록.
    if [ "$invoke_rc" -eq 0 ] && [ -n "${CWC_PROV_LINE:-}" ]; then
        if [ -f "$MANIFEST_FILE" ]; then
            printf -- '- **generated_by**: %s\n' "$CWC_PROV_LINE" >> "$MANIFEST_FILE"
            echo "[OK] provenance 기록: $MANIFEST_FILE"
        else
            echo "[WARN] manifest 없음 — provenance 기록 건너뜀: $MANIFEST_FILE"
        fi
    fi
    echo ""
    echo "--- 다음 단계 ---"
    echo "1. $DESIGN_FILE 의 설계 내용을 최종 검토하세요."
    echo "2. Claude에게 구현을 요청하세요:"
    echo "   ./runtime/claude-implement.sh $TASK_ID"
    # 검증은 통과했지만 --auto codex 호출이 실패했다면 그 실패를 전파한다 (D2).
    if [ "$invoke_rc" -ne 0 ]; then
        echo ""
        echo "[WARN] 단, codex 자동 호출이 실패했습니다 (exit $invoke_rc)."
        exit "$invoke_rc"
    fi
else
    echo ""
    echo "--- 보완 필요 ---"
    echo "1. $DESIGN_FILE 을 열어 누락된 부분을 채우세요."
    echo "2. Status를 'ready'로 변경하세요."
    echo "3. 모든 placeholder 안내문을 실제 내용으로 교체하세요."
    echo "4. 완성 후 구현을 요청하세요:"
    echo "   ./runtime/claude-implement.sh $TASK_ID"
    exit 1
fi
