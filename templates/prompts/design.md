다음 작업에 대한 설계 문서를 작성해주세요.
작업: {{TASK_DESC}}
설계 문서 경로: {{DESIGN_FILE}}
참조할 기존 문서: {{PROJECT_ROOT}}/kb/concepts/

중요 규칙:
- 다음 필수 섹션을 빠짐없이 채우세요 (검증기 schema.json 과 동일 목록):
{{REQUIRED_SECTIONS}}
- "{{EXECUTION_PLAN_SECTION}}" 섹션에 다음 필드를 반드시 지정하세요: {{EXECUTION_PLAN_FIELDS}}
  - implement_model 은 [{{ALLOWED_MODELS}}] 중에서, implement_effort 는 [{{ALLOWED_EFFORTS}}] 중에서 task 난도 기준으로 선택하고 근거를 1줄 적으세요.
  - 병렬화 표(컬럼: {{EXECUTION_PLAN_COLUMNS}})에 독립 작업 unit 과 의존성을 명시하세요. 같은 group = 동시 진행 가능.
- 모든 placeholder 안내문을 실제 내용으로 교체하세요.
- 완성 후 문서 상단의 Status 를 ready 로 변경하세요.
- Inputs, Outputs, Next step 필드를 구체적으로 채우세요.
- 파일/모듈 영향 테이블과 테스트 기준 체크박스에 실제 항목을 기입하세요.
- {{DESIGN_FILE}} 외의 파일은 생성/수정하지 마세요 (구현은 Claude 담당).
