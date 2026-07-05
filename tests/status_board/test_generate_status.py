"""generate-status.py 단위 테스트 (task-003, 파티션 A).

하이픈 파일명이라 importlib 로 로드한다(context-budget 테스트와 동일 패턴).
핵심 로직은 root 주입으로 임시 mini-repo 에서 검증한다:
  - 활성/완료 표가 올바르게 채워지는지
  - 멱등성(두 번 실행 시 2번째는 변화 없음)
  - --check 가 sync 0 / drift 1 / 마커 누락 2 를 반환하는지
  - 마커 밖 텍스트가 byte 보존되는지
"""
import importlib.util
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SPEC_PATH = REPO / "runtime" / "generate-status.py"


def _load():
    spec = importlib.util.spec_from_file_location("generate_status", SPEC_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gs = _load()


# --- mini-repo 빌더 -----------------------------------------------------------

_DESIGN_TMPL = """# 설계 문서 — {tid}

> Status: {status}
> Inputs: x
> Outputs: y
> Next step: z

## 목표 (Objective)

{title}
"""

_SUMMARY_TMPL = """# 산출물 요약 — {tid}

> Status: {status}
> Inputs: kb/tasks/{tid}/design.md
> Outputs: 이 요약 문서
> Next step: 다음

## 작업 요약

- **Task ID**: {tid}
- **제목**: {title}
- **완료일**: {date}
"""

_STATUS_OUTSIDE_BEFORE = """# 작업 현황 (Status Board)

> 마지막 갱신: 2026-06-09

이 prose 는 마커 밖이라 byte 보존되어야 한다.
"""

_STATUS_OUTSIDE_AFTER = """

## 러너 빠른 참조

마커 밖 수동 섹션 — 보존 대상.

러너 도움말도 보존된다.
"""


def _make_repo(tmp_path, designs, summaries):
    """designs: {tid: status}, summaries: {tid: (status, date, title)}."""
    tasks = tmp_path / "kb" / "tasks"
    arts = tmp_path / "kb" / "artifacts"
    tasks.mkdir(parents=True)
    arts.mkdir(parents=True)
    for tid, status in designs.items():
        d = tasks / tid
        d.mkdir()
        (d / "design.md").write_text(
            _DESIGN_TMPL.format(tid=tid, status=status, title=f"{tid} 설계제목"),
            encoding="utf-8",
        )
    for tid, (status, date, title) in summaries.items():
        (arts / f"{tid}-summary.md").write_text(
            _SUMMARY_TMPL.format(tid=tid, status=status, date=date, title=title),
            encoding="utf-8",
        )
    return tmp_path


def _make_status_md(tmp_path, *, with_markers=True, inner=""):
    idx = tmp_path / "kb" / "index"
    idx.mkdir(parents=True, exist_ok=True)
    path = idx / "status.md"
    if with_markers:
        body = (
            _STATUS_OUTSIDE_BEFORE
            + gs.BEGIN_MARKER
            + "\n"
            + inner
            + gs.END_MARKER
            + _STATUS_OUTSIDE_AFTER
        )
    else:
        body = _STATUS_OUTSIDE_BEFORE + "마커 없음\n" + _STATUS_OUTSIDE_AFTER
    path.write_text(body, encoding="utf-8")
    return path


# --- collect / split ----------------------------------------------------------

def test_collect_and_split_active_done(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={
            "task-001": "ready",   # done by summary
            "task-002": "ready",   # active (no done summary)
            "task-003": "blocked",  # active
            "task-004": "draft",   # excluded entirely
        },
        summaries={
            "task-001": ("done", "2026-04-17", "v1 scaffold"),
            "task-002": ("ready", "—", "Phase A"),
        },
    )
    rows = gs.collect_tasks(root)
    active, done = gs.split_active_done(rows)
    assert [r.task_id for r in done] == ["task-001"]
    assert [r.task_id for r in active] == ["task-002", "task-003"]
    # draft 는 어디에도 없음
    all_ids = {r.task_id for r in active} | {r.task_id for r in done}
    assert "task-004" not in all_ids


def test_done_keys_off_summary_not_design(tmp_path):
    # design 이 ready 라도 summary Status done 이면 완료로 본다.
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "스캐폴드")},
    )
    rows = gs.collect_tasks(root)
    _, done = gs.split_active_done(rows)
    assert [r.task_id for r in done] == ["task-001"]
    assert done[0].done_date == "2026-04-17"


