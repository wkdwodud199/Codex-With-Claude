# 설계 문서 — task-004

> Status: ready
> Inputs: `kb/tasks/task-004/manifest.md` 오너 결정, `runtime/validator/schema.json`, `runtime/lib/invoke-codex.{sh,ps1}`, `runtime/lib/invoke-claude.{sh,ps1}`, `templates/design.md`, `runtime/README.md`, `QUICKREF.md`, `tests/{run-smoke.sh,bats,pester,validator}`
> Outputs: 모델/effort 프로필 SSOT, 프롬프트 템플릿 SSOT, 실행 계획 기반 implement 라우팅, 실행 계획 검증 규칙, 명시적 CLI 호출·preflight·provenance 설계
> Next step: Claude가 이 문서를 기준으로 task-004를 구현하고, sh/ps1 및 bats/pester 패리티 검증까지 완료한다.

## 목표 (Objective)

`--auto` 러너가 사용자 전역 CLI 설정에 기대지 않도록 design 레인은 정적 모델/effort로 고정하고, implement 레인은 `design.md`의 실행 계획이 모델/effort와 병렬화 방식을 지시하는 2층 라우팅으로 전환한다. 동시에 프롬프트 본문과 필수 설계 섹션 규칙을 단일 원천에서 렌더링하고, 자동 생성 산출물의 모델/effort/CLI 버전 provenance를 manifest에 남긴다.

## 범위 (Scope)

- 포함:
  - `runtime/config/model-profiles.json`을 새로 만들어 design/review 정적 프로필과 implement 라우팅 정책을 선언한다.
  - `runtime/render-prompt.py`를 새로 만들어 `templates/prompts/*.md`, `runtime/validator/schema.json`, task 변수, 실행 계획 계약을 조합해 프롬프트를 렌더링한다.
  - `templates/prompts/design.md`와 `templates/prompts/implement.md`를 프롬프트 단일 원천으로 추가하고, 네 runner 라이브러리의 하드코딩 프롬프트를 제거한다.
  - `templates/design.md`에 `실행 계획 (Execution Plan)` 섹션을 추가한다.
  - `runtime/validator/`가 실행 계획 섹션을 검증하도록 확장한다. 섹션이 있으면 `implement_model`과 `implement_effort`가 프로필 화이트리스트 안에 있어야 한다.
  - `runtime/lib/invoke-codex.{sh,ps1}`와 `runtime/lib/invoke-claude.{sh,ps1}`가 프로필과 렌더러를 사용하고, CLI 호출에 모델/effort 플래그를 항상 명시한다.
  - `--auto` 성공 시 `kb/tasks/<id>/manifest.md`에 `generated_by` provenance를 기록한다.
  - `runtime/README.md`와 `QUICKREF.md`의 외부 CLI 계약과 러너 절을 갱신한다.
  - pytest, shell smoke, bats, Pester 테스트를 확장해 sh/ps1 및 bats/pester 동작 패리티를 유지한다.
- 제외:
  - 다중 `claude -p` 프로세스 fan-out 구현. v1은 단일 Claude 세션 안에서 서브에이전트 병렬화를 우선한다.
  - 새 외부 의존성 추가. Python은 stdlib만 사용한다.
  - `--skip-git-repo-check` 재도입 또는 codex sandbox 완화.
  - task-001~003 설계 문서에 실행 계획 섹션을 소급 추가하는 작업. 이 세 task는 legacy 예외로 섹션 부재를 허용한다.
  - 실제 외부 CLI 설치, 인증, 계정 설정 변경.

## 제약 (Constraints)

- design 레인 정적 프로필:
  - Codex: `gpt-5.5` + `model_reasoning_effort=xhigh`
  - Claude review/cross-check: `claude-fable-5` + `effort=max`
  - design 레인의 Claude fallback만 `--fallback-model claude-opus-4-8`를 사용하며, effort는 `max` 그대로 유지한다.
- implement 레인은 정적 강제하지 않는다. `실행 계획 (Execution Plan)`의 `implement_model`과 `implement_effort`를 읽고 `claude -p --model <model> --effort <effort>`에 반영한다.
- 실행 계획 부재 시 기본값은 `claude-opus-4-8/high`이지만, task-001~003 같은 legacy 허용 경로에서만 쓴다. 기본값 사용은 경고 로그와 provenance에 남긴다.
- implement 라우팅 화이트리스트는 `claude-fable-5 | claude-opus-4-8`와 `medium | high | xhigh | max`로 제한한다.
- 프로필 파일이 없거나 JSON 해석/검증에 실패하면 `--auto`는 non-zero로 거부한다. 조용한 기본값이나 조용한 fallback은 금지한다.
- CLI preflight는 다음 기준보다 낮은 버전을 안내 후 실패시킨다:
  - Claude CLI `2.1.201`: `--model`, `--effort low|medium|high|xhigh|max`, `--fallback-model` 지원 기준
  - Codex CLI `0.142.4`: `-m`, `-c model_reasoning_effort=` 지원 기준
