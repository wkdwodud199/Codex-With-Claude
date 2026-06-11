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


def test_golden_task_001_passes(schema):
    repo_root = FIXTURES.parent.parent.parent
    design = repo_root / "kb" / "tasks" / "task-001" / "design.md"
    errors = _validate(design, schema)
    assert errors == [], f"golden task-001 failed: {[e.message for e in errors]}"


def test_raw_template_fails(schema):
    repo_root = FIXTURES.parent.parent.parent
    template = repo_root / "templates" / "design.md"
    errors = _validate(template, schema)
    # Template should always trip multiple rules — it is draft + placeholders
    assert len(errors) >= 3
    codes = {e.code for e in errors}
    assert "status_blocked" in codes
    assert "placeholder_remaining" in codes
