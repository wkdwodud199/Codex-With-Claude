"""Validation rules applied to a ParsedDoc.

Each rule function returns a list of ValidationError. The set of rules is
driven by schema.json so bash/PowerShell/future-language runners share a
single source of truth.
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from .parser import ParsedDoc, parse_document

DEFAULT_SCHEMA_PATH = Path(__file__).resolve().parent / "schema.json"

# A markdown table separator row, e.g. '|---|---|' or '| :--- | ---: |'.
_TABLE_SEPARATOR_RE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")
# Any markdown table row (starts with a pipe, allowing leading whitespace).
_TABLE_ROW_RE = re.compile(r"^\s*\|")


@dataclass
class ValidationError:
    code: str
    message: str
    line: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def load_schema(path: Optional[Path] = None) -> Dict[str, Any]:
    """Load and return the validation schema as a dict."""
    schema_path = Path(path) if path else DEFAULT_SCHEMA_PATH
    with schema_path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_with_schema(text: str, schema: Dict[str, Any]) -> ParsedDoc:
    """Convenience: parse text using placeholders from the schema."""
    return parse_document(text, placeholders=schema.get("placeholders", []))


def check_sections(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []
    required = schema.get("required_sections", [])
    titles = [title for _, title in doc.sections]
    for section in required:
        count = titles.count(section)
        if count == 0:
            errors.append(ValidationError(code="section_missing", message=f"[섹션 누락] {section}"))
        elif count > 1:
            # Report each duplicate occurrence except the first
            dup_lines = [ln for ln, t in doc.sections if t == section][1:]
            for ln in dup_lines:
                errors.append(
                    ValidationError(
                        code="section_duplicate",
                        message=f"[섹션 중복] {section} (이 헤더가 여러 번 등장합니다)",
                        line=ln,
                    )
                )
    return errors


def check_status(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    allowed = schema.get("allowed_statuses_for_implementation", [])
    blocked = schema.get("blocked_statuses", {})
    status = doc.metadata.get("Status")
    line = doc.meta_presence.get("Status", 0)
    if status is None:
        return [
            ValidationError(
                code="status_missing",
                message="[상태 누락] '> Status:' 필드가 없습니다. design.md 상단에 추가하세요.",
            )
        ]
    value = status.strip()
    if value in allowed:
        return []
    if value in blocked:
        return [
            ValidationError(
                code="status_blocked",
                message=f"[상태 차단] Status: {value} — {blocked[value]}",
                line=line,
            )
        ]
    allowed_str = ", ".join(allowed)
    return [
        ValidationError(
            code="status_invalid",
            message=f"[상태 오류] Status: '{value}' — 허용 값: {allowed_str}",
            line=line,
        )
    ]


def check_meta_fields(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []
    placeholders = set(schema.get("placeholders", []))
    # Status is validated separately; only check auxiliary required fields here.
    fields = [f for f in schema.get("required_meta_fields", []) if f != "Status"]
    for field_name in fields:
        if field_name not in doc.metadata:
            errors.append(
                ValidationError(
                    code="meta_missing",
                    message=f"[필드 누락] '> {field_name}:' 필드가 없습니다. design.md 상단에 추가하세요.",
                )
            )
            continue
        value = doc.metadata[field_name].strip()
        line_no = doc.meta_presence.get(field_name, 0)
        if not value or value == "()":
            errors.append(
                ValidationError(
                    code="meta_empty",
                    message=f"[빈 필드] {field_name}가 비어 있습니다.",
                    line=line_no,
                )
            )
            continue
        if value in placeholders:
            errors.append(
                ValidationError(
                    code="meta_placeholder",
                    message=f"[placeholder 잔존] {field_name} 값이 템플릿 placeholder입니다: '{value}'",
                    line=line_no,
                )
            )
    return errors


def check_placeholders(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    return [
        ValidationError(
            code="placeholder_remaining",
            message=f"[placeholder 잔존] '{text}'",
            line=line,
        )
        for line, text in doc.placeholder_hits
    ]


def check_empty_content(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []
    seen_codes: set = set()
    for check in schema.get("empty_content_checks", []):
        pattern = re.compile(check["regex"])
        for idx, line in enumerate(doc.lines, start=1):
            if not line:
                continue
            if pattern.search(line):
                key = (check["id"], idx)
                if key in seen_codes:
                    continue
                seen_codes.add(key)
                errors.append(
                    ValidationError(
                        code="empty_content",
                        message=f"[빈 내용] {check['message']}",
                        line=idx,
                    )
                )
                # One report per check id is enough to surface the problem
                break
    return errors


def _section_body_lines(doc: ParsedDoc, section: str) -> List[str]:
    """Return the (1-based) body line range for a section as raw line strings.

    Body = every line after the section heading up to (but excluding) the next
    heading of any level. Lines inside fences are already blanked by the parser.
    """
    starts = [ln for ln, title in doc.sections if title == section]
    if not starts:
        return []
    start = starts[0]
    heading_lines = sorted(ln for ln, _ in doc.sections)
    end = len(doc.lines) + 1
    for ln in heading_lines:
        if ln > start:
            end = ln
            break
    # doc.lines is 0-based; section heading is at index start-1, body follows.
    return doc.lines[start:end - 1]


def _is_substantive_line(line: str, placeholders: set) -> bool:
    """Whether a section body line carries real, non-template content.

    Excludes: blank lines, markdown table separators, table rows whose data
    cells are all empty, the literal template-default 'create / modify / delete'
    row, and lines that are exactly a known placeholder string. A table header
    row counts as substantive ONLY if it has non-empty cells — but a header with
    no following data row is handled by the caller, which requires at least one
    *non-header* substantive row for table sections.
    """
    stripped = line.strip()
    if not stripped:
        return False
    if stripped in placeholders:
        return False
    if _TABLE_SEPARATOR_RE.match(stripped):
        return False
    if _TABLE_ROW_RE.match(line):
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        # All-empty cells (e.g. '| | |') or the template default row → not real.
        joined = " ".join(cells).lower()
        if not any(cells):
            return False
        if "create / modify / delete" in joined and all(
            c == "" or c == "create / modify / delete" for c in cells
        ):
            return False
    return True


def check_section_content(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    """Required sections that must contain at least one substantive content row.

    A section consisting only of a table header + separator (no data rows), or
    only of blank/separator/placeholder lines, is flagged. This generalizes the
    literal template-default checks so structurally-present-but-empty tables no
    longer slip through.
    """
    errors: List[ValidationError] = []
    placeholders = set(schema.get("placeholders", []))
    titles = [title for _, title in doc.sections]
    for check in schema.get("non_empty_sections", []):
        section = check["section"]
        if section not in titles:
            # Missing-section is reported by check_sections; don't double-report.
            continue
        body = _section_body_lines(doc, section)
        substantive = [ln for ln in body if _is_substantive_line(ln, placeholders)]
        # For table sections the first substantive row is the header; require a
        # second one (an actual data row). For prose/list sections any single
        # substantive line suffices.
        has_table = any(_TABLE_ROW_RE.match(ln) for ln in body)
        threshold = 2 if has_table else 1
        if len(substantive) < threshold:
            errors.append(
                ValidationError(
                    code="section_empty",
                    message=f"[빈 섹션] {check['message']}",
                )
            )
    return errors


def check_diagnostics(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    """Surface parser diagnostics (e.g. unterminated fences) as warnings.

    An unterminated fence blanks every following line, which would otherwise
    masquerade as a pile of 'section_missing' errors. Emitting the diagnostic
    explicitly tells the user the real cause so they aren't misled.
    """
    return [
        ValidationError(code=code, message=f"[경고] {message}", line=line)
        for line, code, message in doc.diagnostics
    ]


def run_all_rules(doc: ParsedDoc, schema: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []
    errors.extend(check_sections(doc, schema))
    errors.extend(check_status(doc, schema))
    errors.extend(check_meta_fields(doc, schema))
    errors.extend(check_placeholders(doc, schema))
    errors.extend(check_empty_content(doc, schema))
    errors.extend(check_section_content(doc, schema))
    errors.extend(check_diagnostics(doc, schema))
    return errors


def validate_text(text: str, schema: Optional[Dict[str, Any]] = None) -> List[ValidationError]:
    schema = schema or load_schema()
    doc = parse_with_schema(text, schema)
    return run_all_rules(doc, schema)
