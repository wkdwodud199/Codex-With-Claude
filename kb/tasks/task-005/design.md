# 설계 문서 — task-005

> Status: ready
> Inputs: `kb/tasks/task-005/manifest.md`, `kb/tasks/task-004/design.md`, `runtime/config/model-profiles.json`의 `design.claude_cross_check`, `runtime/render-prompt.py`, `runtime/lib/common.{sh,ps1}`, `runtime/lib/invoke-claude.{sh,ps1}`의 호출/재귀가드 패턴, `runtime/validator/cli.py`, `templates/prompts/{design,implement}.md`, `runtime/README.md`, `QUICKREF.md`, `kb/concepts/workflow.md`, `tests/{run-smoke.sh,bats,pester,validator}`
> Outputs: `runtime/review-design.{sh,ps1}`, `templates/prompts/design-review.md`, `runtime/render-prompt.py`의 `design-review` 렌더 및 `detect-fallback` 서브커맨드, `kb/tasks/<id>/design-review.md` advisory 산출물, manifest `cross_reviewed_by` provenance, sh/ps1 및 bats/Pester/pytest/smoke 검증
> Next step: Claude가 이 설계를 기준으로 task-005를 구현하고, 새 review 러너가 `design.md`를 변경하지 않으며 advisory 결과와 fallback provenance만 남기는지 교차 플랫폼 테스트로 검증한다.

## 목표 (Objective)

Codex가 작성한 `kb/tasks/<id>/design.md`가 validator를 통과한 뒤, Claude `design.claude_cross_check` 프로필(`claude-fable-5/max`, fallback `claude-opus-4-8`)로 읽기전용 2차 설계 검토를 수행하는 독립 러너를 추가한다. 검토 결과는 구현 게이트가 아닌 advisory 문서(`design-review.md`)로 남기고, 실제 응답 모델을 JSON 출력에서 판별해 fallback 여부를 manifest에 명시한다.

## 범위 (Scope)

- 포함:
  - `runtime/review-design.sh <task-id>`와 `runtime/review-design.ps1 <task-id>` 신규 진입점 추가.
  - 러너가 `design.md` 존재 확인과 `runtime/validator/cli.py` 통과를 precondition으로 확인한 뒤 Claude 교차검토를 실행.
  - `templates/prompts/design-review.md`를 교차검토 프롬프트 단일 원천으로 추가하고, 설계 본문은 인라인하지 않고 경로만 전달.
  - `runtime/render-prompt.py render`에 `--phase design-review`를 추가하고 `REVIEW_FILE` 등 필요한 토큰을 렌더링.
  - `runtime/render-prompt.py detect-fallback` 서브커맨드 추가. Claude `--output-format json` 결과에서 응답 본문과 실제 model을 추출하고, 요청 model과 fallback model 중 어느 쪽인지 판정.
  - `design.claude_cross_check` 프로필 조회를 통해 `claude -p <prompt> --model claude-fable-5 --effort max --fallback-model claude-opus-4-8 --output-format json` 형태로 호출.
  - 성공 시 `kb/tasks/<id>/design-review.md`를 결정론적으로 갱신하고, `manifest.md`에 `cross_reviewed_by: claude <actual-model>/max @claude <cli-ver>, <date> (fallback=<true|false>)`를 기록.
  - `runtime/README.md`, `QUICKREF.md`, `kb/concepts/workflow.md`에 선택적 교차검토 단계와 JSON 출력 계약을 반영.
  - pytest, portable smoke, bats, Pester 테스트를 확장해 Bash/PowerShell 동작 패리티를 고정.
- 제외:
  - `design.md` 수정, 보정, 자동 반영. Codex 소유 문서이므로 review 러너는 최종적으로 `design.md` 내용을 바꾸지 않는다.
  - `claude-implement`의 구현 시작 게이트 변경. 교차검토 결과에 우려가 있어도 구현 시작을 차단하지 않는다.
  - `collab.md`, task review status enum, `--check-done`/done-gate, `kb/tasks/<id>/reviews/` 경로. 이는 task-006 Phase D 소관이다.
  - 다중 Claude 프로세스 fan-out, 새 외부 의존성, 비stdlib Python 패키지.
  - 실제 Claude CLI 인증/계정 설정 변경.

