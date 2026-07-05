#!/usr/bin/env python3
"""render-prompt.py — 프로필 조회 · implement 라우팅 · CLI 버전 preflight · 프롬프트 렌더.

`runtime/config/model-profiles.json`(모델/effort SSOT) 과 `templates/prompts/*.md`
(프롬프트 SSOT) 의 단일 소비자다. shell/PowerShell 러너가 JSON 파싱이나
프롬프트 사본을 갖지 않도록, 필요한 값을 하나씩 stdout 으로 출력한다.

서브커맨드:
  profile           --phase <design|implement|review> --cli <codex|claude> --field <이름>
                    필드: model | effort | fallback_model | min_cli_version
                          | default_model | default_effort (implement 전용)
  route-implement   --design-file <path> [--task-id <id>] --field <model|effort|route|reason>
                    실행 계획이 있으면 그 값을(화이트리스트 검사 후), 없으면 legacy 에 한해
                    기본값(route=default)을 반환한다. 비legacy 에서 실행 계획 부재는 실패.
  check-cli-version --phase <p> --cli <c> --version-output "<CLI --version 출력>"
  render            --phase <design|implement> --task-id <id> --design-file <path>
                    [--task-desc <s>] [--impl-notes <path>] [--project-root <path>]
                    [--model <m>] [--effort <e>]

종료 코드 (validator cli.py 와 동일 의미):
  0 = 성공 / 1 = 정책·검증 실패 (화이트리스트 위반, 버전 미달, 비legacy 실행 계획 부재,
  잘못된 phase/field, 렌더 토큰 잔존) / 2 = 환경 오류 (파일 부재, JSON 해석 실패, IO)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from validator.parser import parse_document  # noqa: E402
from validator.rules import extract_execution_plan, load_schema  # noqa: E402

_TASK_ID_RE = re.compile(r"^task-\d+$")
_VERSION_RE = re.compile(r"\d+(?:\.\d+)+")
_LEFTOVER_TOKEN_RE = re.compile(r"\{\{[A-Z_]+\}\}")


def _fail(code: int, message: str) -> "SystemExit":
    print(f"[ERROR] {message}", file=sys.stderr)
    return SystemExit(code)


def _repo_root(cli_root: Optional[str]) -> Path:
    if cli_root:
        return Path(cli_root)
    env_root = os.environ.get("CWC_REPO_ROOT")
    if env_root:
        return Path(env_root)
    return _HERE.parent


def _read_text(path: Path, what: str) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="strict")
    except FileNotFoundError:
        raise _fail(2, f"{what} 파일을 찾을 수 없습니다: {path}")
    except (OSError, UnicodeDecodeError) as e:
        raise _fail(2, f"{what} 읽기 실패: {path} ({e})")


def _load_profiles(root: Path) -> Dict[str, Any]:
    schema = load_schema()
    rel = (schema.get("execution_plan") or {}).get("profile_path", "runtime/config/model-profiles.json")
    path = root / rel
    text = _read_text(path, "프로필")
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise _fail(2, f"프로필 JSON 해석 실패: {path} ({e})")


def _profile_entry(profiles: Dict[str, Any], phase: str, cli: str) -> Dict[str, Any]:
    node = (profiles.get("phases") or {}).get(phase)
    if not isinstance(node, dict):
        raise _fail(1, f"프로필에 phase '{phase}' 가 없습니다.")
    if phase == "implement":
        return node
    key = "claude_cross_check" if (phase == "design" and cli == "claude") else cli
    entry = node.get(key)
    if not isinstance(entry, dict):
        raise _fail(1, f"프로필 phases.{phase} 에 '{key}' 항목이 없습니다.")
    return entry


def _entry_field(entry: Dict[str, Any], phase: str, field: str) -> str:
    if phase == "implement":
        default = entry.get("default") or {}
        mapping = {
            "default_model": default.get("model"),
            "default_effort": default.get("effort"),
            "min_cli_version": entry.get("min_cli_version"),
            "routing": entry.get("routing"),
        }
        if field in ("model", "effort"):
            raise _fail(1, "implement 는 design-directed 라우팅입니다 — route-implement 서브커맨드를 사용하세요.")
    else:
        mapping = {
            "model": entry.get("model"),
            # codex 는 reasoning_effort, claude 는 effort 키를 쓴다 — 소비자에게는 'effort' 로 통일.
            "effort": entry.get("effort") or entry.get("reasoning_effort"),
            "fallback_model": entry.get("fallback_model"),
            "min_cli_version": entry.get("min_cli_version"),
        }
    value = mapping.get(field)
    if not value:
        raise _fail(1, f"프로필 phase '{phase}' 에 필드 '{field}' 가 없습니다.")
    return str(value)


def _derive_task_id(design_file: Optional[str], doc) -> Optional[str]:
    if design_file:
        for part in reversed(Path(design_file).resolve().parts):
            if _TASK_ID_RE.match(part):
                return part
    if doc is not None and doc.sections:
        m = re.search(r"task-\d+", doc.sections[0][1])
        if m:
            return m.group(0)
    return None


def cmd_profile(args: argparse.Namespace) -> int:
    profiles = _load_profiles(_repo_root(args.root))
    entry = _profile_entry(profiles, args.phase, args.cli)
    print(_entry_field(entry, args.phase, args.field))
    return 0


def cmd_route_implement(args: argparse.Namespace) -> int:
    root = _repo_root(args.root)
    schema = load_schema()
    profiles = _load_profiles(root)
    impl = _profile_entry(profiles, "implement", "claude")

    text = _read_text(Path(args.design_file), "설계")
    doc = parse_document(text)
    plan = extract_execution_plan(doc, schema)

    if plan is not None:
        model = (plan.get("implement_model") or "").strip()
        effort = (plan.get("implement_effort") or "").strip()
        reason = (plan.get("routing_reason") or "").strip()
        if not model or not effort:
            raise _fail(1, "실행 계획에 implement_model / implement_effort 가 비어 있습니다.")
        allowed_models = impl.get("allowed_models") or []
        allowed_efforts = impl.get("allowed_efforts") or []
        if allowed_models and model not in allowed_models:
            raise _fail(1, f"implement_model '{model}' 은 화이트리스트에 없습니다: {allowed_models}")
        if allowed_efforts and effort not in allowed_efforts:
            raise _fail(1, f"implement_effort '{effort}' 은 화이트리스트에 없습니다: {allowed_efforts}")
        route = "execution-plan"
    else:
        task_id = args.task_id or _derive_task_id(args.design_file, doc)
        legacy = set((schema.get("execution_plan") or {}).get("legacy_missing_allowed", []))
        if not task_id or task_id not in legacy:
            raise _fail(1, "실행 계획 섹션이 없습니다 (비legacy task). validator 게이트를 먼저 통과시키세요.")
        default = impl.get("default") or {}
        model = default.get("model") or ""
        effort = default.get("effort") or ""
        if not model or not effort:
            raise _fail(2, "프로필 implement.default 가 비어 있습니다.")
        route = "default"
        reason = f"실행 계획 부재 (legacy {task_id}) — 프로필 기본값 사용"

    value = {"model": model, "effort": effort, "route": route, "reason": reason}[args.field]
    print(value)
    return 0


def _version_tuple(text: str) -> Optional[tuple]:
    m = _VERSION_RE.search(text or "")
    if not m:
        return None
    return tuple(int(p) for p in m.group(0).split("."))


def cmd_check_cli_version(args: argparse.Namespace) -> int:
    profiles = _load_profiles(_repo_root(args.root))
    entry = _profile_entry(profiles, args.phase, args.cli)
    min_ver = _entry_field(entry, args.phase, "min_cli_version")
    minimum = _version_tuple(min_ver)
    actual = _version_tuple(args.version_output)
    if actual is None:
        raise _fail(1, f"{args.cli} CLI 버전 문자열을 해석할 수 없습니다: '{args.version_output.strip()}'")
    width = max(len(actual), len(minimum or ()))
    pad = lambda t: t + (0,) * (width - len(t))  # noqa: E731
    if minimum and pad(actual) < pad(minimum):
        raise _fail(1, f"{args.cli} CLI 버전 미달: {'.'.join(map(str, actual))} < 최소 {min_ver}")
    print(".".join(map(str, actual)))
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    root = _repo_root(args.root)
    template_path = root / "templates" / "prompts" / f"{args.phase}.md"
    template = _read_text(template_path, "프롬프트 템플릿")

    schema = load_schema()
    profiles = _load_profiles(root)
    impl = (profiles.get("phases") or {}).get("implement") or {}
    ep_cfg = schema.get("execution_plan") or {}

    required_sections = "\n".join(f"  - {s}" for s in schema.get("required_sections", []))
    subs = {
        "TASK_ID": args.task_id,
        "TASK_DESC": args.task_desc or "",
        "DESIGN_FILE": args.design_file,
        "IMPL_NOTES": args.impl_notes or "",
        "PROJECT_ROOT": args.project_root or str(root),
        "REQUIRED_SECTIONS": required_sections,
        "EXECUTION_PLAN_SECTION": ep_cfg.get("section", "실행 계획 (Execution Plan)"),
        "EXECUTION_PLAN_FIELDS": ", ".join(ep_cfg.get("required_fields", [])),
        "EXECUTION_PLAN_COLUMNS": " / ".join(ep_cfg.get("parallel_table_columns", [])),
        "ALLOWED_MODELS": " | ".join(impl.get("allowed_models") or []),
        "ALLOWED_EFFORTS": " | ".join(impl.get("allowed_efforts") or []),
        "MODEL": args.model or "",
        "EFFORT": args.effort or "",
    }
    rendered = template
    for key, value in subs.items():
        rendered = rendered.replace("{{" + key + "}}", value)
    leftover = _LEFTOVER_TOKEN_RE.search(rendered)
    if leftover:
        raise _fail(1, f"프롬프트 렌더 후 치환되지 않은 토큰이 남았습니다: {leftover.group(0)}")
    print(rendered, end="")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="프로필/프롬프트/라우팅/버전 preflight 헬퍼 (task-004)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("profile", help="프로필 필드 1개 출력")
    p.add_argument("--phase", required=True, choices=["design", "implement", "review"])
    p.add_argument("--cli", required=True, choices=["codex", "claude"])
    p.add_argument("--field", required=True)
    p.add_argument("--root", default=None)
    p.set_defaults(func=cmd_profile)

    r = sub.add_parser("route-implement", help="실행 계획 기반 implement 라우팅 값 출력")
    r.add_argument("--design-file", required=True)
    r.add_argument("--task-id", default=None)
    r.add_argument("--field", required=True, choices=["model", "effort", "route", "reason"])
    r.add_argument("--root", default=None)
    r.set_defaults(func=cmd_route_implement)

    v = sub.add_parser("check-cli-version", help="CLI 버전 preflight (최소 버전 비교)")
    v.add_argument("--phase", required=True, choices=["design", "implement", "review"])
    v.add_argument("--cli", required=True, choices=["codex", "claude"])
    v.add_argument("--version-output", required=True)
    v.add_argument("--root", default=None)
    v.set_defaults(func=cmd_check_cli_version)

    d = sub.add_parser("render", help="프롬프트 템플릿 렌더")
    d.add_argument("--phase", required=True, choices=["design", "implement"])
    d.add_argument("--task-id", required=True)
    d.add_argument("--design-file", required=True)
    d.add_argument("--task-desc", default=None)
    d.add_argument("--impl-notes", default=None)
    d.add_argument("--project-root", default=None)
    d.add_argument("--model", default=None)
    d.add_argument("--effort", default=None)
    d.add_argument("--root", default=None)
    d.set_defaults(func=cmd_render)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
