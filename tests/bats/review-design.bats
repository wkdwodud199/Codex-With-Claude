#!/usr/bin/env bats
# End-to-end smoke tests for runtime/review-design.sh (task-005, P1 설계 교차검토)
#
# Scenarios:
#   1. no args                              -> exit 1, usage
#   2. missing design.md                    -> exit 1
#   3. draft/invalid design.md              -> validator fails, claude NOT called, exit 1
#   4. inside Claude session (no FORCE)      -> recursion guard, exit 0, no review file
#   5. good design + fable stub             -> exit 0, review file + pinned flags + provenance(fallback=false)
#   6. fallback (opus) stub                 -> exit 0, provenance fallback=true
#   7. unknown model JSON                   -> exit 1, no review file, no provenance
#   8. CLI version below minimum            -> preflight fail, exit 1
#   9. profile missing                      -> exit 1 (no silent default)

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/runtime/config" "$WORK/kb/tasks"
    cp -r "$REPO/runtime/validator" "$WORK/runtime/"
    cp -r "$REPO/runtime/lib"       "$WORK/runtime/"
    cp "$REPO/runtime/review-design.sh" "$WORK/runtime/"
    cp "$REPO/runtime/render-prompt.py" "$WORK/runtime/"
    cp "$REPO/runtime/config/model-profiles.json" "$WORK/runtime/config/"
    cp -R "$REPO/templates" "$WORK/templates"
    chmod +x "$WORK/runtime/"*.sh
    export WORK REPO
    unset CLAUDE_CODE_SESSION CLAUDE_CODE_SESSION_ID CLAUDECODE CLAUDE_CODE CLAUDE_AUTO_FORCE
    # good design + manifest 를 task-t 로 준비
    mkdir -p "$WORK/kb/tasks/task-t"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-t/design.md"
    sed 's/task-<NNN>/task-t/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-t/manifest.md"
}

teardown() { rm -rf "$WORK"; }

# fable(정상) 또는 opus(fallback) JSON 을 내는 claude 스텁을 설치한다.
_install_claude() { # <model-json-key>
    cat > "$WORK/claude" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "2.99.0 (Claude Code)"; exit 0; fi
printf '%s\n' "\$*" >> "$WORK/claude-args.log"
echo '$1'
exit 0
EOF
    chmod +x "$WORK/claude"
}

@test "no args -> usage and exit 1" {
    run bash "$WORK/runtime/review-design.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"사용법"* ]]
}

@test "missing design.md -> exit 1" {
    run bash "$WORK/runtime/review-design.sh" task-none
    [ "$status" -eq 1 ]
    [[ "$output" == *"설계 문서가 없습니다"* ]]
}

@test "draft design -> validator fails, claude not called, exit 1" {
    mkdir -p "$WORK/kb/tasks/task-x"
    sed 's/task-<NNN>/task-x/g' "$WORK/templates/design.md" > "$WORK/kb/tasks/task-x/design.md"
    sed 's/task-<NNN>/task-x/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-x/manifest.md"
    _install_claude '{"result":"x","model":"claude-fable-5"}'
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-x
    [ "$status" -ne 0 ]
    [ ! -f "$WORK/kb/tasks/task-x/design-review.md" ]
    [ ! -f "$WORK/claude-args.log" ]   # claude 미호출
}

@test "inside Claude session -> recursion guard, exit 0, no review file" {
    _install_claude '{"result":"x","model":"claude-fable-5"}'
    CLAUDE_CODE_SESSION=1 PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-t
    [ "$status" -eq 0 ]
    [[ "$output" == *"재귀 방지"* ]]
    [ ! -f "$WORK/kb/tasks/task-t/design-review.md" ]
}

@test "good design + fable stub -> review file + pinned flags + provenance(fallback=false)" {
    _install_claude '{"result":"## 요약\n좋음","modelUsage":{"claude-fable-5-20260930":{"outputTokens":9}}}'
    before=$(shasum -a 256 "$WORK/kb/tasks/task-t/design.md" | awk '{print $1}')
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-t
    [ "$status" -eq 0 ]
    [ -f "$WORK/kb/tasks/task-t/design-review.md" ]
    args=$(cat "$WORK/claude-args.log")
    [[ "$args" == *"--model claude-fable-5"* ]]
    [[ "$args" == *"--effort max"* ]]
    [[ "$args" == *"--fallback-model claude-opus-4-8"* ]]
    [[ "$args" == *"--output-format json"* ]]
    grep -q "cross_reviewed_by.*fallback=false" "$WORK/kb/tasks/task-t/manifest.md"
    # design.md 읽기전용 보증
    after=$(shasum -a 256 "$WORK/kb/tasks/task-t/design.md" | awk '{print $1}')
    [ "$before" = "$after" ]
}

@test "fallback (opus) stub -> exit 0, provenance fallback=true" {
    _install_claude '{"result":"검토","model":"claude-opus-4-8"}'
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-t
    [ "$status" -eq 0 ]
    grep -q "cross_reviewed_by.*fallback=true" "$WORK/kb/tasks/task-t/manifest.md"
    [[ "$output" == *"fallback 발동"* ]]
}

@test "unknown model JSON -> exit 1, no review file, no provenance" {
    _install_claude '{"result":"x","model":"claude-sonnet-5"}'
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-t
    [ "$status" -ne 0 ]
    [ ! -f "$WORK/kb/tasks/task-t/design-review.md" ]
    ! grep -q "cross_reviewed_by" "$WORK/kb/tasks/task-t/manifest.md"
}

@test "CLI version below minimum -> preflight fail" {
    cat > "$WORK/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "0.1.0"; exit 0; fi
echo '{"result":"x","model":"claude-fable-5"}'
exit 0
EOF
    chmod +x "$WORK/claude"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-t
    [ "$status" -ne 0 ]
    [[ "$output" == *"버전"* ]]
}

@test "profile missing -> exit 1 (no silent default)" {
    _install_claude '{"result":"x","model":"claude-fable-5"}'
    rm -f "$WORK/runtime/config/model-profiles.json"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/review-design.sh" task-t
    [ "$status" -ne 0 ]
    [[ "$output" == *"프로필"* ]]
}
