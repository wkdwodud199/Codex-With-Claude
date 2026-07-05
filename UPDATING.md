# UPDATING — 기존 클론에 최신 CWC 반영하기

> 이미 CWC 를 클론해서 작업 중인 디렉터리에, 업데이트된 프레임워크를 **당신 작업을 잃지 않고** 반영하는 절차.
> 사람이 따라 해도 되고, **그 디렉터리의 AI 에이전트에게 "이 문서를 읽고 업데이트를 진행하라"** 고 시켜도 된다.
> (이 문서 자체는 프레임워크의 일부다. upstream 에서 함께 받아진다.)

## 0. 멘탈 모델 — 프레임워크 vs 당신 작업

업데이트는 **프레임워크만** 갱신하고 **당신 작업은 건드리지 않는** 것이 목표다.

| 프레임워크 (업데이트로 받는 것) | 당신 작업 (보존) |
|---|---|
| `runtime/`, `templates/`, `tests/`, `.github/` | `kb/tasks/<당신-task>/` |
| `AGENT.md` · `CLAUDE.md` · `AGENTS.md` · `QUICKREF.md` · `collab.md` · `UPDATING.md` | `kb/artifacts/<당신-summary>` |
| `kb/concepts/`, `kb/index/README.md`, `README(.en).md`, `LICENSE`, `.gitignore` | `kb/index/status.md` (당신 보드) |

이번 업데이트로 **삭제된 건 원본 저장소의 예제(`kb/tasks/task-001~006`, `imp.md`)뿐**이고, 프레임워크 로직은 전부 추가/개선이다.

## 1. 먼저 백업 (필수)

```bash
git add -A && git commit -m "wip: 업데이트 전 스냅샷"   # 또는: git stash
git branch backup/pre-update                            # 되돌릴 지점
```

## 2. 어느 경우인지 판별

```bash
git remote -v
```

- 출력에 원본 CWC(`.../Codex-With-Claude(.git)`)가 `origin` 으로 보이면 → **경우 A**.
- `origin` 이 당신의 다른 저장소이거나, 원본과 무관하면 → **경우 B**.

---

## 경우 A — 원본을 그대로 클론한 디렉터리 (origin 동일)

```bash
git fetch origin
git merge origin/main          # 히스토리를 선형으로 원하면: git rebase origin/main
```

- 당신 task 가 **다른 ID**(예: `task-010`)라면 merge 가 프레임워크만 갱신하고 당신 task 는 그대로 둔다.
- ⚠️ **ID 충돌**: 당신이 `task-001~006` **같은 ID** 로 직접 작업해 커밋해뒀다면, main 이 그 경로를 지웠으므로 merge 가 삭제하려 든다. 그때는 당신 버전을 지킨다:
  ```bash
  git checkout --ours kb/tasks/task-00X   # 그리고
  git add kb/tasks/task-00X && git commit
  ```
- 프레임워크 파일에서 충돌이 나면(당신이 `runtime/` 등을 수정했을 때) 보통 upstream 쪽을 채택한다:
  ```bash
  git checkout --theirs runtime/... && git add runtime/...
  ```

---

## 경우 B — 별도 프로젝트 / 독립 저장소

**B-1. upstream 으로 걸어 병합** (git 히스토리 연결이 괜찮을 때)

```bash
git remote add upstream https://github.com/wkdwodud199/Codex-With-Claude.git
git fetch upstream
git merge upstream/main          # 또는 원하는 커밋만: git cherry-pick <sha>
```

**B-2. 파일만 복사** (git 얽힘 없이 프레임워크만 원할 때)

최신 CWC 를 임시로 클론한 경로를 `FRESH` 라 하면:

```bash
FRESH=/tmp/cwc-latest
git clone https://github.com/wkdwodud199/Codex-With-Claude.git "$FRESH"

# 프레임워크만 덮어쓴다 (당신 kb/tasks·artifacts·status.md 는 건드리지 않음)
cp -R "$FRESH"/runtime "$FRESH"/templates "$FRESH"/tests "$FRESH"/.github ./
cp "$FRESH"/AGENT.md "$FRESH"/CLAUDE.md "$FRESH"/AGENTS.md "$FRESH"/QUICKREF.md \
   "$FRESH"/collab.md "$FRESH"/UPDATING.md "$FRESH"/README.md "$FRESH"/README.en.md \
   "$FRESH"/.gitignore ./
cp -R "$FRESH"/kb/concepts ./kb/
cp "$FRESH"/kb/index/README.md ./kb/index/
cp "$FRESH"/kb/tasks/README.md ./kb/tasks/ 2>/dev/null || true
cp "$FRESH"/kb/artifacts/README.md ./kb/artifacts/ 2>/dev/null || true
# 유지되는 것: kb/tasks/<당신 task>, kb/artifacts/<당신 summary>, kb/index/status.md
```

