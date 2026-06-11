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
    check_meta_fields,
    load_schema,
    parse_with_schema,
    run_all_rules,
)
from validator.parser import parse_document  # noqa: E402

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


def check_done(task_arg: str, repo_root: Optional[Path] = None) -> List[ValidationError]:
    """완료 산출물 계약을 검증하고 위반 목록을 반환한다.

    빈 리스트면 통과. 위반은 ValidationError 로 수집한다.
    IO/디코딩/환경 오류는 _DoneIOError 로 던져 호출자가 종료코드 2 로 처리한다.
    """
    repo_root = repo_root or _repo_root()
    _task_id, task_dir = _resolve_task(task_arg, repo_root)
    task_id = task_dir.name

    errors: List[ValidationError] = []

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
        schema = load_schema()
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

    return errors


def _run_check_done(task_arg: str, as_json: bool) -> int:
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
        errors = check_done(task_arg)
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


def main(argv: List[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    # --check-done 모드: 완료 산출물 계약 검증.
    if args.check_done is not None:
        return _run_check_done(args.check_done, args.json)

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

    output = _format_json(args.file, errors) if args.json else _format_human(args.file, errors)
    print(output)
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
