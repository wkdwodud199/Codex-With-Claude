# Manifest — task-006

> **Load**: 기본 로드 세트의 일부. 이 task 가 *실제로* 의존하는 것만 명시해 컨텍스트를 최소화한다.
> 여기에 없는 개념/파일은 기본적으로 열지 않는다.

- **task_id**: task-006
- **inputs**: imp.md(Phase D 절 — 정본 스코프), collab.md(review status enum + no-auto-revert/approved-done 게이트 예약 정의), AGENT.md(리뷰 루프 v2 예약), runtime/config/model-profiles.json(review.codex 프로필), kb/tasks/task-004/design.md(프로필/렌더러 인프라)
- **concepts_needed**: kb/concepts/workflow.md
- **related_files**: runtime/codex-review.{sh,ps1}(신규 예정), runtime/validator/{review_rules.py 또는 rules.py 확장, schema.json, cli.py}, templates/review.md · templates/prompts/review.md(신규 예정), runtime/lib/invoke-codex.{sh,ps1}(참조), collab.md, kb/tasks/<id>/reviews/(신규 관례), tests/{run-smoke.sh,bats,pester,validator}, runtime/README.md, QUICKREF.md, AGENT.md
- **notes**: Phase D — 구현 리뷰 루프. 구현 완료(impl-notes done + artifact summary done) 후 `codex-review` 러너가 Codex(`review.codex` = gpt-5.5/xhigh)로 구현을 리뷰해 `kb/tasks/<id>/reviews/<NNN>.md` 를 생성한다(status enum: `pending|request-changes|approved|rejected`, 정본=collab.md). 게이트: ① **no-auto-revert** — request-changes 가 task status 를 자동으로 되돌리지 않는다 ② **approved-done** — reviews/ 가 존재하면 `--check-done` 이 최신 리뷰 = approved 를 요구하고, reviews/ 부재면 기존 동작 유지(task-001~004 하위호환). collab.md 는 인터페이스/enum 정본으로 유지(데이터는 per-task reviews/). 실행 계획은 task-006 구현 model/effort 를 화이트리스트에서 선택.
