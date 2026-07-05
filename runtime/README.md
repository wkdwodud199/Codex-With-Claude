# runtime — 러너 및 외부 CLI 계약

> Load: on-demand
> 이 문서는 `runtime/` 의 러너 스크립트가 의존하는 **외부 CLI 계약**과
> **종료 코드 규약**을 정의한다. 검증 로직 자체는 [validator/README.md](./validator/README.md) 를 참조.

## 구성

| 경로 | 역할 |
|------|------|
| `codex-design.{sh,ps1}` | 설계자(designer) 러너 — design.md 초안 생성 + (옵션) codex 자동 호출 |
| `claude-implement.{sh,ps1}` | 구현자(implementer) 러너 — design.md 검증 후 + (옵션) claude 자동 호출 |
| `validator/` | design.md 검증 단일 진실 원천 (Python, stdlib) |
| `lib/common.{sh,ps1}` | python probe, 세션 감지, truthy 헬퍼 |
| `lib/invoke-claude.{sh,ps1}` | `claude` CLI 자동 호출 로직 (재귀 가드 포함) |
| `lib/invoke-codex.{sh,ps1}` | `codex` CLI 자동 호출 로직 (재귀 가드 + 샌드박스) |
| `codex-design.{sh,ps1}` 뒤 `review-design.{sh,ps1}` | (선택) 설계 교차검토 — Claude fable-5/max 읽기전용 2차 검토 (task-005, advisory) |
| `codex-review.{sh,ps1}` | (선택) 구현 리뷰 — Codex gpt-5.5/xhigh 가 구현 결과를 리뷰 (task-006, Phase D) |
| `render-prompt.py` | 프로필 조회 · implement 라우팅 · CLI 버전 preflight · 프롬프트 렌더 · fallback 판정 (task-004/005) |
| `config/model-profiles.json` | phase별 모델/effort **강제 프로필 SSOT** — design 정적 강제, implement 는 design-directed |
| `context-budget.py` | 기본 로드 세트 vs baseline 바이트/토큰 비교 — 경고 전용 (warning-only) |
| `generate-status.py` | `kb/index/status.md` 활성/완료 표 재생성 + `--check` drift 검사 |

## 외부 CLI 계약

러너는 다음 두 외부 CLI 이름에 의존한다. 자동 호출(`--auto`) 경로에서만 필요하며,
수동 모드에서는 호출하지 않는다.

### `claude`

- 호출 형태: `claude -p "<prompt>" --model <model> --effort <effort>` — **항상 명시** (task-004).
  - model/effort 는 design.md 의 `실행 계획 (Execution Plan)` 이 라우팅한다 (design-directed).
  - 실행 계획 부재는 legacy(task-001~003)만 허용 — 프로필 기본값(`claude-opus-4-8/high`)으로
    라우팅하며 `[WARN]` 로그 + provenance(`route=default`) 를 남긴다.
  - 선택 가능 값은 `config/model-profiles.json` 의 `allowed_models`/`allowed_efforts` 화이트리스트로 제한.
- 최소 버전: **2.1.201** (`--model`/`--effort low|medium|high|xhigh|max`/`--fallback-model` 지원 기준).
  preflight(`render-prompt.py check-cli-version`) 미달 시 호출하지 않고 실패한다.
- design 레인 교차검증(claude) 프로필은 `claude-fable-5/max` + `--fallback-model claude-opus-4-8`
  (**design 한정**; `--fallback-model` 은 effort 를 바꾸지 않으므로 폴백도 max 로 실행된다).
  폴백 발동 여부를 판별할 수 없으면 해당 auto 경로는 실패 처리한다 (조용한 폴백 금지).
- 용도: 구현자(implementer) 자동 호출 (`claude-implement --auto`).
- 설치/인증: Claude Code CLI. 인증은 CLI 자체 설정을 따른다.
- 프롬프트는 design.md 내용을 인라인하지 않고 **경로만** 전달한다 (컨텍스트 절약).
  프롬프트 본문의 단일 원천은 `templates/prompts/implement.md` (render-prompt.py 가 렌더).

### `codex`

