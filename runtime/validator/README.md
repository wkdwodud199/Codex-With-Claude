# validator — design.md 검증기

> Load: on-demand
> Last-reviewed: 2026-04-17

설계 문서(`kb/tasks/<id>/design.md`) 검증의 **단일 진실 원천**입니다.
bash 스크립트, PowerShell 스크립트, 향후 다른 언어 러너 모두 이 모듈 하나를 호출합니다.

## 사용

```bash
python3 runtime/validator/cli.py <design.md>
python3 runtime/validator/cli.py <design.md> --json
python3 runtime/validator/cli.py <design.md> --schema <alternate.json>
```

종료 코드:
- `0` — 검증 통과
- `1` — 검증 실패 (오류 리스트 출력)
- `2` — 파일 없음 / 디코딩 실패

## 구성

| 파일 | 역할 |
|------|------|
| `schema.json` | 필수 섹션 · placeholder · 메타필드 · 상태값 등 규칙의 선언적 정의 |
| `parser.py` | BOM / CRLF 정규화, fenced-code 제거, 메타블록·섹션·placeholder 수집 |
| `rules.py` | 파싱된 문서에 schema 규칙 적용 → `ValidationError` 리스트 반환 |
| `cli.py` | argv 진입점 (JSON / 사람이 읽는 포맷) |

## Python 의존성

stdlib만 사용. 파이썬 3.8 이상. 설치 패키지 불필요.

러너(`*.sh`, `*.ps1`)가 아래 순서로 파이썬을 탐지합니다:

1. `python3`
2. `python`
3. `py -3`

## 테스트

```bash
# pytest (validator 전체 스위트)
python3 -m pytest tests/validator

# bash 기반 엔드투엔드 smoke
bash tests/run-smoke.sh

# bats 버전 (선택, CI에서 실행)
bats tests/bats
```