- codex 호출 형태는 `codex exec --sandbox workspace-write -C <root> -m <model> -c model_reasoning_effort=<effort> <prompt>`를 유지한다.
- `runtime/validator/schema.json`은 검증 규칙의 단일 진실 원천이다. 프롬프트 템플릿에는 필수 7섹션 이름을 다시 하드코딩하지 않고, 렌더 시점에 schema에서 주입한다.
- sh와 PowerShell은 같은 정책, 같은 오류 의미, 같은 테스트 시나리오를 가져야 한다. bats와 Pester 시나리오 수와 의미도 계속 맞춘다.

## 구현 단계 (Implementation Steps)

1. `runtime/config/model-profiles.json`을 추가한다.
   - `design.codex`에는 `model=gpt-5.5`, `effort=xhigh`, `min_cli_version=0.142.4`를 둔다.
   - `review.claude`에는 `model=claude-fable-5`, `effort=max`, `fallback_model=claude-opus-4-8`, `min_cli_version=2.1.201`을 둔다.
   - `implement`에는 `routing=design-directed`, `default={model: claude-opus-4-8, effort: high}`, `allowed_models`, `allowed_efforts`를 둔다.
2. `runtime/render-prompt.py`를 추가한다.
   - stdlib만 사용한다.
   - `render` 모드는 `templates/prompts/<phase>.md`를 읽고 task id, 경로, 작업 설명, 구현 노트 경로, 필수 섹션 목록, 실행 계획 계약을 주입해 stdout으로 프롬프트를 출력한다.
   - `profile` 모드는 shell/PowerShell이 JSON을 직접 파싱하지 않도록 `--phase`, `--cli`, `--field`로 model, effort, fallback_model, min_cli_version, default 여부를 한 값씩 출력한다.
   - `route-implement` 모드는 `design.md`의 실행 계획을 읽어 implement model/effort를 결정하고, 섹션 부재 legacy 경로에서는 기본값과 warning reason을 반환한다.
   - `check-cli-version` 모드는 CLI 버전 문자열을 받아 프로필의 최소 버전과 비교한다.
3. `templates/prompts/design.md`와 `templates/prompts/implement.md`를 추가한다.
   - design 템플릿은 schema에서 주입된 필수 섹션 목록과 실행 계획 계약을 사용한다.
   - implement 템플릿은 design 경로와 implementation notes 경로만 전달하고, design 본문을 인라인하지 않는다.
   - 기존 heredoc 프롬프트와 중복되는 문구는 runner에서 제거한다.
4. `templates/design.md`에 `실행 계획 (Execution Plan)` 섹션을 추가한다.
   - 최소 필드: `implement_model`, `implement_effort`, `routing_reason`.
   - 병렬화 표 컬럼: `unit`, `파일 범위`, `depends_on`, `group`.
5. validator를 확장한다.
   - `schema.json`에 실행 계획 섹션명, 필수 필드명, 병렬화 표 필수 컬럼, legacy missing 허용 task id(`task-001`, `task-002`, `task-003`), profile path를 선언한다.
   - `rules.py`는 섹션이 존재하면 필드 누락, 모델/effort 화이트리스트 위반, 병렬화 표 누락을 `ValidationError`로 반환한다.
   - task id는 파일 경로 또는 문서 제목의 `task-<NNN>`에서 도출한다. 도출 실패 시 새 규칙은 legacy 예외를 적용하지 않는다.
   - `cli.py`는 profile IO/JSON 오류를 환경 오류로 보고 기존 exit code `2` 의미를 유지한다.
6. `invoke-codex.{sh,ps1}`를 프로필/렌더러 기반으로 바꾼다.
   - `--auto`에서 codex 존재 확인 후 `codex --version` preflight를 수행한다.
   - 프로필 해석 실패, 버전 미달, 프롬프트 렌더 실패는 non-zero로 종료한다.
   - 실제 호출은 `exec --sandbox workspace-write -C <root> -m gpt-5.5 -c model_reasoning_effort=xhigh`를 포함한다.
   - codex 호출 성공과 design validation 통과 후 manifest provenance를 기록한다.
7. `invoke-claude.{sh,ps1}`를 implement 라우팅 기반으로 바꾼다.
   - `claude-implement --auto`는 `route-implement` 결과를 사용해 `claude -p --model <model> --effort <effort>`를 호출한다.
   - 실행 계획이 없는 legacy task는 `claude-opus-4-8/high`를 쓰되, `[WARN]` 로그와 manifest provenance에 `route=default`를 남긴다.
   - design/review phase에서 Claude를 호출하는 소비자는 `claude-fable-5/max --fallback-model claude-opus-4-8`를 사용한다. 이 fallback은 implement phase에는 적용하지 않는다.
