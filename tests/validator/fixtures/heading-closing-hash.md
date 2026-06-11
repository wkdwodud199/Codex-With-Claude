# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: ATX 닫는 해시/들여쓰기 헤더 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective) ##

ATX 닫는 해시와 0-3칸 들여쓰기 헤더가 섹션으로 정상 인식되는지 확인.

 ## 범위 (Scope) ##

- 포함: 닫는 해시 헤더, 들여쓴 헤더

## 제약 (Constraints)

- 없음

## 구현 단계 (Implementation Steps)

1. 헤더 정규화 확인

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| runtime/validator/parser.py | modify | 헤더 정규화 |

## 테스트 기준 (Test Criteria)

- [x] 닫는 해시/들여쓰기 헤더 PASS

## 오픈 이슈 (Open Issues)

- 없음
