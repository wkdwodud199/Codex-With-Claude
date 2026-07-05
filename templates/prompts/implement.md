{{TASK_ID}} 의 설계 문서를 읽고 구현을 시작해주세요.

설계 문서: {{DESIGN_FILE}}
구현 노트: {{IMPL_NOTES}}
프로젝트 루트: {{PROJECT_ROOT}}
라우팅: 이 세션은 설계의 실행 계획에 따라 model={{MODEL}}, effort={{EFFORT}} 로 호출되었습니다.

CLAUDE.md 규약:
  1. design.md 를 먼저 읽으세요 (필수 섹션 / Status / 실행 계획 확인).
  2. 실행 계획의 병렬화 표를 따르세요 — 독립 unit(같은 group)은 단일 세션 안에서 서브에이전트로 병렬 진행할 수 있습니다. 다중 세션 fan-out 은 금지.
  3. 구현 중 결정이 설계와 달라지면 implementation-notes.md 에 기록하세요.
  4. 완료 후 kb/artifacts/{{TASK_ID}}-summary.md 를 작성하고 python3 runtime/generate-status.py 를 실행하세요.
