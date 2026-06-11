"""context-budget.py 단위 테스트 (Phase A, task-002).

하이픈 파일명이라 importlib 로 로드한다. 측정 로직은 root 주입으로 임시 repo 에서 검증하고,
'항상 종료코드 0' 계약은 실제 repo 경로에 대해 main() 으로 검증한다.
"""
import importlib.util
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SPEC_PATH = REPO / "runtime" / "context-budget.py"


def _load():
    spec = importlib.util.spec_from_file_location("context_budget", SPEC_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


cb = _load()


def _make_repo(tmp_path, *, quickref=b"Q", agent=b"A", claude=b"C", design=b"D", manifest=b"M"):
    (tmp_path / "QUICKREF.md").write_bytes(quickref)
    (tmp_path / "AGENT.md").write_bytes(agent)
    (tmp_path / "CLAUDE.md").write_bytes(claude)
    d = tmp_path / "kb" / "tasks" / "task-x"
    d.mkdir(parents=True)
    (d / "design.md").write_bytes(design)
    if manifest is not None:
        (d / "manifest.md").write_bytes(manifest)
    return tmp_path


def test_new_set_total_and_token_estimate(tmp_path):
    # QUICKREF=100, manifest=40, design=200 -> new_total=340, tok=340//4=85
    root = _make_repo(tmp_path, quickref=b"q" * 100, manifest=b"m" * 40, design=b"d" * 200)
    r = cb.compute("task-x", root=root)
    assert r["new_total"] == 340
    assert cb._tok(r["new_total"]) == 85
    assert r["new_missing"] == []


def test_baseline_total_and_detail_output(tmp_path):
    # AGENT=400, CLAUDE=320, design=200 -> base_total=920
    root = _make_repo(tmp_path, agent=b"a" * 400, claude=b"c" * 320, design=b"d" * 200,
                      quickref=b"q" * 100, manifest=b"m" * 40)
    r = cb.compute("task-x", root=root)
    assert r["base_total"] == 920
    report = cb.build_report("task-x", show_baseline=True, root=root)
    assert "[baseline]" in report
    assert "AGENT.md" in report and "CLAUDE.md" in report
    assert "[비교]" in report


def test_missing_manifest_and_quickref_warn_and_zero(tmp_path):
    root = _make_repo(tmp_path, manifest=None)  # no manifest.md
    (root / "QUICKREF.md").unlink()              # no QUICKREF.md
    r = cb.compute("task-x", root=root)
    rels = set(r["new_missing"])
    assert any(x.endswith("manifest.md") for x in rels)
    assert "QUICKREF.md" in rels
    report = cb.build_report("task-x", root=root)
    assert "[경고]" in report and "누락" in report


def test_subtractive_message_when_new_smaller(tmp_path):
    root = _make_repo(tmp_path, quickref=b"q" * 50, manifest=b"m" * 10, design=b"d" * 10,
                      agent=b"a" * 500, claude=b"c" * 500)
    report = cb.build_report("task-x", root=root)
    assert "감산적" in report  # new(70) < base(1010)


def test_non_subtractive_is_warning_only(tmp_path):
    # 신규가 baseline 이상이어도 실패하지 않고 경고만
    root = _make_repo(tmp_path, quickref=b"q" * 5000, manifest=b"m" * 10, design=b"d" * 10,
                      agent=b"a" * 10, claude=b"c" * 10)
    report = cb.build_report("task-x", root=root)
    assert "증가" in report
    assert cb.main(["task-x"]) == 0  # main on real repo still 0 regardless


def test_exit_code_always_zero(capsys):
    assert cb.main(["task-002"]) == 0          # real, existing task
    assert cb.main(["__no_such_task__"]) == 0  # missing files -> still 0
    assert cb.main([]) == 0                     # no task id -> usage, still 0
    capsys.readouterr()
