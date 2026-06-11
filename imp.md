# Codex-With-Claude 개선안 재정리 (실행 우선순위 포함)

---

## 진행 현황 (Progress Tracker)

> 마지막 갱신: 2026-06-09

| Phase | 상태 | 비고 |
|-------|------|------|
| Phase 0 — Validator 버그 픽스 (8건) | ✅ 완료 | Phase 1 과 번들 커밋 |
| Phase 1 — Validator Python 단일화 | ✅ 완료 | `runtime/validator/` + pytest + smoke |
| Phase 2 — Claude/Codex 자동 호출 대칭 | ✅ 완료 | `runtime/lib/invoke-*` + 재귀 가드 + --auto, pytest + smoke |
| Phase A — QUICKREF + per-task Manifest + context-budget (감산적; concepts 샤딩 드롭) | ✅ 완료 | 2026-06-09 (task-002 dogfood, −45% 감산 실측) |
| 거버넌스 enforcement — 사전 하드닝(D1–D3, PS/파서 버그) + status board 생성형 + done-gate + 문서 강등 | ✅ 완료 | 2026-06-09 (규약 Full Review, task-003 dogfood) |
| Phase B — Collab 파티셔닝 | ⏳ 대기 | Status 생성형은 거버넌스에서 당겨 완료; collab 분리만 잔여 |
| Phase C — Backend adapter seam | ⏳ 보류 | 두 번째 backend 요구 시 |
| Phase D — v2 Review loop | ⏳ 대기 | collab.md 예약 인터페이스 기반 |

### 재개 포인트

- 최신 검증기 CLI: `python3 runtime/validator/cli.py <design.md>`
- 러너 기본 동작: 수동 모드 (자동 호출 원하면 `--auto` 또는 `*_AUTO=1`)
- 재귀 가드: `CLAUDECODE`(주)/`CLAUDE_CODE_SESSION_ID` 등 설정 시 `--auto` 거부 (`*_AUTO_FORCE=1` 로만 우회)
- 테스트: `python3 -m pytest tests/validator tests/context_budget tests/status_board` + `bash tests/run-smoke.sh` + (CI) `bats tests/bats` + (Windows) `Invoke-Pester tests/pester`
- 컨텍스트 예산: `python3 runtime/context-budget.py <id> --baseline`
- 거버넌스: `python3 runtime/generate-status.py --check` (보드 drift) + `python3 runtime/validator/cli.py --check-done <id>` (done-gate)
- 다음에 열어야 할 절: Phase B 의 잔여(collab 파티셔닝)는 사용량 증가 후 재평가. Phase A·거버넌스 enforcement 는 2026-06-09 완료.

### Phase 라벨 매핑 (tracker ↔ 본문)

> 트래커 표는 `Phase 0/1/2`(완료) + `A/B/C/D`(예정) 체계를 쓴다.
> 본문 절 제목은 이 lettered 체계에 맞춘다 (내용 기준 매핑).

| Tracker | 본문 절 | 내용 |
|---------|---------|------|
| Phase 0 + 1 | "Phase 0 + Phase 1 — Validator 단일화 …" | 검증기 단일화 + 크로스플랫폼 안정화 (✅ 완료) |
| Phase 2 | (자동 호출 대칭은 Phase B 본문에서 함께 다룸) | invoke 라이브러리 + 재귀 가드 + `--auto` (✅ 완료) |
| Phase A | "Phase A — 최소 컨텍스트 관리 …" | QUICKREF + Manifest + Budget |
| Phase B | "Phase B — 선택적 자동 호출 / status 자동화" | generated status + 자동 호출 후속 |
| Phase C | "Phase C (Deferred) — Backend Adapter Seam" | 백엔드 어댑터 seam (보류) |
| Phase D | "Phase D — Review 자료 파티셔닝 …" | v2 review loop |

> 참고: `CWC_imp.md` 는 **보류(deferred)** 된 대안 방향 메모다 (profile별 스키마로 도메인 무관화,
> 출시된 Python validator 를 grep 재작성하는 방향이 **아님**). 정본 로드맵은 이 문서(`imp.md`)다.

---

