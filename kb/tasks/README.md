# kb/tasks/ — 작업 단위 문서

이 디렉터리에는 task 별 문서가 `kb/tasks/task-<NNN>/` 형태로 쌓인다. 새 워크스페이스에는 비어 있는 것이 정상이다.

## 새 task 시작

```bash
# 설계 요청 (Codex 설계자) — 디렉터리 + design.md 초안 + manifest.md 를 자동 생성한다
runtime/codex-design.sh task-001 "<작업 설명>"      # PowerShell: runtime/codex-design.ps1
```

생성되는 구조:

```
kb/tasks/task-<NNN>/
├── design.md                설계 문서 (Codex 소유)
├── manifest.md              per-task 의존성 선언 (자동 생성)
└── implementation-notes.md  구현 노트 (Claude 작성, claude-implement 실행 시 초안 생성)
```

(선택) 설계 교차검토 `runtime/review-design.sh <id>` → `design-review.md`,
구현 리뷰 `runtime/codex-review.sh <id>` → `reviews/<NNN>.md`.

규약: [QUICKREF.md](../../QUICKREF.md) · [AGENT.md](../../AGENT.md) · [CLAUDE.md](../../CLAUDE.md).
