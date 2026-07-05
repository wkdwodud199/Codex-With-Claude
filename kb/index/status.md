# 작업 현황 (Status Board)

> 아래 자동 생성 블록(HTML 주석 마커 사이)의 **활성/완료 표는 `runtime/generate-status.py` 가 생성**한다. 직접 편집하지 말 것 (CI 가 drift 를 검사).
> 메타 개선 로드맵의 정본은 [imp.md](../../imp.md) "진행 현황" 표다.

<!-- BEGIN:generated -->
## 활성 작업

| Task ID | 제목 | Status | 비고 |
|---------|------|--------|------|
| (없음) | — | — | — |

## 완료 작업

| Task ID | 제목 | 완료일 | 산출물 |
|---------|------|--------|--------|
| task-001 | Claude-Codex 협업 워크스페이스 v1 초기 scaffold | 2026-04-17 | [summary](../artifacts/task-001-summary.md) |
| task-002 | Phase A — context-budget.py + QUICKREF + per-task manifest (감산적 컨텍스트 관리) | 2026-06-09 | [summary](../artifacts/task-002-summary.md) |
| task-003 | 거버넌스 enforcement — status board 생성기 + done-gate | 2026-06-09 | [summary](../artifacts/task-003-summary.md) |
| task-004 | 러너 --auto 모델/effort 강제 — 2층 라우팅 + 프롬프트 SSOT + 실행 계획(병렬화) | 2026-07-05 | [summary](../artifacts/task-004-summary.md) |
| task-005 | 설계 교차검증 러너 (P1) — Codex 설계 후 Claude fable-5/max 읽기전용 2차 검토 | 2026-07-05 | [summary](../artifacts/task-005-summary.md) |
| task-006 | 구현 리뷰 루프 (imp.md Phase D) — codex-review 러너 + review status enum + approved-done 게이트 | 2026-07-05 | [summary](../artifacts/task-006-summary.md) |
<!-- END:generated -->

## 메타 개선 로드맵

정본: [imp.md](../../imp.md) "진행 현황 (Progress Tracker)". (Phase 표 중복 제거 — drift 방지)

## 다음 단계

1. **(선행)** 미커밋 작업 트리를 오너가 커밋.
2. Phase B(generated status / collab 파티셔닝)는 사용량 증가 후 재평가. Phase C(backend seam)는 두 번째 backend 요구 시까지 보류.

러너 (기본 수동 / `--auto` 옵션):

```
# Bash                                        # PowerShell
./runtime/codex-design.sh <id> "<설명>"       ./runtime/codex-design.ps1 <id> "<설명>"
./runtime/claude-implement.sh <id>            ./runtime/claude-implement.ps1 <id>
./runtime/claude-implement.sh --done <id>     ./runtime/claude-implement.ps1 <id> -Done
```

- 재귀 가드: `CLAUDECODE`(주)/`CLAUDE_CODE_SESSION_ID` 등 설정 시 `--auto` 거부 (`*_AUTO_FORCE=1` 로만 우회). `--auto` 실패는 non-zero 전파.
- 컨텍스트 예산: `python3 runtime/context-budget.py <id> --baseline` (경고 전용).
- 완료 검증: `python3 runtime/validator/cli.py --check-done <id>` (done-gate).
- 보드 재생성: `python3 runtime/generate-status.py` (검사: `--check`).
