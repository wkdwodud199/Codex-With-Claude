#!/usr/bin/env bash
# codex-design.sh — Codex에게 설계 문서 생성을 요청하는 래퍼
#
# 사용법:
#   ./runtime/codex-design.sh <task-id> "<작업 설명>"
#
# 예시:
#   ./runtime/codex-design.sh task-001 "사용자 인증 모듈 설계"
#
# 이 스크립트는 다음을 수행한다:
#   1. kb/tasks/<task-id>/ 디렉터리 생성
#   2. 템플릿으로부터 design.md 초안 생성
#   3. Codex에게 설계 작성을 요청 (codex CLI 사용)
#   4. claude-implement와 동일한 수준으로 설계 완성 여부를 후검증
#
# 전제 조건:
#   - codex CLI가 설치되어 있어야 한다 (openai/codex 또는 호환 도구)
#   - 프로젝트 루트에서 실행해야 한다

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- 인자 검증 ---
if [ $# -lt 2 ]; then
    echo "사용법: $0 <task-id> <작업 설명>"
    echo "예시:  $0 task-001 \"사용자 인증 모듈 설계\""
    exit 1
fi

TASK_ID="$1"
TASK_DESC="$2"
TASK_DIR="$PROJECT_ROOT/kb/tasks/$TASK_ID"
DESIGN_FILE="$TASK_DIR/design.md"
TEMPLATE="$PROJECT_ROOT/templates/design.md"

# =============================================================================
# validate_design_file — 설계 문서 종합 검증
# claude-implement.sh와 동일한 검증 로직을 공유한다.
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
        return 1
    fi

    return 0
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

# 템플릿 복사 후 task-id 치환
if [ -f "$TEMPLATE" ]; then
    sed "s/task-<NNN>/$TASK_ID/g" "$TEMPLATE" > "$DESIGN_FILE"
    echo "[OK] 설계 문서 초안 생성: $DESIGN_FILE"
else
    echo "[ERROR] 템플릿 파일 없음: $TEMPLATE"
    exit 1
fi

# --- Codex 호출 ---
CODEX_CALLED=false
if command -v codex &> /dev/null; then
    echo "[INFO] Codex에게 설계 요청 중..."
    echo ""
    CODEX_PROMPT="다음 작업에 대한 설계 문서를 작성해주세요. 작업: $TASK_DESC. 설계 문서 경로: $DESIGN_FILE. 참조할 기존 문서: $PROJECT_ROOT/kb/concepts/. 중요 규칙: 템플릿의 모든 필수 섹션(목표, 범위, 제약, 구현 단계, 파일/모듈 영향, 테스트 기준, 오픈 이슈)을 빠짐없이 채우세요. 모든 placeholder 안내문을 실제 내용으로 교체하세요. 완성 후 문서 상단의 Status를 ready로 변경하세요. Inputs, Outputs, Next step 필드를 구체적으로 채우세요. 파일/모듈 영향 테이블과 테스트 기준 체크박스에 실제 항목을 기입하세요."
    echo "" | codex exec --full-auto --skip-git-repo-check -C "$PROJECT_ROOT" "$CODEX_PROMPT"
    echo ""
    CODEX_CALLED=true
else
    echo "[WARN] codex CLI를 찾을 수 없습니다."
    echo "       수동으로 설계 문서를 작성하거나 codex를 설치하세요."
    echo "       설계 문서 초안 위치: $DESIGN_FILE"
fi

# --- 후검증 (claude-implement와 동일 수준) ---
echo ""
echo "--- 설계 완성 검증 ---"
if validate_design_file "$DESIGN_FILE"; then
    echo "[OK] 설계 문서가 완성 상태입니다."
    echo ""
    echo "--- 다음 단계 ---"
    echo "1. $DESIGN_FILE 의 설계 내용을 최종 검토하세요."
    echo "2. Claude에게 구현을 요청하세요:"
    echo "   ./runtime/claude-implement.sh $TASK_ID"
else
    echo ""
    if [ "$CODEX_CALLED" = true ]; then
        echo "[INFO] Codex가 설계를 생성했지만 아직 완성 기준을 충족하지 않습니다."
    fi
    echo ""
    echo "--- 보완 필요 ---"
    echo "1. $DESIGN_FILE 을 열어 누락된 부분을 채우세요."
    echo "2. Status를 'ready'로 변경하세요."
    echo "3. 모든 placeholder 안내문을 실제 내용으로 교체하세요."
    echo "4. 완성 후 구현을 요청하세요:"
    echo "   ./runtime/claude-implement.sh $TASK_ID"
    exit 1
fi
