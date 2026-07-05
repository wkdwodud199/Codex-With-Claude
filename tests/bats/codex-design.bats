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
#   7-9. (task-004) pinned -m/-c flags + provenance / profile missing -> refuse
#        / CLI version below minimum -> preflight fail

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
if [ "${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
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
if [ "${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
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
# task-004: 모델/effort 강제 — 항상 -m/-c 를 명시하고, 성공 시 provenance 를 남긴다
@test "--auto full pass -> pinned flags (-m/-c) + provenance recorded" {
    cat > "$WORK/codex" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
printf '%s\n' "\$*" >> "$WORK/codex-args.log"
mkdir -p "$WORK/kb/tasks/task-f"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-f/design.md"
exit 0
EOF
    chmod +x "$WORK/codex"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" --auto task-f "sample"
    [ "$status" -eq 0 ]
    args=$(cat "$WORK/codex-args.log")
    [[ "$args" == *"-m gpt-5.5"* ]]
    [[ "$args" == *"model_reasoning_effort=xhigh"* ]]
    [[ "$args" == *"--sandbox workspace-write"* ]]
    [[ "$args" != *"--skip-git-repo-check"* ]]
    grep -q "generated_by.*design=codex gpt-5.5/xhigh" "$WORK/kb/tasks/task-f/manifest.md"
}

# task-004: 프로필 부재 시 --auto 거부 (조용한 기본값 금지)
@test "profile missing -> --auto refused (no silent default)" {
    cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
exit 0
EOF
    chmod +x "$WORK/codex"
    rm -f "$WORK/runtime/config/model-profiles.json"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" --auto task-g "sample"
    [ "$status" -ne 0 ]
    [[ "$output" == *"프로필"* ]]
}

# task-004: 최소 CLI 버전 미달 시 호출 전에 실패 (preflight)
@test "codex CLI version below minimum -> preflight fail before call" {
    cat > "$WORK/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "codex-cli 0.1.0"; exit 0; fi
exit 0
EOF
    chmod +x "$WORK/codex"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" --auto task-h "sample"
    [ "$status" -ne 0 ]
    [[ "$output" == *"버전"* ]]
}

@test "--auto + codex wrote valid design but exited non-zero -> propagate (D2)" {
    cat > "$WORK/codex" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then echo "codex-cli 99.0.0"; exit 0; fi
mkdir -p "$WORK/kb/tasks/task-e"
cp "$REPO/tests/validator/fixtures/good.md" "$WORK/kb/tasks/task-e/design.md"
exit 7
EOF
    chmod +x "$WORK/codex"
    PATH="$WORK:/usr/bin:/bin" run bash "$WORK/runtime/codex-design.sh" --auto task-e "sample"
    [ "$status" -ne 0 ]
    [[ "$output" == *"codex 자동 호출이 실패"* ]]
}
