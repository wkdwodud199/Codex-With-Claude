# 설계 문서 — task-test

> Inputs: 초기 계획 문서
> Outputs: status 누락 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

Status 필드가 아예 없는 경우.

## 범위 (Scope)

- 포함: status missing

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. status 누락

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| rules.py | modify | status 필드 존재 검사 |

## 테스트 기준 (Test Criteria)

- [x] status 누락 FAIL

## 오픈 이슈 (Open Issues)

- 없음
