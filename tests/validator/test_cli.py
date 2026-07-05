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


# done-gate manifest 검증(2026-07-05)을 통과하는 최소 manifest.
VALID_MANIFEST = (
    "# Manifest — {task_id}\n"
    "\n"
    "- **task_id**: {task_id}\n"
    "- **inputs**: kb/tasks/{task_id}/design.md\n"
    "- **concepts_needed**: 없음\n"
    "- **related_files**: runtime/validator/cli.py\n"
    "- **notes**: 테스트용 최소 manifest\n"
)


def _make_task(repo_root: Path, task_id: str, notes: str = None, summary: str = None,
               manifest: str = "__valid__"):
    """tmp repo 루트에 task 디렉터리 + 템플릿 + (선택) 노트/요약/manifest 를 만든다.

    manifest="__valid__"(기본) 이면 통과 가능한 manifest 를 생성, None 이면 생성하지 않음,
    그 외 문자열이면 해당 내용으로 생성한다.
    """
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
    if manifest == "__valid__":
        (task_dir / "manifest.md").write_text(
            VALID_MANIFEST.format(task_id=task_id), encoding="utf-8"
        )
    elif manifest is not None:
        (task_dir / "manifest.md").write_text(manifest, encoding="utf-8")
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
# done-gate 강화 (2026-07-05 codex 리뷰 반영): 상태값 · manifest 게이트
# ---------------------------------------------------------------------------


def test_check_done_notes_in_progress_rejected(tmp_path):
    """구현 노트 Status 가 in-progress(또는 임의 값)이면 완료가 아니다."""
    task_id = "task-110"
    wip_notes = VALID_NOTES.format(task_id=task_id).replace("> Status: done", "> Status: in-progress")
    _make_task(tmp_path, task_id, notes=wip_notes, summary=VALID_SUMMARY.format(task_id=task_id))
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "완료 기준" in result.stdout


def test_check_done_notes_arbitrary_status_rejected(tmp_path):
    task_id = "task-111"
    odd_notes = VALID_NOTES.format(task_id=task_id).replace("> Status: done", "> Status: wip")
    _make_task(tmp_path, task_id, notes=odd_notes, summary=VALID_SUMMARY.format(task_id=task_id))
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "'wip'" in result.stdout


def test_check_done_summary_not_done_rejected(tmp_path):
    """summary 는 완료 신호이므로 Status: done 만 인정한다 (board 집계 기준)."""
    task_id = "task-112"
    wip_summary = VALID_SUMMARY.format(task_id=task_id).replace("> Status: done", "> Status: in-progress")
    _make_task(tmp_path, task_id, notes=VALID_NOTES.format(task_id=task_id), summary=wip_summary)
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "완료 신호" in result.stdout


def test_check_done_manifest_missing_rejected(tmp_path):
    task_id = "task-113"
    _make_task(
        tmp_path, task_id,
        notes=VALID_NOTES.format(task_id=task_id),
        summary=VALID_SUMMARY.format(task_id=task_id),
        manifest=None,
    )
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "manifest 누락" in result.stdout


def test_check_done_manifest_placeholder_rejected(tmp_path):
    """manifest 가 템플릿 placeholder 그대로면 fast-path 로드 세트가 무의미 — 거부."""
    task_id = "task-114"
    template_manifest = (
        "# Manifest — {tid}\n\n"
        "- **task_id**: {tid}\n"
        "- **inputs**: (이 task 가 의존하는 입력 문서/데이터)\n"
        "- **concepts_needed**: (kb/concepts/ 중 실제 필요한 문서만; 없으면 `없음`)\n"
        "- **related_files**: (구현·수정 대상 또는 참조할 소스 파일 경로)\n"
        "- **notes**: (로드 시 주의점; 생략 가능)\n"
    ).format(tid=task_id)
    _make_task(
        tmp_path, task_id,
        notes=VALID_NOTES.format(task_id=task_id),
        summary=VALID_SUMMARY.format(task_id=task_id),
        manifest=template_manifest,
    )
    result = _run(["--check-done", task_id], repo_root=tmp_path)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "placeholder" in result.stdout


# ---------------------------------------------------------------------------
# Phase D — review CLI + approved-done 게이트 (task-006)
# ---------------------------------------------------------------------------

COLLAB = "# collab\n\n<!-- review-status-enum: pending | request-changes | approved | rejected -->\n"

REVIEW_TMPL = (
    "## Review: {tid} — 2026-07-05\n\n"
    "- **Reviewer**: Codex\n"
    "- **Target**: kb/tasks/{tid}/implementation-notes.md\n"
    "- **Review status**: {status}\n"
    "- **Generated by**: review=codex gpt-5.5/xhigh @codex 0.142.4, 2026-07-05 (sandbox=workspace-write)\n"
    "- **Feedback**:\n  - 구현이 설계를 충실히 따른다.\n"
    "- **Action required**:\n  - 없음\n"
)


def _add_review(repo_root: Path, task_id: str, num: str, status: str):
    (repo_root / "collab.md").write_text(COLLAB, encoding="utf-8")
    rd = repo_root / "kb" / "tasks" / task_id / "reviews"
    rd.mkdir(parents=True, exist_ok=True)
    (rd / f"{num}.md").write_text(REVIEW_TMPL.format(tid=task_id, status=status), encoding="utf-8")


