# 아키텍처 개요

> Status: draft
> Inputs: 초기 계획 문서
> Outputs: 워크스페이스 구조 결정
> Next step: 첫 번째 task를 통해 검증

## 3층 구조

이 워크스페이스는 세 가지 층으로 구성된다:

### 1. 협업 런타임 (runtime/)

- Claude가 Codex를 호출하는 스크립트 또는 래퍼
- v1에서는 최소한의 래퍼 명령만 제공
- 설계 생성과 구현 시작은 분리된 진입점으로 유지

### 2. 지식 저장소 (kb/)

- 로컬 마크다운 vault (기본 백엔드: local_md)
- Obsidian은 이 vault를 읽는 선택적 뷰어
- 디렉터리별 역할:
  - `index/` — 전체 현황과 목차
  - `concepts/` — 아키텍처, 설계 원칙, 개념 정리
  - `tasks/` — 작업 단위별 설계·구현 문서
  - `artifacts/` — 산출물 요약과 결정 기록

### 3. 규약 문서 (루트)

- `CLAUDE.md` — Claude 역할, 입력 위치, 구현 규칙, 기록 규칙
- `AGENT.md` — 공통 에이전트 규약, 문서 우선순위, 파일 작성 규칙
- `collab.md` — v2 리뷰 루프용 placeholder

## 협업 루프

```
v1 (현재):
  Codex --[design.md]--> Claude --[implementation]--> kb/

v2 (예정):
  Codex --[design.md]--> Claude --[implementation]--> Codex --[review via collab.md]--> Claude
```

## 저장 백엔드 추상화

v1 은 `local_md`(로컬 파일 시스템 마크다운) 하나만 쓰며, 문서 스키마(필수 필드: Status, Inputs, Outputs, Next step)를 백엔드와 무관하게 유지하므로 v2+ 에서 Notion 등 다른 백엔드를 어댑터 패턴으로 추가할 수 있다. (이 절이 백엔드 추상화의 단일 진실 원천이다.)
