#!/usr/bin/env bash
# Portable shell smoke runner used when bats isn't installed locally.
# Exercises the same scenarios as tests/bats/*.bats but using only bash.
# CI installs bats and runs the real .bats files; this file is for local
# developers who want a fast pre-flight without installing bats.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/runtime/config" "$WORK/templates" "$WORK/kb/tasks"
cp -r "$REPO/runtime/validator" "$WORK/runtime/"
cp -r "$REPO/runtime/lib"       "$WORK/runtime/"
cp "$REPO/runtime/claude-implement.sh" "$WORK/runtime/"
cp "$REPO/runtime/codex-design.sh" "$WORK/runtime/"
cp "$REPO/runtime/render-prompt.py" "$WORK/runtime/"
cp "$REPO/runtime/review-design.sh" "$WORK/runtime/"
cp "$REPO/runtime/config/model-profiles.json" "$WORK/runtime/config/"
# templates/prompts/ 하위 디렉터리 포함 복사 (task-004)
cp -R "$REPO/templates/." "$WORK/templates/"
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
# (task-004: 스텁은 --version preflight 에 응답해야 한다)
cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
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
cat > "$WORK/codex" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
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


# task-004: 모델/effort 강제 + 설계 주도 라우팅 + provenance smoke
echo ""
echo "== model/effort enforcement smoke (task-004) =="

# (1) --auto 성공 경로: 강제 플래그(-m/-c) 전달 + --skip-git-repo-check 부재 + provenance 기록
cat > "$WORK/codex" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
printf '%s\n' "\$*" >> "$WORK/codex-args.log"
mkdir -p "$WORK/kb/tasks/task-f"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-f/design.md"
exit 0
EOF
chmod +x "$WORK/codex"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" --auto task-f "sample" 2>&1); st=$?
set -e
assert_status "--auto full pass -> exit 0" 0 "$st"
args=$(cat "$WORK/codex-args.log" 2>/dev/null || true)
[[ "$args" == *"-m gpt-5.5"* ]] || { echo "    -m gpt-5.5 missing: $args"; fail=1; }
[[ "$args" == *"model_reasoning_effort=xhigh"* ]] || { echo "    reasoning_effort=xhigh missing"; fail=1; }
[[ "$args" == *"--sandbox workspace-write"* ]] || { echo "    sandbox flag missing"; fail=1; }
[[ "$args" != *"--skip-git-repo-check"* ]] || { echo "    --skip-git-repo-check present (금지)"; fail=1; }
grep -q "generated_by.*design=codex gpt-5.5/xhigh" "$WORK/kb/tasks/task-f/manifest.md" \
    || { echo "    provenance missing in manifest"; fail=1; }

# (2) claude --auto: 실행 계획 라우팅 (good.md -> claude-opus-4-8/xhigh) + provenance
cat > "$WORK/claude" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "2.99.0 (Claude Code)"; exit 0; fi
printf '%s\n' "\$*" >> "$WORK/claude-args.log"
exit 0
EOF
chmod +x "$WORK/claude"
mkdir -p "$WORK/kb/tasks/task-r"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-r/design.md"
sed 's/task-<NNN>/task-r/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-r/manifest.md"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/claude-implement.sh" --auto task-r 2>&1); st=$?
set -e
assert_status "claude --auto routed by execution plan" 0 "$st"
args=$(cat "$WORK/claude-args.log" 2>/dev/null || true)
[[ "$args" == *"--model claude-opus-4-8"* ]] || { echo "    --model 누락: $args"; fail=1; }
[[ "$args" == *"--effort xhigh"* ]] || { echo "    --effort xhigh 누락"; fail=1; }
grep -q "generated_by.*route=execution-plan" "$WORK/kb/tasks/task-r/manifest.md" \
    || { echo "    provenance(route=execution-plan) missing"; fail=1; }

