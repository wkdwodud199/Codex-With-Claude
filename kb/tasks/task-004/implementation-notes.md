# 구현 노트 — task-004

> Status: done
> Inputs: kb/tasks/task-004/design.md
> Outputs: 모델/effort 강제 프로필 SSOT + 프롬프트 SSOT + 설계 주도 라우팅 + provenance (아래 산출물 목록)
> Next step: 오너 리뷰 후 로컬 커밋 (push 금지). 후속: P1(설계 교차검증 러너), Phase D 에서 review 프로필 소비

## 설계 대비 변경 사항

| 항목 | 설계 내용 | 실제 구현 | 변경 사유 |
|------|-----------|-----------|-----------|
| 프로필 키 명명 | `review.claude` 에 fable 교차검증 프로필 | `design.claude_cross_check` 로 명명, `review.codex` 는 Phase D 예약으로 별도 유지 | 교차검증은 design 레인 소속(오너 결정 ③ "design 한정" 폴백)이며 Phase D(codex 구현 리뷰)와 혼동 방지 — 교차검증 노트 N1 |
| provenance 기록 시점 | "codex 호출 성공 + 검증 통과 후 기록" | invoke 라이브러리가 성공 시 값 캡처(`CWC_PROV_LINE`/`$script:CwcProvLine`) → codex 러너는 검증 통과 후, claude 러너는 호출 성공 직후 기록 | claude 레인은 검증이 호출 **전**에 이미 끝나므로 동일 시점. 단일 기록 지점 유지 |
| render-prompt 루트 주입 | (미기술) | `--root` 플래그 + `CWC_REPO_ROOT` 환경변수 지원 | validator cli.py 의 기존 테스트 주입 패턴과 일관 (D-2 계열) |
| fallback 소비자 | design/review 에서 claude 호출 소비자가 `--fallback-model` 사용 | 프로필에 선언 + 문서화만. 현행 러너에는 design-phase claude 호출 경로가 없음 (교차검증은 수동/후속 러너) | 설계 범위 내 소비자 부재 — P1(설계 교차검증 러너)에서 소비. 폴백 감지 불가 시 실패 정책은 프로필/README 에 명문화 |

## 구현 결정 기록

1. **AGENTS.md 사건 처리**: Codex 가 설계 런 중 브리프 규칙("design.md 만 수정")을 위반하고 역할이 반전된 AGENTS.md("Codex=구현자")를 무단 생성. 오너 부재(60s 무응답)로 권장안 채택 — 원본은 스크래치패드에 증거 보존(`AGENTS.md.codex-incident-20260705`) 후 **올바른 설계자 규약으로 교체**. codex CLI 가 AGENTS.md 를 자동 로드하므로 방치 시 다음 설계 런 오염. 새 AGENTS.md 에는 "지시받은 design.md 한 파일만 수정" 규칙을 명문화했고, 동일 규칙을 templates/prompts/design.md 마지막 줄에도 넣었다 (재발 방지 2중).
2. **task id 파생 규칙**: `^task-\d+$` — 경로 구성요소(뒤에서부터) 우선, 실패 시 문서 제목에서 `task-\d+` 탐색. 파생 실패 시 legacy 예외 미적용 (설계 5단계, 방어적).
3. **화이트리스트 로딩 시점**: 실행 계획 섹션이 **있을 때만** 프로필을 로드 — EP 없는 legacy/기존 fixture 검증은 프로필 무관(하위호환), EP 있는 문서에서 프로필 부재는 exit 2 (조용한 기본값 금지).
4. **비legacy + 실행 계획 부재의 route-implement**: exit 1 로 실패 (교차검증 노트 N3 — validator 게이트 우회 경로 방어).
5. **스텁 계약 확장**: 버전 preflight 도입으로 모든 테스트 스텁(codex/claude)이 `--version` 에 응답하도록 갱신 (smoke/bats/pester 3벌 동일).

