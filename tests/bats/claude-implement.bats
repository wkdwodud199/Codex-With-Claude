#!/usr/bin/env bats
# End-to-end smoke tests for runtime/claude-implement.sh
#
# Scenarios covered:
#   1. no args                             -> exit 1, usage
#   2. no design.md at all                 -> exit 1, helpful error
#   3. design.md with placeholder/draft    -> exit 1 (validator fails)
#   4. design.md good, default mode        -> exit 0, manual banner, impl-notes created
#   5. design.md good, --auto in session   -> exit 0, recursion guard banner
#   6. design.md good, --auto, no claude   -> NON-ZERO, no-CLI warning (D2)
#   7. --done with legacy task-001         -> exit 0, legacy pass (C-2)
#   8. --done with incomplete task         -> exit 1, done-gate fails (C-2)
#   9-11. (task-004) execution-plan routing + provenance / legacy default route
#         / profile missing -> gate refuses

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/runtime" "$WORK/templates" "$WORK/kb/tasks"
    cp -r "$REPO/runtime/validator" "$WORK/runtime/"
    cp -r "$REPO/runtime/lib"       "$WORK/runtime/"
    cp "$REPO/runtime/claude-implement.sh" "$WORK/runtime/"
    cp "$REPO/runtime/codex-design.sh" "$WORK/runtime/"
    cp "$REPO/runtime/render-prompt.py" "$WORK/runtime/"
    mkdir -p "$WORK/runtime/config"
    cp "$REPO/runtime/config/model-profiles.json" "$WORK/runtime/config/"
    # templates/prompts/ 하위 디렉터리 포함 복사 (task-004)
    cp -R "$REPO/templates/." "$WORK/templates/"
    chmod +x "$WORK/runtime/"*.sh
    export WORK
    # Ensure tests don't inherit a Claude Code session env from the runner.
    # common.sh is_claude_session 이 검사하는 모든 변수를 제거해야 한다
    # (CLAUDE_CODE_SESSION_ID 포함).
    unset CLAUDE_CODE_SESSION CLAUDE_CODE_SESSION_ID CLAUDECODE CLAUDE_CODE \
          CLAUDE_AUTO CLAUDE_AUTO_FORCE
}

teardown() {
    rm -rf "$WORK"
}

@test "no args -> usage and exit 1" {
    run bash "$WORK/runtime/claude-implement.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"사용법"* ]]
}

@test "missing design.md -> exit 1 with hint" {
    run bash "$WORK/runtime/claude-implement.sh" task-missing
    [ "$status" -eq 1 ]
    [[ "$output" == *"설계 문서가 없습니다"* ]]
    [[ "$output" == *"codex-design.sh"* ]]
}

@test "draft design -> validator rejects" {
    mkdir -p "$WORK/kb/tasks/task-x"
    sed 's/task-<NNN>/task-x/g' "$WORK/templates/design.md" > "$WORK/kb/tasks/task-x/design.md"
    run bash "$WORK/runtime/claude-implement.sh" task-x
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"Status: draft"* ]]
}

@test "good design (default manual) -> exit 0 + impl-notes + manual banner" {
    mkdir -p "$WORK/kb/tasks/task-y"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-y/design.md"
    run bash "$WORK/runtime/claude-implement.sh" task-y
    [ "$status" -eq 0 ]
    [ -f "$WORK/kb/tasks/task-y/implementation-notes.md" ]
    [[ "$output" == *"수동 모드"* ]]
    [[ "$output" == *"구현 준비 완료"* ]]
}

@test "good design + --auto in Claude session -> recursion guard" {
    mkdir -p "$WORK/kb/tasks/task-y2"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-y2/design.md"
    CLAUDE_CODE_SESSION=1 run bash "$WORK/runtime/claude-implement.sh" --auto task-y2
    [ "$status" -eq 0 ]
    [[ "$output" == *"재귀 방지"* ]]
}

@test "good design + --auto, no claude CLI -> warn, NON-ZERO (D2)" {
    mkdir -p "$WORK/kb/tasks/task-y3"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-y3/design.md"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/claude-implement.sh" --auto task-y3
    # --auto 인데 claude CLI 부재 → 요청한 자동 작업 실패 → NON-ZERO.
    [ "$status" -ne 0 ]
    [[ "$output" == *"claude CLI를 찾을 수 없습니다"* ]]
}

# task-004: 설계 주도 라우팅 — 실행 계획의 model/effort 가 --model/--effort 로 전달된다
@test "--auto routed by execution plan -> --model/--effort + provenance" {
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
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/claude-implement.sh" --auto task-r
    [ "$status" -eq 0 ]
    args=$(cat "$WORK/claude-args.log")
    [[ "$args" == *"--model claude-opus-4-8"* ]]
    [[ "$args" == *"--effort xhigh"* ]]
    grep -q "generated_by.*route=execution-plan" "$WORK/kb/tasks/task-r/manifest.md"
}

# task-004: legacy(실행 계획 부재) -> 기본값 라우팅 + WARN + provenance(route=default)
@test "legacy design without plan -> default route + WARN + provenance" {
    cat > "$WORK/claude" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "2.99.0 (Claude Code)"; exit 0; fi
printf '%s\n' "\$*" >> "$WORK/claude-args.log"
exit 0
EOF
    chmod +x "$WORK/claude"
    mkdir -p "$WORK/kb/tasks/task-001"
    cp "$REPO/tests/validator/fixtures/legacy-no-execution-plan.md" "$WORK/kb/tasks/task-001/design.md"
    sed 's/task-<NNN>/task-001/g' "$WORK/templates/manifest.md" > "$WORK/kb/tasks/task-001/manifest.md"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/claude-implement.sh" --auto task-001
    [ "$status" -eq 0 ]
    [[ "$output" == *"기본값으로 라우팅"* ]]
    args=$(cat "$WORK/claude-args.log")
    [[ "$args" == *"--model claude-opus-4-8"* ]]
    [[ "$args" == *"--effort high"* ]]
    grep -q "generated_by.*route=default" "$WORK/kb/tasks/task-001/manifest.md"
}

# task-004: 프로필 부재 -> 검증 게이트가 환경 오류(2)로 차단
@test "profile missing -> validator gate refuses (claude lane)" {
    mkdir -p "$WORK/kb/tasks/task-r2"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-r2/design.md"
    rm -f "$WORK/runtime/config/model-profiles.json"
    run bash "$WORK/runtime/claude-implement.sh" --auto task-r2
    [ "$status" -ne 0 ]
    [[ "$output" == *"프로필"* ]]
}

# C-2: --done 러너 통합 경로 — 인자 파싱 → cli.py --check-done 위임 → exit 전파
@test "--done with legacy task-001 -> exit 0 (C-2)" {
    # task-001 은 legacy allowlist 이므로 산출물 없어도 통과.
    mkdir -p "$WORK/kb/tasks/task-001"
    run bash "$WORK/runtime/claude-implement.sh" --done task-001
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy"* ]]
}

@test "--done with incomplete task (template notes) -> exit 1 (C-2)" {
    # implementation-notes 가 템플릿 그대로인 task → done-gate 실패.
    mkdir -p "$WORK/kb/tasks/task-z"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-z/design.md"
    # 템플릿과 동일한 노트(치환만 한 것)를 생성 — done-gate 는 이를 거부한다.
    sed 's|task-<NNN>|task-z|g' "$WORK/templates/implementation-notes.md" \
        > "$WORK/kb/tasks/task-z/implementation-notes.md"
    run bash "$WORK/runtime/claude-implement.sh" --done task-z
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}
