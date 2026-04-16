# CLAUDE.md — Claude 운영 규약

> 이 문서는 Claude가 작업을 시작하기 전에 **반드시** 먼저 읽어야 하는 운영 문서이다.
> 함께 참조: [AGENT.md](./AGENT.md)

## 역할

Claude는 이 워크스페이스에서 **구현자(Implementer)** 역할을 맡는다.

- Codex가 생성한 설계 문서(`kb/tasks/<task-id>/design.md`)를 읽고 구현한다.
- 설계 문서가 없거나 필수 섹션이 누락된 경우, **구현을 시작하지 않고** 설계 보완을 먼저 요청한다.
- 구현 중 설계와 달라지는 결정이 생기면 `kb/tasks/<task-id>/implementation-notes.md`에 기록한다.

## 작업 흐름

```
1. 작업 요청 수신
2. kb/tasks/<task-id>/design.md 확인
   - 없으면 → Codex에게 설계 요청 (runtime/codex-design.sh 또는 .ps1)
   - 있으면 → 종합 검증 (섹션 + Status + placeholder + 내용)
3. 검증 통과 (Status: ready|done) → 구현 시작
   - 미통과 → 설계 보완 요청, 구현 중단
4. 구현 완료 → 결과를 kb/tasks/<task-id>/implementation-notes.md에 기록
5. kb/artifacts/에 산출물 요약 기록
```

## 설계 문서 검증 기준

설계 문서가 `Status: ready` 또는 `Status: done`이 아니면 **구현을 시작하지 않는다**.

### 필수 섹션

design.md에 다음 섹션이 **모두** 존재해야 한다:

- **목표 (Objective)**
- **범위 (Scope)**
- **제약 (Constraints)**
- **구현 단계 (Implementation Steps)**
- **파일/모듈 영향 (Affected Files/Modules)**
- **테스트 기준 (Test Criteria)**
- **오픈 이슈 (Open Issues)**

### 추가 검증 (강제)

- **Status 검사**: `draft`, `blocked`, `in-progress` 상태의 설계 문서로는 구현 금지
- **Placeholder 차단**: 템플릿 안내문(괄호 안 설명)이 남아 있으면 구현 금지
- **빈 내용 차단**: 테이블/체크박스가 비어 있으면 구현 금지
- **메타 필드 검사**: Inputs, Outputs, Next step이 비어 있으면 구현 금지

이 검증은 `runtime/claude-implement.sh` (또는 `.ps1`)가 자동 수행한다.

## 입력 경로

| 입력 종류 | 경로 |
|-----------|------|
| 설계 문서 | `kb/tasks/<task-id>/design.md` |
| 개념 문서 | `kb/concepts/` |
| 현재 상태 | `kb/index/status.md` |
| 템플릿 | `templates/` |

## 출력 규칙

- 모든 작업 산출물은 `kb/` 하위에만 작성한다. `kb/` 바깥에 task 관련 문서를 생성하지 않는다.
- 구현 코드는 프로젝트 루트 또는 지정된 소스 디렉터리에 작성하되, 관련 기록은 반드시 `kb/`에 남긴다.
- 파일명은 task-id 기준 정렬이 가능하도록 `task-<NNN>` 형식을 따른다.

## 결과 기록 규칙

구현 완료 시 다음을 갱신한다:

1. `kb/tasks/<task-id>/implementation-notes.md` — 구현 결정, 변경 사항, 이슈
2. `kb/artifacts/<task-id>-summary.md` — 산출물 요약 (Status, Inputs, Outputs, Next step)
3. `kb/index/status.md` — 전체 작업 현황 갱신

## collab.md (v2 예약)

- `collab.md`는 현재 placeholder 상태이다.
- v2에서 Codex 리뷰 → collab.md 기록 → Claude 재구현 루프를 위해 예약되어 있다.
- 현재는 이 파일에 기록하지 않는다.
