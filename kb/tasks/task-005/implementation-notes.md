# 구현 노트 — task-005

> Status: done
> Inputs: kb/tasks/task-005/design.md
> Outputs: review-design 러너(sh/ps1) + design-review 프롬프트 + render-prompt detect-fallback/design-review 렌더 + advisory 산출물 계약
> Next step: 오너 리뷰 후 커밋/푸시. 후속: task-006(Phase D)와 함께 CI 확인

## 설계 대비 변경 사항

| 항목 | 설계 내용 | 실제 구현 | 변경 사유 |
|------|-----------|-----------|-----------|
| detect-fallback model 경로 | "지원 키 경로는 코드 상수로 작게 유지" | `model` · `modelUsage` 키 · `usage.model` 3경로 + **부분일치**(substring) | claude JSON 의 modelUsage 키는 버전 접미사(`-YYYYMMDD`)가 붙으므로 정확일치로는 요청 model 과 매칭 실패. 부분일치로 방어 |
| detect-fallback response_text | "result/content 계열" | top-level `result`(str) 우선, 없으면 `content[].text` 합 | 두 형식 모두 지원, 비면 exit 1 |
| pytest 위치 | `tests/runtime/test_render_prompt.py`(신규 디렉터리) | 동일 + `tests/runtime/__init__.py` + ci.yml pytest 경로에 `tests/runtime` 추가 | 설계대로 |

## 구현 결정 기록

1. **읽기전용 보증 메커니즘**: CLI 차원의 read-only sandbox 플래그를 가정하지 않고(설계 오픈이슈), design.md 실행 전후 SHA-256 해시(sh: sha256sum/shasum, ps1: Get-FileHash)를 비교해 변경 시 산출물을 쓰지 않고 실패. 프롬프트에도 "파일 수정 금지"를 명시(2중 방어).
2. **advisory 계약**: 검토 우려는 종료코드에 영향 없음. non-zero 는 precondition(validator)/렌더/프로필/CLI버전/JSON파싱/파일쓰기 오류에만. 재귀 가드 스킵은 exit 0(파일 미생성).
3. **경계 준수**: task-005 는 collab.md/done-gate/reviews/ 를 일절 건드리지 않음(task-006 소관). 산출물은 design-review.md + manifest provenance 뿐.
4. **provenance**: manifest 에 `cross_reviewed_by` append. 실제 응답 model 과 fallback 여부(true/false)를 명시 — 조용한 폴백 금지 정책(model-profiles.json)의 실현.

## 발생한 이슈

- claude `--output-format json` 의 실제 schema 가 환경/버전별로 다를 수 있음(설계 오픈이슈) → 지원 키 경로를 코드 상수로 좁게 두고 테스트 fixture 로 고정, 판별 불가 schema 는 실패 처리. 실 CLI 연동 시 schema 확인 후 경로 추가 가능.
- bats/pwsh 로컬 미설치 → review-design 시나리오를 portable smoke(run-smoke.sh)에 5건 미러해 로컬 검증. bats/pester 는 CI 에서 실행.

## 테스트 결과

| 테스트 기준 (design.md 참조) | 결과 | 비고 |
|------------------------------|------|------|
| validator cli.py kb/tasks/task-005/design.md → exit 0 | pass | |
| pytest tests/validator tests/context_budget tests/status_board tests/runtime | pass | 아래 전체 카운트 참조 |
| render --phase design-review + leftover 토큰 실패 | pass | pytest test_render_prompt |
| detect-fallback fable=false / opus=true | pass | pytest + smoke |
| detect-fallback malformed/no-model/no-text/unknown 거부 | pass | pytest 4케이스 |
| bash smoke review-design 5시나리오 | pass | run-smoke.sh |
| bats/Pester review-design 패리티 | 구성 완료 | 로컬 bats/pwsh 없음 → CI |
| 성공 스텁이 --model/--effort/--fallback-model/--output-format json 수신 | pass | smoke + bats/pester |
| 성공 시 design-review.md 생성 + manifest cross_reviewed_by append | pass | smoke |
| fallback(opus) → exit 0 + fallback=true provenance | pass | smoke |
| unknown model → 산출물 없이 실패 | pass | smoke |
| design.md 전후 해시 동일(읽기전용) | pass | smoke |
| CLI 버전 미달 preflight 실패 / 프로필 부재 실패 | pass | smoke |
| collab.md/reviews/done-gate 미접촉 | pass | 산출물 목록으로 확인 |

## 산출물

- `runtime/review-design.sh`, `runtime/review-design.ps1` — 교차검토 러너(신규)
- `templates/prompts/design-review.md` — 교차검토 프롬프트 SSOT(신규)
- `runtime/render-prompt.py` — `render --phase design-review` + `--review-file` + `detect-fallback` 서브커맨드
- `tests/runtime/test_render_prompt.py`(+__init__) — 11 케이스(신규), `.github/workflows/ci.yml` pytest 경로 확장
- `tests/bats/review-design.bats`, `tests/pester/review-design.Tests.ps1` — e2e 패리티(신규)
- `tests/run-smoke.sh` — review-design 5시나리오 추가
- 문서: `runtime/README.md`, `QUICKREF.md`, `kb/concepts/workflow.md`
