# Native model evals

Export the run's `EvalReport` JSON and the exact `[EvalCase]` JSON array used for
that run from the app debug screen, saving them as `report.json` and `cases.json`.
Keep both files together: the report contains outputs, while cases contain source
text and requested languages. Use the same case inputs across providers.

The native debug screen in this branch does not yet have eval run/export controls.
Until that integration lands, the app caller must encode the report and cases with
`JSONEncoder` and share both files. ISO 8601 or default encoded dates both work.
This script does not fetch articles or run models on the device.

From the repository root, with Python 3.9+ and an authenticated `claude` CLI:

```sh
python3 scripts/duckai-native-evals/judge.py \
  --report report.json --cases cases.json --output-dir /tmp/native-evals
```

Each run sends its source text and model output to `claude -p <prompt>
--output-format json`. `--judge-cmd 'path/to/claude --model <model>'` changes the
command prefix; arguments are split without a shell. `--judge-timeout` sets the
per-call deadline in seconds. Use `--dry-run` to skip all judge calls and produce
only performance and outcome analysis.

Read `summary.md` for medians by provider/model and task, outcome counts, and mean
quality scores (1 is unacceptable, 5 is excellent). Missing measurements are `—`.
“Where it breaks” lists incomplete, failed, refused, timed-out or low-scoring runs
by source length and language. Selection cases use selection length; suggested
prompts use the app's 2,000-character cap. `results.json` retains each original
record and its scores/reason. Judge errors are recorded and cause exit status 1;
those records are excluded from score means. Other available scores remain useful.

Summaries are expected in the source language, translations in the case's target
language, and suggested prompts in its UI language (English by default). The
judge rates faithfulness, coverage, output language and completeness, plus
relevance and format for suggested prompts. These are judge estimates; inspect
source and output before interpreting differences between models.

`collect_duckai_references()` is a TODO stub: reference collection needs simulator
automation and is not part of this tool yet.
