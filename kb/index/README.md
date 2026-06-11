# kb/ — 지식 저장소 (Knowledge Base)

> 이 디렉터리는 Claude-Codex 협업 워크스페이스의 로컬 마크다운 vault이다.
> Obsidian 등 마크다운 뷰어로 열어 탐색할 수 있다.

## 디렉터리 구조

```
kb/
├── index/          요약, 목차, 현재 상태
│   ├── README.md   이 문서
│   └── status.md   전체 작업 현황
├── concepts/       개념 문서, 아키텍처, 설계 원칙
├── tasks/          작업 단위별 설계·구현 문서
│   └── task-<NNN>/
│       ├── design.md                설계 문서 (Codex 작성)
│       ├── manifest.md              per-task 의존성 선언 (codex-design 자동 생성, Phase A 이후)
│       └── implementation-notes.md  구현 노트 (Claude 작성)
└── artifacts/      산출물 요약, 로그 링크, 결정 기록
    └── task-<NNN>-summary.md
```

## 규칙

- 모든 task 관련 문서는 이 디렉터리 하위에만 작성한다.
- 저장 백엔드 추상화는 [concepts/architecture.md](../concepts/architecture.md) "저장 백엔드 추상화" 절을 참조한다.
- 자세한 규약은 루트의 [AGENT.md](../../AGENT.md)를 참조한다.
