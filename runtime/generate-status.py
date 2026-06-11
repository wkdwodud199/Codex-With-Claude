#!/usr/bin/env python3
"""status board 생성기 — kb/index/status.md의 생성 블록을 결정론적으로 재작성한다.

`kb/tasks/*/design.md`의 설계 준비도 Status와 `kb/artifacts/*-summary.md`의
완료 Status / 본문 완료일을 읽어 '## 활성 작업'과 '## 완료 작업' 표를 만든다.
meta 추출은 runtime/validator/parser.py의 parse_document를 재사용한다(새 parser 금지).

완료(done) 신호는 design.md가 아니라 artifact summary meta `Status: done` 이다.
이 저장소의 흐름상 design.md는 'ready'로 고정(freeze)되고 완료는 산출물 요약으로 판정한다.

사용법:
  python3 runtime/generate-status.py [status_md_path]   # 기본: 파일 재작성
  python3 runtime/generate-status.py --check [path]      # drift만 검사(파일 미수정)

종료코드:
  0 — 성공(기본 재작성 완료 / --check 일치)
  1 — --check 에서 drift 발견(stderr에 요약 diff)
  2 — 마커 누락 또는 IO/디코딩 오류
"""

from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path
from typing import Dict, List, NamedTuple, Optional

# parse_document(...).metadata 재사용을 위해 runtime/ 을 sys.path 에 올린다.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from validator.parser import parse_document  # noqa: E402  (sys.path mutated above)

BEGIN_MARKER = "<!-- BEGIN:generated -->"
END_MARKER = "<!-- END:generated -->"

# 활성 작업 후보가 되는 design.md Status 집합. draft 는 보드에서 제외.
ACTIVE_STATUSES = {"ready", "blocked"}

# 누락 표기. 완료일 등 좁은 형식 값이 없을 때 채운다.
MISSING = "—"
EMPTY_ROW = "(없음)"

_TASK_ID_RE = re.compile(r"^task-\d+$")
# 본문 '- **완료일**: YYYY-MM-DD' 추출. 값은 좁게(공백/구두점 허용 최소).
_DONE_DATE_RE = re.compile(r"^\s*-\s*\*\*완료일\*\*\s*:\s*(.+?)\s*$")
# 본문 '- **제목**: ...' 추출.
_TITLE_RE = re.compile(r"^\s*-\s*\*\*제목\*\*\s*:\s*(.+?)\s*$")
_H1_RE = re.compile(r"^\s{0,3}#\s+(.+?)\s*$")


class MarkersMissing(Exception):
    """status.md 에 생성 마커가 없을 때 발생. 파일을 부분 수정하지 않는다."""


class TaskRow(NamedTuple):
    task_id: str
    title: str
    design_status: str
    summary_status: str
    done_date: str


def _read_text(path: Path) -> str:
    """UTF-8 strict 로 읽는다. 디코딩/IO 오류는 호출부가 종료코드 2로 변환한다."""
    return path.read_text(encoding="utf-8", errors="strict")


def _extract_title_from_summary(text: str) -> str:
    for line in text.splitlines():
        m = _TITLE_RE.match(line)
        if m:
            return m.group(1).strip()
    return ""


def _extract_done_date(text: str) -> str:
    for line in text.splitlines():
        m = _DONE_DATE_RE.match(line)
        if m:
            return m.group(1).strip()
    return ""


def _extract_title_from_design(text: str) -> str:
    """design 첫 H1, 실패 시 '## 목표' 다음 첫 비어있지 않은 줄을 제목 후보로."""
    lines = text.splitlines()
    for line in lines:
        m = _H1_RE.match(line)
        if m:
            return m.group(1).strip()
    return ""