## 제약 (Constraints)

- 교차검토는 advisory다. Claude가 논리적 공백, 누락된 엣지케이스, 테스트 계획 미비를 지적해도 러너 종료코드는 성공이어야 한다. non-zero는 precondition 실패, 렌더/프로필/CLI/JSON 파싱/파일 쓰기 오류에만 사용한다.
- `design.md`는 읽기전용 입력이다. 러너는 실행 전후 해시를 비교해 정상 경로에서 변경이 없음을 확인하고, 변경 감지 시 provenance를 남기지 않고 non-zero로 실패시킨다. 자동 복구나 design 수정은 하지 않는다.
- 프롬프트는 설계 내용을 인라인하지 않는다. Claude에는 `DESIGN_FILE`, `REVIEW_FILE`, `PROJECT_ROOT`, `TASK_ID`, 호출 model/effort만 전달한다.
- 모델, effort, fallback model, 최소 CLI 버전은 `runtime/config/model-profiles.json`과 `render-prompt.py profile/check-cli-version`에서만 얻는다. sh/ps1에 `claude-fable-5`, `max`, `claude-opus-4-8`, `2.1.201`을 재하드코딩하지 않는다.
- fallback 감지는 필수다. JSON 파싱 실패, actual model 부재, actual model이 요청 model/fallback model 둘 다 아닌 경우는 실패 처리한다. 조용한 fallback 또는 조용한 unknown model은 금지한다.
- fallback이 `claude-opus-4-8`로 발동해도 effort는 `max`로 유지된다. provenance에는 `fallback=true`를 명시한다.
- Claude Code 세션 내부에서 자동 `claude -p` 호출은 기존 `invoke-claude`와 같은 재귀 가드로 거부한다. `CLAUDE_AUTO_FORCE=1`일 때만 우회한다.
- CLI preflight 기준은 Claude CLI `2.1.201` 이상이다. `--output-format json`, `--model`, `--effort`, `--fallback-model`을 안전하게 쓰기 위한 기준으로 취급한다.
- `manifest.md`는 provenance 대상이므로 성공 경로의 사전 조건으로 존재해야 한다. 러너가 새 manifest를 만들지는 않는다.
- Bash와 PowerShell은 같은 인자 의미, 같은 성공/실패 조건, 같은 provenance 문자열, 같은 JSON 판정 규칙을 가져야 한다.
- Python은 stdlib만 사용한다. JSON 해석과 응답 본문 추출은 shell/PowerShell이 아니라 `render-prompt.py`가 담당한다.

## 구현 단계 (Implementation Steps)

1. `templates/prompts/design-review.md`를 추가한다.
   - 입력 토큰은 `TASK_ID`, `DESIGN_FILE`, `REVIEW_FILE`, `PROJECT_ROOT`, `MODEL`, `EFFORT`로 제한한다.
   - 프롬프트에는 읽기전용 검토, 파일 수정 금지, design 본문 인라인 금지, advisory-only 성격을 명시한다.
   - 출력 형식은 Markdown으로 고정한다. 권장 섹션은 `요약`, `주요 우려`, `누락 가능 엣지케이스`, `테스트 보강`, `범위/현실성`, `권고`로 둔다.
2. `runtime/render-prompt.py render`를 확장한다.
   - `choices=["design", "implement", "design-review"]`로 phase를 확장한다.
   - `--review-file` 옵션과 `REVIEW_FILE` 치환 토큰을 추가한다.
   - 기존 leftover token 검사를 그대로 적용해 프롬프트 drift를 실패로 만든다.
