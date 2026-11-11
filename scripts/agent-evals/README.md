# Agent instruction evals

Checks whether `AGENTS.md`/`CLAUDE.md`, skills and `REVIEW*.md` change what coding agents actually
do. Every case is a small, real task with deterministic graders. Each case runs in three arms:

| Arm | Instruction files |
|---|---|
| `candidate` | your working tree |
| `base` | `--base` (default `origin/main`) |
| `none` | your working tree with every `AGENTS.md`/`CLAUDE.md` removed; skills stay |

Local only for now. Runs use your Claude Code login and cost money; the default cap is $20.

## Run

```bash
python3 scripts/agent-evals/run_agent_evals.py --dry-run
python3 scripts/agent-evals/run_agent_evals.py --case 'swift-testing-*' --arms candidate,none --reps 3
```

Small cases cost about $0.05–0.15 per run with `--model sonnet` (the default); bigger tasks cost
more. The report prints the pass
rate, cost and turns per case and arm. Transcripts (`.jsonl`) and diffs for every run are saved
next to it, by default under `$TMPDIR/ddg-agent-evals/results/`.

Runs happen in one reusable worktree (`$TMPDIR/ddg-agent-evals/worktree`), with project settings
only: no user `CLAUDE.md`, rules, skills, auto-memory or MCP servers. A run that loads any of
those is marked failed. Builds, tests, `git push`, `gh` and web access are blocked. Remove the
worktree with `git worktree remove --force "$TMPDIR/ddg-agent-evals/worktree"`.

## When you change agent instructions

1. Run the cases that cover what you changed with `--arms candidate,base`, plus the
   `distractor-*` cases.
2. Compare pass rate and cost. A new line should raise a case's pass rate and leave the
   distractors' cost flat.
3. Adding a line? Add a case where agents get it wrong without the line.

To check whether an existing line still earns its place, run its cases with
`--arms candidate,none`. If `none` passes just as often, the line can go.

## Writing a case

Add `cases/<id>.json`:

```json
{
  "covers": ["@Test timeLimit"],
  "prompt": "Add unit tests for ... using Swift Testing. Don't build or run the tests.",
  "max_turns": 25,
  "graders": [
    {"type": "diff_contains", "path": "*Tests.swift", "pattern": "\\.timeLimit\\(\\.minutes\\(1\\)\\)"}
  ]
}
```

- Phrase the prompt like a real request. Don't hint at the rule being tested.
- Keep tasks small, and say "don't build" when building isn't the point.
- This repo is public: no internal task text, names or data in prompts.

Graders: `diff_contains` / `diff_not_contains` (regex over added lines, optional `path` glob),
`file_changed`, `no_changes`, `skill_invoked` / `skill_not_invoked`, `file_read` /
`file_not_read` (regex over paths the agent read), `command_run` (regex over shell commands).
Optional keys: `commit` (the start commit; defaults to `--commit`, i.e. `HEAD`), `timeout_seconds`,
`allowed_tools`.

Tests for the runner: `python3 -m unittest discover -s scripts/agent-evals`