def _done_task(tmp_path, task_id):
    _make_task(tmp_path, task_id, notes=VALID_NOTES.format(task_id=task_id),
               summary=VALID_SUMMARY.format(task_id=task_id))


def test_check_review_valid(tmp_path):
    _add_review(tmp_path, "task-200", "001", "approved")
    r = _run(["--check-review", "kb/tasks/task-200/reviews/001.md"], repo_root=tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_check_review_invalid_status(tmp_path):
    _add_review(tmp_path, "task-201", "001", "maybe")
    r = _run(["--check-review", "kb/tasks/task-201/reviews/001.md"], repo_root=tmp_path)
    assert r.returncode == 1
    assert "리뷰 상태 오류" in r.stdout


def test_latest_review_sorts_numeric(tmp_path):
    _add_review(tmp_path, "task-202", "001", "approved")
    _add_review(tmp_path, "task-202", "002", "request-changes")
    _add_review(tmp_path, "task-202", "010", "approved")
    r = _run(["--latest-review", "task-202", "--json"], repo_root=tmp_path)
    assert r.returncode == 0
    payload = json.loads(r.stdout)
    assert payload["latest"] == "010.md" and payload["status"] == "approved"


def test_latest_review_missing_dir(tmp_path):
    _done_task(tmp_path, "task-203")
    r = _run(["--latest-review", "task-203"], repo_root=tmp_path)
    assert r.returncode == 1


def test_check_done_approved_review_passes(tmp_path):
    _done_task(tmp_path, "task-204")
    _add_review(tmp_path, "task-204", "001", "approved")
    r = _run(["--check-done", "task-204"], repo_root=tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_check_done_request_changes_fails_and_no_auto_revert(tmp_path):
    _done_task(tmp_path, "task-205")
    _add_review(tmp_path, "task-205", "001", "request-changes")
    notes_path = tmp_path / "kb" / "tasks" / "task-205" / "implementation-notes.md"
    summary_path = tmp_path / "kb" / "artifacts" / "task-205-summary.md"
    r = _run(["--check-done", "task-205"], repo_root=tmp_path)
    assert r.returncode == 1
    assert "미승인" in r.stdout
    # no-auto-revert: task status 파일은 그대로 done 이어야 한다
    assert "Status: done" in notes_path.read_text(encoding="utf-8")
    assert "Status: done" in summary_path.read_text(encoding="utf-8")


def test_check_done_latest_wins_over_older_approved(tmp_path):
    """오래된 approved 가 있어도 최신이 request-changes 면 실패."""
    _done_task(tmp_path, "task-206")
    _add_review(tmp_path, "task-206", "001", "approved")
    _add_review(tmp_path, "task-206", "002", "request-changes")
    r = _run(["--check-done", "task-206"], repo_root=tmp_path)
    assert r.returncode == 1


def test_check_done_empty_reviews_dir_fails(tmp_path):
    _done_task(tmp_path, "task-207")
    (tmp_path / "collab.md").write_text(COLLAB, encoding="utf-8")
    (tmp_path / "kb" / "tasks" / "task-207" / "reviews").mkdir(parents=True)
    r = _run(["--check-done", "task-207"], repo_root=tmp_path)
    assert r.returncode == 1
    assert "리뷰 없음" in r.stdout


def test_check_review_target_ignores_review_gate(tmp_path):
    """이전 리뷰가 request-changes 여도 base 검증(target)은 통과 → 재리뷰 가능."""
    _done_task(tmp_path, "task-208")
    _add_review(tmp_path, "task-208", "001", "request-changes")
    r = _run(["--check-review-target", "task-208"], repo_root=tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_check_done_no_reviews_backward_compat(tmp_path):
    """reviews/ 가 없으면 기존 done-gate 동작(리뷰 게이트 미적용)."""
    _done_task(tmp_path, "task-209")
    r = _run(["--check-done", "task-209"], repo_root=tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


# ---------------------------------------------------------------------------
# 실행 계획 (Execution Plan) — CLI 통합 경로 (task-004)
# ---------------------------------------------------------------------------


def test_cli_execution_plan_bad_model_exit_one():
    result = _run([str(FIXTURES / "execution-plan-bad-model.md")])
    assert result.returncode == 1, result.stdout + result.stderr
    assert "화이트리스트" in result.stdout


def test_cli_execution_plan_legacy_absent_ok():
    """title 이 task-001 인 legacy 설계는 실행 계획 없이 통과한다."""
    result = _run([str(FIXTURES / "legacy-no-execution-plan.md")])
    assert result.returncode == 0, result.stdout + result.stderr


def test_cli_execution_plan_absent_nonlegacy_exit_one():
    result = _run([str(FIXTURES / "execution-plan-absent-nonlegacy.md")])
    assert result.returncode == 1, result.stdout + result.stderr
    assert "실행 계획 누락" in result.stdout


def test_cli_profile_missing_exit_two(tmp_path):
    """실행 계획이 있는 설계 + 프로필 부재 → 환경 오류(2), 조용한 기본값 금지."""
    # CWC_REPO_ROOT 를 빈 tmp 로 주입하면 runtime/config/model-profiles.json 이 없다.
    result = _run([str(FIXTURES / "good.md")], repo_root=tmp_path)
    assert result.returncode == 2, result.stdout + result.stderr
    assert "프로필" in (result.stderr + result.stdout)


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
