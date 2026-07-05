"""Design document validator CLI.

Usage:
  python3 runtime/validator/cli.py <file>
  python3 runtime/validator/cli.py <file> --json
  python3 runtime/validator/cli.py <file> --schema path/to/schema.json
  python3 runtime/validator/cli.py --check-done <task-id-or-dir>
  python3 runtime/validator/cli.py --check-done <task-id-or-dir> --json

Exit codes:
  0 — validation passed
  1 — validation failed (errors reported)
  2 — file not found or other IO error
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Optional, Tuple

# Make `from validator...` resolvable when invoked directly as a script:
#   python3 /path/to/runtime/validator/cli.py <file>
_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:
    sys.path.insert(0, str(_HERE.parent))

from validator.rules import (  # noqa: E402  (sys.path mutated above)
    ValidationError,
    check_execution_plan,
    check_meta_fields,
    extract_execution_plan,
    load_schema,
    parse_with_schema,
    run_all_rules,
)
from validator.parser import parse_document  # noqa: E402
from validator.review_rules import (  # noqa: E402
    ReviewConfigError,
    check_review,
    latest_review,
    load_review_enum,
    review_status,
)

# Windows 에서 파이프된 stdout 은 locale 인코딩(cp1252 등)이 기본이라 한국어 출력이
# UnicodeEncodeError 로 crash 한다 (stderr 는 backslashreplace 라 살아남음 — CI 첫 실행에서 발견).
# 러너/CI/파이프 어디서든 UTF-8 로 강제한다 (PS 러너도 콘솔을 UTF-8 로 맞춘다).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# repo root = .../runtime/validator/cli.py -> parents[2]
_DEFAULT_REPO_ROOT = _HERE.parent.parent


def _repo_root() -> Path:
    """완료 검증 기준 repo root.

    기본값은 스크립트 위치 기준(parents[2])이지만, 테스트가 임시 repo 를
    주입할 수 있도록 CWC_REPO_ROOT 환경변수가 있으면 그것을 우선한다.
    프로덕션 호출(러너/CI)은 환경변수를 설정하지 않으므로 동작이 동일하다.
    """
    override = os.environ.get("CWC_REPO_ROOT")
    if override:
        return Path(override)
    return _DEFAULT_REPO_ROOT


# task-001 은 규약 이전 산출물이므로 명시 allowlist 로 완료 검증을 통과시킨다.
# 이 allowlist 는 다른 task 로 확장하지 않는다.
LEGACY_TASKS = {"task-001"}

# 실행 계획 규칙용 task id 파생 (^task-\d+$ 만 인정 — 파생 실패 시 legacy 예외 미적용).
_TASK_ID_RE = re.compile(r"^task-\d+$")


def _derive_task_id(path: Path, doc) -> Optional[str]:
    """design.md 경로(kb/tasks/<id>/design.md) 또는 문서 제목에서 task id 를 파생한다."""
    try:
        parts = Path(path).resolve().parts
    except OSError:
        parts = Path(path).parts
    for part in reversed(parts):
        if _TASK_ID_RE.match(part):
            return part
    if doc.sections:
        m = re.search(r"task-\d+", doc.sections[0][1])
        if m:
            return m.group(0)
    return None


class _ProfileIOError(Exception):
    """프로필(model-profiles.json) IO/JSON 오류 — 환경 오류(종료코드 2)."""


def _load_implement_whitelist(schema) -> Optional[dict]:
    """schema.execution_plan.profile_path 의 implement 화이트리스트를 로드한다.

    프로필 부재/해석 실패는 _ProfileIOError — 조용한 기본값으로 대체하지 않는다.
    """
    ep_cfg = schema.get("execution_plan") or {}
    rel = ep_cfg.get("profile_path")
    if not rel:
        return None
    profile_path = _repo_root() / rel
    try:
        data = json.loads(profile_path.read_text(encoding="utf-8", errors="strict"))
    except FileNotFoundError as e:
        raise _ProfileIOError(f"프로필 파일을 찾을 수 없습니다: {profile_path}") from e
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        raise _ProfileIOError(f"프로필 해석 실패: {profile_path} ({e})") from e
    impl = (data.get("phases") or {}).get("implement") or {}
    return {
        "allowed_models": impl.get("allowed_models") or [],
        "allowed_efforts": impl.get("allowed_efforts") or [],
    }


def _format_human(file: Path, errors: List[ValidationError]) -> str:
    if not errors:
        return "[OK] 설계 문서 검증 통과 (섹션, 상태, placeholder, 내용)"
    lines = [
        "",
        f"[FAIL] 설계 문서 검증 실패 ({len(errors)}건): {file}",
    ]
    for err in errors:
        suffix = f" (line {err.line})" if err.line else ""
        lines.append(f"  - {err.message}{suffix}")
    lines.append("")
    lines.append("설계 문서를 보완한 후 다시 실행하세요.")
    return "\n".join(lines)


def _format_json(file: Path, errors: List[ValidationError]) -> str:
    payload = {
        "ok": not errors,
        "file": str(file),
        "errors": [err.to_dict() for err in errors],
    }
    return json.dumps(payload, ensure_ascii=False)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate a Codex-authored design document.")
    # positional file 은 --check-done 모드에서는 생략 가능하도록 선택적(nargs="?")으로 둔다.
    # 기존 호출 문법(`cli.py <design.md>`)은 그대로 동작한다.
    parser.add_argument("file", type=Path, nargs="?", default=None, help="Path to design.md")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of text")
    parser.add_argument("--schema", type=Path, default=None, help="Override schema.json path")
    parser.add_argument(
        "--check-done",
        dest="check_done",
        metavar="TASK",
        default=None,
        help="완료 산출물 계약 검증 (task-id 또는 kb/tasks/<id> 경로)",
    )
    parser.add_argument(
        "--check-review",
        dest="check_review",
        metavar="REVIEW_MD",
        default=None,
        help="단일 리뷰 문서 검증 (reviews/NNN.md 경로)",
    )
    parser.add_argument(
        "--latest-review",
        dest="latest_review",
        metavar="TASK",
        default=None,
        help="task 의 최신 리뷰 파일/상태 조회 (task-id 또는 경로)",
    )
    parser.add_argument(
        "--check-review-target",
        dest="check_review_target",
        metavar="TASK",
        default=None,
        help="리뷰 게이트를 제외한 base 완료 검증 (재리뷰 순환 방지용)",
    )
    return parser


# ---------------------------------------------------------------------------
# --check-done 모드
# ---------------------------------------------------------------------------


class _DoneIOError(Exception):
    """완료 검증 중 IO/디코딩/환경 오류 (종료코드 2)."""


def _resolve_task(arg: str, repo_root: Path) -> Tuple[str, Path]:
    """'task-003' 또는 'kb/tasks/task-003' 입력을 (task_id, task_dir) 로 해석한다."""
    raw = Path(arg)
    # 경로 형태이면 마지막 구성요소를 task id 로 본다.
    task_id = raw.name if raw.name else arg
    if raw.is_absolute() or len(raw.parts) > 1:
        task_dir = raw if raw.is_absolute() else (repo_root / raw)
    else:
        task_dir = repo_root / "kb" / "tasks" / task_id
    return task_id, task_dir


def _read_utf8(path: Path) -> str:
    """UTF-8 로 읽되 실패 시 _DoneIOError 로 변환한다."""
    try:
        return path.read_text(encoding="utf-8", errors="strict")
    except FileNotFoundError as e:
        raise _DoneIOError(f"파일을 찾을 수 없습니다: {path}") from e
    except UnicodeDecodeError as e:
        raise _DoneIOError(f"UTF-8 디코딩 실패: {path} ({e})") from e
    except OSError as e:
        raise _DoneIOError(f"파일 읽기 실패: {path} ({e})") from e


def _template_with_id(repo_root: Path, task_id: str) -> str:
    """templates/implementation-notes.md 의 'task-<NNN>' 를 task_id 로 치환한 본문.

    템플릿이 없거나 읽을 수 없으면 환경 오류(_DoneIOError)로 보고한다.
    """
    tmpl_path = repo_root / "templates" / "implementation-notes.md"
    if not tmpl_path.exists():
        raise _DoneIOError(f"템플릿을 찾을 수 없습니다: {tmpl_path}")
    text = _read_utf8(tmpl_path)
    return text.replace("task-<NNN>", task_id)


def _review_gate_errors(task_dir: Path, repo_root: Path, schema: dict) -> List[ValidationError]:
    """approved-done 게이트 (task-006). reviews/ 가 존재할 때만 적용한다.

    - reviews/ 없음 → 빈 리스트 (기존 done-gate 동작 유지, 하위호환).
    - reviews/ 있는데 NNN.md 없음 → review_missing (exit 1).
    - 최신 리뷰가 형식 위반 → 그 오류 (exit 1).
    - 최신 리뷰 status != approved → review_not_approved (exit 1).
    - 리뷰 파일 IO / enum 마커 로드 실패 → _DoneIOError (exit 2).
    """
    cfg = schema.get("review") or {}
    reviews_dir = task_dir / cfg.get("review_dir", "reviews")
    if not reviews_dir.is_dir():
        return []
    latest = latest_review(reviews_dir, schema)
    if latest is None:
        return [
            ValidationError(
                code="review_missing",
                message=f"[리뷰 없음] {reviews_dir} 가 있으나 NNN.md 리뷰가 없습니다 (approved-done 게이트).",
            )
        ]
    text = _read_utf8(latest)  # IO/decode 실패 → _DoneIOError(2)
    try:
        enum = load_review_enum(repo_root, schema)
    except ReviewConfigError as e:
        raise _DoneIOError(str(e)) from e
    review_errors = check_review(text, schema, enum)
    if review_errors:
        return review_errors
    status = review_status(text, schema)
    approved = cfg.get("approved_status", "approved")
    if status != approved:
        return [
            ValidationError(
                code="review_not_approved",
                message=f"[리뷰 미승인] 최신 리뷰({latest.name}) status='{status}' — '{approved}' 이어야 완료입니다.",
            )
        ]
    return []


def check_done(
    task_arg: str, repo_root: Optional[Path] = None, include_review: bool = True
) -> List[ValidationError]:
    """완료 산출물 계약을 검증하고 위반 목록을 반환한다.

    빈 리스트면 통과. 위반은 ValidationError 로 수집한다.
    IO/디코딩/환경 오류는 _DoneIOError 로 던져 호출자가 종료코드 2 로 처리한다.
    include_review=False 면 approved-done 리뷰 게이트를 건너뛴다(재리뷰 순환 방지용 base 검증).
    """
    repo_root = repo_root or _repo_root()
    _task_id, task_dir = _resolve_task(task_arg, repo_root)
    task_id = task_dir.name

    errors: List[ValidationError] = []
    schema = load_schema()
    # done-gate 강화 (2026-07-05 codex 리뷰 반영): 상태값·manifest 를 schema 로 게이트.
    done_gate = schema.get("done_gate", {})
    notes_allowed = done_gate.get("notes_allowed_statuses", ["done"])
    summary_allowed = done_gate.get("summary_allowed_statuses", ["done"])

    # 1) implementation-notes.md 검증
    notes_path = task_dir / "implementation-notes.md"
    if not notes_path.exists():
        errors.append(
            ValidationError(
                code="impl_notes_missing",
                message=f"[구현 노트 누락] {notes_path} 가 없습니다.",
            )
        )
    else:
        notes_text = _read_utf8(notes_path)  # IO/decode 실패 → 종료코드 2
        template_text = _template_with_id(repo_root, task_id)
        if notes_text == template_text:
            errors.append(
                ValidationError(
                    code="impl_notes_template",
                    message="[구현 노트 미작성] implementation-notes.md 가 템플릿과 동일합니다.",
                )
            )
        notes_doc = parse_document(notes_text)
        notes_status = (notes_doc.metadata.get("Status") or "").strip()
        if not notes_status:
            errors.append(
                ValidationError(
                    code="impl_notes_status_missing",
                    message="[구현 노트 상태 누락] '> Status:' 필드가 없습니다.",
                )
            )
        elif notes_status == "draft":
            errors.append(
                ValidationError(
                    code="impl_notes_status_draft",
                    message="[구현 노트 미완료] Status 가 'draft' 입니다. 완료 시 갱신하세요.",
                )
            )
        elif notes_status not in notes_allowed:
            # in-progress 포함 임의 상태값 차단 — 완료 주장은 'done' 만 인정한다.
            errors.append(
                ValidationError(
                    code="impl_notes_status_not_done",
                    message=(
                        f"[구현 노트 미완료] Status 가 '{notes_status}' 입니다 — "
                        f"완료 기준은 {', '.join(notes_allowed)} 입니다 (AGENT.md 상태 모델)."
                    ),
                )
            )

    # 2) artifact summary 검증
    summary_path = repo_root / "kb" / "artifacts" / f"{task_id}-summary.md"
    if not summary_path.exists():
        errors.append(
            ValidationError(
                code="summary_missing",
                message=f"[산출물 요약 누락] {summary_path} 가 없습니다.",
            )
        )
    else:
        summary_text = _read_utf8(summary_path)  # IO/decode 실패 → 종료코드 2
        summary_doc = parse_with_schema(summary_text, schema)
        # Inputs/Outputs/Next step 비어있지 않음 → check_meta_fields 재사용
        meta_errors = check_meta_fields(summary_doc, schema)
        errors.extend(meta_errors)
        # Status 는 check_meta_fields 에서 제외되므로 명시적으로 확인한다.
        summary_status = (summary_doc.metadata.get("Status") or "").strip()
        if not summary_status:
            errors.append(
                ValidationError(
                    code="summary_status_empty",
                    message="[빈 필드] 산출물 요약의 Status 가 비어 있습니다.",
                )
            )
        elif summary_status not in summary_allowed:
            errors.append(
                ValidationError(
                    code="summary_status_not_done",
                    message=(
                        f"[산출물 요약 상태 오류] Status 가 '{summary_status}' 입니다 — "
                        f"완료 신호는 {', '.join(summary_allowed)} 입니다 (status board 집계 기준)."
                    ),
                )
            )

    # 3) manifest.md 검증 (2026-07-05 codex 리뷰 반영)
    # fast-path 로드 세트(QUICKREF + manifest + design)의 구성 요소이므로,
    # 완료 시점에는 존재해야 하고 필수 필드가 템플릿 placeholder 가 아니어야 한다.
    manifest_path = task_dir / "manifest.md"
    if not manifest_path.exists():
        errors.append(
            ValidationError(
                code="manifest_missing",
                message=f"[manifest 누락] {manifest_path} 가 없습니다 (기본 로드 세트 구성 요소).",
            )
        )
    else:
        manifest_text = _read_utf8(manifest_path)  # IO/decode 실패 → 종료코드 2
        manifest_placeholders = set(done_gate.get("manifest_placeholders", []))
        fields: dict = {}
        for line in manifest_text.splitlines():
            m = re.match(r"^-\s*\*\*([a-z_]+)\*\*\s*:\s*(.*)$", line)
            if m and m.group(1) not in fields:
                fields[m.group(1)] = m.group(2).strip()
        for field_name in done_gate.get("manifest_required_fields", []):
            value = fields.get(field_name, "")
            if not value:
                errors.append(
                    ValidationError(
                        code="manifest_field_empty",
                        message=f"[manifest 미작성] '{field_name}' 필드가 없거나 비어 있습니다.",
                    )
                )
            elif value in manifest_placeholders:
                errors.append(
                    ValidationError(
                        code="manifest_field_placeholder",
                        message=f"[manifest 미작성] '{field_name}' 값이 템플릿 placeholder입니다: '{value}'",
                    )
                )

    # 4) approved-done 리뷰 게이트 (task-006) — reviews/ 존재 시에만, base 검증(target)에서는 제외.
    if include_review:
        errors.extend(_review_gate_errors(task_dir, repo_root, schema))

    return errors


def _run_check_done(task_arg: str, as_json: bool, include_review: bool = True) -> int:
    # legacy allowlist: 파일 상태와 무관하게 통과 — IO 검사보다 먼저 판정한다.
    # (templates/ 없는 sparse checkout 환경에서도 legacy task 는 항상 통과해야 한다.)
    try:
        _task_id, task_dir = _resolve_task(task_arg, _repo_root())
    except _DoneIOError as e:
        msg = f"[ERROR] {e}"
        if as_json:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "mode": "check-done",
                        "task": task_arg,
                        "errors": [{"code": "io_error", "message": msg, "line": 0}],
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(msg, file=sys.stderr)
        return 2

    task_id = task_dir.name
    if task_id in LEGACY_TASKS:
        if as_json:
            print(
                json.dumps(
                    {"ok": True, "mode": "check-done", "task": task_id, "legacy": True, "errors": []},
                    ensure_ascii=False,
                )
            )
        else:
            print("[OK] 완료 검증 통과 (legacy)")
        return 0

    try:
        errors = check_done(task_arg, include_review=include_review)
    except _DoneIOError as e:
        msg = f"[ERROR] {e}"
        if as_json:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "mode": "check-done",
                        "task": task_arg,
                        "errors": [{"code": "io_error", "message": msg, "line": 0}],
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(msg, file=sys.stderr)
        return 2

    if as_json:
        print(
            json.dumps(
                {
                    "ok": not errors,
                    "mode": "check-done",
                    "task": task_id,
                    "errors": [err.to_dict() for err in errors],
                },
                ensure_ascii=False,
            )
        )
    else:
        if not errors:
            print("[OK] 완료 검증 통과")
        else:
            print("")
            print(f"[FAIL] 완료 검증 실패 ({len(errors)}건): {task_id}")
            for err in errors:
                print(f"  - {err.message}")
            print("")
            print("완료 산출물을 보완한 후 다시 실행하세요.")
    return 0 if not errors else 1


def _run_check_review(review_arg: str, as_json: bool) -> int:
    """단일 리뷰 문서(reviews/NNN.md)를 검증한다."""
    path = Path(review_arg)
    if not path.is_absolute():
        path = _repo_root() / path
    schema = load_schema()
    try:
        text = _read_utf8(path)
        enum = load_review_enum(_repo_root(), schema)
    except _DoneIOError as e:
        _emit_mode_error("check-review", review_arg, str(e), as_json)
        return 2
    except ReviewConfigError as e:
        _emit_mode_error("check-review", review_arg, f"[ERROR] {e}", as_json)
        return 2
    errors = check_review(text, schema, enum)
    if as_json:
        print(json.dumps(
            {"ok": not errors, "mode": "check-review", "file": str(path),
             "errors": [e.to_dict() for e in errors]}, ensure_ascii=False))
    else:
        if not errors:
            print(f"[OK] 리뷰 검증 통과: {path.name}")
        else:
            print(f"\n[FAIL] 리뷰 검증 실패 ({len(errors)}건): {path}")
            for e in errors:
                print(f"  - {e.message}")
    return 0 if not errors else 1


def _run_latest_review(task_arg: str, as_json: bool) -> int:
    """task 의 최신 리뷰 파일과 status 를 조회·검증한다."""
    schema = load_schema()
    try:
        _tid, task_dir = _resolve_task(task_arg, _repo_root())
    except _DoneIOError as e:
        _emit_mode_error("latest-review", task_arg, str(e), as_json)
        return 2
    reviews_dir = task_dir / (schema.get("review") or {}).get("review_dir", "reviews")
    latest = latest_review(reviews_dir, schema)
    if latest is None:
        msg = f"[FAIL] 최신 리뷰가 없습니다: {reviews_dir}"
        if as_json:
            print(json.dumps({"ok": False, "mode": "latest-review", "task": task_dir.name,
                              "errors": [{"code": "review_missing", "message": msg, "line": 0}]},
                             ensure_ascii=False))
        else:
            print(msg)
        return 1
    try:
        text = _read_utf8(latest)
        enum = load_review_enum(_repo_root(), schema)
    except _DoneIOError as e:
        _emit_mode_error("latest-review", task_arg, str(e), as_json)
        return 2
    except ReviewConfigError as e:
        _emit_mode_error("latest-review", task_arg, f"[ERROR] {e}", as_json)
        return 2
    errors = check_review(text, schema, enum)
    status = review_status(text, schema)
    if as_json:
        print(json.dumps(
            {"ok": not errors, "mode": "latest-review", "task": task_dir.name,
             "latest": latest.name, "status": status,
             "errors": [e.to_dict() for e in errors]}, ensure_ascii=False))
    else:
        if not errors:
            print(f"[OK] 최신 리뷰: {latest.name} (status={status})")
        else:
            print(f"\n[FAIL] 최신 리뷰({latest.name}) 형식 오류 ({len(errors)}건)")
            for e in errors:
                print(f"  - {e.message}")
    return 0 if not errors else 1


def _emit_mode_error(mode: str, target: str, msg: str, as_json: bool) -> None:
    if not msg.startswith("[ERROR]"):
        msg = f"[ERROR] {msg}"
    if as_json:
        print(json.dumps(
            {"ok": False, "mode": mode, "task": target,
             "errors": [{"code": "io_error", "message": msg, "line": 0}]}, ensure_ascii=False))
    else:
        print(msg, file=sys.stderr)


def main(argv: List[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    # --check-done 모드: 완료 산출물 계약 검증 (approved-done 리뷰 게이트 포함).
    if args.check_done is not None:
        return _run_check_done(args.check_done, args.json)

    # --check-review-target: 리뷰 게이트를 제외한 base 완료 검증 (재리뷰 순환 방지).
    if args.check_review_target is not None:
        return _run_check_done(args.check_review_target, args.json, include_review=False)

    # --check-review: 단일 리뷰 문서 검증.
    if args.check_review is not None:
        return _run_check_review(args.check_review, args.json)

    # --latest-review: 최신 리뷰 조회.
    if args.latest_review is not None:
        return _run_latest_review(args.latest_review, args.json)

    # 기존 design.md 검증 경로 (100% 보존).
    if args.file is None:
        # 위치 인자도 --check-done 도 없는 호출은 사용법 오류.
        build_parser().error("file 인자 또는 --check-done 중 하나가 필요합니다.")

    if not args.file.exists():
        msg = f"[ERROR] 파일을 찾을 수 없습니다: {args.file}"
        if args.json:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "file": str(args.file),
                        "errors": [{"code": "file_not_found", "message": msg, "line": 0}],
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(msg, file=sys.stderr)
        return 2

    try:
        text = args.file.read_text(encoding="utf-8", errors="strict")
    except UnicodeDecodeError as e:
        msg = f"[ERROR] UTF-8 디코딩 실패: {args.file} ({e})"
        if args.json:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "file": str(args.file),
                        "errors": [{"code": "decode_error", "message": msg, "line": 0}],
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(msg, file=sys.stderr)
        return 2

    schema = load_schema(args.schema)
    doc = parse_with_schema(text, schema)
    errors = run_all_rules(doc, schema)

    # 실행 계획(Execution Plan) 규칙 — task-004 설계 주도 라우팅 게이트.
    # 화이트리스트(프로필)는 섹션이 실제로 있을 때만 로드한다. 프로필 IO/JSON
    # 오류는 검증 실패(1)가 아니라 환경 오류(2)다 — 조용한 기본값 금지.
    if schema.get("execution_plan"):
        whitelist = None
        if extract_execution_plan(doc, schema) is not None:
            try:
                whitelist = _load_implement_whitelist(schema)
            except _ProfileIOError as e:
                msg = f"[ERROR] {e}"
                if args.json:
                    print(
                        json.dumps(
                            {
                                "ok": False,
                                "file": str(args.file),
                                "errors": [{"code": "profile_error", "message": msg, "line": 0}],
                            },
                            ensure_ascii=False,
                        )
                    )
                else:
                    print(msg, file=sys.stderr)
                return 2
        errors.extend(
            check_execution_plan(
                doc, schema, task_id=_derive_task_id(args.file, doc), whitelist=whitelist
            )
        )

    output = _format_json(args.file, errors) if args.json else _format_human(args.file, errors)
    print(output)
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
