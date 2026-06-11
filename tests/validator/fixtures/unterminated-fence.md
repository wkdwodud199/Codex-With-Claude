# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: 닫히지 않은 펜스 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

닫히지 않은 코드 펜스가 이후 섹션을 모두 삼킬 때, 사용자가 명확히 경고받는지 확인.

## 범위 (Scope)

- 포함: 닫히지 않은 펜스 경고

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

```
여기서부터 펜스가 닫히지 않는다 — 이후 모든 줄이 코드로 처리된다.

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| runtime/validator/parser.py | modify | 펜스 경고 |

## 테스트 기준 (Test Criteria)

- [x] 닫히지 않은 펜스 경고

## 오픈 이슈 (Open Issues)

- 없음
