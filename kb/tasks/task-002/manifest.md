# Manifest — task-002

> **Load**: 기본 로드 세트의 일부. 이 task 가 *실제로* 의존하는 것만 명시해 컨텍스트를 최소화한다.

- **task_id**: task-002
- **inputs**: kb/tasks/task-002/design.md, imp.md(Phase A), AGENT.md(필수 필드/상태 규칙)
- **concepts_needed**: 없음
- **related_files**: runtime/context-budget.py, tests/context_budget/test_budget.py, QUICKREF.md, templates/manifest.md
- **notes**: 경고 전용 측정 도구. 감산 기준 = (QUICKREF + manifest + design) < (AGENT + CLAUDE + design).