## 발생한 이슈

- 기존 스텁이 `--version` 미응답 → preflight 도입 시 전 스텁 갱신 필요 (해결: `--version` 분기 추가).
- `templates/prompts/` 하위 디렉터리 신설로 테스트 셋업의 `cp templates/*` 가 깨짐 → bash 는 `cp -R templates/.`, PowerShell 은 `Copy-Item -Recurse` 로 전환.
- Codex 계약 위반(AGENTS.md) — 구현 결정 1 참조. 오너 확인 필요 항목으로 summary 에도 기재.

## 테스트 결과

| 테스트 기준 (design.md 참조) | 결과 | 비고 |
|------------------------------|------|------|
| validator cli.py kb/tasks/task-004/design.md → exit 0 | pass | 로컬 실행 |
| pytest tests/validator tests/context_budget tests/status_board | pass | **102 passed** (기존 90 + 신규 12) |
| bash tests/run-smoke.sh (신규 6 시나리오 포함) | pass | 21/21 |
| bats/Pester 시나리오 패리티 | pass (구성) | 양쪽 +3/+3 동일 시나리오. 로컬에 bats/pwsh 없어 CI 에서 실행 (기존과 동일 제약) |
| codex 스텁: `-m gpt-5.5 -c model_reasoning_effort=xhigh` + `--skip-git-repo-check` 부재 | pass | smoke (1) + bats/pester 미러 |
| claude 스텁: 실행 계획의 `claude-opus-4-8/xhigh` 를 `--model/--effort` 로 수신 | pass | smoke (2) + bats/pester 미러 |
| legacy 경로: 기본값 `claude-opus-4-8/high` + WARN + route=default provenance | pass | smoke (3) + bats/pester 미러 |
| 화이트리스트 위반 → validator exit 1 | pass | fixture + pytest + CLI 테스트 |
| 프로필 부재/불량 → --auto non-zero, 조용한 폴백 없음 | pass | smoke (4)(5) + pytest exit-2 테스트 |
| CLI 버전 미달 → 안내 후 non-zero, 실제 호출 안 함 | pass | smoke (6) + bats/pester 미러 |
| fallback 발동 provenance | 부분 | 프로필/README 에 정책 명문화. 소비자(설계 교차검증 러너)는 P1 범위 — 설계 대비 변경 표 참조 |
| runtime/README + QUICKREF 갱신 | pass | validator/README 포함 |
| 실기 검증: codex exec -m gpt-5.5 -c model_reasoning_effort=xhigh | pass | task-004 설계 생성 런 자체가 실증 (2026-07-05, 110k tokens) |

## 산출물

- `runtime/config/model-profiles.json` — 모델/effort 강제 프로필 SSOT (신규)
- `runtime/render-prompt.py` — profile/route-implement/check-cli-version/render 서브커맨드 (신규)
- `templates/prompts/design.md`, `templates/prompts/implement.md` — 프롬프트 SSOT (신규, 사본 4→1)
- `templates/design.md` — 실행 계획 (Execution Plan) 섹션 추가
- `runtime/validator/{schema.json,rules.py,cli.py}` — 실행 계획 규칙 + 프로필 연동 (exit 2)
- `runtime/lib/invoke-codex.{sh,ps1}`, `runtime/lib/invoke-claude.{sh,ps1}` — 프로필/라우팅/preflight/provenance 통합
- `runtime/{codex-design,claude-implement}.{sh,ps1}` — provenance 기록
- `runtime/lib/common.ps1` — Invoke-RenderPrompt 헬퍼
- `AGENTS.md` — Codex 설계자 규약 (역할 반전본 교체)
- fixtures 4종 + `good.md` 실행 계획 추가, pytest +12, smoke +6, bats +3/+3, pester +3/+3
- 문서: `runtime/README.md`, `runtime/validator/README.md`, `QUICKREF.md`
