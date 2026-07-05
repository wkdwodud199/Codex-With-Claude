"""Fixture-driven tests for validator.rules — one parametrized case per fixture."""

from __future__ import annotations

from pathlib import Path

import pytest

from validator.rules import load_schema, run_all_rules, parse_with_schema

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture(scope="module")
def schema():
    return load_schema()


def _validate(path: Path, schema):
    text = path.read_text(encoding="utf-8")
    doc = parse_with_schema(text, schema)
    return run_all_rules(doc, schema)


@pytest.mark.parametrize(
    "filename",
    [
        "good.md",
        "bom.md",
        "crlf.md",
        "trailing-ws-status.md",
        "fenced-status-draft.md",
        "placeholder-substring.md",
        "heading-closing-hash.md",
        "fence-longer-opener.md",
    ],
)
def test_pass_fixtures(schema, filename):
    errors = _validate(FIXTURES / filename, schema)
    assert errors == [], f"{filename}: {[e.message for e in errors]}"


@pytest.mark.parametrize(
    "filename, expected_code",
    [
        ("missing-section.md", "section_missing"),
        ("duplicate-section.md", "section_duplicate"),
        ("status-draft.md", "status_blocked"),
        ("status-blocked.md", "status_blocked"),
        ("status-missing.md", "status_missing"),
        ("status-invalid.md", "status_invalid"),
        ("empty-meta.md", "meta_empty"),
        ("empty-table.md", "empty_content"),
        ("empty-checkbox.md", "empty_content"),
        ("empty-affected-files-table.md", "section_empty"),
        ("placeholder-remaining.md", "placeholder_remaining"),
        ("bullet-placeholder.md", "placeholder_remaining"),
    ],
)
def test_fail_fixtures(schema, filename, expected_code):
    errors = _validate(FIXTURES / filename, schema)
    codes = [e.code for e in errors]
    assert expected_code in codes, f"{filename} expected {expected_code}, got {codes}"


def test_empty_affected_files_table_flagged(schema):
    """A table with only header + separator (no data rows) must be flagged."""
    errors = _validate(FIXTURES / "empty-affected-files-table.md", schema)
    codes = [e.code for e in errors]
    assert "section_empty" in codes


def test_unterminated_fence_warns_not_silent(schema):
    """A stray unterminated fence surfaces an explicit warning to the user.

    The fence swallows the sections after it, but instead of (only) emitting
    misleading 'section_missing' errors the validator must clearly warn the
    user via the 'unterminated_fence' diagnostic so the real cause is visible.
    """
    errors = _validate(FIXTURES / "unterminated-fence.md", schema)
    codes = [e.code for e in errors]
    assert "unterminated_fence" in codes, f"got {codes}"


def test_in_progress_status_message_points_to_implementation_notes(schema):
    """D1: in-progress stays blocked but the message explains it's an impl state."""
    blocked = schema["blocked_statuses"]
    assert "in-progress" in blocked
    msg = blocked["in-progress"]
    assert "구현 상태" in msg
    assert "implementation-notes.md" in msg


def test_status_in_progress_still_blocked(schema):
    """D1: design start must still refuse in-progress (only ready|done allowed)."""
    text = (
        "> Status: in-progress\n"
        "> Inputs: x\n> Outputs: y\n> Next step: z\n"
        "## 목표 (Objective)\n내용\n"
        "## 범위 (Scope)\n내용\n"
        "## 제약 (Constraints)\n내용\n"
        "## 구현 단계 (Implementation Steps)\n1. 내용\n"
        "## 파일/모듈 영향 (Affected Files/Modules)\n"
        "| 파일/모듈 | 변경 유형 | 설명 |\n|---|---|---|\n| a.py | modify | b |\n"
        "## 테스트 기준 (Test Criteria)\n- [x] ok\n"
        "## 오픈 이슈 (Open Issues)\n- 없음\n"
    )
    from validator.rules import run_all_rules, parse_with_schema

    doc = parse_with_schema(text, schema)
    errors = run_all_rules(doc, schema)
    codes = [e.code for e in errors]
    assert "status_blocked" in codes


# ---------------------------------------------------------------------------
# 실행 계획 (Execution Plan) 규칙 — task-004
# whitelist 는 cli.py 가 profiles.json 에서 로드해 주입하므로, 단위 테스트는
# 동일 형태의 dict 를 직접 주입한다 (규칙 모듈은 IO 없음).
# ---------------------------------------------------------------------------

EP_WHITELIST = {
    "allowed_models": ["claude-fable-5", "claude-opus-4-8"],
    "allowed_efforts": ["medium", "high", "xhigh", "max"],
}


def _ep_errors(filename, schema, task_id=None, whitelist=EP_WHITELIST):
    from validator.rules import check_execution_plan

    text = (FIXTURES / filename).read_text(encoding="utf-8")
    doc = parse_with_schema(text, schema)
    return check_execution_plan(doc, schema, task_id=task_id, whitelist=whitelist)


def test_execution_plan_good_fixture_passes(schema):
    assert _ep_errors("good.md", schema) == []


def test_execution_plan_bad_model_and_effort_flagged(schema):
    codes = [e.code for e in _ep_errors("execution-plan-bad-model.md", schema)]
    assert "execution_plan_model_not_allowed" in codes
    assert "execution_plan_effort_not_allowed" in codes


def test_execution_plan_missing_table_flagged(schema):
    codes = [e.code for e in _ep_errors("execution-plan-missing-table.md", schema)]
    assert "execution_plan_table_missing" in codes


def test_execution_plan_absent_legacy_ok(schema):
    assert _ep_errors("legacy-no-execution-plan.md", schema, task_id="task-001") == []


def test_execution_plan_absent_nonlegacy_flagged(schema):
    codes = [e.code for e in _ep_errors("execution-plan-absent-nonlegacy.md", schema, task_id="task-999")]
    assert "execution_plan_missing" in codes


def test_execution_plan_absent_unknown_task_id_flagged(schema):
    """task id 파생 실패 시 legacy 예외를 적용하지 않는다 (설계 5단계, 방어)."""
    codes = [e.code for e in _ep_errors("legacy-no-execution-plan.md", schema, task_id=None)]
    assert "execution_plan_missing" in codes


def test_execution_plan_template_placeholders_flagged(schema):
    """템플릿의 실행 계획 placeholder 가 실제 값으로 교체되지 않으면 걸린다."""
    from validator.rules import check_execution_plan

    repo_root = FIXTURES.parent.parent.parent
    text = (repo_root / "templates" / "design.md").read_text(encoding="utf-8")
    doc = parse_with_schema(text, schema)
    codes = [e.code for e in check_execution_plan(doc, schema, task_id=None, whitelist=EP_WHITELIST)]
    assert "execution_plan_field_placeholder" in codes


def test_execution_plan_extracts_expected_values(schema):
    """실행 계획 필드 추출값을 fixture(good.md)로 고정한다 (self-contained)."""
    from validator.rules import extract_execution_plan

    text = (FIXTURES / "good.md").read_text(encoding="utf-8")
    doc = parse_with_schema(text, schema)
    plan = extract_execution_plan(doc, schema)
    assert plan is not None
    assert plan["implement_model"] == "claude-opus-4-8"
    assert plan["implement_effort"] == "xhigh"


def test_raw_template_fails(schema):
    repo_root = FIXTURES.parent.parent.parent
    template = repo_root / "templates" / "design.md"
    errors = _validate(template, schema)
    # Template should always trip multiple rules — it is draft + placeholders
    assert len(errors) >= 3
    codes = {e.code for e in errors}
    assert "status_blocked" in codes
    assert "placeholder_remaining" in codes