- 호출 형태: `codex exec --sandbox workspace-write -C "<root>" -m <model> -c model_reasoning_effort=<effort> "<prompt>"`
  — 모델/effort **항상 명시** (task-004; design 정적 프로필 `gpt-5.5/xhigh`).
  - **`--skip-git-repo-check` 는 사용하지 않는다** (이 레포는 git 저장소이며, git 안전망을 복원한다).
  - **`--sandbox workspace-write`** 로 codex 의 쓰기 범위를 워크스페이스로 제한한다.
  - 설계 생성기는 `kb/tasks/<id>/` 아래 파일 하나만 쓰면 되므로 넓은 쓰기 표면이 필요 없다.
  - 프롬프트 본문의 단일 원천은 `templates/prompts/design.md` — 필수 섹션 목록은
    렌더 시점에 `validator/schema.json` 에서 주입된다 (드리프트 불가).
- 용도: 설계자(designer) 자동 호출 (`codex-design --auto`).
- 최소 버전: **codex 0.142.4** (`-m`, `-c model_reasoning_effort=` 지원 기준).
  preflight 미달 시 호출하지 않고 실패한다.
- 설치/인증: Codex CLI. 인증은 CLI 자체 설정을 따른다.
- **preflight**: auto 호출 전 codex 존재 여부를 점검하고, 부재 시 자동 동작 실패로 처리한다(아래 종료 코드 참조).

## 종료 코드 규약

### validator CLI (`runtime/validator/cli.py`)

| 코드 | 의미 |
|------|------|
| `0` | 검증 통과 |
| `1` | 검증 실패 (오류 리스트 출력) |
| `2` | 파일 없음 / 디코딩 실패 |

### 러너 자동 호출(`--auto`) 종료 코드 전파

자동 호출 경로의 실패 의미는 다음과 같다 (방어적 설계):

| 상황 | 종료 코드 | 이유 |
|------|-----------|------|
| 수동 모드 (no `--auto`) | `0` | 정보성 스킵 — 자동 동작을 요청하지 않았다 |
| `--auto` + 재귀 가드 발동 (Claude/Codex 세션 내부) | `0` | 의도된 **안전** 스킵 (중첩 세션 방지) |
| `--auto` + 대상 CLI **부재** | **non-zero** | 요청된 자동 동작을 **수행하지 못한 실패** |
| `--auto` + CLI 호출했으나 non-zero 반환 | **그 코드 전파** | 하위 CLI 의 실패를 삼키지 않는다 |
| `--auto` + 프로필 부재/해석 실패 (task-004) | **non-zero (2)** | 조용한 기본값 금지 — 강제 대상이 불명확하면 실행하지 않는다 |
| `--auto` + CLI 버전 preflight 미달 (task-004) | **non-zero (1)** | 필요한 플래그(`--effort`, `-c`)가 없는 구버전 호출 방지 |
| `--auto` + 실행 계획 라우팅 실패 (claude) | **non-zero** | 비legacy 에서 실행 계획 부재/화이트리스트 위반 |

### provenance (task-004)

`--auto` 호출이 성공하면 러너가 `kb/tasks/<id>/manifest.md` 에 한 줄을 추가한다:

```
- **generated_by**: design=codex gpt-5.5/xhigh @codex 0.142.4, 2026-07-05 (fallback=none)
- **generated_by**: implement=claude claude-opus-4-8/xhigh @claude 2.1.201, 2026-07-05 (route=execution-plan)
```

codex 레인은 **검증 통과 후에만** 기록한다. manifest 가 없으면 `[WARN]` 후 건너뛴다(파일 무단 생성 금지).

> 재귀 가드: `CLAUDECODE` / `CLAUDE_CODE_SESSION_ID` / `CLAUDE_CODE_SESSION` / `CLAUDE_CODE` 중 하나라도 설정되면
> 세션 내부로 간주해 `--auto` 를 거부한다. `*_AUTO_FORCE=1` (예: `CODEX_AUTO_FORCE=1`,
> `CLAUDE_AUTO_FORCE=1`) 로만 우회한다.

## Python 탐지

러너는 `python3` → `python` → `py -3` 순으로 파이썬을 탐지한다 (`lib/common.{sh,ps1}`).
파이썬이 없으면 설치 힌트를 출력하고 실패한다. validator 는 stdlib 만 사용한다 (파이썬 3.8+).

## 테스트와 CLI 계약의 경계

