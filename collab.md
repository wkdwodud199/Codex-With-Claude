# collab.md — 협업 리뷰 로그 (v2 예약)

> **Status: placeholder**
> 이 문서는 v2에서 Codex 리뷰 → collab.md 기록 → Claude 재구현 루프를 위해 예약되어 있다.
> v1에서는 이 파일에 기록하지 않는다.

## 용도 (v2)

- Codex가 Claude의 구현 결과를 리뷰한 내용을 기록한다.
- Claude는 이 문서를 읽고 재구현 또는 수정을 진행한다.
- 각 리뷰 항목은 task-id와 연결되며, 시간순으로 누적된다.

## 예상 스키마 (v2)

리뷰 상태(review status)는 task 상태와 **분리된 별도 필드**다 (imp.md Phase D).
예약 enum: `pending | request-changes | approved | rejected`.

```markdown
## Review: task-<NNN> — <YYYY-MM-DD>

- **Reviewer**: Codex
- **Target**: kb/tasks/task-<NNN>/implementation-notes.md
- **Review status**: pending | request-changes | approved | rejected
- **Feedback**:
  - (리뷰 내용)
- **Action required**:
  - (Claude가 수행해야 할 항목)
```

## 훅 인터페이스 (v2 예약)

- 리뷰 완료 시 Claude에게 알림을 보내는 훅 연결 지점
- **no-auto-revert 게이트**(imp.md Phase D): `request-changes` 가 나와도 task status 를
  **자동으로 되돌리지 않는다**. review status 만 기록하고, 구현자가 다음 액션을 판단한다.
  `done` 으로 최종 간주하려면 최신 review 가 `approved` 여야 한다.
