# 산출물 요약 — task-005

> Status: done
> Inputs: kb/tasks/task-005/implementation-notes.md
> Outputs: 이 요약 문서
> Next step: task-006(Phase D)와 함께 커밋/푸시/CI 확인

## 작업 요약

- **Task ID**: task-005
- **제목**: 설계 교차검증 러너 (P1) — Codex 설계 후 Claude fable-5/max 읽기전용 2차 검토
- **완료일**: 2026-07-05

## 산출물 목록

| 산출물 | 경로 | 설명 |
|--------|------|------|
| 교차검토 러너 | `runtime/review-design.{sh,ps1}` | validator 통과 후 Claude fable-5/max 읽기전용 검토, advisory |
| 교차검토 프롬프트 | `templates/prompts/design-review.md` | 읽기전용/파일수정금지/advisory 명시 SSOT |
| 렌더러 확장 | `runtime/render-prompt.py` | `render --phase design-review` + `detect-fallback`(JSON→실제model/fallback/본문) |
| advisory 산출물 | `kb/tasks/<id>/design-review.md` + manifest `cross_reviewed_by` | fallback 여부 provenance 포함 |
| 테스트 | pytest +11(tests/runtime) · smoke +5 · bats +9 · pester +9 | sh↔ps1 / bats↔pester 패리티 |

## 주요 결정

- **첫 fable-5/max 소비자**: task-004 가 선언만 해둔 `design.claude_cross_check` 프로필을 실제로 사용.
- **advisory (게이트 아님)**: 검토 우려는 종료코드에 영향 없음 — 구현 시작/done 을 막지 않는다.
- **읽기전용 보증**: design.md 전후 SHA-256 해시 비교 + 프롬프트 명시(2중). Codex 소유 문서 불변.
- **조용한 폴백 금지**: `--output-format json` 의 실제 model 을 판별해 fallback=true/false 를 provenance 에 명시. 판별 불가 시 실패.
- **경계**: collab.md / done-gate / reviews/ 미접촉 — 그건 task-006(Phase D).

## 관련 문서

- 설계: `kb/tasks/task-005/design.md`
- 구현 노트: `kb/tasks/task-005/implementation-notes.md`
