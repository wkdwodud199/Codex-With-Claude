# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: 불릿 접두 placeholder 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

불릿 접두사 뒤에 placeholder 문구만 있는 경우도 잡아야 함.

## 범위 (Scope)

- 포함: 불릿 접두 placeholder

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. 불릿 placeholder 삽입

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| parser.py | modify | 불릿 마커 제거 후 매칭 |

## 테스트 기준 (Test Criteria)

- [x] 불릿 placeholder FAIL

## 오픈 이슈 (Open Issues)

- (설계 시점에 해결되지 않은 질문이나 리스크)
