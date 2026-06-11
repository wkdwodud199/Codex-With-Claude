"""Markdown-aware parser for design documents.

Handles brittle input that bash/PowerShell regex cannot:
  - UTF-8 BOM stripping
  - CRLF / CR normalization
  - Fenced code block removal (``` and ~~~) while preserving line numbers
  - Blockquote metadata extraction (> Field: value)
  - Section header scanning with duplicate detection

The parser output is a pure data structure consumed by rules.py.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

BOM = "\ufeff"

_FENCE_RE = re.compile(r"^(\s*)(```+|~~~+)")
# CommonMark allows 0-3 leading spaces before an ATX heading; 4+ spaces is an
# indented code block. The trailing ATX close sequence (e.g. '## 목표 ##') is
# optional and stripped from the captured title by _strip_atx_close.
_HEADING_RE = re.compile(r"^ {0,3}(#+)\s+(.+?)\s*$")
_ATX_CLOSE_RE = re.compile(r"\s+#+\s*$")
_META_RE = re.compile(r"^>\s*([A-Za-z][A-Za-z0-9 _-]*?)\s*:\s*(.*)$")
_LIST_PREFIX_RE = re.compile(r"^\s*(?:[-*+]\s+|[0-9]+[.)]\s+)")


@dataclass
class ParsedDoc:
    """Parsed representation of a design document.

    All line-indexed collections use 1-based line numbers.
    Lines inside fenced code blocks are blanked (empty string) but preserved
    in position so downstream line references stay meaningful.
    """

    raw_text: str
    normalized_text: str
    lines: List[str]                          # fence-blanked, CRLF/BOM-normalized
    sections: List[Tuple[int, str]] = field(default_factory=list)   # (line_no, title)
    metadata: Dict[str, str] = field(default_factory=dict)          # key -> value, preserves first occurrence
    meta_presence: Dict[str, int] = field(default_factory=dict)     # key -> line_no where first seen
    placeholder_hits: List[Tuple[int, str]] = field(default_factory=list)  # (line_no, placeholder_text)
    fenced_ranges: List[Tuple[int, int]] = field(default_factory=list)     # 1-based inclusive ranges
    diagnostics: List[Tuple[int, str, str]] = field(default_factory=list)  # (line_no, code, message)


def normalize(text: str) -> str:
    """Strip UTF-8 BOM and normalize line endings to LF."""
    if text.startswith(BOM):
        text = text[len(BOM):]
    # CRLF -> LF, then lone CR -> LF
    return text.replace("\r\n", "\n").replace("\r", "\n")


def strip_fenced_blocks(
    lines: List[str],
) -> Tuple[List[str], List[Tuple[int, int]], List[Tuple[int, str, str]]]:
    """Blank out lines inside fenced code blocks.

    Returns (blanked_lines, fence_ranges, diagnostics).

    Fences may be ``` or ~~~, optionally indented, and the closing fence must
    match the opener marker family (` vs ~) and be **at least as long** as the
    opener (CommonMark §4.5). A shorter run of the same marker does NOT close
    the block, so '~~~~' is only closed by '~~~~' or longer, never by '~~~'.

    An unterminated fence (no matching closer before EOF) is a likely authoring
    mistake that would otherwise blank every following line and hide real
    required sections. Rather than silently swallow the rest of the document we
    record an `unterminated_fence` diagnostic so downstream rules can warn the
    user instead of emitting spurious 'section_missing' errors.
    """
    result: List[str] = []
    ranges: List[Tuple[int, int]] = []
    diagnostics: List[Tuple[int, str, str]] = []
    in_fence = False
    opener_marker = ""
    opener_len = 0
    opener_start = 0

    for idx, line in enumerate(lines, start=1):
        m = _FENCE_RE.match(line)
        if m:
            marker = m.group(2)
            if not in_fence:
                in_fence = True
                opener_marker = marker[0]  # first char: ` or ~
                opener_len = len(marker)
                opener_start = idx
                result.append("")
                continue
            # Potential closer: must be same family (` vs ~) and at least as
            # long as the opener (honors the documented ">= opener length" rule).
            if marker[0] == opener_marker and len(marker) >= opener_len:
                in_fence = False
                ranges.append((opener_start, idx))
                result.append("")
                continue
            result.append("")
            continue

        if in_fence:
            result.append("")
        else:
            result.append(line)

    # Unterminated fence: treat remainder as fenced and record partial range,
    # plus a diagnostic so callers can surface the problem to the user.
    if in_fence:
        ranges.append((opener_start, len(lines)))
        diagnostics.append(
            (
                opener_start,
                "unterminated_fence",
                "코드 펜스가 닫히지 않았습니다. 이후 줄이 모두 코드로 처리되어 "
                "필수 섹션 검사가 누락될 수 있습니다. 닫는 펜스(``` 또는 ~~~)를 추가하세요.",
            )
        )

    return result, ranges, diagnostics


def _strip_atx_close(title: str) -> str:
    """Drop an optional trailing ATX close sequence from a heading title.

    CommonMark allows '## 목표 (Objective) ##' as a heading; the trailing run
    of '#' is decorative and not part of the title. So this yields
    '목표 (Objective)'. A title that is only hashes (already consumed by the
    opener) is left untouched.
    """
    stripped = _ATX_CLOSE_RE.sub("", title)
    return stripped if stripped else title


def _find_sections(lines: List[str]) -> List[Tuple[int, str]]:
    out: List[Tuple[int, str]] = []
    for idx, line in enumerate(lines, start=1):
        m = _HEADING_RE.match(line)
        if m:
            title = _strip_atx_close(m.group(2).strip()).strip()
            out.append((idx, title))
    return out


def _extract_metadata(lines: List[str]) -> Tuple[Dict[str, str], Dict[str, int]]:
    meta: Dict[str, str] = {}
    positions: Dict[str, int] = {}
    for idx, line in enumerate(lines, start=1):
        m = _META_RE.match(line)
        if not m:
            continue
        key = m.group(1).strip()
        val = m.group(2).rstrip()
        if key in meta:
            continue  # keep first occurrence to mirror historic `head -1` behavior
        meta[key] = val
        positions[key] = idx
    return meta, positions


def _find_placeholders(lines: List[str], placeholders: List[str]) -> List[Tuple[int, str]]:
    """Return line-anchored placeholder hits.

    A line matches a placeholder when its content, after stripping leading
    list markers (`-`, `*`, `+`, `1.`, `1)`) and whitespace, exactly equals
    the placeholder string. Blockquote metadata lines are skipped; meta
    values are validated by rules.check_meta_fields separately.
    """
    hits: List[Tuple[int, str]] = []
    wanted = set(placeholders)
    for idx, line in enumerate(lines, start=1):
        if line.lstrip().startswith(">"):
            continue
        candidate = _LIST_PREFIX_RE.sub("", line, count=1).strip()
        if candidate in wanted:
            hits.append((idx, candidate))
    return hits


def parse_document(text: str, placeholders: Optional[List[str]] = None) -> ParsedDoc:
    """Parse markdown text into a ParsedDoc for validation.

    `placeholders` is optional at parse time; rules.py will call the parser
    with the schema's placeholder list so hits are populated.
    """
    normalized = normalize(text)
    raw_lines = normalized.split("\n")
    blanked, ranges, diagnostics = strip_fenced_blocks(raw_lines)
    sections = _find_sections(blanked)
    metadata, positions = _extract_metadata(blanked)
    placeholder_hits = _find_placeholders(blanked, placeholders or [])
    return ParsedDoc(
        raw_text=text,
        normalized_text=normalized,
        lines=blanked,
        sections=sections,
        metadata=metadata,
        meta_presence=positions,
        placeholder_hits=placeholder_hits,
        fenced_ranges=ranges,
        diagnostics=diagnostics,
    )
