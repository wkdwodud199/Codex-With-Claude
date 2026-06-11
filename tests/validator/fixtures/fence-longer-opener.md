# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: 긴 펜스 닫힘 규칙 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

긴 여는 펜스(~~~~)가 더 짧은 ~~~ 로는 닫히지 않고, 같은 길이 이상으로만 닫히는지 확인.

## 범위 (Scope)

- 포함: 펜스 길이 규칙

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

~~~~
이 블록 안의 ~~~ 는 닫는 펜스가 아니다.
## 가짜 섹션 (Fake Section)
~~~~

1. 위 코드 블록은 같은 길이의 ~~~~ 로만 닫힌다.

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| runtime/validator/parser.py | modify | 펜스 길이 규칙 |

## 테스트 기준 (Test Criteria)

- [x] 펜스 길이 규칙 PASS

## 오픈 이슈 (Open Issues)

- 없음
