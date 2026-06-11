#!/usr/bin/env bats
# End-to-end smoke tests for runtime/codex-design.sh
#
# Scenarios covered:
#   1. no args                                 -> exit 1, usage
#   2. codex missing, raw template             -> exit 1 (post-validation fails)
#   3. existing design.md                       -> exit 1 (overwrite guard)
#   4. --auto + codex stub -> stub invoked     -> template drafted, validation fails
#   5. default (no --auto) + codex stub        -> skipped, manual-mode banner
#   6. --auto + codex wrote valid design, exit!=0 -> failure propagated (D2)

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/runtime" "$WORK/templates" "$WORK/kb/tasks"
    cp -r "$REPO/runtime/validator" "$WORK/runtime/"
    cp -r "$REPO/runtime/lib"       "$WORK/runtime/"
    cp "$REPO/runtime/claude-implement.sh" "$WORK/runtime/"
    cp "$REPO/runtime/codex-design.sh" "$WORK/runtime/"
    cp "$REPO/templates/"* "$WORK/templates/"
    chmod +x "$WORK/runtime/"*.sh
    # codex-design 의 git preflight(D3)가 통과하도록 작업 디렉터리를 git 저장소로 만든다.
    git init -q "$WORK" 2>/dev/null || true
    export WORK
    export ORIG_PATH="$PATH"
    # common.sh is_claude_session 이 검사하는 모든 변수를 제거 (CLAUDE_CODE_SESSION_ID 포함).
    unset CLAUDE_CODE_SESSION CLAUDE_CODE_SESSION_ID CLAUDECODE CLAUDE_CODE \
          CODEX_AUTO CODEX_AUTO_FORCE
}

teardown() {
    rm -rf "$WORK"
    export PATH="$ORIG_PATH"
}

@test "no args -> usage and exit 1" {
    run bash "$WORK/runtime/codex-design.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"사용법"* ]]
}

@test "codex missing, raw draft -> post-validation fails" {
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" task-a "sample"
    [ "$status" -eq 1 ]
    [ -f "$WORK/kb/tasks/task-a/design.md" ]
    [[ "$output" == *"보완 필요"* ]] || [[ "$output" == *"FAIL"* ]]
}

# Phase A: 새 task 생성 시 manifest.md 가 자동 생성되어야 한다
@test "new task -> manifest.md auto-generated" {
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" task-a "sample"
    [ -f "$WORK/kb/tasks/task-a/manifest.md" ]
    [[ "$(cat "$WORK/kb/tasks/task-a/manifest.md")" == *"task-a"* ]]
}

@test "existing design.md -> refuses to overwrite" {
    mkdir -p "$WORK/kb/tasks/task-b"
    cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-b/design.md"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" task-b "sample"
    [ "$status" -eq 1 ]
    [[ "$output" == *"이미 존재"* ]]
}

@test "--auto + codex stub on PATH -> stub invoked, validation follows" {
    cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WORK/codex"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" --auto task-c "sample"
    [ "$status" -eq 1 ]
    [ -f "$WORK/kb/tasks/task-c/design.md" ]
    [[ "$output" == *"Codex"* ]]
}

@test "default (no --auto) + codex stub -> stub skipped, manual banner" {
    cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WORK/codex"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" task-d "sample"
    [ "$status" -eq 1 ]
    [[ "$output" == *"수동 모드"* ]]
}

# D2: codex 가 유효한 design 을 썼더라도 non-zero 로 끝나면 그 실패를 전파한다
# (검증 통과 + invoke_rc!=0 분기를 커버; codex 부재 케이스는 draft 검증 실패에 가려지므로
#  '유효 design 작성 후 비정상 종료' 스텁으로 전파 경로를 직접 검증한다)
@test "--auto + codex wrote valid design but exited non-zero -> propagate (D2)" {
    cat > "$WORK/codex" <<EOF
#!/usr/bin/env bash
mkdir -p "$WORK/kb/tasks/task-e"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-e/design.md"
exit 7
EOF
    chmod +x "$WORK/codex"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" --auto task-e "sample"
    [ "$status" -ne 0 ]
    [[ "$output" == *"codex 자동 호출이 실패"* ]]
}
