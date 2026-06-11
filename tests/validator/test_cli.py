"""CLI-level tests for validator.cli — exit codes, output formatting, --json flag."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CLI = REPO_ROOT / "runtime" / "validator" / "cli.py"
FIXTURES = Path(__file__).parent / "fixtures"


def _run(args, cwd=None, repo_root=None):
    env = None
    if repo_root is not None:
        env = dict(os.environ)
        env["CWC_REPO_ROOT"] = str(repo_root)
    return subprocess.run(
        [sys.executable, str(CLI), *args],
        cwd=cwd or REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        env=env,
    )


def test_cli_exit_zero_on_good_fixture():
    result = _run([str(FIXTURES / "good.md")])
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[OK]" in result.stdout


def test_cli_exit_one_on_bad_fixture():
    result = _run([str(FIXTURES / "status-draft.md")])
    assert result.returncode == 1
    assert "[FAIL]" in result.stdout


def test_cli_exit_two_on_missing_file(tmp_path):
    missing = tmp_path / "nope.md"
    result = _run([str(missing)])
    assert result.returncode == 2


def test_cli_json_output_ok():
    result = _run([str(FIXTURES / "good.md"), "--json"])
    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["errors"] == []


def test_cli_json_output_errors_list_all():
    result = _run([str(FIXTURES / "empty-checkbox.md"), "--json"])
    assert result.returncode == 1
    payload = json.loads(result.stdout)
    assert payload["ok"] is False
    assert any(e["code"] == "empty_content" for e in payload["errors"])


def test_cli_respects_custom_schema(tmp_path):
    """--schema points the CLI at an alternate schema file."""
    custom = tmp_path / "custom.json"
    custom.write_text(
        json.dumps(
            {
                "version": 1,
                "required_sections": [],
                "placeholders": [],
                "required_meta_fields": ["Status"],
                "allowed_statuses_for_implementation": ["ready"],
                "blocked_statuses": {},
                "empty_content_checks": [],
            }
        ),
        encoding="utf-8",
    )
    minimal = tmp_path / "mini.md"
    minimal.write_text("> Status: ready\n", encoding="utf-8")
    result = _run([str(minimal), "--schema", str(custom)])
    assert result.returncode == 0, result.stdout


def test_cli_exit_two_on_decode_error(tmp_path):
    path = tmp_path / "bad.md"
    path.write_bytes(b"\xff\xfe\xfd not utf-8")
    result = _run([str(path)])
    assert result.returncode == 2


# ---------------------------------------------------------------------------
# --check-done 모드
# ---------------------------------------------------------------------------

TEMPLATE_NOTES = (REPO_ROOT / "templates" / "implementation-notes.md").read_text(encoding="utf-8")

# check_meta_fields 가 통과하는 최소 산출물 요약(Status/Inputs/Outputs/Next step 모두 존재).
VALID_SUMMARY = (
    "# 산출물 요약 — {task_id}\n"
    "\n"
    "> Status: done\n"
    "> Inputs: kb/tasks/{task_id}/implementation-notes.md\n"
    "> Outputs: 이 요약 문서\n"
    "> Next step: 완료\n"
    "\n"
    "## 작업 요약\n"
    "\n"
    "- **Task ID**: {task_id}\n"
    "- **완료일**: 2026-06-09\n"
)

# 템플릿과 byte 불일치하는, 실제로 작성된 구현 노트(Status: done).
VALID_NOTES = (
    "# 구현 노트 — {task_id}\n"
    "\n"
    "> Status: done\n"
    "> Inputs: kb/tasks/{task_id}/design.md\n"
    "> Outputs: 구현 결과\n"
    "> Next step: 완료\n"
    "\n"
    "## 산출물\n"
    "\n"
    "- runtime/validator/cli.py\n"
)


def _make_task(repo_root: Path, task_id: str, notes: str = None, summary: str = None):
    """tmp repo 루트에 task 디렉터리 + 템플릿 + (선택) 노트/요약을 만든다."""
    task_dir = repo_root / "kb" / "tasks" / task_id
    task_dir.mkdir(parents=True, exist_ok=True)
    templates_dir = repo_root / "templates"
    templates_dir.mkdir(parents=True, exist_ok=True)
    (templates_dir / "implementation-notes.md").write_text(TEMPLATE_NOTES, encoding="utf-8")
    if notes is not None:
        (task_dir / "implementation-notes.md").write_text(notes, encoding="utf-8")
    if summary is not None:
        artifacts_dir = repo_root / "kb" / "artifacts"
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        (artifacts_dir / f"{task_id}-summary.md").write_text(summary, encoding="utf-8")
    return task_dir


def test_check_done_legacy_task_passes(tmp_path):
    """task-001 은 allowlist 로 파일 상태와 무관하게 통과(0)한다."""
    # tmp repo 에 task-001 디렉터리/파일이 없어도 legacy 통과해야 한다.
    _make_task(tmp_path, "task-001")  # 템플릿만, 노트/요약 없음
    result = _run(["--check-done", "task-001"], repo_root=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "legacy" in result.stdout


def test_check_done_legacy_passes_even_without_template(tmp_path):
    """B-1: sparse checkout 등 templates/ 없는 환경에서도 legacy task 는 exit 0.

    check_done() 이 _template_with_id() 를 호출하기 전에 legacy 판정이 이뤄져야 한다.
    """
    # templates/ 디렉터리를 아예 만들지 않는다 (sparse checkout 시뮬레이션).
    task_dir = tmp_path / "kb" / "tasks" / "task-001"
    task_dir.mkdir(parents=True)
    result = _run(["--check-done", "task-001"], repo_root=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "legacy" in result.stdout


def test_check_done_missing_impl_notes(tmp_path):
    """구현 노트가 없으면 계약 위반(1)."""
    task_id = "task-100"
    _make_task(tmp_path, task_id, notes=None, summary=VALID_SUMMARY.format(task_id=task_id))
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "[FAIL]" in result.stdout
    assert "구현 노트 누락" in result.stdout


def test_check_done_impl_notes_identical_to_template(tmp_path):
    """구현 노트가 템플릿(task id 치환)과 byte 동일하면 위반(1)."""
    task_id = "task-101"
    template_filled = TEMPLATE_NOTES.replace("task-<NNN>", task_id)
    _make_task(
        tmp_path,
        task_id,
        notes=template_filled,
        summary=VALID_SUMMARY.format(task_id=task_id),
    )
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "템플릿과 동일" in result.stdout


def test_check_done_impl_notes_status_draft(tmp_path):
    """구현 노트 Status 가 draft 이면 위반(1)."""
    task_id = "task-102"
    draft_notes = VALID_NOTES.format(task_id=task_id).replace(
        "> Status: done", "> Status: draft"
    )
    _make_task(
        tmp_path,
        task_id,
        notes=draft_notes,
        summary=VALID_SUMMARY.format(task_id=task_id),
    )
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "draft" in result.stdout


def test_check_done_summary_missing_meta_field(tmp_path):
    """요약에서 meta 필드(Next step) 하나가 비어 있으면 위반(1)."""
    task_id = "task-103"
    bad_summary = VALID_SUMMARY.format(task_id=task_id).replace(
        "> Next step: 완료", "> Next step:"
    )
    _make_task(
        tmp_path,
        task_id,
        notes=VALID_NOTES.format(task_id=task_id),
        summary=bad_summary,
    )
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "[FAIL]" in result.stdout


def test_check_done_summary_missing_entirely(tmp_path):
    """요약 문서가 아예 없으면 위반(1)."""
    task_id = "task-104"
    _make_task(tmp_path, task_id, notes=VALID_NOTES.format(task_id=task_id), summary=None)
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "산출물 요약 누락" in result.stdout


def test_check_done_fully_valid_task(tmp_path):
    """노트(작성+done) + 요약(meta 완비)이면 통과(0)."""
    task_id = "task-105"
    _make_task(
        tmp_path,
        task_id,
        notes=VALID_NOTES.format(task_id=task_id),
        summary=VALID_SUMMARY.format(task_id=task_id),
    )
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[OK] 완료 검증 통과" in result.stdout


def test_check_done_accepts_path_argument(tmp_path):
    """'kb/tasks/<id>' 경로 인자도 id 와 동일하게 해석된다."""
    task_id = "task-106"
    _make_task(
        tmp_path,
        task_id,
        notes=VALID_NOTES.format(task_id=task_id),
        summary=VALID_SUMMARY.format(task_id=task_id),
    )
    result = _run(["--check-done", f"kb/tasks/{task_id}"], repo_root=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[OK]" in result.stdout


def test_check_done_json_adds_mode(tmp_path):
    """--json 출력에 mode:check-done 가 포함된다."""
    task_id = "task-107"
    _make_task(
        tmp_path,
        task_id,
        notes=VALID_NOTES.format(task_id=task_id),
        summary=VALID_SUMMARY.format(task_id=task_id),
    )
    result = _run(["--check-done", task_id, "--json"], repo_root=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(result.stdout)
    assert payload["mode"] == "check-done"
    assert payload["ok"] is True


# ---------------------------------------------------------------------------
# 회귀: 기존 design 검증 경로의 출력/종료코드가 바뀌지 않았는지 고정한다.
# ci.yml golden step 과 PS1 runner step 이 이 계약에 의존한다.
# ---------------------------------------------------------------------------


def test_regression_existing_positional_path_unchanged():
    """`cli.py <good.md>` 와 `--json` 의 출력·종료코드가 보존된다."""
    human = _run([str(FIXTURES / "good.md")])
    assert human.returncode == 0
    assert human.stdout == "[OK] 설계 문서 검증 통과 (섹션, 상태, placeholder, 내용)\n"

    js = _run([str(FIXTURES / "good.md"), "--json"])
    assert js.returncode == 0
    payload = json.loads(js.stdout)
    assert payload == {
        "ok": True,
        "file": str(FIXTURES / "good.md"),
        "errors": [],
    }