## 요약 판단

이 저장소의 개선 방향 자체는 맞다. 다만 현재 저장소 규모를 기준으로 보면, **즉시 해야 할 개선**과 **미리 해두면 좋아 보이지만 아직은 이른 개선**이 섞여 있다.

핵심 판단은 다음과 같다.

1. **즉시 추진 권장**
   - 검증기 단일화
   - 크로스플랫폼 버그 픽스
   - 테스트/CI 보강
   - Bash 실행 권한 정상화
2. **작게 시작하며 도입 권장**
   - `QUICKREF.md`
   - per-task `manifest.md`
   - 컨텍스트 예산 측정 도구 (`warning`부터 시작)
3. **당장은 보류 권장**
   - 생성형 `status.md`
   - 조기 backend abstraction
4. **설계 수정 후 추진 권장**
   - review loop는 좋지만, `task status`와 `review status`는 분리해야 함

---

## 관찰 사실 (Phase 0/1/2 반영)

> 갱신: Phase 0/1/2 완료 후 기준. 아래 "해결됨" 항목은 초기 진단이었고 현재는 처리되었다.

### 해결됨 (Phase 0/1)

- ~~검증 로직이 4개 runner 파일에 복제~~ → **해결**: `runtime/validator/` Python 모듈로 단일화.
  4개 runner(`codex-design.{sh,ps1}`, `claude-implement.{sh,ps1}`)는 이제 validator CLI 만 호출한다.
- ~~Bash 스크립트 실행 비트 없음~~ / ~~`task-001` 노트의 `chmod +x 적용 완료` 와 실제 권한 불일치~~
  → **해결**: 러너 실행 권한 정리 + CI 가 `chmod +x` 후 smoke 를 실행해 회귀를 막는다.

### Phase 2 에서 추가된 것

- `runtime/lib/invoke-claude.{sh,ps1}`, `invoke-codex.{sh,ps1}` 로 자동 호출(`--auto`) 대칭화.
- 재귀 가드: Claude Code 세션 내부에서 `--auto` 거부 (`*_AUTO_FORCE=1` 로만 우회).

### 아직 작은 파일 (컨텍스트 확장은 여전히 미래 대비 성격)

- `kb/index/status.md`, `collab.md`, `kb/concepts/architecture.md` 는 아직 작다.

즉,

- **validator/크로스플랫폼 문제는 Phase 0/1 에서 이미 해소**되었고,
- **status/collab/backend 확장은 여전히 미래 대비 성격이 더 강하다** (Phase A 이후 단계적으로).

---

## 개선 원칙

### 1. 먼저 실제 문제를 줄인다
- 복제된 검증 로직 제거
- 플랫폼 차이로 생기는 버그 제거
- 문서와 실제 상태의 불일치 제거

### 2. 컨텍스트 관리는 “작게, 강제는 늦게” 간다
- 먼저 `QUICKREF + manifest + budget 측정`을 도입한다
- 충분히 운영한 뒤 hard fail 게이트로 올린다

### 3. 새 추상화는 실제 두 번째 사용처가 생길 때 도입한다
- backend seam은 Notion/Git backend 요구가 실제 생길 때 시작한다

### 4. 상태 모델은 역할을 분리한다
- 구현 상태와 리뷰 상태를 한 필드로 섞지 않는다

### 5. 새 의존성은 기본적으로 추가하지 않는다
- 테스트는 우선 **Python stdlib `unittest` + shell smoke**로 시작한다
- `pytest`, `bats`는 명시적 승인 또는 기존 도입 맥락이 생길 때 확장한다

---

## 권장 로드맵

---

## Phase 0 + Phase 1 — Validator 단일화 + 크로스플랫폼 안정화 (최우선)

### Goal
현재 4곳에 복제된 설계 검증 로직을 Python 단일 모듈로 통합하고, 이미 확인된 크로스플랫폼 취약점을 테스트와 함께 고친다.