# (3) legacy(실행 계획 부재) -> 기본값 라우팅 + WARN + provenance(route=default)
rm -f "$WORK/claude-args.log"
mkdir -p "$WORK/kb/tasks/task-001"
cp "$REPO/tests/validator/fixtures/legacy-no-execution-plan.md" "$WORK/kb/tasks/task-001/design.md"
sed 's/task-<NNN>/task-001/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-001/manifest.md"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/claude-implement.sh" --auto task-001 2>&1); st=$?
set -e
assert_status "legacy no-plan -> default route" 0 "$st"
[[ "$out" == *"기본값으로 라우팅"* ]] || { echo "    default-route WARN missing"; fail=1; }
args=$(cat "$WORK/claude-args.log" 2>/dev/null || true)
[[ "$args" == *"--effort high"* ]] || { echo "    default --effort high 누락: $args"; fail=1; }
grep -q "generated_by.*route=default" "$WORK/kb/tasks/task-001/manifest.md" \
    || { echo "    provenance(route=default) missing"; fail=1; }

# (4) 프로필 부재 -> codex --auto 거부 (조용한 기본값 금지)
mv "$WORK/runtime/config/model-profiles.json" "$WORK/model-profiles.json.bak"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" --auto task-g "sample" 2>&1); st=$?
set -e
if [ "$st" -ne 0 ] && [[ "$out" == *"프로필"* ]]; then
    printf '  [PASS] %s\n' "profile missing -> codex --auto refused"
else
    printf '  [FAIL] %s (exit=%s)\n' "profile missing -> codex --auto refused" "$st"; fail=1
fi

# (5) 프로필 부재 -> claude 경로도 거부 (validator 게이트가 exit 2)
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/claude-implement.sh" --auto task-r 2>&1); st=$?
set -e
if [ "$st" -ne 0 ] && [[ "$out" == *"프로필"* ]]; then
    printf '  [PASS] %s\n' "profile missing -> claude gate refused"
else
    printf '  [FAIL] %s (exit=%s)\n' "profile missing -> claude gate refused" "$st"; fail=1
fi
mv "$WORK/model-profiles.json.bak" "$WORK/runtime/config/model-profiles.json"

