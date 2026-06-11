# 구현 노트 — task-003

> Status: done
> Inputs: kb/tasks/task-003/design.md
> Outputs: runtime/generate-status.py, runtime/validator/cli.py(--check-done), claude-implement(--done), CI enforcement, tests/status_board, status.md 마커
> Next step: 거버넌스 enforcement 안정화 후 Phase B/D 는 사용량 증가 시 재평가

## 설계 대비 변경 사항

| 항목 | 설계 내용 | 실제 구현 | 변경 사유 |
|------|-----------|-----------|-----------|
| 완료(done) 신호 | design.md `Status: done` 인 task 를 완료 처리 | **artifacts/<id>-summary.md 의 meta `Status: done`** 을 완료 신호로 사용 | 이 워크스페이스 흐름은 design 을 `ready` 에서 동결한다(설계는 ready 까지만). design 을 done 으로 자동 전이하지 않으므로(설계 '제외' 항목) summary 를 권위 신호로 채택 |
| 테스트 root 주입 | 명시 안 됨 | generate-status 핵심 함수 root 인자화 + cli.py `--check-done` 은 `CWC_REPO_ROOT` env 오버라이드 | 임시 repo fixture 단위 테스트 (운영 동작은 불변) |

## 구현 결정 기록

1. `generate-status.py` 는 `validator/parser.parse_document` 로 meta 를 읽어 새 파서를 만들지 않음(단일 진실 원천 유지).
2. 생성 블록은 `<!-- BEGIN:generated -->`~`<!-- END:generated -->` 만 치환, 마커 밖 prose/로드맵 포인터는 byte 보존. 입력 동일 시 byte-stable(휘발성 날짜 미포함) → `--check` drift 판정 가능.
3. `cli.py --check-done` 은 기존 단일 design.md 경로/`--json`/`--schema` 동작을 100% 보존(positional 을 optional 로). task-001 은 `LEGACY_TASKS` allowlist 로 grandfather.
4. done-gate 는 `rules.check_meta_fields` 를 summary 에 재사용 → 새 파싱 없음.

## 발생한 이슈

- **incident(빌드 중)**: 병렬 빌드 에이전트가 `generate-status.py` 를 경로 인자 없이 실제 `kb/index/status.md` 에 실행해 생성 블록을 덮어씀 → 커밋 blob 으로 복원됨(마커 없는 원본). **교훈**: 라이브 보드에는 명시 경로로 호출하고, 무인자 기본 경로가 스모크에서 실 파일을 건드리지 않게 한다. 통합에서 status.md 마커를 재도입하고 명시 경로로 재생성하여 해소.
- design 의 open issue 대로 `완료일` 은 summary blockquote meta 가 아니라 본문 `- **완료일**:` 에서 추출(기존 산출물 호환).

## 테스트 결과

| 테스트 기준 (design.md 참조) | 결과 | 비고 |
|------------------------------|------|------|
| task-003 design 게이트 통과 | pass | 독립 validator exit 0 |
| pytest validator+context_budget+status_board | pass | 워크플로 verify 88 passed |
| generate-status 멱등성 | pass | test_generate_status (2회차 무변화) |
| `--check` drift 0/1/2 | pass | in-sync 0 / drift 1 / 마커 누락 2 |
| 마커 밖 byte 보존 | pass | head/tail byte 동일 단언 |
| `--check-done` legacy task-001 → 0 | pass | LEGACY allowlist |
| `--check-done` 위반(노트 템플릿/draft/summary 빈필드) → 1 | pass | test_cli 10케이스 |
| 기존 cli.py design.md/--json 계약 불변 | pass | 회귀 테스트 byte 고정 |

## 산출물

- `runtime/generate-status.py` (+ `tests/status_board/`, 15 테스트)
- `runtime/validator/cli.py` `--check-done` (+ `tests/validator/test_cli.py` 10 케이스)
- `runtime/claude-implement.{sh,ps1}` `--done`/`-Done` 단계
- `.github/workflows/ci.yml` — pytest 확장 + status board drift check + done-task 루프
- `kb/index/status.md` — 생성 마커 도입(활성/완료 표는 generate-status 가 생성)
- 문서 강등 패스(별도: README/CLAUDE/AGENT/imp.md/architecture/collab 중복 → 단일 포인터)
