# collab.md — 협업 리뷰 로그 (v2 예약)

> **Status: placeholder**
> 이 문서는 v2에서 Codex 리뷰 → collab.md 기록 → Claude 재구현 루프를 위해 예약되어 있다.
> v1에서는 이 파일에 기록하지 않는다.

## 용도 (v2)

- Codex가 Claude의 구현 결과를 리뷰한 내용을 기록한다.
- Claude는 이 문서를 읽고 재구현 또는 수정을 진행한다.
- 각 리뷰 항목은 task-id와 연결되며, 시간순으로 누적된다.

## 예상 스키마 (v2)

```markdown
## Review: task-<NNN> — <YYYY-MM-DD>

- **Reviewer**: Codex
- **Target**: kb/tasks/task-<NNN>/implementation-notes.md
- **Verdict**: approve | request-changes | reject
- **Feedback**:
  - (리뷰 내용)
- **Action required**:
  - (Claude가 수행해야 할 항목)
```

## 훅 인터페이스 (v2 예약)

- 리뷰 완료 시 Claude에게 알림을 보내는 훅 연결 지점
- 리뷰 결과에 따라 자동으로 task status를 갱신하는 로직 연결 지점
