#!/usr/bin/env bash
# Portable shell smoke runner used when bats isn't installed locally.
# Exercises the same scenarios as tests/bats/*.bats but using only bash.
# CI installs bats and runs the real .bats files; this file is for local
# developers who want a fast pre-flight without installing bats.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/runtime" "$WORK/templates" "$WORK/kb/tasks"
cp -r "$REPO/runtime/validator" "$WORK/runtime/"
cp -r "$REPO/runtime/lib"       "$WORK/runtime/"
cp "$REPO/runtime/claude-implement.sh" "$WORK/runtime/"
cp "$REPO/runtime/codex-design.sh" "$WORK/runtime/"
cp "$REPO/templates/"* "$WORK/templates/"
chmod +x "$WORK/runtime/"*.sh

# codex-design 의 git preflight(D3)가 통과하도록 작업 디렉터리를 git 저장소로 만든다.
git init -q "$WORK" 2>/dev/null || true

# Claude Code 세션 변수를 한 번에 제거하기 위한 공통 스크럽 목록.
# (common.sh is_claude_session 이 검사하는 모든 변수를 포함해야 한다.)
SCRUB=(-u CLAUDE_CODE_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE)

fail=0
assert_status() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        printf '  [PASS] %s\n' "$desc"
    else
        printf '  [FAIL] %s (expected exit %s, got %s)\n' "$desc" "$expected" "$actual"
        fail=1
    fi
}

echo "== claude-implement smoke =="
set +e
out=$(bash "$WORK/runtime/claude-implement.sh" 2>&1); st=$?
set -e
assert_status "no args" 1 "$st"
[[ "$out" == *"사용법"* ]] || { echo "    missing '사용법'"; fail=1; }

set +e
out=$(bash "$WORK/runtime/claude-implement.sh" task-missing 2>&1); st=$?
set -e
assert_status "missing design" 1 "$st"
[[ "$out" == *"설계 문서가 없습니다"* ]] || { echo "    missing '설계 문서가 없습니다'"; fail=1; }

mkdir -p "$WORK/kb/tasks/task-x"
sed 's/task-<NNN>/task-x/g' "$WORK/templates/design.md" > "$WORK/kb/tasks/task-x/design.md"
set +e
out=$(bash "$WORK/runtime/claude-implement.sh" task-x 2>&1); st=$?
set -e
assert_status "draft -> reject" 1 "$st"
[[ "$out" == *"FAIL"* ]] || { echo "    missing 'FAIL'"; fail=1; }

mkdir -p "$WORK/kb/tasks/task-y"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-y/design.md"
set +e
out=$(bash "$WORK/runtime/claude-implement.sh" task-y 2>&1); st=$?
set -e
assert_status "good -> accept" 0 "$st"
[ -f "$WORK/kb/tasks/task-y/implementation-notes.md" ] || { echo "    impl-notes missing"; fail=1; }
[[ "$out" == *"수동 모드"* ]] || { echo "    manual-mode banner missing"; fail=1; }

# --auto in Claude Code session -> recursion guard (no claude CLI call)
mkdir -p "$WORK/kb/tasks/task-y2"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-y2/design.md"
set +e
out=$(CLAUDE_CODE_SESSION=1 bash "$WORK/runtime/claude-implement.sh" --auto task-y2 2>&1); st=$?
set -e
assert_status "--auto in session -> guard" 0 "$st"
[[ "$out" == *"재귀 방지"* ]] || { echo "    recursion-guard banner missing"; fail=1; }

# --auto with no claude CLI (outside session) -> warn, NON-ZERO (D2)
# 요청한 자동 작업(claude 호출)을 수행하지 못했으므로 실패로 종료해야 한다.
mkdir -p "$WORK/kb/tasks/task-y3"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-y3/design.md"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/claude-implement.sh" --auto task-y3 2>&1); st=$?
set -e
if [ "$st" -ne 0 ]; then
    printf '  [PASS] %s\n' "--auto, no claude CLI -> NON-ZERO (D2)"
else
    printf '  [FAIL] %s (expected non-zero, got %s)\n' "--auto, no claude CLI -> NON-ZERO (D2)" "$st"
    fail=1
fi
[[ "$out" == *"claude CLI를 찾을 수 없습니다"* ]] || { echo "    no-CLI banner missing"; fail=1; }

