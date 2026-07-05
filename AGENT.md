# AGENT.md — 공통 에이전트 규약

> 이 문서는 이 워크스페이스에서 작동하는 **모든 에이전트**(Claude, Codex 등)의
> 공통 운영 규약 **정본**이다. 역할별 세부 규칙: [CLAUDE.md](./CLAUDE.md)
>
> **routine 작업은 [QUICKREF.md](./QUICKREF.md) + `kb/tasks/<id>/manifest.md` + `design.md` 만 읽어도 충분하다.**
> 이 문서와 CLAUDE.md 는 예외·경계 상황에서 참조하는 상세 규약이다.
> (컨텍스트 예산 확인: `python3 runtime/context-budget.py <id>`)

## 문서 우선순위

- **빠른 경로 (routine)**: `QUICKREF.md` → `kb/tasks/<id>/manifest.md` → `kb/tasks/<id>/design.md`
- **상세 경로 (예외/경계)**: 위에 더해 이 **AGENT.md**(공통 정본) → **CLAUDE.md**(역할별) → `kb/index/status.md`

manifest 의 `concepts_needed` / `related_files` 에 적힌 것만 추가로 연다 (전부 읽지 않는다).

## 파일 작성 규칙

### 경로 규칙

- 작업 관련 모든 문서는 `kb/` 하위에만 작성한다.
- 디렉터리별 용도:
  - `kb/index/` — 요약, 목차, 현재 상태
  - `kb/concepts/` — 개념 문서, 아키텍처, 설계 원칙
  - `kb/tasks/<task-id>/` — 작업 단위별 설계·구현 문서
  - `kb/artifacts/` — 산출물 요약, 로그 링크, 결정 기록
- `kb/` 바깥에 task 관련 산출물을 흩뿌리지 않는다.

### 파일명 규칙

- task 디렉터리: `task-<NNN>` (예: `task-001`, `task-012`)
- 문서 파일: 영문 소문자, 하이픈 구분 (예: `design.md`, `implementation-notes.md`)
- frontmatter 없이 plain markdown을 기본으로 한다.

### 필수 필드

모든 task 관련 문서에는 최소한 다음 필드를 포함한다:

- **Status** — 아래 상태 전이 참조
- **Inputs** — 이 문서가 의존하는 입력 목록 (빈 값 금지)
- **Outputs** — 이 문서가 생성하는 산출물 목록 (빈 값 금지)
- **Next step** — 다음에 해야 할 일 (빈 값 금지)

### 문서 상태 전이

상태 모델은 **두 층으로 분리**된다. 한 필드에 설계 준비도와 구현 진행도를 섞지 않는다.

- **design.md 의 `Status`** = **설계 준비도(design readiness)** 만 나타낸다.
- **구현 진행(in-progress → done)** 은 design.md 가 아니라 **implementation-notes.md** 의 라이프사이클에 기록한다.

검증기(`runtime/validator/`)는 **design.md 만 게이트한다.** design.md 의 `Status` 가
`ready` 또는 `done` 이 아니면 구현 시작을 거부한다. 즉 검증기는 design.md 의 준비도만 본다.

#### design.md 상태 (설계 준비도)

design.md 의 `Status` 는 아래 4개 값만 사용한다.

```
draft ──→ ready ──→ done
  │         │
  └─────────┴──→ blocked
```

| 상태 | 의미 | 누가 설정 |
|------|------|-----------|
| `draft` | 템플릿 또는 미완성 | 자동 (초안 생성 시) |
| `ready` | Codex 설계 완료, Claude 구현 가능 | Codex (설계 완성 시) |
| `done` | (선택) 설계 동결. 완료 신호는 `kb/artifacts/<id>-summary.md` 의 `Status: done`. | Claude (선택, 구현 완료 후) |
| `blocked` | 설계가 차단된 상태 | 누구든 (차단 사유 발생 시) |

**핵심 규칙**: Claude(검증기)는 design.md 의 `Status` 가 `ready` 또는 `done` 일 때만 구현한다.
`draft` / `blocked` 상태 design.md 로는 구현을 시작하지 않는다.
(`in-progress` 는 design.md 의 유효한 값이 아니다 — 아래 참조.)

#### implementation-notes.md 라이프사이클 (구현 진행도)

구현 진행 상태는 design.md 와 **별개로** implementation-notes.md 에 기록한다.
이 값은 검증기가 보지 않으며, design.md 의 `Status` 에 쓰지 않는다.

```
in-progress ──→ done
```

| 상태 | 의미 | 누가 설정 |
|------|------|-----------|
| `in-progress` | Claude 구현 진행 중 | Claude (구현 시작 시) |
| `done` | 구현 및 기록 완료 | Claude (구현 완료 시) |

이렇게 분리함으로써 design.md 의 `Status` 의미(준비도)와 검증기 동작(준비도만 게이트)이
서로 모순되지 않는다.

## 지식베이스 갱신 규칙

1. 작업 완료 시 `python3 runtime/generate-status.py` 를 실행해 `kb/index/status.md` 를 재생성한다.
   (수동 편집 금지 — 마커 블록은 generate-status.py 가 소유. `--check` 로 drift 확인 가능.)
2. 새로운 개념이나 아키텍처 결정이 생기면 `kb/concepts/`에 문서를 추가한다.
3. 산출물 요약은 `kb/artifacts/<task-id>-summary.md`에 기록한다.
4. 기존 문서를 수정할 때는 변경 사유를 문서 내에 간략히 남긴다.

## 협업 프로토콜

### Codex → Claude (설계 → 구현)

1. Codex는 `kb/tasks/<task-id>/design.md`에 설계를 작성한다.
2. Claude는 해당 문서를 읽고 필수 섹션을 검증한 뒤 구현한다.
3. 설계가 불충분하면 Claude는 구현을 시작하지 않고 보완을 요청한다.

### 구현 중 변경 처리

- 설계와 다른 결정을 내려야 할 경우 `implementation-notes.md`에 사유를 기록한다.
- 설계 문서 자체를 수정하지 않는다 (설계 문서는 Codex 소유).

### 리뷰 루프 (v2 active)

- Codex 가 Claude 구현 결과를 리뷰하는 루프가 **활성화**되었다. 러너: `runtime/codex-review.{sh,ps1} <id>` (opt-in).
- 리뷰 데이터는 per-task `kb/tasks/<id>/reviews/<NNN>.md` 에 **누적**한다(collab.md 에 직접 쌓지 않는다).
- review status enum(`pending|request-changes|approved|rejected`)·no-auto-revert·approved-done 게이트의
  단일 정본은 [collab.md](./collab.md) 다. 검증기(`review_rules.py`)가 collab.md 의 enum 마커를 읽어 게이트한다.
- **approved-done**: `reviews/` 가 있으면 `--check-done` 은 최신 리뷰가 `approved` 일 때만 통과한다
  (없으면 기존 done-gate 동작 유지 — 리뷰 없는 기존 task 하위호환).

## 저장 백엔드

- v1 기본값: **local_md** (로컬 마크다운 파일 시스템). Obsidian은 이 vault를 읽는 선택적 뷰어다.
- 백엔드 추상화(어댑터 패턴, 백엔드 독립 스키마)는 [kb/concepts/architecture.md](./kb/concepts/architecture.md) "저장 백엔드 추상화" 절을 참조한다.
