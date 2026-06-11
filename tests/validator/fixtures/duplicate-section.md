# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: 섹션 중복 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

목표 섹션이 두 번 등장하는 케이스.

## 범위 (Scope)

- 포함: 중복 섹션 감지

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. 목표 섹션 두 번 삽입

## 목표 (Objective)

두 번째 목표 섹션 — 중복 감지 대상.

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| rules.py | modify | 섹션 중복 검사 |

## 테스트 기준 (Test Criteria)

- [x] 중복 섹션 FAIL

## 오픈 이슈 (Open Issues)

- 없음
