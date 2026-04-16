# 작업 현황 (Status Board)

> 마지막 갱신: 2026-04-17

## 활성 작업

| Task ID | 제목 | Status | 담당 | 비고 |
|---------|------|--------|------|------|
| (없음) | — | — | — | — |

## 완료 작업

| Task ID | 제목 | 완료일 | 산출물 |
|---------|------|--------|--------|
| task-001 | 워크스페이스 v1 초기 scaffold | 2026-04-17 | [summary](../artifacts/task-001-summary.md) |

## 다음 단계

- 첫 실제 작업(task-002)을 생성하고 Codex에게 설계를 요청한다.

```powershell
# PowerShell (Windows 기본)
./runtime/codex-design.ps1 task-002 "<작업 설명>"
./runtime/claude-implement.ps1 task-002

# Bash (Git Bash / MSYS2)
./runtime/codex-design.sh task-002 "<작업 설명>"
./runtime/claude-implement.sh task-002
```