### 이 Phase에서 반드시 해결할 것
1. `Status: ready\r` / trailing whitespace 허용
2. UTF-8 BOM 처리
3. fenced code block 내부의 가짜 section/status 무시
4. placeholder substring false positive 제거
5. duplicate section 감지
6. Bash 스크립트 실행 권한 정리 (`0755`)
7. PowerShell UTF-8 출력 안정화
8. `> Status:` 정규식 여유 공백 허용

### 수정 파일
- `runtime/codex-design.sh`
- `runtime/claude-implement.sh`
- `runtime/codex-design.ps1`
- `runtime/claude-implement.ps1`

### 추가 파일
- `runtime/validator/__init__.py`
- `runtime/validator/rules.py`
- `runtime/validator/parser.py`
- `runtime/validator/cli.py`
- `tests/validator/fixtures/*.md`
- `tests/validator/test_parser.py`
- `tests/validator/test_rules.py`
- `tests/validator/test_cli.py`

### 구현 원칙
- shell/PowerShell 래퍼는 검증 규칙을 가지지 않고, **오직 Python validator CLI를 호출**한다
- validator는 stdlib만 사용한다
- Python probe 순서는 `python3` → `python` → `py -3`
- Python이 없으면 설치 힌트를 출력하고 실패한다
- **legacy shell validator fallback은 두지 않는다**
  - 이유: 단일 진실 원천 원칙을 다시 깨기 때문

### Risks
- 규칙이 엄격해지면서 기존 `task-001/design.md`가 실패할 수 있음
- Windows에서 줄바꿈/인코딩 처리 차이로 예상 밖 실패 가능
- Python probe가 환경별로 다르게 동작할 수 있음

### Mitigations
- `task-001/design.md`를 golden fixture로 포함
- Windows/macOS/Linux CI matrix 필수
- 규칙 변경과 fixture 변경은 같은 PR에서 묶는다
- 실패 메시지를 사람이 바로 수정 가능한 수준으로 구체화한다

### Tests added
- `python -m unittest discover -s tests/validator -v`
- shell smoke test:
  - good fixture에 대해 0 반환
  - bad fixture에 대해 non-zero 반환
- CI matrix:
  - ubuntu-latest
  - macos-latest
  - windows-latest

### Context cost delta
- 런타임 중복 코드 감소
- 에이전트 로드량 변화는 거의 없지만 유지보수 비용이 크게 줄어듦

### 이 Phase 완료 기준
- 검증 로직이 1곳에만 존재한다
- `.sh` 스크립트가 실제 실행 가능하다
- `task-001` 회귀 테스트가 통과한다
- Windows/macOS/Linux에서 동일 fixture 결과가 나온다

---

## Phase A — 최소 컨텍스트 관리 도입 (QUICKREF + Manifest + Budget Warning)

> ✅ **완료 (2026-06-09, task-002 dogfood)**: `QUICKREF.md` + `templates/manifest.md` + 러너 manifest 자동생성(`codex-design.{sh,ps1}`) + `runtime/context-budget.py`. 실측 감산 **−45%** (신규 7,607B < baseline 13,922B). **concepts 샤딩은 드롭** — 현재 `kb/concepts/` 는 단일 1.5KB 파일이라 샤딩은 파일만 증가시킨다(concepts/ 가 ~5–6개 초과 시 재평가). QUICKREF 는 AGENT/CLAUDE preamble 을 routine 경로에서 **대체**하도록 설계(추가 아님).

### Goal
문서 구조를 과하게 쪼개지 않고, 에이전트가 매 턴 읽어야 할 파일 수를 줄이는 최소 장치를 도입한다.

### 이 Phase에서 도입할 것
1. 루트 `QUICKREF.md` 추가
2. per-task `kb/tasks/<id>/manifest.md` 추가
3. `runtime/context-budget.py` 추가
4. `AGENT.md`, `CLAUDE.md`는 소폭 슬림화하되 과도한 샤딩은 하지 않음

### 수정 파일
- `AGENT.md`
- `CLAUDE.md`
- `templates/design.md`
- `runtime/codex-design.sh`
- `runtime/codex-design.ps1`

### 추가 파일
- `QUICKREF.md`
- `templates/manifest.md`
- `kb/tasks/<id>/manifest.md` (새 task부터 적용)
- `runtime/context-budget.py`
- `tests/context_budget/test_budget.py`