> `collab.md` 는 프레임워크(리뷰 enum/게이트 정본)라 덮어써야 한다. 단, 당신이 collab.md 에 직접
> 무언가 적어뒀다면 먼저 백업하라 (원칙상 리뷰 데이터는 collab.md 가 아니라 `kb/tasks/<id>/reviews/` 에 쌓인다).

---

## 3. 업데이트 후 검증 (프레임워크 정상 동작 확인)

```bash
python3 -m pytest tests/validator tests/context_budget tests/status_board tests/runtime -q
bash tests/run-smoke.sh
python3 runtime/generate-status.py --check     # 보드 drift 없는지
```

셋 다 통과하면 프레임워크는 정상이다. (bats/Pester 는 설치돼 있으면 `bats tests/bats` / `Invoke-Pester tests/pester`.)

## 4. 호환성 마이그레이션 (검증 계약이 엄격해짐 — 중요)

업데이트로 검증 규칙이 강화됐다. **기존에 만들던 문서**를 이어서 쓰려면 아래를 확인한다.

1. **실행 계획 섹션 필수** — 새 task 의 `design.md` 에는 `## 실행 계획 (Execution Plan)` 섹션이 있어야
   validator 를 통과한다(예전 예제 `task-001~003` 만 면제). 예전 템플릿으로 만든 진행 중 설계에는 이 섹션을 추가하라:
   ```markdown
   ## 실행 계획 (Execution Plan)

   - implement_model: claude-opus-4-8      # 화이트리스트: claude-fable-5 | claude-opus-4-8
   - implement_effort: high                # 화이트리스트: medium | high | xhigh | max
   - routing_reason: (선택 근거 1줄)

   | unit | 파일 범위 | depends_on | group |
   |------|-----------|------------|-------|
   | U1   | ...       | 없음       | G1    |
   ```
   확인: `python3 runtime/validator/cli.py kb/tasks/<id>/design.md`

2. **done-gate 강화** — 완료(`--check-done`) 조건에 다음이 추가됐다:
   - `manifest.md` 의 `inputs`/`concepts_needed`/`related_files` 가 placeholder 가 아닌 실제 값.
   - `implementation-notes.md` 와 `kb/artifacts/<id>-summary.md` 의 `Status: done`.
   - `kb/tasks/<id>/reviews/` 가 있으면 **최신 리뷰가 `approved`** (Phase D). 없으면 이 조건은 적용 안 됨.

3. **--auto 모델/effort 강제** — 자동 호출을 쓰면 `runtime/config/model-profiles.json`(프레임워크에 포함)과
   `runtime/render-prompt.py` 가 있어야 한다. design 은 `gpt-5.5/xhigh`, implement 는 실행 계획이 라우팅한다.
   자세한 계약은 [runtime/README.md](./runtime/README.md), 요약은 [QUICKREF.md](./QUICKREF.md).

4. 정리 후 보드 재생성: `python3 runtime/generate-status.py`.

---

## AI 에이전트에게 (이 문서를 받고 업데이트를 수행할 때의 순서)

1. **백업**: 현재 변경을 커밋하거나 `git stash`, `git branch backup/pre-update`. 사용자 확인 없이 강제 삭제/리셋 금지.
2. **판별**: `git remote -v` 로 경우 A/B 결정.
3. **업데이트**: 경우 A 는 `git fetch && git merge origin/main`, 경우 B 는 upstream 병합 또는 파일 복사(위 명령). **`kb/tasks/`·`kb/artifacts/`·`kb/index/status.md` 의 사용자 작업은 절대 덮어쓰지 말 것.**
4. **충돌 처리**: 사용자 task 는 `--ours`, 프레임워크 파일은 원칙적으로 `--theirs`. 애매하면 멈추고 사용자에게 물어라.
5. **검증**: 위 §3 명령 3개 실행. 실패하면 원인 보고 후 중단.
6. **마이그레이션**: 진행 중 `design.md` 에 실행 계획 섹션 보강(§4-1), 완료 주장 task 는 `--check-done` 으로 점검(§4-2).
7. **보고**: 무엇을 갱신/보존/보강했는지, 검증 결과, 남은 수동 조치를 요약. 커밋/푸시는 사용자 지시가 있을 때만.
