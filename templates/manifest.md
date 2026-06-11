# Manifest — task-<NNN>

> **Load**: 기본 로드 세트의 일부. 이 task 가 *실제로* 의존하는 것만 명시해 컨텍스트를 최소화한다.
> 여기에 없는 개념/파일은 기본적으로 열지 않는다.

- **task_id**: task-<NNN>
- **inputs**: (이 task 가 의존하는 입력 문서/데이터)
- **concepts_needed**: (kb/concepts/ 중 실제 필요한 문서만; 없으면 `없음`)
- **related_files**: (구현·수정 대상 또는 참조할 소스 파일 경로)
- **notes**: (로드 시 주의점; 생략 가능)
