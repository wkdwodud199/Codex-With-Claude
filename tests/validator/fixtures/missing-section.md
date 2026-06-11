# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: 섹션 누락 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

"오픈 이슈" 섹션을 의도적으로 제거하여 누락 감지 확인.

## 범위 (Scope)

- 포함: 섹션 누락 케이스

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. 섹션 제거

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| rules.py | modify | 섹션 검사 |

## 테스트 기준 (Test Criteria)

- [x] 섹션 누락 FAIL
