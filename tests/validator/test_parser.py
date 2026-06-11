"""Unit tests for validator.parser — BOM, CRLF, fence stripping, metadata extraction."""

from __future__ import annotations

import pytest

from validator.parser import (
    normalize,
    parse_document,
    strip_fenced_blocks,
)


def test_normalize_strips_bom():
    text = "\ufeffhello\nworld"
    assert normalize(text) == "hello\nworld"


def test_normalize_converts_crlf():
    assert normalize("a\r\nb\r\nc") == "a\nb\nc"


def test_normalize_converts_lone_cr():
    assert normalize("a\rb\rc") == "a\nb\nc"


def test_strip_fences_basic():
    lines = ["alpha", "```", "code", "```", "beta"]
    blanked, ranges, diags = strip_fenced_blocks(lines)
    assert blanked == ["alpha", "", "", "", "beta"]
    assert ranges == [(2, 4)]
    assert diags == []


def test_strip_fences_tilde():
    lines = ["~~~", "x", "~~~"]
    blanked, ranges, diags = strip_fenced_blocks(lines)
    assert blanked == ["", "", ""]
    assert ranges == [(1, 3)]
    assert diags == []


def test_strip_fences_unterminated():
    lines = ["```", "x", "y"]
    blanked, ranges, diags = strip_fenced_blocks(lines)
    assert blanked == ["", "", ""]
    assert ranges == [(1, 3)]
    # Unterminated fence must surface a diagnostic so downstream rules can warn.
    assert len(diags) == 1
    assert diags[0][1] == "unterminated_fence"
    assert diags[0][0] == 1


def test_strip_fences_longer_opener_not_closed_by_shorter():
    """A '~~~~' opener must NOT be closed by a shorter '~~~' run (>= opener len)."""
    lines = ["~~~~", "x", "~~~", "y"]
    blanked, ranges, diags = strip_fenced_blocks(lines)
    # The shorter ~~~ does not close, so the fence runs to EOF (unterminated).
    assert blanked == ["", "", "", ""]
    assert ranges == [(1, 4)]
    assert len(diags) == 1
    assert diags[0][1] == "unterminated_fence"


def test_strip_fences_longer_opener_closed_by_equal_length():
    lines = ["~~~~", "x", "~~~~", "y"]
    blanked, ranges, diags = strip_fenced_blocks(lines)
    assert blanked == ["", "", "", "y"]
    assert ranges == [(1, 3)]
    assert diags == []


def test_metadata_extraction_preserves_first():
    text = (
        "> Status: ready\n"
        "> Status: done\n"
        "> Inputs: a, b, c\n"
    )
    doc = parse_document(text)
    assert doc.metadata["Status"] == "ready"
    assert doc.metadata["Inputs"] == "a, b, c"
    assert doc.meta_presence["Status"] == 1


def test_metadata_status_trailing_whitespace():
    doc = parse_document("> Status: ready   \n")
    # Parser keeps trailing-space stripped value already via .rstrip()
    assert doc.metadata["Status"] == "ready"


def test_metadata_inside_fence_is_ignored():
    text = "```\n> Status: draft\n```\n> Status: ready\n"
    doc = parse_document(text)
    assert doc.metadata["Status"] == "ready"


def test_sections_detected():
    text = "## 목표 (Objective)\n\n## 범위 (Scope)\n"
    doc = parse_document(text)
    titles = [t for _, t in doc.sections]
    assert "목표 (Objective)" in titles
    assert "범위 (Scope)" in titles


def test_sections_in_fence_ignored():
    text = "```\n## 목표 (Objective)\n```\n## 범위 (Scope)\n"
    doc = parse_document(text)
    titles = [t for _, t in doc.sections]
    assert titles == ["범위 (Scope)"]


def test_heading_with_closing_hashes_strips_atx_close():
    """'## 목표 (Objective) ##' yields title '목표 (Objective)' (ATX close stripped)."""
    text = "## 목표 (Objective) ##\n"
    doc = parse_document(text)
    assert doc.sections == [(1, "목표 (Objective)")]


def test_heading_with_trailing_hashes_no_space_kept():
    """A trailing run preceded by whitespace is stripped; bare '#title#' has no close."""
    text = "## 범위 (Scope)   ###\n"
    doc = parse_document(text)
    assert doc.sections == [(1, "범위 (Scope)")]


def test_indented_heading_up_to_three_spaces_detected():
    """CommonMark allows 0-3 leading spaces before an ATX heading."""
    text = "   ## 제약 (Constraints)\n"
    doc = parse_document(text)
    assert doc.sections == [(1, "제약 (Constraints)")]


def test_indented_heading_four_spaces_is_not_heading():
    """4+ leading spaces is an indented code block, not a heading."""
    text = "    ## 제약 (Constraints)\n"
    doc = parse_document(text)
    assert doc.sections == []


def test_unterminated_fence_surfaces_diagnostic():
    """A stray unterminated fence records a diagnostic on the ParsedDoc."""
    text = "## 목표 (Objective)\n\n```\ncode forever\n## 범위 (Scope)\n"
    doc = parse_document(text)
    codes = [code for _, code, _ in doc.diagnostics]
    assert "unterminated_fence" in codes


def test_placeholder_line_anchored_pass_for_inline_mention():
    text = "## 목표 (Objective)\n\n참고로 (이 작업이 달성하려는 것을 1-2문장으로 기술) 는 금지.\n"
    doc = parse_document(text, placeholders=["(이 작업이 달성하려는 것을 1-2문장으로 기술)"])
    assert doc.placeholder_hits == []


def test_placeholder_line_anchored_flags_solo_line():
    text = "(이 작업이 달성하려는 것을 1-2문장으로 기술)\n"
    doc = parse_document(text, placeholders=["(이 작업이 달성하려는 것을 1-2문장으로 기술)"])
    assert len(doc.placeholder_hits) == 1


def test_placeholder_with_bullet_prefix_flagged():
    text = "- (설계 시점에 해결되지 않은 질문이나 리스크)\n"
    doc = parse_document(text, placeholders=["(설계 시점에 해결되지 않은 질문이나 리스크)"])
    assert len(doc.placeholder_hits) == 1


def test_bom_and_crlf_combined():
    text = "\ufeff> Status: ready\r\n## 목표 (Objective)\r\n"
    doc = parse_document(text)
    assert doc.metadata["Status"] == "ready"
    assert doc.sections == [(2, "목표 (Objective)")]


@pytest.mark.parametrize("fence_pair", ["```", "~~~"])
def test_fenced_code_line_numbers_preserved(fence_pair):
    lines = [fence_pair, "> Status: draft", fence_pair, "> Status: ready"]
    doc = parse_document("\n".join(lines))
    # Only the outside Status should be captured and its line number is 4
    assert doc.metadata["Status"] == "ready"
    assert doc.meta_presence["Status"] == 4
