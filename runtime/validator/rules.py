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


# 실행 계획 필드 라인: '- implement_model: `claude-opus-4-8`' / '- **routing_reason**: ...'
_EP_FIELD_RE = re.compile(
    r"^\s*-\s*(?:\*\*)?(implement_model|implement_effort|routing_reason)(?:\*\*)?\s*:\s*(.*)$"
)


def extract_execution_plan(doc: ParsedDoc, schema: Dict[str, Any]) -> Optional[Dict[str, str]]:
    """실행 계획 섹션의 필드 dict 를 반환한다. 섹션 자체가 없으면 None.

    섹션은 있으나 필드가 없으면 빈 dict — '부재(None)' 와 구분해
    호출자(라우터/규칙)가 각각 다른 오류를 낼 수 있게 한다.
    """
    ep_cfg = schema.get("execution_plan") or {}
    section = ep_cfg.get("section", "실행 계획 (Execution Plan)")
    titles = [title for _, title in doc.sections]
    if section not in titles:
        return None
    fields: Dict[str, str] = {}
    for line in _section_body_lines(doc, section):
        m = _EP_FIELD_RE.match(line)
        if m and m.group(1) not in fields:
            fields[m.group(1)] = m.group(2).strip().strip("`").strip()
    return fields


def check_execution_plan(
    doc: ParsedDoc,
    schema: Dict[str, Any],
    task_id: Optional[str] = None,
    whitelist: Optional[Dict[str, List[str]]] = None,
) -> List[ValidationError]:
    """실행 계획(Execution Plan) 규칙 — task-004 설계 주도 라우팅의 게이트.

    - 섹션 부재: legacy(task-001~003) 만 허용. task_id 파생 실패 시 예외 미적용(방어).
    - 섹션 존재: 필수 필드 채움 + (whitelist 제공 시) model/effort 화이트리스트 검사
      + 병렬화 표(필수 컬럼, 데이터 행 >= 1) 검사.
    whitelist 는 cli.py 가 profiles.json 에서 로드해 주입한다 (규칙 모듈은 IO 없음).
    """
    ep_cfg = schema.get("execution_plan")
    if not ep_cfg:
        return []
    section = ep_cfg["section"]
    plan = extract_execution_plan(doc, schema)

    if plan is None:
        legacy = set(ep_cfg.get("legacy_missing_allowed", []))
        if task_id and task_id in legacy:
            return []
        return [
            ValidationError(
                code="execution_plan_missing",
                message=(
                    f"[실행 계획 누락] '{section}' 섹션이 없습니다. "
                    "implement_model/implement_effort/routing_reason 과 병렬화 표를 지정하세요."
                ),
            )
        ]

    errors: List[ValidationError] = []
    placeholders = set(schema.get("placeholders", []))
    for field_name in ep_cfg.get("required_fields", []):
        value = (plan.get(field_name) or "").strip()
        if not value:
            errors.append(
                ValidationError(
                    code="execution_plan_field_missing",
                    message=f"[실행 계획] '{field_name}' 필드가 없거나 비어 있습니다.",
                )
            )
        elif value in placeholders:
            errors.append(
                ValidationError(
                    code="execution_plan_field_placeholder",
                    message=f"[실행 계획] '{field_name}' 값이 템플릿 placeholder입니다: '{value}'",
                )
            )

    if whitelist:
        allowed_models = whitelist.get("allowed_models") or []
        allowed_efforts = whitelist.get("allowed_efforts") or []
        model = (plan.get("implement_model") or "").strip()
        effort = (plan.get("implement_effort") or "").strip()
        if model and allowed_models and model not in allowed_models:
            errors.append(
                ValidationError(
                    code="execution_plan_model_not_allowed",
                    message=f"[실행 계획] implement_model '{model}' 은 화이트리스트에 없습니다: {allowed_models}",
                )
            )
        if effort and allowed_efforts and effort not in allowed_efforts:
            errors.append(
                ValidationError(
                    code="execution_plan_effort_not_allowed",
                    message=f"[실행 계획] implement_effort '{effort}' 은 화이트리스트에 없습니다: {allowed_efforts}",
                )
            )

    required_cols = ep_cfg.get("parallel_table_columns", [])
    header: Optional[List[str]] = None
    data_rows = 0
    for line in _section_body_lines(doc, section):
        if not _TABLE_ROW_RE.match(line):
            continue
        if _TABLE_SEPARATOR_RE.match(line.strip()):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None:
            header = cells
        elif any(cells):
            data_rows += 1
    if header is None:
        errors.append(
            ValidationError(
                code="execution_plan_table_missing",
                message=f"[실행 계획] 병렬화 표가 없습니다. 컬럼: {' / '.join(required_cols)}",
            )
        )
    else:
        missing_cols = [c for c in required_cols if c not in header]
        if missing_cols:
            errors.append(
                ValidationError(
                    code="execution_plan_table_missing",
                    message=f"[실행 계획] 병렬화 표에 필수 컬럼이 없습니다: {missing_cols}",
                )
            )
        elif data_rows < 1:
            errors.append(
                ValidationError(
                    code="execution_plan_table_empty",
                    message="[실행 계획] 병렬화 표에 데이터 행이 없습니다 (unit 을 1개 이상 기입하세요).",
                )
            )
    return errors


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
