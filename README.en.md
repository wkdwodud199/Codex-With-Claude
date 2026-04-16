# Codex-With-Claude

> English | **[한국어](./README.md)**

A collaborative workspace where Codex designs and Claude implements.

## Overview

This repository creates a repeatable **Codex (Designer) → Claude (Implementer)** workflow.

- Codex writes a design in `design.md`
- Claude reads that document and implements accordingly
- Incomplete design documents are automatically blocked from implementation

## Structure

```
├── CLAUDE.md                  # Claude operating rules
├── AGENT.md                   # Shared agent protocol + state transitions
├── collab.md                  # v2 review loop placeholder
├── kb/                        # Knowledge base (local markdown vault)
│   ├── index/                 # Status board, table of contents
│   ├── concepts/              # Architecture, design principles
│   ├── tasks/<task-id>/       # Per-task design & implementation docs
│   └── artifacts/             # Output summaries
├── runtime/                   # Scripts (Bash + PowerShell)
│   ├── codex-design.sh/.ps1   # Request Codex design + post-validation
│   └── claude-implement.sh/.ps1 # Design validation + implementation guide
└── templates/                 # Document templates
```

## Usage

### Step 1: Request design from Codex

```powershell
# PowerShell
./runtime/codex-design.ps1 task-002 "Design user auth module"

# Bash
./runtime/codex-design.sh task-002 "Design user auth module"
```

### Step 2: Request implementation from Claude

```powershell
# PowerShell
./runtime/claude-implement.ps1 task-002

# Bash
./runtime/claude-implement.sh task-002
```

## Design Document Validation

Both `claude-implement` and `codex-design` perform identical validation:

| Check | Blocked when |
|-------|-------------|
| 7 required sections | Any missing |
| Status | Not `ready` or `done` |
| Placeholders | Any of 8 template placeholders remain |
| Meta fields | Inputs/Outputs/Next step missing or empty |
| Empty content | Tables or checkboxes still at default |

## Document State Transitions

```
draft → ready → in-progress → done
                                ↓
                             blocked
```

| State | Meaning |
|-------|---------|
| `draft` | Template or incomplete |
| `ready` | Design complete, ready for implementation |
| `in-progress` | Implementation underway |
| `done` | Completed |
| `blocked` | Blocked |

## Environment

- **Windows**: PowerShell `.ps1` scripts (UTF-8 BOM, calls `codex.cmd`)
- **macOS/Linux**: Bash `.sh` scripts
- **Knowledge base**: Local markdown files (viewable with Obsidian, etc.)

## Roadmap

- **v1 (current)**: Codex design → Claude implementation loop
- **v2**: Codex review via `collab.md` → Claude re-implementation loop
- **v2+**: External backend adapters (Notion, etc.)

## License

MIT