8. provenance 기록을 구현한다.
   - 형식: `generated_by: <phase>=<cli> <model>/<effort> @<cli-version>, <YYYY-MM-DD> (<route/fallback/default detail>)`
   - 예: `generated_by: design=codex gpt-5.5/xhigh @codex 0.142.4, 2026-07-05 (fallback=false); implement=claude claude-opus-4-8/xhigh @claude 2.1.201, 2026-07-05 (route=execution-plan)`
   - fallback이 설정만 되었는지, 실제 발동했는지 구분해 기록한다. CLI가 실제 fallback 발동 여부를 보고하지 못하면 design/review auto 경로는 경고가 아니라 실패로 처리한다.
9. 문서를 갱신한다.
   - `runtime/README.md`: 새 호출 형태, 최소 CLI 버전, preflight 실패, fallback/default/provenance 정책을 반영한다.
   - `QUICKREF.md`: 러너 `--auto` 절에 모델/effort 명시, execution-plan routing, legacy default warning을 추가한다.
10. 테스트를 확장한다.
   - validator pytest에 실행 계획 통과 fixture, 잘못된 model/effort fixture, 병렬화 표 누락 fixture, legacy task-001~003 섹션 부재 통과 케이스를 추가한다.
   - shell smoke와 bats/Pester에 모델/effort 인자 전달, profile 파일 부재/불량 JSON 실패, CLI 버전 미달 실패, legacy default warning, manifest provenance 기록을 추가한다.
   - codex 스텁은 `--sandbox workspace-write -C <root> -m gpt-5.5 -c model_reasoning_effort=xhigh`가 들어오는지 검증하고, `--skip-git-repo-check`가 없는지 계속 검증한다.
   - claude 스텁은 execution plan에서 지정한 `--model`과 `--effort`가 들어오는지 검증한다.

## 실행 계획 (Execution Plan)

- implement_model: `claude-opus-4-8`
- implement_effort: `xhigh`
- routing_reason: sh/PowerShell 러너, Python validator, 프롬프트 렌더링, provenance가 맞물리는 cross-runtime 변경이라 기본 `high`보다 높은 추론을 쓰되, 요구사항과 파일 범위가 명확하므로 `max`는 쓰지 않는다.
- execution_mechanism: v1은 단일 `claude -p` 세션에서 구현하고, 필요하면 세션 내부 서브에이전트로 독립 unit을 병렬화한다. 다중 `claude -p` 프로세스 fan-out은 같은 워크트리 충돌 위험 때문에 보류한다.

