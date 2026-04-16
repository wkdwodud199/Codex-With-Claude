# Codex-With-Claude

> **[English](./README.en.md)** | 한국어

Codex가 설계하고, Claude가 구현하는 협업 워크스페이스.

## 개요

이 저장소는 **Codex(설계자) → Claude(구현자)** 루프를 반복 가능한 작업 환경으로 만든 것입니다.

- Codex가 `design.md`에 설계를 작성하면
- Claude가 그 문서를 읽고 구현을 진행합니다
- 설계 문서가 불완전하면 구현이 자동으로 차단됩니다

## 구조

```
├── CLAUDE.md                  # Claude 운영 규약
├── AGENT.md                   # 공통 에이전트 규약 + 상태 전이 정의
├── collab.md                  # v2 리뷰 루프 placeholder
├── kb/                        # 지식 저장소 (로컬 마크다운 vault)
│   ├── index/                 # 작업 현황, 목차
│   ├── concepts/              # 아키텍처, 설계 원칙
│   ├── tasks/<task-id>/       # 작업별 설계·구현 문서
│   └── artifacts/             # 산출물 요약
├── runtime/                   # 실행 스크립트 (Bash + PowerShell)
│   ├── codex-design.sh/.ps1   # Codex 설계 요청 + 후검증
│   └── claude-implement.sh/.ps1 # 설계 검증 + 구현 안내
└── templates/                 # 문서 템플릿
```

## 사용법

### 1단계: Codex에게 설계 요청

```powershell
# PowerShell
./runtime/codex-design.ps1 task-002 "사용자 인증 모듈 설계"

# Bash
./runtime/codex-design.sh task-002 "사용자 인증 모듈 설계"
```

### 2단계: Claude에게 구현 요청

```powershell
# PowerShell
./runtime/claude-implement.ps1 task-002

# Bash
./runtime/claude-implement.sh task-002
```

## 설계 문서 검증

`claude-implement`와 `codex-design` 모두 동일한 검증을 수행합니다:

| 검증 항목 | 차단 조건 |
|-----------|-----------|
| 필수 섹션 7개 | 하나라도 누락 시 |
| Status | `ready` 또는 `done`이 아닌 경우 |
| Placeholder | 템플릿 안내문 8종 중 하나라도 잔존 시 |
| 메타 필드 | Inputs/Outputs/Next step 누락 또는 빈 값 |
| 빈 내용 | 테이블·체크박스가 기본값 그대로인 경우 |

## 문서 상태 전이

```
draft → ready → in-progress → done
                                ↓
                             blocked
```

| 상태 | 의미 |
|------|------|
| `draft` | 템플릿 또는 미완성 |
| `ready` | 설계 완료, 구현 가능 |
| `in-progress` | 구현 중 |
| `done` | 완료 |
| `blocked` | 차단 |

## 환경

- **Windows**: PowerShell `.ps1` 스크립트 (UTF-8 BOM, `codex.cmd` 호출)
- **macOS/Linux**: Bash `.sh` 스크립트
- **지식 저장소**: 로컬 마크다운 파일 (Obsidian 등으로 열람 가능)

## 로드맵

- **v1 (현재)**: Codex 설계 → Claude 구현 루프
- **v2**: `collab.md`를 통한 Codex 리뷰 → Claude 재구현 루프
- **v2+**: Notion 등 외부 백엔드 어댑터

## License

MIT
