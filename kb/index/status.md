# 작업 현황 (Status Board)

> 아래 자동 생성 블록(HTML 주석 마커 사이)의 **활성/완료 표는 `runtime/generate-status.py` 가 생성**한다.
> 직접 편집하지 말 것 (CI 가 drift 를 검사한다). 새 워크스페이스에는 task 가 없어 표가 비어 있는 것이 정상이다.

<!-- BEGIN:generated -->
## 활성 작업

| Task ID | 제목 | Status | 비고 |
|---------|------|--------|------|
| (없음) | — | — | — |

## 완료 작업

| Task ID | 제목 | 완료일 | 산출물 |
|---------|------|--------|--------|
| (없음) | — | — | — |
<!-- END:generated -->

## 러너 빠른 참조

기본은 수동 모드, 자동 호출은 `--auto` (세션 내부에서는 재귀 가드가 막으며 `*_AUTO_FORCE=1` 로만 우회).

```
# Bash                                        # PowerShell
./runtime/codex-design.sh <id> "<설명>"       ./runtime/codex-design.ps1 <id> "<설명>"
./runtime/claude-implement.sh <id>            ./runtime/claude-implement.ps1 <id>
./runtime/claude-implement.sh --done <id>     ./runtime/claude-implement.ps1 <id> -Done
```

- 컨텍스트 예산: `python3 runtime/context-budget.py <id> --baseline` (경고 전용).
- 완료 검증: `python3 runtime/validator/cli.py --check-done <id>` (done-gate).
- 보드 재생성: `python3 runtime/generate-status.py` (검사: `--check`).
- (선택) 설계 교차검토: `runtime/review-design.sh <id>` · 구현 리뷰: `runtime/codex-review.sh <id>`.