echo ""
echo "== codex-design smoke =="
set +e
out=$(bash "$WORK/runtime/codex-design.sh" 2>&1); st=$?
set -e
assert_status "no args" 1 "$st"

set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" task-a "sample" 2>&1); st=$?
set -e
assert_status "no codex + raw draft -> fail" 1 "$st"
# Phase A: 새 task 생성 시 manifest.md 가 자동 생성되어야 한다 (FRICTION#1 해소)
if [ -f "$WORK/kb/tasks/task-a/manifest.md" ]; then
    printf '  [PASS] %s\n' "manifest.md auto-generated (Phase A)"
else
    printf '  [FAIL] %s\n' "manifest.md not auto-generated"; fail=1
fi
[ -f "$WORK/kb/tasks/task-a/design.md" ] || { echo "    draft not created"; fail=1; }

mkdir -p "$WORK/kb/tasks/task-b"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-b/design.md"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" task-b "sample" 2>&1); st=$?
set -e
assert_status "refuse overwrite" 1 "$st"
[[ "$out" == *"이미 존재"* ]] || { echo "    missing '이미 존재'"; fail=1; }

# --auto + codex stub on PATH + draft remains broken -> post-validation fails
cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$WORK/codex"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" --auto task-c "sample" 2>&1); st=$?
set -e
assert_status "--auto + codex stub -> stub invoked, validation fails" 1 "$st"
[[ "$out" == *"Codex"* ]] || { echo "    no 'Codex' reference"; fail=1; }

# default (no --auto) + codex stub present -> still skips invocation
mkdir -p "$WORK/kb/tasks/task-d-parent"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" task-d "sample" 2>&1); st=$?
set -e
assert_status "default + codex stub -> skip (manual)" 1 "$st"
[[ "$out" == *"수동 모드"* ]] || { echo "    manual-mode banner missing (codex)"; fail=1; }

# --auto + codex 가 유효한 design 을 썼지만 non-zero 로 종료 -> 실패 전파 (D2)
# (검증은 통과하더라도 codex 의 비정상 종료를 삼키지 않는지 확인하는 분기 119-122 커버)
cat > "$WORK/codex" <<EOF
#!/usr/bin/env bash
mkdir -p "$WORK/kb/tasks/task-e"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-e/design.md"
exit 7
EOF
chmod +x "$WORK/codex"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" --auto task-e "sample" 2>&1); st=$?
set -e
if [ "$st" -ne 0 ] && [[ "$out" == *"codex 자동 호출이 실패"* ]]; then
    printf '  [PASS] %s\n' "--auto + codex 비정상 종료(유효 design) -> 전파 (D2)"
else
    printf '  [FAIL] %s (exit=%s, expected non-zero + 전파 배너)\n' "--auto + codex non-zero 전파 (D2)" "$st"
    fail=1
fi


# C-2: --done 러너 통합 경로 smoke
echo ""
echo "== --done smoke =="
# legacy task-001 → done-gate 통과 (exit 0)
mkdir -p "$WORK/kb/tasks/task-001"
set +e
out=$(bash "$WORK/runtime/claude-implement.sh" --done task-001 2>&1); st=$?
set -e
assert_status "--done legacy task-001 -> exit 0 (C-2)" 0 "$st"
[[ "$out" == *"legacy"* ]] || { echo "    legacy 배너 없음"; fail=1; }

# 미완성 task → done-gate 실패 (exit 1)
mkdir -p "$WORK/kb/tasks/task-z"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-z/design.md"
sed "s|task-<NNN>|task-z|g" "$WORK/templates/implementation-notes.md" \
    > "$WORK/kb/tasks/task-z/implementation-notes.md"
set +e
out=$(bash "$WORK/runtime/claude-implement.sh" --done task-z 2>&1); st=$?
set -e
assert_status "--done incomplete task -> exit 1 (C-2)" 1 "$st"
[[ "$out" == *"FAIL"* ]] || { echo "    FAIL 배너 없음"; fail=1; }

echo ""
if [ $fail -eq 0 ]; then
    echo "[OK] All smoke tests passed."
    exit 0
else
    echo "[FAIL] Some smoke tests failed."
    exit 1
fi
