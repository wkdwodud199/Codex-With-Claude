# QUICKREF — 빠른 운영 참조 (routine fast-path)

> **Load**: 일반 task 는 이 파일 + `kb/tasks/<id>/manifest.md` + `kb/tasks/<id>/design.md` 만 읽으면 충분하다.
> 예외·상세 규칙이 필요할 때만 [AGENT.md](./AGENT.md)(공통 규약·상태 전이 **정본**) / [CLAUDE.md](./CLAUDE.md)(구현자 규칙)으로 에스컬레이션한다.

## 역할
- **Codex** = 설계자 → `kb/tasks/<id>/design.md` 작성 · (Phase D) 구현 **리뷰어** → `reviews/<NNN>.md`
- **Claude** = 구현자 → design.md 검증 후 구현, 결과를 `kb/tasks/<id>/implementation-notes.md` 에 기록

## 기본 로드 세트 (per task)
1. `QUICKREF.md` (이 파일)
2. `kb/tasks/<id>/manifest.md` — 이 task 가 실제로 의존하는 입력/개념/관련 파일만 나열
3. `kb/tasks/<id>/design.md` — 설계 (구현 대상)

manifest 의 `concepts_needed` / `related_files` 에 적힌 것만 추가로 연다. **전부 읽지 않는다.**

## 상태 모델 (요약 — 정본은 AGENT.md "문서 상태 전이")
- **design.md `Status`** = 설계 준비도: `draft → ready → done` (+ `blocked`). `in-progress` 는 design.md 에 쓰지 않는다.
- **implementation-notes.md** = 구현 진행도: `in-progress → done` (+ `blocked`).
- Claude 는 `Status: ready` 또는 `done` 인 design.md 만 구현한다.

## 검증 게이트 (구현 시작 전 필수)
```
python3 runtime/validator/cli.py kb/tasks/<id>/design.md
```
통과 조건: 필수 7섹션 존재 · placeholder 없음 · 빈 테이블/체크박스 없음 · Inputs/Outputs/Next step 채워짐
· **실행 계획**(implement_model/effort 가 화이트리스트 내 + 병렬화 표; legacy task-001~003 만 부재 허용).
종료코드 `0`=통과 / `1`=설계 보완 필요 / `2`=환경 오류(Python 미설치·프로필 부재 등).

## 러너 명령
```
# 설계 (Codex)                              # 구현 (Claude)
runtime/codex-design.sh <id> "<desc>"       runtime/claude-implement.sh <id>
```
- 자동 호출: `--auto` (또는 `*_AUTO=1`). 세션 내부에서는 재귀 가드가 막으며 `*_AUTO_FORCE=1` 로만 우회한다.
- `--auto` 실패(CLI 부재/비정상 종료/프로필 부재/버전 미달)는 non-zero 로 전파된다(방어적).
- **모델/effort 강제 (task-004)**: design 은 정적 프로필(`gpt-5.5/xhigh` + 교차검증 `fable-5/max`,
  design 한정 폴백 `opus-4-8`), implement 는 design.md **실행 계획이 라우팅** (부재 시 legacy 만
  `opus-4-8/high` 기본값 + 경고). SSOT: `runtime/config/model-profiles.json` · `templates/prompts/`.
  `--auto` 성공 시 manifest 에 `generated_by` provenance 가 기록된다.
- **설계 교차검토 (task-005, 선택)**: `runtime/review-design.sh <id>` — design.md 검증 통과 후 Claude
  `fable-5/max` 로 **읽기전용** 2차 검토를 받아 `kb/tasks/<id>/design-review.md` 를 남긴다(**advisory** —
  구현 게이트 아님). design.md 는 해시로 불변 보증, fallback 은 provenance 에 기록.
- **구현 리뷰 (task-006 Phase D, 선택)**: `runtime/codex-review.sh <id>` — 구현 완료 후 Codex `gpt-5.5/xhigh`
  가 리뷰해 `kb/tasks/<id>/reviews/<NNN>.md` 를 누적한다. status enum(`pending|request-changes|approved|rejected`)
  정본은 collab.md. **approved-done**: reviews/ 가 있으면 `--check-done` 은 최신 리뷰가 `approved` 여야 통과
  (없으면 기존 동작). **no-auto-revert**: 리뷰가 task status 를 자동으로 되돌리지 않는다.

## 컨텍스트 예산 (경고 전용)
```
python3 runtime/context-budget.py <id>
```
기본 로드 세트 vs baseline(AGENT+CLAUDE+design)의 바이트/토큰 추정을 리포트한다. fail gate 아님.

## 출력 규칙
모든 task 산출물은 `kb/` 하위에만 작성한다. 구현 완료 시 순서대로 갱신:
`implementation-notes.md` → `kb/artifacts/<id>-summary.md` → `python3 runtime/generate-status.py`
(status.md 는 직접 편집하지 않는다 — 생성 블록 내용은 generate-status.py 가 관리).

done-gate(`--done`/`--check-done`)는 **notes Status=done · summary Status=done · manifest 실값
(placeholder 금지)** 를 모두 요구한다 (정본: schema.json `done_gate`).