def collect_tasks(root: Path) -> List[TaskRow]:
    """repo root 기준으로 task 메타를 모은다(테스트가 root 를 주입한다).

    각 kb/tasks/<id>/design.md 의 meta Status 와 (있으면)
    kb/artifacts/<id>-summary.md 의 meta Status + 본문 완료일/제목을 읽어
    task id 오름차순 TaskRow 리스트로 반환한다.
    """
    tasks_dir = root / "kb" / "tasks"
    artifacts_dir = root / "kb" / "artifacts"
    rows: List[TaskRow] = []
    if not tasks_dir.is_dir():
        return rows

    for task_dir in sorted(
        p for p in tasks_dir.iterdir() if p.is_dir() and _TASK_ID_RE.match(p.name)
    ):
        task_id = task_dir.name
        design_path = task_dir / "design.md"
        if not design_path.is_file():
            continue
        design_text = _read_text(design_path)
        design_meta = parse_document(design_text).metadata
        design_status = (design_meta.get("Status") or "").strip()

        summary_path = artifacts_dir / f"{task_id}-summary.md"
        summary_status = ""
        done_date = ""
        summary_title = ""
        if summary_path.is_file():
            summary_text = _read_text(summary_path)
            summary_meta = parse_document(summary_text).metadata
            summary_status = (summary_meta.get("Status") or "").strip()
            done_date = _extract_done_date(summary_text)
            summary_title = _extract_title_from_summary(summary_text)

        # 제목: summary 제목 > design H1 > task id
        title = summary_title or _extract_title_from_design(design_text) or task_id

        rows.append(
            TaskRow(
                task_id=task_id,
                title=title,
                design_status=design_status,
                summary_status=summary_status,
                done_date=done_date or MISSING,
            )
        )

    rows.sort(key=lambda r: int(re.search(r"\d+", r.task_id).group()))
    return rows


def _is_done(row: TaskRow) -> bool:
    """완료 판정: artifact summary meta Status == 'done'."""
    return row.summary_status == "done"


def split_active_done(rows: List[TaskRow]):
    """(active, done) 으로 분리. done = summary Status done.
    active = design Status in {ready, blocked} 이며 done 집합 제외."""
    done = [r for r in rows if _is_done(r)]
    done_ids = {r.task_id for r in done}
    active = [
        r
        for r in rows
        if r.task_id not in done_ids and r.design_status in ACTIVE_STATUSES
    ]
    return active, done


def _cell(value: str) -> str:
    """표 셀 안에서 파이프가 표를 깨지 않도록 이스케이프."""
    return (value or MISSING).replace("|", "\\|")


def render_active_table(active: List[TaskRow]) -> str:
    header = "| Task ID | 제목 | Status | 비고 |\n|---------|------|--------|------|"
    if not active:
        body = f"| {EMPTY_ROW} | {MISSING} | {MISSING} | {MISSING} |"
    else:
        body = "\n".join(
            f"| {_cell(r.task_id)} | {_cell(r.title)} | {_cell(r.design_status)} | {MISSING} |"
            for r in active
        )
    return f"## 활성 작업\n\n{header}\n{body}"


def render_done_table(done: List[TaskRow]) -> str:
    header = "| Task ID | 제목 | 완료일 | 산출물 |\n|---------|------|--------|--------|"
    if not done:
        body = f"| {EMPTY_ROW} | {MISSING} | {MISSING} | {MISSING} |"
    else:
        body = "\n".join(
            "| {id} | {title} | {date} | [summary](../artifacts/{id}-summary.md) |".format(
                id=_cell(r.task_id), title=_cell(r.title), date=_cell(r.done_date)
            )
            for r in done
        )
    return f"## 완료 작업\n\n{header}\n{body}"


def render_generated_block(rows: List[TaskRow]) -> str:
    """마커 사이에 들어갈 내용. 활성 표 다음 완료 표만, 그 외엔 아무것도 없음.
    동일 입력에서 byte-stable(휘발성 날짜 없음)."""
    active, done = split_active_done(rows)
    return render_active_table(active) + "\n\n" + render_done_table(done)


