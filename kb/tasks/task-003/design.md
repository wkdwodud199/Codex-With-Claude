# 설계 문서 — task-003

> Status: ready
> Inputs: templates/design.md, AGENT.md, QUICKREF.md, runtime/validator/parser.py, runtime/validator/rules.py, runtime/validator/cli.py, kb/index/status.md, kb/artifacts/*-summary.md
> Outputs: runtime/generate-status.py, runtime/validator/cli.py --check-done, claude-implement --done 연결, CI enforcement, status_board/validator 테스트
> Next step: Claude가 이 설계를 검증한 뒤 task-003 구현을 시작

## 목표 (Objective)

task 완료 상태를 사람이 수동으로 집계하지 않아도 되도록 `kb/index/status.md`의 생성 블록을 결정론적으로 재생성하고, `design.md`가 `done`인 task가 실제 완료 산출물까지 갖췄는지 검증하는 enforcement를 추가한다. 새 구현은 기존 design 검증 CLI의 단일 파일 경로 동작과 Bash/PowerShell 러너 호환성을 깨지 않아야 한다.

## 범위 (Scope)

- 포함:
  - stdlib 전용 Python 3.8+ 스크립트 `runtime/generate-status.py` 추가.
  - `parser.py`의 기존 blockquote meta 추출을 재사용해 `kb/tasks/*/design.md`의 설계 준비도 `Status`와 `kb/artifacts/*-summary.md`의 `Status`/`완료일`을 읽음.
  - `kb/index/status.md` 안의 `<!-- BEGIN:generated -->`부터 `<!-- END:generated -->`까지 생성 블록만 갱신하고, 그 안의 `활성 작업`/`완료 작업` 표를 재작성.
  - `runtime/validator/cli.py`에 `--check-done <task-dir-or-id>` 모드를 추가해 완료 산출물 계약을 검사.
  - `runtime/claude-implement.sh`와 `runtime/claude-implement.ps1`에 선택적 `--done`/`-Done` 단계를 추가해 `cli.py --check-done`을 호출.
  - CI에 status board drift check, done task 완료 검증 루프, `tests/context_budget` 및 `tests/status_board` pytest 실행을 연결.
  - `tests/status_board/test_generate_status.py`와 `tests/validator/test_cli.py`에 생성/검증/회귀 케이스 추가.
- 제외:
  - parser.py를 대체하는 새 Markdown parser 작성.
  - 외부 패키지 또는 런타임 의존성 추가.
  - 마커 밖 status board prose, 다음 단계 안내, 러너 도움말, imp.md 로드맵 포인터 자동 수정.
  - task 완료 시 `design.md`를 자동으로 `done`으로 변경하는 기능.

## 제약 (Constraints)

- 모든 신규 Python 코드는 stdlib만 사용하고 Python 3.8+에서 동작해야 한다.
- meta 추출은 `runtime/validator/parser.py`의 `parse_document`/`ParsedDoc.metadata`를 재사용한다. `Status`, `Inputs`, `Outputs`, `Next step` 검증은 `rules.check_meta_fields`를 재사용하고 새 정규식 파싱으로 우회하지 않는다.
- 기존 CLI 호출 `python runtime/validator/cli.py <design.md>`, `--json`, `--schema`의 출력 형식과 종료코드는 100% 유지한다. `.github/workflows/ci.yml`의 기존 golden step과 PS1 runner step이 계속 통과해야 한다.
- `--check-done` 종료코드는 통과 `0`, 계약 위반 `1`, 파일 없음/디코딩/환경 등 IO 오류 `2`로 구분한다.
- `task-001`은 규약 이전 산출물이므로 `LEGACY_TASKS = {"task-001"}` 같은 명시 allowlist로 완료 검증을 통과시킨다. allowlist는 다른 task로 확장하지 않는다.
- status board 생성은 동일 입력에서 byte-stable 해야 하며 `--check`는 파일을 쓰지 않고 drift 여부만 종료코드로 보고한다.
- `kb/index/status.md`에 생성 마커가 없을 때의 동작은 환경/문서 구조 오류로 보고하고 파일을 부분 수정하지 않는다.

## 구현 단계 (Implementation Steps)

1. status 생성 블록 계약 정의
   - `kb/index/status.md`에 생성 블록이 존재한다고 가정하고, 블록 내부를 `## 활성 작업` 표와 `## 완료 작업` 표로만 재생성한다.
   - 활성 작업은 `kb/tasks/*/design.md`의 `Status`가 `ready` 또는 `blocked`인 항목을 대상으로 한다. `draft`는 미완성 초안이므로 보드 집계에서 제외하고, `done`은 완료 표 후보로 넘긴다.
   - 완료 작업은 `kb/artifacts/<task-id>-summary.md`가 있고 summary meta `Status: done`이며 본문에서 `- **완료일**: YYYY-MM-DD` 값을 찾을 수 있는 항목을 대상으로 한다.
   - 정렬은 task id 오름차순으로 고정한다. 누락 정보는 `—`로 채우되, 완료 검증 대상에서는 누락 자체를 실패로 처리한다.

2. `runtime/generate-status.py` 작성
   - repo root는 스크립트 위치 기준으로 계산하고, 테스트에서는 함수 인자로 root/status path를 주입할 수 있게 핵심 로직을 함수화한다.
   - design summary meta는 `parser.parse_document(text).metadata`로 읽는다.
   - task 제목은 우선 summary의 `- **제목**:` 또는 design 첫 제목/목표에서 추출하고, 실패 시 task id를 사용한다.
   - `render_generated_block(tasks, artifacts)`가 표 문자열을 만들고, `replace_generated_block(current_text, block)`이 마커 내부만 치환한다.
   - 기본 모드는 `kb/index/status.md`를 갱신하고, `--check`는 재생성 결과와 현재 파일을 비교해 같으면 `0`, 다르면 diff 요약을 stderr에 출력하고 `1`을 반환한다. 마커 누락/읽기 실패는 `2`를 반환한다.

3. `runtime/validator/cli.py --check-done` 추가
   - argparse는 기존 positional `file` 경로를 유지하면서 `--check-done TASK`를 선택 모드로 추가한다. 이 모드에서는 positional design file 없이도 동작하게 하되, 기존 호출 문법은 그대로 둔다.
   - task 인자는 `task-003` 같은 id 또는 `kb/tasks/task-003` 같은 경로를 모두 허용한다.
   - legacy allowlist에 포함된 task는 파일 상태와 무관하게 통과 메시지와 `0`을 반환한다.
   - non-legacy task는 `implementation-notes.md` 존재, UTF-8 read 성공, `templates/implementation-notes.md`의 task id 치환 결과와 byte 불일치, meta `Status`가 존재하고 `draft`가 아님을 검사한다.
   - `kb/artifacts/<id>-summary.md` 존재와 UTF-8 read 성공을 확인한 뒤, `parse_document`와 `rules.check_meta_fields`를 이용해 `Status`/`Inputs`/`Outputs`/`Next step`이 비어있지 않은지 검사하고 summary `Status`가 비어있지 않은지도 명시 확인한다.
   - human 출력은 `[OK] 완료 검증 통과` 또는 `[FAIL] 완료 검증 실패` 형식을 사용하고, `--json`은 기존 payload 형태에 `mode: "check-done"` 정도만 추가해도 된다.

4. 러너 연결
   - Bash는 인자 파서에 `--done`을 추가하고 `DONE_MODE=1`일 때 구현 안내 출력 전에 `python runtime/validator/cli.py --check-done "$TASK_DIR"`을 실행한다.
   - PowerShell은 `[switch]$Done`을 추가하고 동일하게 `Invoke-Validator` 또는 직접 Python 호출 경로를 통해 `--check-done $TaskDir`을 실행한다.
   - `--done`은 구현 완료 후 사람이 실행하는 선택 단계이므로 기존 `--auto` 동작, 구현 노트 초안 생성, Claude 호출 경로를 변경하지 않는다.

5. CI 연결
   - unit job의 pytest 대상을 `tests/validator tests/context_budget tests/status_board`로 확장한다.
   - status board drift check step을 추가해 `python runtime/generate-status.py --check`를 실행한다.
   - design meta `Status`가 `done`인 `kb/tasks/*/design.md`만 찾아 `python runtime/validator/cli.py --check-done <task-dir>`를 반복 실행하는 cross-platform Python one-liner 또는 작은 inline script를 추가한다.
   - 기존 Windows golden validator와 PS1 runner step은 유지해 호환성 회귀를 잡는다.

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| `runtime/generate-status.py` | create | task design과 artifact summary meta를 읽어 status board 생성 블록을 갱신하고 `--check` drift 검사를 제공 |
| `runtime/validator/cli.py` | modify | 기존 design.md 검증 경로를 보존하면서 `--check-done <task-dir-or-id>` 완료 검증 모드 추가 |
| `runtime/validator/rules.py` | modify | 필요 시 summary meta 재사용을 위한 작은 helper만 추가; `check_meta_fields` 동작 자체는 보존 |
| `runtime/claude-implement.sh` | modify | 선택적 `--done` 인자와 완료 검증 호출 연결 |
| `runtime/claude-implement.ps1` | modify | 선택적 `-Done` 인자와 완료 검증 호출 연결 |
| `.github/workflows/ci.yml` | modify | pytest 대상 확장, status board `--check`, done task 완료 검증 루프 추가 |
| `tests/status_board/test_generate_status.py` | create | 생성 결과, 멱등성, `--check` drift, 마커 밖 보존 검증 |
| `tests/validator/test_cli.py` | modify | `--check-done` 통과/위반/legacy/IO 종료코드 케이스 추가 |
| `kb/index/status.md` | modify | 생성 블록 마커 도입 및 초기 재생성 결과 반영; 마커 밖 prose와 imp.md 로드맵 포인터 보존 |

## 테스트 기준 (Test Criteria)

- [ ] `python runtime/validator/cli.py kb/tasks/task-003/design.md`가 통과한다.
- [ ] `python -m pytest tests/validator tests/context_budget tests/status_board -v`가 통과한다.
- [ ] `python runtime/generate-status.py`를 두 번 실행해 두 번째 실행에서 내용이 바뀌지 않는다.
- [ ] `python runtime/generate-status.py --check`가 정상 보드에서 `0`, 생성 블록 drift가 있는 임시 보드에서 `1`, 마커 누락 임시 보드에서 `2`를 반환한다.
- [ ] status board 테스트가 생성 블록 밖의 다음 단계 안내, 러너 도움말, imp.md 로드맵 포인터가 byte-preserved 되는 것을 검증한다.
- [ ] `python runtime/validator/cli.py --check-done task-001`은 legacy allowlist로 `0`을 반환한다.
- [ ] `--check-done`은 구현 노트가 템플릿과 byte 동일하거나 `Status: draft`이면 `1`을 반환한다.
- [ ] `--check-done`은 summary의 `Status`/`Inputs`/`Outputs`/`Next step` 중 하나가 비어있으면 `rules.check_meta_fields` 기반 오류와 함께 `1`을 반환한다.
- [ ] 기존 호출 `python runtime/validator/cli.py tests/validator/fixtures/good.md --json`과 `python runtime/validator/cli.py kb/tasks/task-001/design.md`의 종료코드/출력 계약이 유지된다.
- [ ] Bash `./runtime/claude-implement.sh --done task-001` 및 PowerShell `./runtime/claude-implement.ps1 task-001 -Done`이 완료 검증 단계를 호출하고 legacy 통과를 보고한다.
- [ ] CI에서 status board drift check와 done task loop가 실행되며, 기존 Windows PS1 golden step이 계속 통과한다.

## 오픈 이슈 (Open Issues)

- 생성 블록 마커가 현재 status board에 없으므로 구현 시 최초 1회 `kb/index/status.md`에 마커를 도입해야 한다. 이때 마커 밖 prose와 imp.md 로드맵 포인터를 이동하거나 재작성하지 않는다.
- 완료일은 summary meta가 아니라 현재 summary 본문 `- **완료일**:` 형식에 존재한다. 요구사항의 "Status/완료일" 중 `Status`는 parser meta로, `완료일`은 summary 본문에서 좁은 형식으로 추출한다.
- summary 문서에는 아직 `완료일` blockquote meta가 없다. 새 meta 필드를 강제하면 기존 산출물이 깨지므로 task-003에서는 본문 완료일 추출로 호환성을 유지한다.
