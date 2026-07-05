# 산출물 요약 — task-006

> Status: done
> Inputs: kb/tasks/task-006/implementation-notes.md
> Outputs: 이 요약 문서
> Next step: 커밋/푸시/CI 확인. (선택) codex-review self-dogfood

## 작업 요약

- **Task ID**: task-006
- **제목**: 구현 리뷰 루프 (imp.md Phase D) — codex-review 러너 + review status enum + approved-done 게이트
- **완료일**: 2026-07-05

## 산출물 목록

| 산출물 | 경로 | 설명 |
|--------|------|------|
| 리뷰 러너 | `runtime/codex-review.{sh,ps1}` | base done 전제 → codex 리뷰 → staging 검증 → reviews/NNN.md 승격 |
| review invoke helper | `runtime/lib/invoke-codex.{sh,ps1}` | review phase codex 호출(gpt-5.5/xhigh, git/버전 preflight, sandbox) |
| review validator | `runtime/validator/review_rules.py` + schema review 블록 | enum(collab.md 마커) 파싱, 리뷰 필드/상태 검증, 최신 조회 |
| validator CLI | `runtime/validator/cli.py` | `--check-review` / `--latest-review` / `--check-review-target` + approved-done `--check-done` |
| 프롬프트/템플릿 | `templates/review.md`, `templates/prompts/review.md`, render `--phase review` | 리뷰 문서/프롬프트 SSOT |
| 인터페이스 정본 | `collab.md` (v2 active) | enum·no-auto-revert·approved-done 게이트 정의 |
| 테스트 | pytest(review_rules + cli 확장) · smoke +6 · bats +7 · pester +7 | sh↔ps1 / bats↔pester 패리티 |

## 주요 결정

- **review status 는 제3의 상태**: design 준비도 / 구현 진행도와 분리. 정본 enum 은 collab.md 마커.
- **approved-done (하위호환)**: reviews/ 있으면 최신=approved 요구, 없으면 기존 done-gate 유지 → task-001~005 무영향.
- **no-auto-revert**: 리뷰는 task status 를 자동으로 되돌리지 않는다. done 게이트만 실패.
- **재리뷰 순환 방지**: `--check-review-target`(리뷰 게이트 제외 base 검증)으로 러너 전제 확인.
- **staging → 승격**: 검증 통과 리뷰만 reviews/ 로 승격 → 부분 리뷰가 게이트를 오염시키지 않음.
- **경계**: task-005(설계 교차검토)와 분리 — task-006 은 *구현 후* 리뷰만 다룬다.

## 관련 문서

- 설계: `kb/tasks/task-006/design.md`
- 구현 노트: `kb/tasks/task-006/implementation-notes.md`
- 인터페이스 정본: `collab.md`