def replace_generated_block(text: str, new_block: str) -> str:
    """마커 사이 내용만 치환한다. 마커 밖은 byte 보존.

    마커는 **자기 줄 전체**로 존재해야 한다 — prose 안에 인라인으로 언급된
    동일 문자열은 무시한다(오탐 방지). 마커가 없으면 MarkersMissing 을 던진다.
    """
    lines = text.splitlines(keepends=True)
    begin_idx = end_idx = -1
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == BEGIN_MARKER and begin_idx == -1:
            begin_idx = i
        elif stripped == END_MARKER and begin_idx != -1 and end_idx == -1:
            end_idx = i
    if begin_idx == -1 or end_idx == -1 or end_idx < begin_idx:
        raise MarkersMissing(
            f"생성 마커를 각자 한 줄로 찾을 수 없습니다: '{BEGIN_MARKER}' / '{END_MARKER}'"
        )
    head = "".join(lines[: begin_idx + 1])
    if not head.endswith("\n"):
        head += "\n"
    tail = "".join(lines[end_idx:])
    return f"{head}{new_block}\n{tail}"


def build_status_text(root: Path, current_text: str) -> str:
    """현재 status.md 텍스트의 마커 내부만 새 블록으로 교체한 전체 텍스트."""
    rows = collect_tasks(root)
    block = render_generated_block(rows)
    return replace_generated_block(current_text, block)


def _default_status_path(root: Path) -> Path:
    return root / "kb" / "index" / "status.md"


def _repo_root() -> Path:
    # runtime/generate-status.py → repo root 는 한 단계 위.
    return _HERE.parent


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="kb/index/status.md 생성 블록을 재작성하거나 drift를 검사한다."
    )
    parser.add_argument(
        "status_md_path",
        nargs="?",
        type=Path,
        default=None,
        help="대상 status.md 경로(기본: kb/index/status.md)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="파일을 쓰지 않고 drift 여부만 종료코드로 보고",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    root = _repo_root()
    status_path = args.status_md_path or _default_status_path(root)
    # status.md 가 root 밖(테스트 tmp)인 경우 root 를 그 부모 체인에서 추정.
    if args.status_md_path is not None:
        root = _root_from_status_path(status_path)

    try:
        current_text = _read_text(status_path)
    except FileNotFoundError:
        print(f"[ERROR] status 파일을 찾을 수 없습니다: {status_path}", file=sys.stderr)
        return 2
    except UnicodeDecodeError as e:
        print(f"[ERROR] UTF-8 디코딩 실패: {status_path} ({e})", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"[ERROR] status 파일 읽기 실패: {status_path} ({e})", file=sys.stderr)
        return 2

    try:
        new_text = build_status_text(root, current_text)
    except MarkersMissing as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        return 2

    if args.check:
        if new_text == current_text:
            return 0
        diff = difflib.unified_diff(
            current_text.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile=str(status_path),
            tofile=f"{status_path} (regenerated)",
        )
        sys.stderr.write("[DRIFT] status board 생성 블록이 최신이 아닙니다.\n")
        sys.stderr.writelines(diff)
        if not new_text.endswith("\n"):
            sys.stderr.write("\n")
        return 1

    if new_text != current_text:
        try:
            status_path.write_text(new_text, encoding="utf-8")
        except OSError as e:
            print(f"[ERROR] status 파일 쓰기 실패: {status_path} ({e})", file=sys.stderr)
            return 2
        print(f"[OK] status board 갱신: {status_path}")
    else:
        print(f"[OK] status board 변경 없음: {status_path}")
    return 0


def _root_from_status_path(status_path: Path) -> Path:
    """주입된 status.md 경로(.../kb/index/status.md)에서 repo root 를 역산.

    표준 레이아웃이면 status_path.parents[2] 가 root. 아니면 부모 디렉터리.
    """
    p = status_path.resolve()
    parents = p.parents
    if (
        len(parents) >= 3
        and p.parent.name == "index"
        and parents[1].name == "kb"
    ):
        return parents[2]
    return p.parent


if __name__ == "__main__":
    sys.exit(main())