### Manifest 최소 스키마
초기 버전은 아래만 가진다.

- `task_id`
- `inputs`
- `concepts_needed`
- `related_files`
- `notes`

### 하지 않을 것
- 아직 `estimated_tokens` 같은 수기 추정 필드는 넣지 않음
- `kb/concepts/architecture.md`를 무조건 다분할하지 않음
- `AGENT.md` / `CLAUDE.md`를 억지로 1 KB대까지 줄이지 않음
- `Load:` 헤더는 권장하되, 초기에는 lint 강제보다 문서 관례로 시작

### 운영 규칙
- 기본 로드 세트는 `QUICKREF.md + manifest.md + design.md`
- `context-budget.py`는 우선 **경고(warning)** 만 출력
- CI fail gate는 운영 경험이 쌓인 뒤 도입

### Risks
- manifest를 만들어도 실제 사용자가 무시할 수 있음
- QUICKREF와 AGENT/CLAUDE 내용이 중복될 수 있음
- 문서 수가 늘어 관리 포인트가 오히려 많아질 수 있음

### Mitigations
- QUICKREF는 1페이지 요약만 유지
- manifest는 새 task 생성 시 runner가 자동 생성
- AGENT/CLAUDE는 “상세 규칙 보존 + 진입부 요약 강화” 정도로만 조정
- budget는 fail이 아니라 warning으로 시작해 운영 마찰을 줄임

### Tests added
- manifest 생성 테스트
- context budget 계산 테스트
- task-001 기준 기본 로드 세트 바이트 측정 테스트

### Context cost delta
- 평균 task 진입 컨텍스트를 줄일 가능성이 높음
- 다만 실제 효과 측정 전까지 수치는 목표치로만 다루고, hard commitment로 고정하지 않음

### 이 Phase 완료 기준
- 새 task 생성 시 `manifest.md`가 자동 생성된다
- QUICKREF만 읽어도 기본 흐름을 이해할 수 있다
- context budget이 CI 로그에 표시된다

---

## Phase D — Review 자료 파티셔닝 + Review Loop 기반 다지기

### Goal
v2 review loop를 준비하되, 현재 작은 파일들을 너무 이르게 generated/archived 구조로 바꾸지 않고, per-task review 축적 구조부터 도입한다.

### 이 Phase에서 도입할 것
1. `kb/tasks/<id>/reviews/` 디렉터리 관례 추가
2. `templates/review.md` 추가
3. `runtime/codex-review.sh` / `.ps1` 추가
4. review 규칙 validator 추가

### 유지할 것
- 루트 `collab.md`는 당장 삭제하지 않음
- `collab.md`는 v2 개요/인터페이스 설명 문서로 유지
- `kb/index/status.md`는 아직 수동 관리 유지

### 추가 파일
- `runtime/codex-review.sh`
- `runtime/codex-review.ps1`
- `runtime/validator/review_rules.py`
- `templates/review.md`
- `tests/review/test_rules.py`

### 상태 모델 수정
리뷰 상태와 작업 상태를 분리한다.

- design.md(설계 준비도) / implementation-notes.md(구현 진행도) 상태 모델 정의는
  [AGENT.md](./AGENT.md) "문서 상태 전이" 절이 단일 진실 원천이다.
- review status enum(`pending | request-changes | approved | rejected`)과 no-auto-revert /
  approved-done 게이트의 단일 예약 정의는 [collab.md](./collab.md) 다. 이 Phase 는 그 게이트를
  per-task review 축적 구조로 구현하는 작업만 다룬다.

### Risks
- review 파일이 task별로 누적되며 가시성이 떨어질 수 있음
- 문서 상태와 리뷰 상태가 어긋날 수 있음

### Mitigations
- 최신 review 한 건을 manifest나 implementation-notes에서 참조
- 필요 시 나중에 `reviews-digest.md`를 추가하되, 이 Phase에서는 필수 아님
- 상태 자동 전이보다 “게이트” 중심으로 설계해 모델 복잡도를 낮춤

