# 구현 노트 — task-002

> Status: done
> Inputs: kb/tasks/task-002/design.md
> Outputs: runtime/context-budget.py, tests/context_budget/test_budget.py, QUICKREF.md, templates/manifest.md, 러너 manifest 자동생성
> Next step: Phase B 는 사용량 증가 후 재평가 (generated status / review loop)

## 설계 대비 변경 사항

| 항목 | 설계 내용 | 실제 구현 | 변경 사유 |
|------|-----------|-----------|-----------|
| 종료코드 "항상 0" | 모든 실행 경로 0 | 측정 경로는 0; 인자 없으면 사용법 출력 후 0 | argparse 필수인자 대신 `nargs='?'` 로 처리해 사용법 경로도 0 유지(설계 의도 보존) |
| 테스트 용이성 | 명시 안 됨 | `compute(task_id, root=...)` root 주입형 | 임시 repo fixture 로 측정 로직 단위 검증 가능하게 |

## 구현 결정 기록

1. 하이픈 파일명(`context-budget.py`)은 일반 import 불가 → 테스트에서 `importlib` 로 로드.
2. 토큰 추정 = `bytes // 4` (`TOKEN_DIVISOR` 상수). 수기 `estimated_tokens` 필드는 도입하지 않음(설계 '제외' 항목 준수).
3. `--baseline` 없이도 baseline 합계와 감산 여부를 항상 출력(핵심 성공 기준 가시화).

## 발생한 이슈 (dogfood 마찰 기록)

- **FRICTION#1**: 기존 러너가 `manifest.md` 를 자동 생성하지 않음 → `codex-design.{sh,ps1}` 에 manifest 자동생성 추가 + `templates/manifest.md` 신설 + smoke/bats 검증 추가.
- **FRICTION#2**: `QUICKREF.md` 부재 → 신설(감산적 설계: AGENT/CLAUDE 중복 preamble 을 routine 경로에서 대체). `AGENT.md` 상단에 진입 포인터 추가.
- **FRICTION#3**: Codex 가 생성한 `design.md` 의 H1 에 '템플릿' 단어가 잔존("설계 문서 템플릿 — task-002") → `templates/design.md` H1 을 "설계 문서 — task-<NNN>" 로 수정해 재발 방지. (design.md 본문은 Codex 소유이므로 수정하지 않음 — AGENT.md 협업 규약 준수.)
- 검증 게이트는 1회 통과로 충분했음 — Codex 가 영향 테이블 실데이터 행/체크박스/Status:ready 를 한 번에 채워, 새 `non_empty_sections` 규칙도 즉시 통과.

## 테스트 결과

| 테스트 기준 (design.md 참조) | 결과 | 비고 |
|------------------------------|------|------|
| 신규 세트 총 바이트/토큰 추정 | pass | test_new_set_total_and_token_estimate |
| `--baseline` 상세 + 차이 출력 | pass | test_baseline_total_and_detail_output |
| manifest/QUICKREF 누락 시 0B + 경고 | pass | test_missing_manifest_and_quickref_warn_and_zero |
| 누락 파일 있어도 종료코드 0 | pass | test_exit_code_always_zero |
| 감산 성공 메시지 출력 | pass | test_subtractive_message_when_new_smaller |
| 비감산 시 실패 없이 경고만 | pass | test_non_subtractive_is_warning_only |

**실측(task-002, `--baseline`)**: 신규 7,607 B < baseline 13,922 B → **감산적 −6,315 B (−45%)**.

## 산출물

- `runtime/context-budget.py` — 경고 전용 컨텍스트 예산 CLI
- `tests/context_budget/test_budget.py` (+ `__init__.py`) — 6 케이스
- `QUICKREF.md` — routine fast-path (감산적)
- `templates/manifest.md` — per-task manifest 템플릿
- `kb/tasks/task-002/manifest.md` — task-002 manifest
- `runtime/codex-design.{sh,ps1}` — manifest 자동생성 추가
