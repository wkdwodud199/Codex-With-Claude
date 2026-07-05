# Manifest — task-005

> **Load**: 기본 로드 세트의 일부. 이 task 가 *실제로* 의존하는 것만 명시해 컨텍스트를 최소화한다.
> 여기에 없는 개념/파일은 기본적으로 열지 않는다.

- **task_id**: task-005
- **inputs**: kb/tasks/task-004/design.md(프로필/렌더러 인프라), runtime/config/model-profiles.json(design.claude_cross_check 프로필), runtime/render-prompt.py(재사용), imp.md(로드맵 P1)
- **concepts_needed**: kb/concepts/workflow.md
- **related_files**: runtime/review-design.{sh,ps1}(신규 예정), runtime/render-prompt.py(서브커맨드/헬퍼 확장), templates/prompts/design-review.md(신규 예정), runtime/lib/common.{sh,ps1}, runtime/lib/invoke-claude.{sh,ps1}(참조), tests/{run-smoke.sh,bats,pester,validator}, runtime/README.md, QUICKREF.md
- **notes**: P1 — 설계 교차검증(design cross-review). Codex 설계가 validator 를 통과한 뒤 Claude(`design.claude_cross_check` = fable-5/max + `--fallback-model claude-opus-4-8`)가 **읽기전용** 2차 검토를 수행해 `kb/tasks/<id>/design-review.md`(advisory)를 생성한다. 핵심 제약: ① design.md 를 수정하지 않는다(Codex 소유) ② 게이트가 아니라 조언 ③ 폴백 발동 여부를 `claude -p --output-format json` 의 실제 model 로 판별하고, 판별 불가 시 실패(조용한 폴백 금지) ④ collab.md/done-gate 미접촉(task-006 소관). 실행 계획은 task-005 구현 model/effort 를 화이트리스트에서 선택.
