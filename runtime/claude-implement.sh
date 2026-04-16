#!/usr/bin/env bash
# claude-implement.sh — Claude에게 설계 기반 구현을 시작하도록 안내하는 래퍼
#
# 사용법:
#   ./runtime/claude-implement.sh <task-id>
#
# 예시:
#   ./runtime/claude-implement.sh task-001
#
# 이 스크립트는 다음을 수행한다:
#   1. design.md 존재 여부 확인
#   2. 필수 섹션 검증
#   3. placeholder/draft 상태 차단
#   4. 필수 메타 필드 존재 및 내용 검증
#   5. 검증 통과 시 Claude에게 구현 컨텍스트 제공
#
# 전제 조건:
#   - 프로젝트 루트에서 실행해야 한다
#   - design.md가 Codex에 의해 작성 완료되어 있어야 한다 (Status: ready 이상)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- 인자 검증 ---
if [ $# -lt 1 ]; then
    echo "사용법: $0 <task-id>"
    echo "예시:  $0 task-001"
    exit 1
fi

TASK_ID="$1"
TASK_DIR="$PROJECT_ROOT/kb/tasks/$TASK_ID"
DESIGN_FILE="$TASK_DIR/design.md"
IMPL_NOTES="$TASK_DIR/implementation-notes.md"
IMPL_TEMPLATE="$PROJECT_ROOT/templates/implementation-notes.md"

# =============================================================================
# validate_design_file — 설계 문서 종합 검증
#
# 검증 항목:
#   1. 필수 7개 섹션 존재
#   2. Status가 ready 또는 done (draft/blocked 차단)
#   3. 템플릿 placeholder 문구 잔존 여부
#   4. 빈 표/빈 리스트 검사
#   5. 필수 메타 필드(Inputs, Outputs, Next step) 존재 및 빈 값 검사
# =============================================================================
validate_design_file() {
    local file="$1"
    local errors=()

    # --- 1. 필수 섹션 존재 검사 ---
    local required_sections=(
        "목표 (Objective)"
        "범위 (Scope)"
        "제약 (Constraints)"
        "구현 단계 (Implementation Steps)"
        "파일/모듈 영향 (Affected Files/Modules)"
        "테스트 기준 (Test Criteria)"
        "오픈 이슈 (Open Issues)"
    )

    for section in "${required_sections[@]}"; do
        if ! grep -q "$section" "$file"; then
            errors+=("[섹션 누락] $section")
        fi
    done

    # --- 2. Status 검사 (ready 또는 done만 허용) ---
    if grep -q "^> Status:" "$file"; then
        local status_value
        status_value=$(grep "^> Status:" "$file" | head -1 | sed 's/^> Status:[[:space:]]*//')
        case "$status_value" in
            ready|done)
                ;; # 통과
            draft)
                errors+=("[상태 차단] Status: draft — 설계가 아직 미완성입니다. Status를 'ready'로 변경하세요.")
                ;;
            blocked)
                errors+=("[상태 차단] Status: blocked — 설계가 차단 상태입니다.")
                ;;
            in-progress)
                errors+=("[상태 차단] Status: in-progress — 설계가 아직 작성 중입니다.")
                ;;
            *)
                errors+=("[상태 오류] Status: '$status_value' — 허용 값: ready, done")
                ;;
        esac
    else
        errors+=("[상태 누락] '> Status:' 필드가 없습니다. design.md 상단에 추가하세요.")
    fi

    # --- 3. 템플릿 placeholder 잔존 검사 ---
    local placeholders=(
        "(이 작업이 달성하려는 것을 1-2문장으로 기술)"
        "(이 작업에 포함되는 것과 포함되지 않는 것을 명시)"
        "(기술적, 시간적, 또는 기타 제약 조건)"
        "(설계 시점에 해결되지 않은 질문이나 리스크)"
        "task-<NNN>"
        "(이 설계가 의존하는 입력 나열)"
        "(이 설계가 생성할 산출물 나열)"
        "(구현 완료 후 다음 단계 기술)"
    )

    for ph in "${placeholders[@]}"; do
        if grep -qF "$ph" "$file"; then
            errors+=("[placeholder 잔존] '$ph'")
        fi
    done

    # --- 4. 빈 표/빈 리스트 검사 ---
    if grep -qE '^\|[[:space:]]*\|[[:space:]]*(create / modify / delete|create \/ modify \/ delete)[[:space:]]*\|' "$file"; then
        errors+=("[빈 내용] 파일/모듈 영향 테이블이 템플릿 기본값 그대로입니다.")
    fi

    if grep -qE '^\- \[ \][[:space:]]*$' "$file"; then
        errors+=("[빈 내용] 테스트 기준에 내용 없는 빈 체크박스가 있습니다.")
    fi

    # --- 5. 필수 메타 필드 존재 및 빈 값 검사 ---
    for field in "Inputs" "Outputs" "Next step"; do
        if grep -q "^> ${field}:" "$file"; then
            local val
            val=$(grep "^> ${field}:" "$file" | head -1 | sed "s/^> ${field}:[[:space:]]*//")
            if [ -z "$val" ] || [ "$val" = "()" ]; then
                errors+=("[빈 필드] ${field}가 비어 있습니다.")
            fi
        else
            errors+=("[필드 누락] '> ${field}:' 필드가 없습니다. design.md 상단에 추가하세요.")
        fi
    done

    # --- 결과 출력 ---
    if [ ${#errors[@]} -gt 0 ]; then
        echo ""
        echo "[FAIL] 설계 문서 검증 실패 (${#errors[@]}건):"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        echo ""
        echo "설계 문서를 보완한 후 다시 실행하세요."
        echo "구현을 시작하지 않습니다 (CLAUDE.md 규약에 따름)."
        return 1
    fi

    return 0
}

# --- design.md 존재 확인 ---
if [ ! -f "$DESIGN_FILE" ]; then
    echo "[ERROR] 설계 문서가 없습니다: $DESIGN_FILE"
    echo "        먼저 Codex에게 설계를 요청하세요:"
    echo "        ./runtime/codex-design.sh $TASK_ID \"<작업 설명>\""
    exit 1
fi

echo "[OK] 설계 문서 확인: $DESIGN_FILE"

# --- 종합 검증 ---
if ! validate_design_file "$DESIGN_FILE"; then
    exit 1
fi

echo "[OK] 설계 문서 검증 통과 (섹션, 상태, placeholder, 내용)"

# --- implementation-notes.md 초안 생성 ---
if [ ! -f "$IMPL_NOTES" ]; then
    if [ -f "$IMPL_TEMPLATE" ]; then
        sed "s/task-<NNN>/$TASK_ID/g" "$IMPL_TEMPLATE" > "$IMPL_NOTES"
        echo "[OK] 구현 노트 초안 생성: $IMPL_NOTES"
    else
        echo "[WARN] 구현 노트 템플릿 없음. 빈 파일을 생성합니다."
        echo "# 구현 노트 — $TASK_ID" > "$IMPL_NOTES"
    fi
else
    echo "[INFO] 구현 노트 이미 존재: $IMPL_NOTES"
fi

# --- Claude 구현 안내 출력 ---
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
