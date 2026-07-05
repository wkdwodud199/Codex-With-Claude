# Manifest — task-003

> **Load**: 기본 로드 세트의 일부. 이 task 가 *실제로* 의존하는 것만 명시해 컨텍스트를 최소화한다.
> 여기에 없는 개념/파일은 기본적으로 열지 않는다.

- **task_id**: task-003
- **inputs**: kb/tasks/task-003/design.md, imp.md(거버넌스 enforcement 절), AGENT.md(문서 상태 전이 — 상태 모델 정본)
- **concepts_needed**: kb/concepts/workflow.md
- **related_files**: runtime/generate-status.py, runtime/validator/cli.py(--check-done), runtime/claude-implement.{sh,ps1}(--done/-Done), tests/status_board/, tests/bats/claude-implement.bats, tests/pester/claude-implement.Tests.ps1
- **notes**: 소급 기입(2026-07-05, done-gate manifest 검증 도입 시) — task-003 수행 당시 템플릿 상태로 남아 있던 것을 실제 의존성으로 채움. 내용은 design.md/implementation-notes.md 기준.