`tests/run-smoke.sh` 와 `tests/bats/*` 는 `claude` / `codex` 실제 CLI 를 **스텁(stub)** 으로 대체한다.
즉 CI 는 **러너의 래퍼 로직**(인자 파싱, 검증 게이트, 재귀 가드, 종료 코드 전파)을 증명하지만,
**실제 CLI 계약**(codex 가 정말 `--sandbox workspace-write` 를 받는지, 실제 인증/출력 형식 등)은
증명하지 않는다. 실제 CLI 동작은 로컬 수동 검증 또는 별도 통합 테스트로 확인한다.

## 설계 교차검토 (`review-design.{sh,ps1}` — task-005, P1)

- 호출 형태: `runtime/review-design.sh <task-id>` — design.md 가 validator 를 통과한 뒤 **선택적으로** 실행.
- 내부 Claude 호출: `claude -p "<prompt>" --model claude-fable-5 --effort max --fallback-model claude-opus-4-8 --output-format json`
  (design.claude_cross_check 프로필; 모델/effort 항상 명시, CLI 버전 preflight 계승).
- **advisory**: 검토가 우려를 지적해도 러너 종료코드는 `0`. non-zero 는 precondition/렌더/프로필/CLI/
  JSON 파싱/파일 쓰기 오류에만 쓴다 — 구현 시작을 차단하지 않는다.
- **읽기전용 보증**: design.md 는 Codex 소유. 러너는 실행 전후 SHA-256 해시를 비교해 변경이 없을 때만
  산출물을 쓰고, 변경 감지 시 아무것도 기록하지 않고 실패한다.
- **fallback 판별 (조용한 폴백 금지)**: `--output-format json` 응답의 실제 model 을 `render-prompt.py
  detect-fallback` 로 판정한다(경로: `model` / `modelUsage` 키 / `usage.model`, 버전 접미사는 부분일치).
  실제 model 이 요청도 fallback 도 아니거나 본문/model 을 못 찾으면 non-zero 로 실패한다.
- 산출물: `kb/tasks/<id>/design-review.md`(advisory) + manifest 에
  `- **cross_reviewed_by**: claude <actual-model>/max @claude <cli-ver>, <date> (fallback=<true|false>)`.
- 경계: `collab.md` / done-gate / `reviews/` 는 건드리지 않는다 (그건 Phase D = task-006 소관).

## 구현 리뷰 루프 (`codex-review.{sh,ps1}` — task-006, Phase D)

- 호출 형태: `runtime/codex-review.sh <task-id>` — 구현 완료(**base done**) 후 **선택적으로** 실행.
- base 전제: `validator/cli.py --check-review-target <id>` 로 impl-notes(done)+summary(done)+manifest 를
  확인한다(approved-done 리뷰 게이트는 **제외** — 이전 리뷰가 request-changes 여도 재리뷰 가능하게).
- codex 호출: `codex exec --sandbox workspace-write -C <root> -m gpt-5.5 -c model_reasoning_effort=xhigh`
  (review.codex 프로필; `--skip-git-repo-check` 금지, git preflight/버전 preflight 계승).
- 산출물: `kb/tasks/<id>/reviews/<NNN>.md` (3자리, 최댓값+1 누적). codex 는 먼저 staging 파일에 쓰고,
  `--check-review` 검증을 통과해야만 `reviews/` 로 승격 → 부분/오류 리뷰가 게이트를 오염시키지 않는다.
- **review status enum** 의 정본은 [collab.md](../collab.md) (`pending|request-changes|approved|rejected`).
- **게이트** (validator CLI):
  - `--check-review <NNN.md>`: 단일 리뷰 형식/enum 검증.
  - `--latest-review <id>`: 최신 리뷰/상태 조회.
  - `--check-review-target <id>`: 리뷰 게이트 제외 base 검증(재리뷰 순환 방지).
  - `--check-done <id>`: **approved-done** — `reviews/` 가 있으면 최신 리뷰가 `approved` 여야 통과.
    `reviews/` 가 없으면 기존 동작 유지(하위호환). exit `1`=미승인/형식오류, `2`=collab enum·IO 오류.
- **no-auto-revert**: 어떤 리뷰 결과도 implementation-notes/summary 의 `Status` 를 자동으로 되돌리지 않는다.

## 참고

- 상태 모델(설계 준비도 vs 구현 진행도): [AGENT.md](../AGENT.md) "문서 상태 전이" 절.
- 리뷰 루프 인터페이스/enum/게이트 정본: [collab.md](../collab.md).
