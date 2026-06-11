# 설계 문서 — task-test

> Status: ready
> Inputs: 
> Outputs: 빈 메타 필드 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

Inputs가 비어있으면 실패해야 함.

## 범위 (Scope)

- 포함: 빈 meta

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. Inputs 비우기

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| rules.py | modify | empty meta 검사 |

## 테스트 기준 (Test Criteria)

- [x] empty meta FAIL

## 오픈 이슈 (Open Issues)

- 없음
