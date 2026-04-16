# AGENT.md — 공통 에이전트 규약

> 이 문서는 이 워크스페이스에서 작동하는 **모든 에이전트**(Claude, Codex 등)가
> 작업 전에 **반드시** 읽어야 하는 공통 운영 규약이다.
> 역할별 세부 규칙: [CLAUDE.md](./CLAUDE.md)

## 문서 우선순위

에이전트는 작업 시작 전 다음 순서로 문서를 참조한다:

1. **AGENT.md** (이 문서) — 공통 규약
2. **CLAUDE.md** 또는 역할별 규약 문서 — 역할별 세부 규칙
3. **kb/index/status.md** — 현재 작업 현황
4. **kb/tasks/<task-id>/design.md** — 해당 작업 설계 문서

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

모든 task 문서는 다음 상태값을 사용한다. 문서와 스크립트가 동일한 정의를 따른다.

```
draft ──→ ready ──→ in-progress ──→ done
  │         │           │
  └─────────┴───────────┴──→ blocked
```

| 상태 | 의미 | 누가 설정 |
|------|------|-----------|
| `draft` | 템플릿 또는 미완성 | 자동 (초안 생성 시) |
| `ready` | Codex 설계 완료, Claude 구현 가능 | Codex (설계 완성 시) |
| `in-progress` | Claude 구현 중 | Claude (구현 시작 시) |
| `done` | 구현 및 기록 완료 | Claude (구현 완료 시) |
| `blocked` | 설계 또는 구현 차단 상태 | 누구든 (차단 사유 발생 시) |

**핵심 규칙**: Claude는 `Status: ready` 또는 `Status: done`인 설계 문서만 구현한다. `draft` 상태 문서로 구현을 시작하지 않는다.

## 지식베이스 갱신 규칙

1. 작업 완료 시 `kb/index/status.md`를 반드시 갱신한다.
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

### 리뷰 루프 (v2 예약)

- `collab.md`를 통한 Codex 리뷰 → Claude 재구현 루프는 v2에서 활성화한다.
- v1에서는 이 파일에 기록하지 않으며, 인터페이스만 예약한다.

## 저장 백엔드

- v1 기본값: **local_md** (로컬 마크다운 파일 시스템)
- Obsidian은 이 vault를 읽는 선택적 뷰어로 취급한다.
- v2에서 Notion 등 다른 백엔드를 어댑터 패턴으로 추가할 수 있도록 문서 스키마를 유지한다.