3. `runtime/render-prompt.py detect-fallback`을 추가한다.
   - 입력: `--json-file <path>` 또는 stdin, `--requested-model <model>`, `--fallback-model <model>`, `--field <actual_model|fallback|response_text>`.
   - JSON 파싱은 stdlib `json`만 사용한다.
   - actual model은 Claude JSON의 명시적 model 필드에서 추출한다. 지원할 키 경로는 코드 상수로 작게 유지하고, 어느 경로에서도 찾지 못하면 exit `1`로 실패한다.
   - response text는 JSON의 명시적 result/content 계열 필드에서 추출한다. 비어 있거나 문자열로 정규화할 수 없으면 exit `1`로 실패한다.
   - actual model이 requested와 같으면 `fallback=false`, fallback model과 같으면 `fallback=true`, 둘 다 아니면 exit `1`.
   - 같은 JSON을 shell/PowerShell이 여러 번 파싱하지 않도록 field별 plain text 값을 stdout으로 출력한다.
4. `runtime/review-design.sh`를 추가한다.
   - 인자: `<task-id>` 단일 필수 인자, `--help|-h` 안내.
   - 경로: `TASK_DIR`, `DESIGN_FILE`, `REVIEW_FILE`, `MANIFEST_FILE`, `VALIDATOR_CLI`, `render-prompt.py`를 기존 러너와 같은 방식으로 계산.
   - `design.md`와 `manifest.md` 존재 확인 후 validator를 실행한다. validator rc `1`/`2+`는 그대로 실패 전파하고 Claude를 호출하지 않는다.
   - 재귀 가드: `is_claude_session && ! CLAUDE_AUTO_FORCE`면 경고 후 exit `0`, 파일을 만들지 않는다.
   - `profile --phase design --cli claude --field model|effort|fallback_model`로 프로필을 읽고, `check-cli-version --phase design --cli claude`로 최소 버전을 검증한다.
   - `render --phase design-review`로 프롬프트를 만들고, `claude -p "$prompt" --model "$model" --effort "$effort" --fallback-model "$fallback_model" --output-format json < /dev/null > "$tmp_json"` 형태로 호출한다.
   - Claude 호출 non-zero는 전파한다. 성공하면 `detect-fallback`으로 actual model, fallback 여부, response text를 추출한다.
   - `design.md` 실행 전후 해시가 다르면 `design-review.md`와 manifest를 쓰지 않고 실패한다.
   - `design-review.md`는 temp 파일에 쓴 뒤 atomic move로 교체한다. 헤더에는 task id, design path, reviewer, fallback 여부, advisory-only 문구를 포함하고 본문에는 Claude response text를 붙인다.
   - manifest에는 `- **cross_reviewed_by**: claude <actual-model>/<effort> @claude <cli-ver>, <YYYY-MM-DD> (fallback=<true|false>)`를 append한다.
5. `runtime/review-design.ps1`을 Bash와 동등하게 추가한다.
   - `#Requires -Version 5.1`, UTF-8 출력 설정, `common.ps1`의 `Resolve-Python`, `Invoke-Validator`, `Invoke-RenderPrompt`, `Test-ClaudeSession`, `Test-Truthy`를 재사용한다.
   - `claude.cmd` 우선 탐색 후 `claude` Application 탐색 패턴을 `invoke-claude.ps1`과 맞춘다.
   - JSON 응답은 temp file로 저장하고 `detect-fallback` field 호출로만 읽는다.
   - 출력 파일과 manifest append는 `System.Text.UTF8Encoding($false)`로 수행해 기존 PowerShell 파일 쓰기 관례와 맞춘다.
6. 문서를 갱신한다.
   - `runtime/README.md`: `review-design.{sh,ps1}` 구성 항목, Claude `--output-format json` 계약, fallback 감지 실패 조건, `cross_reviewed_by` provenance 예시를 추가한다.
   - `QUICKREF.md`: 설계 검증 뒤 선택적으로 `runtime/review-design.sh <id>`를 실행할 수 있음을 러너 절에 추가하고, advisory라 구현 게이트가 아님을 명시한다.
   - `kb/concepts/workflow.md`: Codex 레인과 Claude 구현 레인 사이에 선택적 design cross-review 노드를 추가하되, `claude-implement`의 validator 게이트와 done-gate 의미는 바꾸지 않는다.