### Tests added
- review rule 단위 테스트
- 간단한 end-to-end smoke:
  - design ready
  - implementation notes 존재
  - review 생성
  - latest review status에 따라 done 게이트 판정

### Context cost delta
- 리뷰 문서가 per-task 경로에 갇히므로 전역 컨텍스트 오염은 낮음

### 이 Phase 완료 기준
- task별 review 기록 위치가 표준화된다
- review verdict가 task completion gate에 사용된다
- `collab.md`를 유지한 상태에서도 실제 review 문서가 per-task 경로에 축적되기 시작한다

---

## Phase B — 선택적 자동 호출 / status 자동화 (사용량 증가 후 재평가)

### Goal
사용량이 실제로 늘어난 뒤, 자동 호출과 generated status board가 필요할 때만 도입한다.

### 포함 후보
1. `claude-implement --auto`
2. `codex-design` / `claude-implement` 공통 invoke 라이브러리
3. generated `kb/index/status.md`
4. `kb/index/history/` 아카이브

### 지금 바로 하지 않는 이유
- 현재 `status.md`는 작다
- `collab.md`도 아직 placeholder 수준이다
- 자동 호출은 validator/manifest보다 우선순위가 낮다
- pre-commit 기반 generated file 워크플로는 아직 관리 비용이 더 클 수 있다

### 도입 조건
아래 중 2개 이상 충족 시 재평가:

- 활성 task가 10개 이상 지속
- `status.md`가 3 KB 이상으로 성장
- review 파일이 여러 task에 누적되어 탐색 비용이 커짐
- 사용자가 실제로 `--auto` 흐름을 자주 원함

### Risks
- 자동 호출이 중첩 세션/재귀 실행을 만들 수 있음
- generated status가 merge conflict를 늘릴 수 있음

### Mitigations
- `--auto`는 opt-in 유지
- 세션 감지 환경변수로 재귀 차단
- generated status는 도입 시에도 수동 preamble + generated block만 사용
- pre-commit보다 CI regenerate check를 우선 고려

---

## Phase C (Deferred) — Backend Adapter Seam

### 판단
현재 시점에서는 **보류**가 맞다.

### 이유
- 실제 backend는 `local_md` 하나뿐이다
- 두 번째 backend가 아직 요구사항으로 확정되지 않았다
- 지금 추상화를 만들면 유지 표면적만 커질 가능성이 높다

### 재개 조건
아래 중 하나가 실제 요구로 들어오면 시작:

- Notion backend를 실제 연결해야 함
- Git-backed remote storage가 실제 필요해짐
- validator/runtime가 local filesystem 가정을 깨야 하는 요구가 생김

### 그때의 최소 시작점
- `local_md.py` 유틸리티부터
- abstract base는 실제 두 번째 구현이 생길 때 도입

---

## Failure Mode Catalog — 우선 관리할 실패 모드

| # | 실패 모드 | 방어 수단 |
|---|----------|----------|
| 1 | Python 미설치 | `python3 → python → py -3` 순 probe, 없으면 설치 힌트 + 실패 |
| 2 | BOM/CRLF 회귀 | validator fixture + Windows CI |
| 3 | fenced code false positive | parser에서 fenced block 제거 후 규칙 평가 |
| 4 | placeholder substring 오탐 | 전체 라인/정확 패턴 기준 검사 |
| 5 | task-001 golden 회귀 | fixture 동기화 + 같은 PR에서 갱신 |
| 6 | Bash 실행 불가 | `0755` 권한 검증 테스트 추가 |
| 7 | QUICKREF/manifest가 실제로 안 쓰임 | runner 자동 생성 + CI 로그에 budget 표시 |
| 8 | review 상태와 task 상태 혼선 | 상태 필드 분리 |
| 9 | generated status 도입 후 충돌 | 현재는 도입 보류, 필요 시 CI regenerate check 우선 |
| 10 | 조기 추상화로 구조 과복잡화 | backend seam 보류 |
| 11 | codex exec 자율 쓰기 표면 (`--full-auto` / `--skip-git-repo-check`) | 샌드박스 `--sandbox workspace-write` 로 쓰기 범위 제한, `--skip-git-repo-check` 제거(git 안전망 복원), auto 호출 전 preflight, codex 종료 코드 전파 |

