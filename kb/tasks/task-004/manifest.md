# Manifest — task-004

> **Load**: 기본 로드 세트의 일부. 이 task 가 *실제로* 의존하는 것만 명시해 컨텍스트를 최소화한다.
> 여기에 없는 개념/파일은 기본적으로 열지 않는다.

- **task_id**: task-004
- **inputs**: imp.md(로드맵 — 본 task 는 신규 P0 항목), runtime/validator/schema.json(프롬프트 렌더 원천), runtime/lib/invoke-claude.{sh,ps1} · invoke-codex.{sh,ps1}(현행 호출 지점), 오너 결정(아래 notes)
- **concepts_needed**: kb/concepts/workflow.md
- **related_files**: runtime/config/model-profiles.json(신규 예정), runtime/render-prompt.py(신규 예정), templates/prompts/design.md · implement.md(신규 예정), templates/design.md(실행 계획 섹션 추가), runtime/validator/schema.json(실행 계획 규칙), runtime/lib/invoke-claude.{sh,ps1}, runtime/lib/invoke-codex.{sh,ps1}, runtime/README.md, QUICKREF.md, tests/bats/, tests/pester/
- **notes**: 오너 결정 (2026-07-05, 2층 라우팅으로 개정):
  ① design 정적 강제 = codex `gpt-5.5` + reasoning `xhigh`, claude 교차검증 = `claude-fable-5` + effort `max`. 정적 강제는 design 레인에만 둔다(부트스트랩 앵커).
  ② implement 는 정적 강제하지 않는다 — **설계 산출물이 라우팅한다**: design.md 의 `실행 계획 (Execution Plan)` 섹션이 구현 model/effort/병렬화 계획을 지정하고, 러너가 이를 `claude -p --model/--effort` 에 반영한다. `claude-opus-4-8`+`high` 는 실행 계획 부재 시(legacy 등) 기본값 — 조용한 미지정 금지, 사용 시 로그.
  ③ fable 불가 시 `claude-opus-4-8`(effort `max` 유지) 폴백 — **design 레인 한정**.
  ④ design 은 **병렬작업 가능성 판단을 포함**한다: 실행 계획에 독립 작업 단위/의존성/병렬 그룹 명시. v1 실행 메커니즘은 단일 세션 내 병렬(서브에이전트) 우선, 다중 `claude -p` fan-out 은 워크트리 충돌 위험으로 후속 검토.
  설계 제약: 라우팅 가능 model/effort 는 profiles.json 화이트리스트 내로 제한(validator 검사) · legacy task-001~003 은 실행 계획 부재 허용(기본값 라우팅, 게이트 하위호환) · `--fallback-model` 은 effort 를 바꾸지 않으므로 design 레인(이미 max)에서 정확히 "opus-4-8 max" 성립 · 조용한 폴백 금지(발동 시 provenance 기록) · 프로필 파일 없거나 해석 실패 시 `--auto` 거부 · `gpt-5.5` 모델 문자열은 kickoff 시 실검증.