7. 테스트를 확장한다.
   - pytest에 `render-prompt.py render --phase design-review`와 `detect-fallback`의 requested/fallback/unknown/malformed JSON 케이스를 추가한다.
   - `tests/run-smoke.sh`가 새 review 러너 파일을 임시 워크스페이스에 복사하고 성공/실패 대표 시나리오를 실행하도록 한다.
   - `tests/bats/review-design.bats`와 `tests/pester/review-design.Tests.ps1`을 추가하고, 두 파일의 시나리오 수와 의미를 맞춘다.
   - CI pytest 대상에 새 pytest 디렉터리가 생기면 `.github/workflows/ci.yml`의 pytest 경로를 함께 갱신한다.

## 실행 계획 (Execution Plan)

- implement_model: `claude-opus-4-8`
- implement_effort: `xhigh`
- routing_reason: 새 Bash/PowerShell 러너, Python JSON 판별, 문서 provenance, cross-platform 테스트가 맞물리는 변경이라 높은 추론이 필요하지만, 요구사항과 제외 범위가 명확하므로 `max` 대신 `xhigh`로 충분하다.

| unit | 파일 범위 | depends_on | group |
|------|-----------|------------|-------|
| U1-prompt-and-render | `templates/prompts/design-review.md`, `runtime/render-prompt.py` render phase 확장 | 없음 | G1 |
| U2-fallback-detector | `runtime/render-prompt.py` `detect-fallback`, pytest JSON fixture/case | 없음 | G1 |
| U3-bash-runner | `runtime/review-design.sh`, `tests/run-smoke.sh`, `tests/bats/review-design.bats` | U1-prompt-and-render, U2-fallback-detector | G2 |
| U4-powershell-runner | `runtime/review-design.ps1`, `tests/pester/review-design.Tests.ps1` | U1-prompt-and-render, U2-fallback-detector | G2 |
| U5-docs-and-ci | `runtime/README.md`, `QUICKREF.md`, `kb/concepts/workflow.md`, `.github/workflows/ci.yml` | U3-bash-runner, U4-powershell-runner | G3 |

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| `runtime/review-design.sh` | create | Bash 교차검토 러너. validator 통과 후 Claude JSON 호출, fallback 판별, `design-review.md` 작성, manifest provenance 기록 |
| `runtime/review-design.ps1` | create | PowerShell 교차검토 러너. Bash와 같은 인자/종료코드/파일 쓰기/재귀가드 의미 유지 |
| `templates/prompts/design-review.md` | create | Claude 교차검토 프롬프트 SSOT. design path만 전달하고 read-only/advisory 출력 형식 고정 |
| `runtime/render-prompt.py` | modify | `render --phase design-review`, `--review-file` 토큰, `detect-fallback` JSON 파서/판별 서브커맨드 추가 |
| `runtime/README.md` | modify | 외부 Claude CLI 계약에 `--output-format json`, fallback 판별, `review-design` 러너, `cross_reviewed_by` provenance 설명 추가 |
| `QUICKREF.md` | modify | 러너 빠른 참조에 선택적 설계 교차검토 명령과 advisory 의미 추가 |
| `kb/concepts/workflow.md` | modify | 전체 흐름도에 validator 통과 후 선택적 design cross-review 단계를 반영 |
| `.github/workflows/ci.yml` | modify | 새 pytest 디렉터리를 만들 경우 CI pytest 대상에 포함 |
| `tests/run-smoke.sh` | modify | portable smoke에 review 러너 복사와 성공/fallback/실패 대표 시나리오 추가 |
| `tests/bats/review-design.bats` | create | Bash review 러너 e2e 시나리오: validation gate, recursion guard, CLI/profile/version failures, success/fallback provenance |
| `tests/pester/review-design.Tests.ps1` | create | Pester mirror. bats와 같은 의미의 PowerShell review 러너 시나리오 |
| `tests/runtime/test_render_prompt.py` | create | `render-prompt.py`의 design-review 렌더와 `detect-fallback` JSON 판정 단위 테스트 |