| unit | 파일 범위 | depends_on | group |
|------|-----------|------------|-------|
| U1-profile-contract | `runtime/config/model-profiles.json`, `runtime/render-prompt.py`의 profile/version 서브커맨드 | 없음 | G1 |
| U2-prompt-ssot | `runtime/render-prompt.py`의 render 서브커맨드, `templates/prompts/design.md`, `templates/prompts/implement.md` | U1-profile-contract | G1 |
| U3-validator-execution-plan | `runtime/validator/schema.json`, `runtime/validator/rules.py`, `runtime/validator/cli.py`, `templates/design.md`, `tests/validator/*` | U1-profile-contract | G2 |
| U4-bash-runner-integration | `runtime/lib/invoke-codex.sh`, `runtime/lib/invoke-claude.sh`, `tests/run-smoke.sh`, `tests/bats/*` | U1-profile-contract, U2-prompt-ssot, U3-validator-execution-plan | G3 |
| U5-powershell-runner-integration | `runtime/lib/invoke-codex.ps1`, `runtime/lib/invoke-claude.ps1`, `tests/pester/*` | U1-profile-contract, U2-prompt-ssot, U3-validator-execution-plan | G3 |
| U6-docs-and-provenance-polish | `runtime/README.md`, `QUICKREF.md`, manifest provenance assertions in smoke/bats/pester | U4-bash-runner-integration, U5-powershell-runner-integration | G4 |

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| `runtime/config/model-profiles.json` | create | phase별 모델/effort, 최소 CLI 버전, implement whitelist/default를 담는 SSOT |
| `runtime/render-prompt.py` | create | prompt 렌더링, 프로필 조회, implement route 해석, CLI 버전 비교를 stdlib로 제공 |
| `templates/prompts/design.md` | create | Codex design 프롬프트 템플릿 단일 원천 |
| `templates/prompts/implement.md` | create | Claude implement 프롬프트 템플릿 단일 원천 |
| `templates/design.md` | modify | 신규 `실행 계획 (Execution Plan)` 섹션 추가 |
| `runtime/validator/schema.json` | modify | 실행 계획 검증 규칙, legacy 예외, profile path 선언 |
| `runtime/validator/rules.py` | modify | 실행 계획 필드/화이트리스트/병렬화 표 검증 추가 |
| `runtime/validator/cli.py` | modify | profile 로드 오류를 exit `2`로 전달하고 task id context를 규칙에 제공 |
| `runtime/validator/README.md` | modify | 실행 계획 검증과 profile 의존성 문서화 |
| `runtime/lib/invoke-codex.sh` | modify | design 프로필, prompt renderer, codex `-m/-c`, version preflight, provenance 통합 |
| `runtime/lib/invoke-codex.ps1` | modify | Bash와 동일한 Codex auto 호출 정책 구현 |
| `runtime/lib/invoke-claude.sh` | modify | implement 실행 계획 라우팅, Claude `--model/--effort`, legacy default warning, provenance 통합 |
| `runtime/lib/invoke-claude.ps1` | modify | Bash와 동일한 Claude auto 호출 정책 구현 |
| `runtime/README.md` | modify | 외부 CLI 호출 계약과 최소 버전, fallback/default/provenance 정책 갱신 |
| `QUICKREF.md` | modify | 러너 빠른 참조에 execution-plan routing과 명시적 모델/effort 정책 추가 |
| `tests/validator/fixtures/*` | modify/create | 실행 계획 good/bad/legacy fixture 추가 및 기존 good fixture 갱신 |
| `tests/validator/test_rules.py` | modify | 실행 계획 규칙 단위 테스트 추가 |
| `tests/validator/test_cli.py` | modify | profile IO/JSON 오류 exit code와 JSON 출력 테스트 추가 |
| `tests/run-smoke.sh` | modify | shell smoke에 모델/effort, profile 실패, default warning, provenance 시나리오 추가 |
| `tests/bats/codex-design.bats` | modify | Codex auto 인자·preflight·provenance 시나리오 추가 |
| `tests/bats/claude-implement.bats` | modify | Claude route/default/provenance 시나리오 추가 |
| `tests/pester/codex-design.Tests.ps1` | modify | bats Codex 시나리오와 동등한 PowerShell 검증 추가 |
| `tests/pester/claude-implement.Tests.ps1` | modify | bats Claude 시나리오와 동등한 PowerShell 검증 추가 |

## 테스트 기준 (Test Criteria)

- [ ] `python3 runtime/validator/cli.py kb/tasks/task-004/design.md`가 exit `0`으로 통과한다.
- [ ] `python3 -m pytest tests/validator tests/context_budget tests/status_board`가 통과한다.
- [ ] `bash tests/run-smoke.sh`가 통과하며 새 model/effort, profile failure, default warning, provenance 시나리오를 포함한다.
- [ ] `bats tests/bats`와 `Invoke-Pester tests/pester`가 의미상 같은 시나리오 수와 기대 결과로 통과한다.
- [ ] Codex 스텁 테스트가 `exec --sandbox workspace-write -C <root> -m gpt-5.5 -c model_reasoning_effort=xhigh`를 확인하고 `--skip-git-repo-check` 부재를 확인한다.
- [ ] Claude 스텁 테스트가 실행 계획의 `claude-opus-4-8/xhigh`를 `--model/--effort`로 받는지 확인한다.
- [ ] 실행 계획이 없는 task-001~003 legacy 경로는 `claude-opus-4-8/high` 기본값을 쓰며, warning 로그와 `route=default` provenance가 남는다.
- [ ] 실행 계획이 있는 문서에서 허용되지 않은 model/effort는 validator exit `1`로 차단된다.
- [ ] `runtime/config/model-profiles.json` 부재 또는 malformed JSON은 `--auto`를 non-zero로 차단하고 조용한 fallback을 하지 않는다.
- [ ] CLI 버전 미달 스텁은 안내 메시지와 non-zero 종료를 만들고, 실제 CLI 호출로 진행하지 않는다.
- [ ] design/review fallback이 실제 발동하면 provenance에 fallback source와 target이 기록된다. fallback 발동 여부를 CLI에서 판별할 수 없으면 design/review auto는 실패한다.
- [ ] `runtime/README.md`와 `QUICKREF.md`가 새 호출 계약과 라우팅 정책을 설명한다.

## 오픈 이슈 (Open Issues)

- `gpt-5.5` 모델 문자열은 구현 시작 시 실제 Codex CLI preflight에서 최종 확인한다. 실패 시 다른 모델로 조용히 대체하지 않고 안내 후 non-zero로 종료한다.
- Claude CLI가 fallback 발동 여부를 구조적으로 보고하지 않는 환경이면 design/review auto provenance 계약을 만족할 수 없으므로 해당 경로는 실패시킨다. implement 경로에는 fallback을 적용하지 않는다.