# (6) CLI 버전 미달 -> 호출 전 실패 (preflight)
cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex-cli 0.1.0"; exit 0; fi
exit 0
EOF
chmod +x "$WORK/codex"
set +e
out=$(env "${SCRUB[@]}" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/codex-design.sh" --auto task-h "sample" 2>&1); st=$?
set -e
if [ "$st" -ne 0 ] && [[ "$out" == *"버전"* ]]; then
    printf '  [PASS] %s\n' "CLI version below minimum -> preflight fail"
else
    printf '  [FAIL] %s (exit=%s)\n' "CLI version below minimum -> preflight fail" "$st"; fail=1
fi


# task-005: 설계 교차검토(review-design) smoke
echo ""
echo "== review-design smoke (task-005) =="
mkdir -p "$WORK/kb/tasks/task-rv"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-rv/design.md"
sed 's/task-<NNN>/task-rv/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-rv/manifest.md"

# (1) 정상(fable) -> review 파일 + 강제 플래그 + provenance(fallback=false) + design.md 불변
cat > "$WORK/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "2.99.0 (Claude Code)"; exit 0; fi
printf '%s\n' "$*" >> "$WORK/rv-args.log"
echo '{"result":"## 요약\n좋음\n## 주요 우려\n없음","modelUsage":{"claude-fable-5-20260930":{"outputTokens":9}}}'
exit 0
EOF
chmod +x "$WORK/claude"
before=$(shasum -a 256 "$WORK/kb/tasks/task-rv/design.md" | awk '{print $1}')
set +e
out=$(env "${SCRUB[@]}" WORK="$WORK" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/review-design.sh" task-rv 2>&1); st=$?
set -e
assert_status "review-design fable -> exit 0" 0 "$st"
[ -f "$WORK/kb/tasks/task-rv/design-review.md" ] || { echo "    review file missing"; fail=1; }
args=$(cat "$WORK/rv-args.log" 2>/dev/null || true)
[[ "$args" == *"--model claude-fable-5"* ]] || { echo "    --model 누락: $args"; fail=1; }
[[ "$args" == *"--effort max"* ]] || { echo "    --effort max 누락"; fail=1; }
[[ "$args" == *"--fallback-model claude-opus-4-8"* ]] || { echo "    --fallback-model 누락"; fail=1; }
[[ "$args" == *"--output-format json"* ]] || { echo "    --output-format json 누락"; fail=1; }
grep -q "cross_reviewed_by.*fallback=false" "$WORK/kb/tasks/task-rv/manifest.md" \
    || { echo "    provenance(fallback=false) missing"; fail=1; }
after=$(shasum -a 256 "$WORK/kb/tasks/task-rv/design.md" | awk '{print $1}')
[ "$before" = "$after" ] || { echo "    design.md 가 변경됨(읽기전용 위반)"; fail=1; }

# (2) fallback(opus) -> exit 0 + provenance fallback=true
mkdir -p "$WORK/kb/tasks/task-rw"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-rw/design.md"
sed 's/task-<NNN>/task-rw/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-rw/manifest.md"
cat > "$WORK/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "2.99.0 (Claude Code)"; exit 0; fi
echo '{"result":"검토","model":"claude-opus-4-8"}'
exit 0
EOF
chmod +x "$WORK/claude"
set +e
out=$(env "${SCRUB[@]}" WORK="$WORK" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/review-design.sh" task-rw 2>&1); st=$?
set -e
assert_status "review-design fallback(opus) -> exit 0" 0 "$st"
grep -q "cross_reviewed_by.*fallback=true" "$WORK/kb/tasks/task-rw/manifest.md" \
    || { echo "    provenance(fallback=true) missing"; fail=1; }

# (3) unknown model -> 실패, review 파일/ provenance 없음
mkdir -p "$WORK/kb/tasks/task-ru"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-ru/design.md"
sed 's/task-<NNN>/task-ru/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-ru/manifest.md"
cat > "$WORK/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "2.99.0 (Claude Code)"; exit 0; fi
echo '{"result":"x","model":"claude-sonnet-5"}'
exit 0
EOF
chmod +x "$WORK/claude"
set +e
out=$(env "${SCRUB[@]}" WORK="$WORK" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/review-design.sh" task-ru 2>&1); st=$?
set -e
if [ "$st" -ne 0 ] && [ ! -f "$WORK/kb/tasks/task-ru/design-review.md" ]; then
    printf '  [PASS] %s\n' "review-design unknown model -> fail, no artifact"
else
    printf '  [FAIL] %s (exit=%s)\n' "review-design unknown model -> fail" "$st"; fail=1
fi

# (4) 세션 내부 -> 재귀 가드 스킵(exit 0), review 파일 없음
set +e
out=$(env WORK="$WORK" CLAUDE_CODE_SESSION=1 PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/review-design.sh" task-ru 2>&1); st=$?
set -e
assert_status "review-design in session -> guard exit 0" 0 "$st"
[[ "$out" == *"재귀 방지"* ]] || { echo "    recursion-guard banner missing"; fail=1; }

# (5) 프로필 부재 -> 실패
set +e
mv "$WORK/runtime/config/model-profiles.json" "$WORK/mp.bak"
out=$(env "${SCRUB[@]}" WORK="$WORK" PATH="$WORK:/usr/bin:/bin" \
    bash "$WORK/runtime/review-design.sh" task-rv 2>&1); st=$?
mv "$WORK/mp.bak" "$WORK/runtime/config/model-profiles.json"
set -e
if [ "$st" -ne 0 ] && [[ "$out" == *"프로필"* ]]; then
    printf '  [PASS] %s\n' "review-design profile missing -> fail"
else
    printf '  [FAIL] %s (exit=%s)\n' "review-design profile missing -> fail" "$st"; fail=1
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
