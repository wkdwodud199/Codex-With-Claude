"""Subprocess tests for runtime/render-prompt.py — render(design-review) + detect-fallback (task-005).

render-prompt.py 는 하이픈 파일명이라 import 불가 → cli.py 테스트와 동일하게 subprocess 로 구동한다.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
RP = REPO_ROOT / "runtime" / "render-prompt.py"


def _run(args, stdin=None):
    return subprocess.run(
        [sys.executable, str(RP), *args],
        cwd=REPO_ROOT,
        input=stdin,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


# --- render --phase design-review ---------------------------------------------

def test_render_design_review_ok():
    r = _run([
        "render", "--phase", "design-review", "--task-id", "task-005",
        "--design-file", "kb/tasks/task-005/design.md",
        "--review-file", "kb/tasks/task-005/design-review.md",
        "--project-root", str(REPO_ROOT), "--model", "claude-fable-5", "--effort", "max",
    ])
    assert r.returncode == 0, r.stdout + r.stderr
    assert "읽기전용" in r.stdout
    assert "kb/tasks/task-005/design-review.md" in r.stdout
    assert "{{" not in r.stdout  # 치환 누락 없음


def test_render_unknown_phase_rejected():
    r = _run([
        "render", "--phase", "bogus", "--task-id", "t",
        "--design-file", "x", "--project-root", str(REPO_ROOT),
    ])
    assert r.returncode != 0  # argparse choices 위반


# --- detect-fallback ----------------------------------------------------------

FABLE_JSON = json.dumps({"result": "검토 본문", "modelUsage": {"claude-fable-5-20260930": {"outputTokens": 9}}})
OPUS_JSON = json.dumps({"result": "검토 본문", "model": "claude-opus-4-8"})


def _detect(field, stdin, requested="claude-fable-5", fallback="claude-opus-4-8"):
    return _run([
        "detect-fallback", "--requested-model", requested,
        "--fallback-model", fallback, "--field", field,
    ], stdin=stdin)


def test_detect_fallback_false_on_requested_model():
    r = _detect("fallback", FABLE_JSON)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.strip() == "false"


def test_detect_fallback_true_on_fallback_model():
    r = _detect("fallback", OPUS_JSON)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.strip() == "true"


def test_detect_actual_model_prefix_match():
    """버전 접미사가 붙은 modelUsage 키도 요청 model 로 판정된다."""
    r = _detect("actual_model", FABLE_JSON)
    assert r.returncode == 0
    assert r.stdout.strip() == "claude-fable-5"


def test_detect_response_text_extracted():
    r = _detect("response_text", FABLE_JSON)
    assert r.returncode == 0
    assert "검토 본문" in r.stdout


def test_detect_response_text_from_content_blocks():
    payload = json.dumps({"content": [{"text": "블록1 "}, {"text": "블록2"}], "model": "claude-fable-5"})
    r = _detect("response_text", payload)
    assert r.returncode == 0
    assert "블록1 블록2" in r.stdout


def test_detect_malformed_json_rejected():
    r = _detect("fallback", "not json at all")
    assert r.returncode == 1
    assert "파싱 실패" in r.stderr


def test_detect_unknown_model_rejected():
    r = _detect("fallback", json.dumps({"result": "x", "model": "claude-sonnet-5"}))
    assert r.returncode == 1
    assert "요청" in r.stderr and "fallback" in r.stderr


def test_detect_missing_model_rejected():
    r = _detect("actual_model", json.dumps({"result": "x"}))
    assert r.returncode == 1
    assert "model" in r.stderr


def test_detect_missing_text_rejected():
    r = _detect("actual_model", json.dumps({"model": "claude-fable-5"}))
    assert r.returncode == 1
    assert "본문" in r.stderr
