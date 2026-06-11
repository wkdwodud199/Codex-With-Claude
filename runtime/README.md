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
| `context-budget.py` | 기본 로드 세트 vs baseline 바이트/토큰 비교 — 경고 전용 (warning-only) |
| `generate-status.py` | `kb/index/status.md` 활성/완료 표 재생성 + `--check` drift 검사 |

## 외부 CLI 계약

러너는 다음 두 외부 CLI 이름에 의존한다. 자동 호출(`--auto`) 경로에서만 필요하며,
수동 모드에서는 호출하지 않는다.

### `claude`

- 호출 형태: `claude -p "<prompt>"`
- 용도: 구현자(implementer) 자동 호출 (`claude-implement --auto`).
- 설치/인증: Claude Code CLI. 인증은 CLI 자체 설정을 따른다.
- 프롬프트는 design.md 내용을 인라인하지 않고 **경로만** 전달한다 (컨텍스트 절약).

### `codex`

- 호출 형태: `codex exec --sandbox workspace-write -C "<project-root>" "<prompt>"`
  - **`--skip-git-repo-check` 는 사용하지 않는다** (이 레포는 git 저장소이며, git 안전망을 복원한다).
  - **`--sandbox workspace-write`** 로 codex 의 쓰기 범위를 워크스페이스로 제한한다 (codex 0.137+ 지원).
  - 설계 생성기는 `kb/tasks/<id>/` 아래 파일 하나만 쓰면 되므로 넓은 쓰기 표면이 필요 없다.
- 용도: 설계자(designer) 자동 호출 (`codex-design --auto`).
- 최소 버전: **codex 0.137** (관찰 기준). `--sandbox` 옵션이 이 버전에서 지원된다.
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

## 참고

- 상태 모델(설계 준비도 vs 구현 진행도): [AGENT.md](../AGENT.md) "문서 상태 전이" 절.
- 로드맵 / 실패 모드: [imp.md](../imp.md) (Failure Mode #11 — codex 자율 쓰기 표면).
