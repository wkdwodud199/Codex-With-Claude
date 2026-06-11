# 설계 문서 — task-test

> Status: ready
> Inputs: 초기 계획 문서
> Outputs: placeholder 문구 문장 내 사용 샘플
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

설명 도중에 (이 작업이 달성하려는 것을 1-2문장으로 기술) 같은 템플릿 문구를 인용해도 검증이 통과해야 함.

## 범위 (Scope)

- 포함: 문장 내 placeholder 인용
- 제외: 단독 라인의 placeholder는 실패로 유지

## 제약 (Constraints)

- 템플릿 문구가 문장 일부일 때 false-positive를 피해야 한다.

## 구현 단계 (Implementation Steps)

1. placeholder 문구를 인용 포함한 설명 작성
2. 검증 통과 확인

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| parser.py | modify | line-anchored 매칭 |

## 테스트 기준 (Test Criteria)

- [x] 문장 내 인용은 검증 통과

## 오픈 이슈 (Open Issues)

- 없음
