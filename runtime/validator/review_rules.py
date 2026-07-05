"""Review 문서 검증 규칙 (task-006, Phase D).

- review status enum 의 정본은 collab.md 의 기계판독 마커(`<!-- review-status-enum: ... -->`)다.
- 이 모듈은 IO 를 최소화하고, enum 로드/파일 읽기 실패는 ReviewConfigError 로 던져
  호출자(cli.py)가 환경 오류(exit 2)로 처리하게 한다. 문서 형식/enum 위반은 ValidationError(exit 1).
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from .rules import ValidationError

# '- **Field**: inline value' 형태의 필드 라인.
_FIELD_RE = re.compile(r"^-\s*\*\*([^*]+)\*\*\s*:\s*(.*)$")
# 하위 불릿 (들여쓰기 + 리스트 마커).
_SUBBULLET_RE = re.compile(r"^\s+(?:[-*+]\s+)?(.*)$")


class ReviewConfigError(Exception):
    """enum 마커/계약 파일 로드 실패 등 환경 오류 (exit 2)."""


def load_review_enum(repo_root: Path, schema: Dict[str, Any]) -> List[str]:
    """collab.md 의 `<!-- review-status-enum: a | b | c -->` 마커에서 enum 을 읽는다."""
    cfg = schema.get("review") or {}
    contract_rel = cfg.get("contract_path", "collab.md")
    prefix = cfg.get("enum_marker_prefix", "<!-- review-status-enum:")
    path = repo_root / contract_rel
    try:
        text = path.read_text(encoding="utf-8", errors="strict")
    except (OSError, UnicodeDecodeError) as e:
        raise ReviewConfigError(f"리뷰 계약 파일 읽기 실패: {path} ({e})") from e
    for line in text.splitlines():
        s = line.strip()
        if s.startswith(prefix):
            inner = s[len(prefix):]
            inner = inner.replace("-->", "").strip()
            values = [v.strip() for v in inner.split("|") if v.strip()]
            if values:
                return values
    raise ReviewConfigError(
        f"리뷰 계약 파일에 enum 마커('{prefix} ... -->')가 없습니다: {path}"
    )


def parse_review_fields(text: str) -> Dict[str, Dict[str, Any]]:
    """review 문서에서 필드 dict 를 추출한다.

    반환: field -> {"inline": str, "body": [str]} (최초 등장 우선).
    body 는 다음 '- **' 필드 라인 전까지의 하위 불릿 내용(마커 제거)이다.
    """
    fields: Dict[str, Dict[str, Any]] = {}
    lines = text.split("\n")
    current: Optional[str] = None
    for line in lines:
        m = _FIELD_RE.match(line)
        if m:
            key = m.group(1).strip()
            if key not in fields:
                fields[key] = {"inline": m.group(2).strip(), "body": []}
                current = key
            else:
                current = None  # 중복 필드는 첫 것만
            continue
        if current is not None:
            if line.strip() == "":
                continue
            sm = _SUBBULLET_RE.match(line)
            if sm and (line.startswith(" ") or line.startswith("\t")):
                fields[current]["body"].append(sm.group(1).strip())
            else:
                current = None
    return fields


def _field_filled(field: Dict[str, Any], placeholders: set) -> bool:
    inline = (field.get("inline") or "").strip()
    if inline and inline not in placeholders:
        return True
    for b in field.get("body", []):
        if b and b not in placeholders:
            return True
    return False


def check_review(text: str, schema: Dict[str, Any], enum: List[str]) -> List[ValidationError]:
    """단일 review 문서를 검증한다 (필수 필드 채움 + status enum)."""
    cfg = schema.get("review") or {}
    required = cfg.get("required_fields", [])
    status_field = cfg.get("status_field", "Review status")
    placeholders = set(cfg.get("field_placeholders", []))
    fields = parse_review_fields(text)
    errors: List[ValidationError] = []

    for f in required:
        if f not in fields:
            errors.append(ValidationError(code="review_field_missing", message=f"[리뷰 필드 누락] '{f}'"))
        elif not _field_filled(fields[f], placeholders):
            errors.append(ValidationError(code="review_field_empty", message=f"[리뷰 필드 빈값] '{f}'"))

    if status_field in fields:
        status_val = (fields[status_field].get("inline") or "").strip()
        if status_val and status_val not in enum:
            errors.append(
                ValidationError(
                    code="review_status_invalid",
                    message=f"[리뷰 상태 오류] '{status_val}' — 허용 값: {', '.join(enum)}",
                )
            )
    return errors


def review_status(text: str, schema: Dict[str, Any]) -> str:
    cfg = schema.get("review") or {}
    status_field = cfg.get("status_field", "Review status")
    fields = parse_review_fields(text)
    return (fields.get(status_field, {}).get("inline") or "").strip()


def latest_review(reviews_dir: Path, schema: Dict[str, Any]) -> Optional[Path]:
    """reviews/ 에서 NNN.md 중 숫자 최댓값 파일을 반환한다 (없으면 None)."""
    cfg = schema.get("review") or {}
    regex = re.compile(cfg.get("filename_regex", r"^[0-9]{3}\.md$"))
    if not reviews_dir.is_dir():
        return None
    candidates = []
    for p in reviews_dir.iterdir():
        if p.is_file() and regex.match(p.name):
            candidates.append((int(p.stem), p))
    if not candidates:
        return None
    candidates.sort(key=lambda t: t[0])
    return candidates[-1][1]
