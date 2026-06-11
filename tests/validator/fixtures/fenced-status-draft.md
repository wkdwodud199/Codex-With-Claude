# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: fenced-status regression fixture
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

Fenced code block 안의 `> Status: draft` 같은 문구가 검증기를 오탐지시키지 않는지 확인.

예시:

```
> Status: draft
> Inputs: (이 설계가 의존하는 입력 나열)
## 목표 (Objective)
```

## 범위 (Scope)

- 포함: fenced-code 회귀 커버리지
- 제외: 실제 구현

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. fenced block 삽입
2. 검증기가 통과해야 함

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| parser.py | modify | 펜스 제거 |

## 테스트 기준 (Test Criteria)

- [x] fenced draft 문구 무시

## 오픈 이슈 (Open Issues)

- 없음