def test_title_precedence_summary_then_design_then_id(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={"task-002": "ready", "task-009": "ready"},
        summaries={"task-002": ("done", "2026-01-01", "요약제목")},
    )
    rows = {r.task_id: r for r in gs.collect_tasks(root)}
    # summary 제목 우선
    assert rows["task-002"].title == "요약제목"
    # summary 없으면 design H1 사용
    assert rows["task-009"].title == "설계 문서 — task-009"


# --- rendering ----------------------------------------------------------------

def test_render_tables_content(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready", "task-002": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "스캐폴드")},
    )
    rows = gs.collect_tasks(root)
    block = gs.render_generated_block(rows)
    assert "## 활성 작업" in block
    assert "## 완료 작업" in block
    # 완료 표에 산출물 링크
    assert "[summary](../artifacts/task-001-summary.md)" in block
    assert "2026-04-17" in block
    # 활성 표에 task-002
    assert "| task-002 |" in block
    # 활성 표 헤더 컬럼
    assert "| Task ID | 제목 | Status | 비고 |" in block


def test_empty_sets_render_none_row(tmp_path):
    root = _make_repo(tmp_path, designs={"task-001": "draft"}, summaries={})
    rows = gs.collect_tasks(root)
    block = gs.render_generated_block(rows)
    # active 와 done 둘 다 비어 → (없음) 행
    assert block.count(gs.EMPTY_ROW) == 2


# --- generation (full file rewrite) ------------------------------------------

def test_generation_fills_tables_and_preserves_outside(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready", "task-002": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "스캐폴드")},
    )
    status_path = _make_status_md(tmp_path, inner="OLD CONTENT\n")
    original = status_path.read_text(encoding="utf-8")

    rc = gs.main([str(status_path)])
    assert rc == 0
    after = status_path.read_text(encoding="utf-8")

    # 마커 밖 보존: before/after prose 가 그대로 남아야 한다
    assert after.startswith(_STATUS_OUTSIDE_BEFORE)
    assert after.endswith(_STATUS_OUTSIDE_AFTER)
    assert "마커 밖 수동 섹션 — 보존 대상." in after
    # 마커 내부는 갱신됨
    assert "OLD CONTENT" not in after
    assert "task-002" in after
    assert "[summary](../artifacts/task-001-summary.md)" in after
    assert original != after


def test_outside_markers_byte_preserved(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "t")},
    )
    status_path = _make_status_md(tmp_path, inner="x\n")
    gs.main([str(status_path)])
    after = status_path.read_text(encoding="utf-8")
    begin = after.index(gs.BEGIN_MARKER)
    end = after.index(gs.END_MARKER) + len(gs.END_MARKER)
    head = after[: begin + len(gs.BEGIN_MARKER)]
    tail = after[end - len(gs.END_MARKER) :]
    # 마커 앞부분과 뒷부분이 원본과 byte 동일
    assert head == _STATUS_OUTSIDE_BEFORE + gs.BEGIN_MARKER
    assert tail == gs.END_MARKER + _STATUS_OUTSIDE_AFTER


# --- idempotency --------------------------------------------------------------

def test_idempotent_second_run_no_change(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready", "task-002": "blocked"},
        summaries={"task-001": ("done", "2026-04-17", "t")},
    )
    status_path = _make_status_md(tmp_path, inner="seed\n")
    assert gs.main([str(status_path)]) == 0
    first = status_path.read_text(encoding="utf-8")
    assert gs.main([str(status_path)]) == 0
    second = status_path.read_text(encoding="utf-8")
    assert first == second
    # --check 도 sync 이므로 0
    assert gs.main(["--check", str(status_path)]) == 0


