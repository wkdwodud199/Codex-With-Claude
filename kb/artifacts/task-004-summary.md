# 산출물 요약 — task-004

> Status: done
> Inputs: kb/tasks/task-004/implementation-notes.md
> Outputs: 이 요약 문서
> Next step: 오너 리뷰 → 로컬 커밋 (push 금지). 후속 후보: P1 설계 교차검증 러너(fable-5/max 소비자), Phase D review 프로필 소비

## 작업 요약

- **Task ID**: task-004
- **제목**: 러너 --auto 모델/effort 강제 — 2층 라우팅 + 프롬프트 SSOT + 실행 계획(병렬화)
- **완료일**: 2026-07-05

## 산출물 목록

| 산출물 | 경로 | 설명 |
|--------|------|------|
| 모델 프로필 SSOT | `runtime/config/model-profiles.json` | design 정적 강제(gpt-5.5/xhigh · fable-5/max, design 한정 opus 폴백), implement design-directed(기본 opus-4-8/high) + 화이트리스트 |
| 렌더러/라우터 | `runtime/render-prompt.py` | profile · route-implement · check-cli-version · render (stdlib) |
| 프롬프트 SSOT | `templates/prompts/{design,implement}.md` | 하드코딩 프롬프트 4벌 → 1벌, 필수 섹션은 schema.json 에서 렌더 시점 주입 |
| 실행 계획 게이트 | `runtime/validator/*` + `templates/design.md` | 신규 task 는 실행 계획 필수(legacy 001~003 면제), model/effort 화이트리스트 + 병렬화 표 검증 |
| 러너 통합 | `runtime/lib/invoke-*.{sh,ps1}` + 러너 4종 | 항상 `-m/-c` · `--model/--effort` 명시, 버전 preflight, provenance(manifest `generated_by`) |
| Codex 규약 | `AGENTS.md` | 사건 대응: 역할 반전본 교체 → 설계자 규약 + "design.md 만 수정" 명문화 |
| 테스트 | pytest +12(102) · smoke +6(21) · bats +6 · pester +6 | sh↔ps1 / bats↔pester 패리티 유지 |

## 주요 결정

- implement 는 정적 강제하지 않음 — **design.md 실행 계획이 라우팅** (오너 결정, 2층 라우팅). 부재 시 legacy 만 기본값 + 경고.
- 조용한 기본값/폴백 금지 — 프로필 부재·버전 미달·라우팅 실패는 전부 non-zero, 성공은 provenance 로 추적.
- fable 폴백(→opus-4-8, effort max 유지)은 **design 레인 한정** 프로필로 선언 (소비자는 P1 교차검증 러너에서).
- **오너 확인 필요**: Codex 가 설계 런 중 AGENTS.md 를 무단 생성(브리프 위반) — 증거 보존 후 올바른 규약으로 교체함. 원본: 세션 스크래치패드 `AGENTS.md.codex-incident-20260705`.

## 관련 문서

- 설계: `kb/tasks/task-004/design.md`
- 구현 노트: `kb/tasks/task-004/implementation-notes.md`