---

## 첫 PR 스코프 (권장)

### PR 1 — Validator 추출 + 회귀 테스트 + 권한 수정

포함:
- `runtime/validator/` 추가
- 4개 runner의 인라인 validator 제거
- Python CLI 호출로 전환
- `.sh` 실행 권한 수정
- validator fixture/test 추가
- GitHub Actions matrix 추가

불포함:
- manifest
- QUICKREF
- generated status
- collab 구조 변경
- backend abstraction
- review loop

### 이 PR이 좋은 이유
- 가장 큰 현실 문제를 먼저 해결한다
- diff가 비교적 응집적이다
- 되돌리기 쉽다
- 이후 단계의 기반이 된다

---

## 이후 PR 순서 (권장)

1. **PR 1**: Phase 0+1 (validator 단일화 + 크로스플랫폼) — ✅ 완료
2. **PR 2**: Phase A (`QUICKREF + manifest + context budget warning`)
3. **PR 3**: Phase D (`per-task reviews + review gate`)
4. **PR 4**: Phase B 후보 중 정말 필요한 것만 선택 (자동 호출 / generated status)
5. **PR 5 이후**: Phase C — backend seam 재평가

---

## Verification 계획

### PR 1 검증
1. `python -m unittest discover -s tests/validator -v`
2. Bash smoke:
   - good fixture → 0
   - bad fixture → non-zero
3. PowerShell smoke:
   - good fixture → success
   - bad fixture → failure
4. CI matrix 전체 green
5. `./runtime/claude-implement.sh task-001` 회귀 확인
6. `stat` 또는 동등 수단으로 `.sh` 실행 비트 확인

### PR 2 검증
1. 새 task 생성 시 `manifest.md` 자동 생성 확인
2. `python runtime/context-budget.py ...` 실행 시 기본 로드 세트 보고 확인
3. QUICKREF만 읽어도 기본 흐름 이해 가능 여부 수동 점검

### PR 3 검증
1. review 문서 생성
2. latest review verdict 파싱
3. `approved` 전까지 최종 done gate 차단
4. `request-changes`가 task status를 무조건 덮어쓰지 않는지 확인

---

## 수정 대상 후보 파일

### PR 1 기준
- `runtime/codex-design.sh`
- `runtime/claude-implement.sh`
- `runtime/codex-design.ps1`
- `runtime/claude-implement.ps1`
- `runtime/validator/*.py`
- `tests/validator/*`
- `.github/workflows/ci.yml`

### PR 2 기준
- `AGENT.md`
- `CLAUDE.md`
- `templates/design.md`
- `templates/manifest.md`
- `runtime/context-budget.py`
- `QUICKREF.md`

### PR 3 기준
- `runtime/codex-review.sh`
- `runtime/codex-review.ps1`
- `runtime/validator/review_rules.py`
- `templates/review.md`
- `collab.md` (삭제가 아니라 역할 재정의 여부만 검토)

---

## 실행 체크리스트

1. PR 1 브랜치 생성 (`feat/validator-python-extract`)
2. Python validator 모듈 작성
3. 4개 runner를 validator CLI 호출로 전환
4. `.sh` 실행 권한 수정
5. validator fixture/test 작성
6. CI matrix 추가
7. task-001 회귀 확인
8. PR 2에서 `QUICKREF + manifest` 도입
9. PR 3에서 per-task review 구조 도입
10. generated status / backend seam은 실제 사용량 증가 후 재평가

---

## 최종 판단

이 저장소의 개선 방향은 **“validator 안정화 → 최소 컨텍스트 관리 → review loop 기반”** 순서가 가장 타당하다.

반대로 아래는 지금 당장 강하게 밀 이유가 약하다.

- 생성형 `status.md`
- `collab.md` 즉시 삭제
- `architecture.md` 과도한 샤딩
- backend adapter seam 선도입

즉, **지금은 작고 확실한 기반 개선을 먼저 하고, 구조 확장은 실제 사용량이 늘어날 때 단계적으로 여는 계획**이 가장 현실적이다.