# --- --check ------------------------------------------------------------------

def test_check_returns_zero_when_in_sync(tmp_path):
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "t")},
    )
    status_path = _make_status_md(tmp_path, inner="seed\n")
    gs.main([str(status_path)])  # bring in sync
    assert gs.main(["--check", str(status_path)]) == 0


def test_check_returns_one_on_drift(tmp_path, capsys):
    root = _make_repo(
        tmp_path,
        designs={"task-001": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "t")},
    )
    # 마커 내부가 stale 한 상태로 둔다(생성하지 않음)
    status_path = _make_status_md(tmp_path, inner="STALE\n")
    assert gs.main(["--check", str(status_path)]) == 1
    err = capsys.readouterr().err
    assert "DRIFT" in err


def test_check_returns_two_when_markers_missing(tmp_path, capsys):
    _make_repo(
        tmp_path,
        designs={"task-001": "ready"},
        summaries={"task-001": ("done", "2026-04-17", "t")},
    )
    status_path = _make_status_md(tmp_path, with_markers=False)
    assert gs.main(["--check", str(status_path)]) == 2
    err = capsys.readouterr().err
    assert "마커" in err


def test_default_mode_markers_missing_returns_two(tmp_path):
    _make_repo(tmp_path, designs={"task-001": "ready"}, summaries={})
    status_path = _make_status_md(tmp_path, with_markers=False)
    before = status_path.read_text(encoding="utf-8")
    assert gs.main([str(status_path)]) == 2
    # 부분 수정 금지 — 파일 그대로
    assert status_path.read_text(encoding="utf-8") == before


def test_missing_status_file_returns_two(tmp_path):
    _make_repo(tmp_path, designs={"task-001": "ready"}, summaries={})
    missing = tmp_path / "kb" / "index" / "status.md"  # not created
    assert gs.main([str(missing)]) == 2


# --- replace_generated_block direct -------------------------------------------

def test_replace_block_raises_when_markers_absent():
    with pytest.raises(gs.MarkersMissing):
        gs.replace_generated_block("no markers here", "BLOCK")


def test_replace_block_only_touches_inside():
    text = f"HEAD\n{gs.BEGIN_MARKER}\nold\n{gs.END_MARKER}\nTAIL\n"
    out = gs.replace_generated_block(text, "NEW")
    assert out == f"HEAD\n{gs.BEGIN_MARKER}\nNEW\n{gs.END_MARKER}\nTAIL\n"


# --- B-2: 비-task 디렉터리 필터 -------------------------------------------

def test_non_task_dir_filtered(tmp_path):
    """B-2: kb/tasks/ 에 task-NNN 형식이 아닌 디렉터리가 있어도 보드에 나타나지 않는다."""
    root = tmp_path
    (root / "kb" / "tasks").mkdir(parents=True)
    (root / "kb" / "artifacts").mkdir(parents=True)
    (root / "kb" / "index").mkdir(parents=True)

    # 정상 task
    t1 = root / "kb" / "tasks" / "task-001"
    t1.mkdir()
    (t1 / "design.md").write_text("> Status: ready\n> Inputs: -\n> Outputs: -\n> Next step: -\n", encoding="utf-8")

    # 비-task 디렉터리 (task-001-backup, notes)
    for bad in ("task-001-backup", "notes", ".cache"):
        bad_dir = root / "kb" / "tasks" / bad
        bad_dir.mkdir()
        (bad_dir / "design.md").write_text("> Status: ready\n> Inputs: -\n> Outputs: -\n> Next step: -\n", encoding="utf-8")

    rows = gs.collect_tasks(root)
    task_ids = [r.task_id for r in rows]
    assert "task-001" in task_ids
    assert "task-001-backup" not in task_ids
    assert "notes" not in task_ids
    assert ".cache" not in task_ids
