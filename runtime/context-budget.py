#!/usr/bin/env python3
"""context-budget.py — task 진입 기본 로드 세트의 컨텍스트 예산(바이트/토큰 추정) 경고 리포트.

Phase A 최소 컨텍스트 관리 도구. **경고 전용(warning-only)**: 측정 실행 경로는
파일 누락이나 예산 초과와 무관하게 항상 종료코드 0 을 반환한다(구현/CI 비차단).
의존성 없음(Python 3.8+, stdlib).

사용법:
    python3 runtime/context-budget.py <task-id> [--baseline]

신규 기본 로드 세트 : QUICKREF.md + kb/tasks/<id>/manifest.md + kb/tasks/<id>/design.md
baseline           : AGENT.md + CLAUDE.md + kb/tasks/<id>/design.md
핵심 출력          : 신규 세트 총 바이트 < baseline 총 바이트 인지(감산적 효과)와 차이.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
TOKEN_DIVISOR = 4  # 대략 토큰 추정 = bytes / 4

Row = Tuple[str, int, bool]  # (표시 경로, 바이트, 존재여부)


def _rel(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def _tok(num_bytes: int) -> int:
    return num_bytes // TOKEN_DIVISOR


def measure(paths: List[Path], root: Path) -> Tuple[List[Row], int, List[str]]:
    """경로별 바이트 측정. 반환: (행 목록, 총합, 누락 경로 목록). 누락은 0바이트로 계산."""
    rows: List[Row] = []
    total = 0
    missing: List[str] = []
    for path in paths:
        rel = _rel(path, root)
        if path.is_file():
            size = path.stat().st_size
            rows.append((rel, size, True))
            total += size
        else:
            rows.append((rel, 0, False))
            missing.append(rel)
    return rows, total, missing


def compute(task_id: str, root: Path = REPO_ROOT) -> Dict[str, object]:
    """신규 세트와 baseline 의 측정 결과를 구조화해 반환(리포트/테스트 공용)."""
    root = Path(root)
    design = root / "kb" / "tasks" / task_id / "design.md"
    manifest = root / "kb" / "tasks" / task_id / "manifest.md"
    quickref = root / "QUICKREF.md"
    agent = root / "AGENT.md"
    claude = root / "CLAUDE.md"

    new_rows, new_total, new_missing = measure([quickref, manifest, design], root)
    base_rows, base_total, base_missing = measure([agent, claude, design], root)
    return {
        "new_rows": new_rows,
        "new_total": new_total,
        "new_missing": new_missing,
        "base_rows": base_rows,
        "base_total": base_total,
        "base_missing": base_missing,
        "is_subtractive": new_total < base_total,
    }


def _fmt_rows(rows: List[Row]) -> List[str]:
    width = max((len(r[0]) for r in rows), default=0)
    out = []
    for rel, size, exists in rows:
        mark = "" if exists else "  (누락→0B)"
        out.append(f"  {rel:<{width}}  {size:>8,} B  (~{_tok(size):>6,} tok){mark}")
    return out


def build_report(task_id: str, show_baseline: bool = False, root: Path = REPO_ROOT) -> str:
    r = compute(task_id, root)
    new_total = r["new_total"]
    base_total = r["base_total"]

    lines: List[str] = [f"컨텍스트 예산 리포트 — {task_id}", ""]
    lines.append("[신규 기본 로드 세트] QUICKREF + manifest + design")
    lines.extend(_fmt_rows(r["new_rows"]))
    lines.append(f"  └ 합계  {new_total:>8,} B  (~{_tok(new_total):,} tok)")
    lines.append("")
    if show_baseline:
        lines.append("[baseline] AGENT + CLAUDE + design")
        lines.extend(_fmt_rows(r["base_rows"]))
        lines.append(f"  └ 합계  {base_total:>8,} B  (~{_tok(base_total):,} tok)")
    else:
        lines.append(
            f"[baseline] AGENT+CLAUDE+design 합계  {base_total:,} B  "
            f"(~{_tok(base_total):,} tok)   (--baseline 로 상세)"
        )
    lines.append("")

    diff = base_total - new_total
    pct = round(diff / base_total * 100) if base_total > 0 else 0
    if new_total < base_total:
        lines.append(f"[비교] 신규 {new_total:,} B < baseline {base_total:,} B  →  ✅ 감산적 (−{diff:,} B, −{pct}%)")
    elif new_total == base_total:
        lines.append(f"[비교] 신규 {new_total:,} B = baseline {base_total:,} B  →  ⚠ 동일")
    else:
        lines.append(f"[비교] 신규 {new_total:,} B > baseline {base_total:,} B  →  ⚠ 증가 (+{-diff:,} B)")

    warnings: List[str] = [f"신규 세트 파일 누락(0B 처리): {m}" for m in r["new_missing"]]
    warnings += [
        f"baseline 파일 누락(0B 처리): {m}" for m in r["base_missing"] if m not in r["new_missing"]
    ]
    if warnings:
        lines.append("")
        lines.append("[경고]")
        lines.extend(f"  - {w}" for w in warnings)
    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="context-budget.py",
        description="task 기본 로드 세트의 컨텍스트 예산(바이트/토큰 추정) 경고 리포트 (warning-only).",
    )
    parser.add_argument("task_id", nargs="?", help="대상 task id (예: task-002)")
    parser.add_argument("--baseline", action="store_true", help="baseline 파일별 상세 출력")
    args = parser.parse_args(argv)

    if not args.task_id:
        print("사용법: python3 runtime/context-budget.py <task-id> [--baseline]")
        return 0

    print(build_report(args.task_id, args.baseline))
    return 0  # 경고 전용: 측정 경로는 항상 0


if __name__ == "__main__":
    sys.exit(main())
