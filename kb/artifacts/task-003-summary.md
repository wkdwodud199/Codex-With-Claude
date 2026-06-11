# 산출물 요약 — task-003

> Status: done
> Inputs: kb/tasks/task-003/implementation-notes.md
> Outputs: 이 요약 문서
> Next step: Phase B/D 는 사용량 증가 시 재평가

## 작업 요약

- **Task ID**: task-003
- **제목**: 거버넌스 enforcement — status board 생성기 + done-gate
- **완료일**: 2026-06-09
- **방식**: Codex→Claude dogfood (Codex 설계 → validator 게이트 → Claude 구현)

## 산출물 목록

| 산출물 | 경로 | 설명 |
|--------|------|------|
| status board 생성기 | `runtime/generate-status.py` | task Status 에서 status.md 활성/완료 표를 결정론적 생성 + `--check` drift 검사 |
| done-gate | `runtime/validator/cli.py --check-done` | done task 가 impl-notes + artifact 산출물을 갖췄는지 검증 (task-001 legacy 예외) |
| 러너 연결 | `runtime/claude-implement.{sh,ps1}` | 선택적 `--done` 단계로 done-gate 호출 |
| CI enforcement | `.github/workflows/ci.yml` | pytest 확장 + status board drift check + done-task 루프 |
| status 마커 | `kb/index/status.md` | 생성 블록 마커 도입 (사람 prose/로드맵 포인터는 블록 밖 보존) |
| 테스트 | `tests/status_board/`, `tests/validator/test_cli.py` | 25 케이스 (생성/멱등/drift/done-gate) |

## 주요 결정

- **완료 신호 = artifacts summary `Status: done`** (design Status 아님 — 설계는 ready 에서 동결). 설계 대비 의도적 편차, impl-notes 기록.
- status.md 를 **생성형**으로 전환 → "사람이 문서를 손대지 않아도 정확히 유지" 원칙 직접 구현. CI `--check` 가 drift 를 차단.
- 강제 고도는 **P0 3건**(CI 테스트 보강 + status board + done-gate)만; kb/-경로 lint·manifest CI 검사는 2-task 규모엔 과잉이라 prose 유지.

## 관련 문서

- 설계: `kb/tasks/task-003/design.md` (Codex 작성)
- 구현 노트: `kb/tasks/task-003/implementation-notes.md`
- 거버넌스 근거: 규약 Full Review (Claude 워크플로우 + Codex 독립, 2026-06-09)
