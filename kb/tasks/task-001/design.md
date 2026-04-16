# 설계 문서 — task-001

> Status: done
> Inputs: 초기 계획 문서, 워크스페이스 요구사항
> Outputs: 워크스페이스 scaffold, 규약 문서, 런타임 스크립트
> Next step: Claude가 이 문서를 읽고 구현 시작

## 목표 (Objective)

Claude-Codex 협업 워크스페이스 v1의 초기 scaffold를 구축한다. Codex가 설계를 남기고 Claude가 그 설계를 따라 구현할 수 있는 반복 가능한 작업 환경을 만든다.

## 범위 (Scope)

- 포함:
  - 디렉터리 구조 생성 (kb/, runtime/, templates/)
  - 규약 문서 작성 (CLAUDE.md, AGENT.md)
  - 설계/구현/산출물 템플릿 작성
  - Codex 설계 요청 래퍼 스크립트
  - Claude 구현 시작 래퍼 스크립트
  - collab.md placeholder
- 제외:
  - 자동 리뷰 루프 (v2)
  - Notion/외부 백엔드 연동 (v2)
  - CI/CD 파이프라인

## 제약 (Constraints)

- 로컬 마크다운 파일 시스템만 사용 (local_md 백엔드)
- Codex CLI 설치 여부에 관계없이 수동 워크플로도 지원해야 함
- 기존 코드 없는 빈 저장소에서 시작

## 구현 단계 (Implementation Steps)

1. 필수 디렉터리 생성 (kb/index, kb/concepts, kb/tasks, kb/artifacts, runtime, templates)
2. CLAUDE.md 작성 — Claude 운영 규약
3. AGENT.md 작성 — 공통 에이전트 규약
4. collab.md placeholder 작성
5. kb/index/status.md, kb/index/README.md 작성
6. kb/concepts/architecture.md 작성
7. templates/ 하위에 design.md, implementation-notes.md, artifact-summary.md 템플릿 작성
8. runtime/codex-design.sh 작성 — Codex 설계 요청 래퍼
9. runtime/claude-implement.sh 작성 — Claude 구현 시작 래퍼 (필수 섹션 검증 포함)
10. 샘플 task-001로 전체 흐름 검증

## 파일/모듈 영향 (Affected Files/Modules)

| 파일/모듈 | 변경 유형 | 설명 |
|-----------|-----------|------|
| kb/ 전체 | create | 지식 저장소 디렉터리 구조 |
| runtime/ | create | 실행 스크립트 디렉터리 |
| templates/ | create | 문서 템플릿 디렉터리 |
| CLAUDE.md | create | Claude 운영 규약 |
| AGENT.md | create | 공통 에이전트 규약 |
| collab.md | create | v2 리뷰 루프 placeholder |
| .gitignore | create | Git 무시 규칙 |

## 테스트 기준 (Test Criteria)

- [ ] 필수 디렉터리 6개가 모두 존재한다
- [ ] CLAUDE.md와 AGENT.md가 존재하고, 작업 흐름을 설명한다
- [ ] 템플릿 3개가 templates/에 존재한다
- [ ] runtime 스크립트 2개가 실행 가능하다
- [ ] claude-implement.sh가 필수 섹션 누락 시 오류를 반환한다
- [ ] 샘플 task-001의 design.md가 필수 섹션 검증을 통과한다

## 오픈 이슈 (Open Issues)

- Codex CLI의 정확한 호출 인터페이스는 설치 환경에 따라 다를 수 있다. v1에서는 fallback으로 수동 작성을 안내한다.
- Windows 환경에서 bash 스크립트 호환성 — Git Bash 또는 MSYS2 환경을 전제한다.
