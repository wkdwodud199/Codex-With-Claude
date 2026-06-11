# 설계 문서 — task-test

> Status: ready   
> Inputs: 초기 계획 문서
> Outputs: 공백 허용 확인
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

Status 라인의 후행 공백이 무시되는지 확인.

## 범위 (Scope)

- 포함: trailing whitespace
- 제외: 없음

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. 공백 포함
2. 통과 확인

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| parser.py | modify | whitespace 관용 |

## 테스트 기준 (Test Criteria)

- [x] 후행 공백 허용

## 오픈 이슈 (Open Issues)

- 없음
