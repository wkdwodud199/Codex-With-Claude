# kb/artifacts/ — 산출물 요약

task 완료 시 `kb/artifacts/task-<NNN>-summary.md`(`templates/artifact-summary.md` 기반)를 이곳에 작성한다.
새 워크스페이스에는 비어 있는 것이 정상이다.

- `Status: done` 인 요약이 곧 완료 신호이며, `runtime/generate-status.py` 가 이를 읽어
  `kb/index/status.md` 의 완료 표를 재생성한다.
- done-gate: `runtime/validator/cli.py --check-done <id>` 가 요약 + implementation-notes + manifest 를 검사한다.
