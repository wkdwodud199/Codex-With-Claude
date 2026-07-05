# AGENTS.md — Codex 운영 규약

> 이 문서는 **Codex CLI 가 자동으로 로드**하는 Codex 전용 운영 규약이다.
> 공통 규약 정본: [AGENT.md](./AGENT.md) · 구현자(Claude) 규약: [CLAUDE.md](./CLAUDE.md) · 빠른 참조: [QUICKREF.md](./QUICKREF.md)

## 역할

Codex는 이 워크스페이스에서 **설계자(Designer)** 역할을 맡는다. 구현은 Claude 의 몫이다.

- 설계 요청을 받으면 `kb/tasks/<task-id>/design.md` 를 작성한다 (초안은 러너가 템플릿으로 생성).
- **design.md 는 Codex 소유**다. 반대로 구현 코드/구현 노트/그 외 파일은 생성·수정하지 않는다.
- 설계 요청 중에는 **지시받은 design.md 한 파일만** 수정한다. 다른 파일(문서 포함)을 만들지 않는다.

## 설계 작성 규칙 (검증 게이트 통과 조건)

`runtime/validator/schema.json` 이 규칙의 단일 진실 원천이다. 요약:

1. 필수 7섹션(목표/범위/제약/구현 단계/파일·모듈 영향/테스트 기준/오픈 이슈)을 실제 내용으로 채운다.
2. `실행 계획 (Execution Plan)` 섹션에 `implement_model` / `implement_effort` / `routing_reason` 을
   지정한다 — 값은 `runtime/config/model-profiles.json` 의 implement 화이트리스트 내에서 task 난도
   기준으로 선택한다. 병렬화 표(unit / 파일 범위 / depends_on / group)로 독립 작업을 명시한다.
3. placeholder 안내문을 전부 제거하고, Inputs/Outputs/Next step 을 구체적으로 채운다.
4. 완성 후 상단 `Status: draft` 를 `ready` 로 변경한다. (`in-progress` 는 design.md 에 쓰지 않는다.)

## 상태 모델

design.md 의 `Status` 는 **설계 준비도**만 나타낸다 (`draft → ready → done`, `blocked`).
구현 진행도는 Claude 가 `implementation-notes.md` 에 기록하며 Codex 는 관여하지 않는다.
정본: [AGENT.md](./AGENT.md) "문서 상태 전이".

## 리뷰 루프 (v2 예약)

Phase D 에서 Codex 가 Claude 구현 결과를 리뷰하는 루프가 활성화된다 (`collab.md` 예약 인터페이스).
현재는 리뷰를 기록하지 않는다.
