# 설계 문서 — task-test

> Status: wip
> Inputs: 초기 계획 문서
> Outputs: 허용되지 않은 status 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

알 수 없는 status 값 처리.

## 범위 (Scope)

- 포함: unknown status

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. invalid status 지정

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| rules.py | modify | status check |

## 테스트 기준 (Test Criteria)

- [x] invalid status FAIL

## 오픈 이슈 (Open Issues)

- 없음
