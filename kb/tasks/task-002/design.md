# 설계 문서 템플릿 — task-002

> Status: ready
> Inputs: templates/design.md, AGENT.md, imp.md Phase A, kb/concepts/architecture.md, task-002 구현 요구사항
> Outputs: runtime/context-budget.py 설계, tests/context_budget/test_budget.py 테스트 기준
> Next step: Claude가 이 문서를 읽고 runtime/context-budget.py와 tests/context_budget/test_budget.py를 구현

## 목표 (Objective)

task 진입 시 에이전트가 기본으로 로드해야 하는 문서 세트의 총 바이트 수와 대략 토큰 추정치(bytes/4)를 계산하는 warning-only CLI를 추가한다. 신규 기본 로드 세트가 기존 baseline보다 작은지 비교해 Phase A의 최소 컨텍스트 관리 효과를 사람이 확인할 수 있게 한다.

## 범위 (Scope)

- 포함:
  - `runtime/context-budget.py` stdlib 전용 CLI 신규 작성
  - 신규 기본 세트 `QUICKREF.md + kb/tasks/<task-id>/manifest.md + kb/tasks/<task-id>/design.md` 측정
  - baseline `AGENT.md + CLAUDE.md + kb/tasks/<task-id>/design.md` 측정
  - `--baseline` 옵션으로 baseline 상세 출력 지원
  - 누락 파일을 0바이트로 처리하고 warning 메시지에 누락 목록 표시
  - 종료코드가 항상 0임을 보장하는 pytest 테스트 작성
- 제외:
  - CI fail gate 또는 hard budget 제한 도입
  - `AGENT.md`, `CLAUDE.md`, `QUICKREF.md`, manifest 파일 내용 수정
  - 새 런타임 의존성 또는 패키지 추가
  - 수기 `estimated_tokens` 필드 도입

## 제약 (Constraints)

- Python 3.8 이상에서 동작해야 하며 stdlib만 사용한다.
- CLI 형식은 `python3 runtime/context-budget.py <task-id> [--baseline]`이다.
- 모든 실행 경로의 종료코드는 0이어야 한다. 이 도구는 경고 전용이며 구현 또는 CI를 차단하지 않는다.
- 파일 크기는 실제 파일의 바이트 수로 계산하고, 토큰 추정치는 `bytes / 4` 기준의 정수 또는 사람이 읽기 쉬운 근사값으로 출력한다.
- 누락 파일은 예외로 중단하지 않고 0바이트로 계산하되, 리포트에 warning으로 표시한다.
- 핵심 성공 기준은 신규 기본 세트 바이트 수가 baseline 바이트 수보다 작은지 여부를 명확히 출력하는 것이다.

## 구현 단계 (Implementation Steps)

1. `argparse` 기반 CLI를 만들고 `<task-id>`와 선택 옵션 `--baseline`을 파싱한다.
2. 저장소 루트 기준 경로 목록을 구성한다. 신규 세트는 `QUICKREF.md`, `kb/tasks/<task-id>/manifest.md`, `kb/tasks/<task-id>/design.md`이고 baseline은 `AGENT.md`, `CLAUDE.md`, `kb/tasks/<task-id>/design.md`이다.
3. 각 파일에 대해 `Path.stat().st_size`로 바이트 수를 읽고, 존재하지 않는 파일은 0바이트와 누락 warning으로 기록한다.
4. 신규 세트의 파일별 바이트, 총 바이트, 대략 토큰 추정치를 출력한다.
5. `--baseline`이 지정되면 baseline의 파일별 바이트, 총 바이트, 대략 토큰 추정치를 함께 출력한다.
6. 신규 총 바이트와 baseline 총 바이트를 항상 비교해 `new < baseline` 여부와 차이를 warning-only 결과로 출력한다.
7. 모든 오류성 상황을 사용자에게 warning으로 보고하고 `main()`이 항상 0을 반환하도록 정리한다.

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| runtime/context-budget.py | create | 신규 기본 로드 세트와 baseline의 바이트/토큰 추정치를 계산하는 warning-only CLI |
| tests/context_budget/test_budget.py | create | 정상 계산, 누락 파일, `--baseline`, 항상 0 종료코드 동작을 검증하는 pytest 테스트 |

## 테스트 기준 (Test Criteria)

- [ ] 임시 repo fixture에서 신규 기본 세트 총 바이트와 bytes/4 토큰 추정치가 기대값으로 출력된다.
- [ ] `--baseline` 실행 시 baseline 파일별/총합 정보와 신규 세트 대비 차이가 출력된다.
- [ ] `manifest.md` 또는 `QUICKREF.md`가 없을 때 해당 파일은 0바이트로 계산되고 warning이 출력된다.
- [ ] 누락 파일이 있어도 CLI 종료코드는 0이다.
- [ ] 신규 기본 세트 바이트 수가 baseline보다 작은 경우 성공 기준 메시지가 명확히 출력된다.
- [ ] 신규 기본 세트 바이트 수가 baseline 이상인 경우에도 실패하지 않고 warning-only 메시지와 종료코드 0을 유지한다.

## 오픈 이슈 (Open Issues)

- 없음. Phase A 방침에 따라 이 작업은 측정과 경고 출력까지만 담당하며 fail gate 도입은 후속 운영 경험 이후 별도 task로 다룬다.