## 테스트 기준 (Test Criteria)

- [ ] `python3 runtime/validator/cli.py kb/tasks/task-005/design.md`가 exit `0`으로 통과한다.
- [ ] `python3 -m pytest tests/validator tests/context_budget tests/status_board tests/runtime`가 통과한다.
- [ ] `runtime/render-prompt.py render --phase design-review`가 `templates/prompts/design-review.md`를 렌더하고 치환되지 않은 `{{TOKEN}}`이 남으면 exit `1`로 실패한다.
- [ ] `runtime/render-prompt.py detect-fallback`은 actual model이 `claude-fable-5`면 `fallback=false`, `claude-opus-4-8`이면 `fallback=true`를 출력한다.
- [ ] `detect-fallback`은 malformed JSON, model 필드 부재, response text 부재, 허용되지 않은 actual model을 모두 non-zero로 거부한다.
- [ ] `bash tests/run-smoke.sh`가 기존 시나리오와 새 review 러너 시나리오를 모두 통과한다.
- [ ] `bats tests/bats`와 `Invoke-Pester tests/pester`가 review 러너에 대해 의미상 같은 시나리오를 검증한다.
- [ ] review 러너는 invalid/draft `design.md`에서 Claude를 호출하지 않고 validator 실패를 전파한다.
- [ ] review 러너는 Claude Code 세션 내부에서 `CLAUDE_AUTO_FORCE=1` 없이는 재귀 가드로 스킵하고 `design-review.md`를 만들지 않는다.
- [ ] 성공 스텁은 `claude -p ... --model claude-fable-5 --effort max --fallback-model claude-opus-4-8 --output-format json` 인자를 받는다.
- [ ] 성공 시 `kb/tasks/<id>/design-review.md`가 생성 또는 교체되고, `manifest.md`에 `cross_reviewed_by`가 actual model, effort, CLI 버전, 날짜, fallback 여부와 함께 append된다.
- [ ] fallback 스텁이 actual model `claude-opus-4-8` JSON을 반환하면 러너는 exit `0`이며 provenance에 `fallback=true`를 남긴다.
- [ ] unknown model JSON은 `design-review.md`와 manifest를 쓰지 않고 non-zero로 실패한다.
- [ ] 정상 성공 경로 전후 `design.md` 해시가 동일함을 테스트한다.
- [ ] review 러너는 `implementation-notes.md`, `collab.md`, `kb/tasks/<id>/reviews/`, done-gate 관련 파일/규칙을 만들거나 수정하지 않는다.
- [ ] Claude CLI 버전 미달 스텁은 preflight에서 실패하고 실제 review 호출로 진행하지 않는다.
- [ ] `runtime/config/model-profiles.json` 부재 또는 malformed JSON은 조용한 기본값 없이 non-zero로 실패한다.
- [ ] `runtime/README.md`, `QUICKREF.md`, `kb/concepts/workflow.md`가 새 단계의 advisory 성격과 task-006 범위와의 분리를 설명한다.

## 오픈 이슈 (Open Issues)

- Claude CLI `--output-format json`의 실제 응답 schema가 환경별로 달라질 수 있다. task-005 구현은 지원하는 model/response 키 경로를 코드 상수와 테스트 fixture로 명시하고, 판별 불가 schema는 실패 처리한다.
- CLI 차원의 진정한 read-only sandbox flag는 이번 범위에서 가정하지 않는다. 대신 프롬프트 계약, runner가 직접 쓰는 산출물 제한, `design.md` 전후 해시 검증으로 정상 경로의 읽기전용 동작을 고정한다.
- `review-design`을 `codex-design`이나 `claude-implement`에 자동 연결할지는 이번 범위에서 결정하지 않는다. 문서에는 권장 선택 단계로만 노출하고, 구현 게이트는 validator 중심으로 유지한다.
