# Codex-With-Claude

> **[English](./README.en.md)** | 한국어

Codex가 설계하고, Claude가 구현하는 협업 워크스페이스.

## 개요

이 저장소는 **Codex(설계자) → Claude(구현자)** 루프를 반복 가능한 작업 환경으로 만든 것입니다.

- Codex가 `design.md`에 설계를 작성하면
- Claude가 그 문서를 읽고 구현을 진행합니다
- 설계 문서가 불완전하면 구현이 자동으로 차단됩니다

## 워크플로우

사용자 프롬프트부터 **Codex(설계자)** 와 **Claude(구현자)** 가 각각 거치는 흐름. 자세한 설명은 [kb/concepts/workflow.md](./kb/concepts/workflow.md).

```mermaid
flowchart TD
    U["USER PROMPT — task 요청"] --> ENTRY["진입 로드세트: QUICKREF + manifest + design.md"]
    ENTRY --> Q{"design.md 있나?"}

    Q -->|"없음"| C1["codex-design 실행"]
    Q -->|"있음 · ready/done"| L1["claude-implement 실행"]

    subgraph CODEX["① Codex 레인 · 설계자"]
        direction TB
        C1 --> C2["task 디렉터리 + design 초안 + manifest 자동생성"]
        C2 --> C4{"--auto?"}
        C4 -->|"수동"| C5["안내 후 종료 0"]
        C4 -->|"세션 내부"| C6["재귀가드 스킵 0"]
        C4 -->|"자동"| C7["codex exec · sandbox + git preflight"]
        C7 --> C8["design.md = Status ready"]
    end

    C8 --> L1

    subgraph CLAUDE["② Claude 레인 · 구현자"]
        direction TB
        L1 --> L2{"검증 게이트 · validator/cli.py · schema.json"}
        L2 -->|"rc1 보완 · rc2 환경오류"| X1["구현 중단"]
        L2 -->|"rc0 통과"| L3["impl-notes 초안 → 구현 → 변경점 기록"]
        L3 --> L6["artifact summary = Status done"]
    end

    L6 --> ENF1

    subgraph ENF["③ 완료·집계 강제 규약"]
        direction TB
        ENF1["--done → check-done · notes + artifact 검증"]
        ENF2["generate-status.py → status.md 표 자동생성 · 사람 손 ✗"]
        ENF1 --> ENF2
    end

    ENF2 --> CI["CI 3-OS · pytest · smoke · bats · Pester · board drift · done-gate"]
```

곳곳의 방어선: `--auto` 실패 non-zero 전파 · 재귀가드(`CLAUDECODE`) · 컨텍스트 예산 `context-budget.py`(경고) · `design.md` 는 Codex 소유(Claude 미수정).

## 구조

```
├── QUICKREF.md                # 빠른 운영 참조 (routine 진입점)
├── AGENT.md                   # 공통 에이전트 규약 + 상태 전이 정의 (정본)
├── CLAUDE.md                  # Claude 운영 규약
├── collab.md                  # 리뷰 루프 인터페이스/enum/게이트 정본 (v2 active)
├── UPDATING.md                # 기존 클론에 최신 CWC 반영하는 절차
├── kb/                        # 지식 저장소 (로컬 마크다운 vault)
│   ├── index/                 # status.md(생성형 보드), 목차
│   ├── concepts/              # 아키텍처, 워크플로우
│   ├── tasks/<task-id>/       # design.md · implementation-notes.md · manifest.md
│   └── artifacts/             # 산출물 요약
├── runtime/                   # 실행 스크립트 + 검증/도구 (Bash · PowerShell · Python)
│   ├── codex-design.{sh,ps1}      # Codex 설계 요청 + manifest 자동생성 + 후검증
│   ├── claude-implement.{sh,ps1}  # 설계 검증 + 구현 안내 + --done 완료검증
│   ├── validator/                 # design.md 검증 단일원천 (schema.json + Python)
│   ├── lib/                       # python probe · 세션감지 · invoke-codex/claude
│   ├── context-budget.py          # 컨텍스트 예산 경고 (warning-only)
│   ├── generate-status.py         # status.md 보드 자동생성 + --check drift
│   └── README.md                  # 외부 CLI 계약 + 종료코드 규약
├── templates/                 # design · implementation-notes · artifact · manifest 템플릿
└── tests/                     # pytest(validator·context_budget·status_board) + bats + pester + smoke
```

## 사용법

### 1단계: Codex에게 설계 요청

```powershell
# PowerShell
./runtime/codex-design.ps1 task-004 "사용자 인증 모듈 설계"

# Bash
./runtime/codex-design.sh task-004 "사용자 인증 모듈 설계"
```

> 새 task 생성 시 `manifest.md` 가 자동 생성된다. `--auto` 를 주면 Codex 가 자동 호출된다.

### 2단계: Claude에게 구현 요청

```powershell
# PowerShell
./runtime/claude-implement.ps1 task-004

# Bash
./runtime/claude-implement.sh task-004
```

### 3단계: 완료 검증 (구현 후, 선택)

```powershell
# PowerShell
./runtime/claude-implement.ps1 task-004 -Done

# Bash
./runtime/claude-implement.sh --done task-004
```

> done-gate: `implementation-notes.md` 와 `kb/artifacts/<id>-summary.md` 가 채워졌는지 검사한다.
> 완료 task 가 생기면 `python3 runtime/generate-status.py` 로 `kb/index/status.md` 보드가 자동 갱신된다(CI 가 drift 를 검사).

## 설계 문서 검증

`claude-implement`와 `codex-design` 모두 동일한 검증을 수행합니다. 검증 항목·차단 조건의 단일 진실 원천은 [`runtime/validator/schema.json`](./runtime/validator/schema.json) 이며, 사람이 읽는 요약은 [QUICKREF.md](./QUICKREF.md) "검증 게이트" 절에 있습니다.

## 문서 상태 전이

설계 준비도(design.md)와 구현 진행도(implementation-notes.md)를 **두 층으로 분리**합니다. 상태 모델의 단일 진실 원천은 [AGENT.md](./AGENT.md) "문서 상태 전이" 절입니다.

## 환경

- **Windows**: PowerShell `.ps1` 스크립트 (UTF-8 BOM, `codex.cmd` 호출)
- **macOS/Linux**: Bash `.sh` 스크립트
- **지식 저장소**: 로컬 마크다운 파일 (Obsidian 등으로 열람 가능)

## 로드맵

- **v1**: Codex 설계 → Claude 구현 루프 + 검증 게이트 · 컨텍스트 예산 · 생성형 status board · done-gate.
- **v2 (현재)**: 모델/effort 강제 + 프롬프트 SSOT, (선택) 설계 교차검토(`review-design`),
  `collab.md` 기반 Codex 구현 리뷰 루프(`codex-review`) + approved-done 게이트.
- **v2+ (보류)**: Notion 등 외부 백엔드 어댑터 — 두 번째 backend 요구가 실제로 생길 때 도입.

## 업데이트

이미 CWC 를 클론해서 작업 중인 디렉터리에 최신 프레임워크를 **작업 손실 없이** 반영하는 절차는
[UPDATING.md](./UPDATING.md) 에 있다. 그 디렉터리의 AI 에이전트에게 "UPDATING.md 를 읽고 업데이트를
진행하라" 고 시켜도 된다 (문서 하단에 에이전트용 순서가 있다).

## License

MIT
