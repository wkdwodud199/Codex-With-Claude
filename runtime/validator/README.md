# validator — design.md 검증기

> Load: on-demand
> Last-reviewed: 2026-04-17

설계 문서(`kb/tasks/<id>/design.md`) 검증의 **단일 진실 원천**입니다.
bash 스크립트, PowerShell 스크립트, 향후 다른 언어 러너 모두 이 모듈 하나를 호출합니다.

## 사용

```bash
python3 runtime/validator/cli.py <design.md>
python3 runtime/validator/cli.py <design.md> --json
python3 runtime/validator/cli.py <design.md> --schema <alternate.json>
```

종료 코드:
- `0` — 검증 통과
- `1` — 검증 실패 (오류 리스트 출력)
- `2` — 파일 없음 / 디코딩 실패 / **프로필(model-profiles.json) 부재·해석 실패** (task-004)

## 실행 계획 (Execution Plan) 규칙 — task-004

design.md 의 `실행 계획 (Execution Plan)` 섹션을 게이트한다 (설계 주도 라우팅):

- 섹션 **부재**: legacy(`task-001`~`task-003`)만 허용. task id 는 경로(`kb/tasks/<id>/`) 또는
  문서 제목의 `task-<NNN>` 에서 파생하며, 파생 실패 시 legacy 예외를 적용하지 않는다.
- 섹션 **존재**: `implement_model` / `implement_effort` / `routing_reason` 필수,
  model/effort 는 `runtime/config/model-profiles.json` 의 implement 화이트리스트 내여야 하고,
  병렬화 표(`unit / 파일 범위 / depends_on / group`)에 데이터 행이 1개 이상 있어야 한다.
- 화이트리스트는 섹션이 있을 때만 로드한다 — 프로필 IO/JSON 오류는 종료 코드 `2`.

## done-gate (`--check-done`) 강화 — 2026-07-05

`schema.json` 의 `done_gate` 블록이 단일 원천이다:

- **구현 노트 Status**: `done` 만 완료로 인정 (`draft`/`in-progress`/임의 값 차단).
- **산출물 요약 Status**: `done` 만 인정 — status board 집계 기준과 일치.
- **manifest.md**: 존재해야 하고, `inputs`/`concepts_needed`/`related_files` 가
  비어 있거나 템플릿 placeholder 면 거부 (fast-path 로드 세트 품질 게이트).
- legacy `task-001` 은 기존 allowlist 로 전체 우회 (변경 없음).

## 구성

| 파일 | 역할 |
|------|------|
| `schema.json` | 필수 섹션 · placeholder · 메타필드 · 상태값 등 규칙의 선언적 정의 |
| `parser.py` | BOM / CRLF 정규화, fenced-code 제거, 메타블록·섹션·placeholder 수집 |
| `rules.py` | 파싱된 문서에 schema 규칙 적용 → `ValidationError` 리스트 반환 |
| `cli.py` | argv 진입점 (JSON / 사람이 읽는 포맷) |

## Python 의존성

stdlib만 사용. 파이썬 3.8 이상. 설치 패키지 불필요.

러너(`*.sh`, `*.ps1`)가 아래 순서로 파이썬을 탐지합니다:

1. `python3`
2. `python`
3. `py -3`

## 테스트

```bash
# pytest (validator 전체 스위트)
python3 -m pytest tests/validator

# bash 기반 엔드투엔드 smoke
bash tests/run-smoke.sh

# bats 버전 (선택, CI에서 실행)
bats tests/bats
```
