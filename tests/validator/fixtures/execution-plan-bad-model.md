# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: 실행 계획 화이트리스트 위반 샘플
> Next step: 검증기가 이 문서를 거부해야 함

## 목표 (Objective)

화이트리스트에 없는 implement_model 이 거부되는지 확인.

## 범위 (Scope)

- 포함: 검증기 실패 경로
- 제외: 실제 구현

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. 문서 읽기
2. 테스트 실행

## 실행 계획 (Execution Plan)

- implement_model: gpt-5.5
- implement_effort: ultra
- routing_reason: 잘못된 모델/effort 지정 샘플

| unit | 파일 범위 | depends_on | group |
|------|-----------|------------|-------|
| U1 | tests/ | 없음 | G1 |

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| tests/validator/fixtures/execution-plan-bad-model.md | create | 위반 샘플 |

## 테스트 기준 (Test Criteria)

- [x] 검증기가 1 코드 반환

## 오픈 이슈 (Open Issues)

- 없음
