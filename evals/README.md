# Evals

How good is the inline agent, with which model? This folder is the answer, as numbers. The code is `nvim/lua/agent/eval/`; the
front end is `make eval`.

```sh
make eval MODELS=replay/golden,replay/noop          # free: the harness against its own cassettes
make eval MODELS=claude/haiku FILTER=fix SAMPLES=3  # a live model (spends tokens, capped by MAX_USD=1.00)
make eval MODELS=ollama/qwen2.5-coder:7b SCAFFOLD=0 # the same model bare: no repairs, schema or cascade
make eval MODELS=ollama/qwen2.5-coder:7b PROFILE_OUT=1   # keep what was measured as a capability profile
make eval MODELS=… BASELINE=evals/results/v1.json   # exit 1 if an action × model got worse by more than 10 points
```

Run a model with and without `SCAFFOLD=0` to see what the pipeline adds for it, and with `DECOMPOSE=1|0` to force the chain of single steps on or off:
those differences are the claim of the product. A model that errors three times in a row is given up on (the rest are `skipped`); errors are never counted as
failures. `make eval-table` writes `RESULTS.md` from `baselines/*.json` (publish a run with `EVAL_OUT=evals/baselines/<name>.json`).

## A case

A folder `evals/<action>/<name>/` with a small project and a `case.json` (the contract is at the top of
`nvim/lua/agent/eval/cases.lua`): which file, where the cursor is, the instruction, the diagnostics a language server would
report, and a `check`. Every question in a `check` is answered by code, never by another model:

| key | the result passes when |
|---|---|
| `outside` | the lines around the target are untouched (on by default: scope discipline) |
| `contains` / `absent` | the new target has / has not these substrings |
| `preserves` | every code line the target had is still there, in order (docs: only the comment may change) |
| `findings` + `max_findings` | a finding sits near each expected line, and the model did not flag everything |
| `cmd` | a command run in the case's temp project exits 0 (a script that imports the code and asserts its behaviour) |

A result that changes nothing never passes, except `findings` cases and cases with `"changes": false`.

## Rules for cases

- **Solvable and failable.** `cassettes/<case>/golden.json` is a hand-written good answer; `scripts/test-agent-eval.lua` checks that
  it passes and that a do-nothing answer (`noop`) fails (a `"clean": true` case is the false-positive guard and is the exception).
  A case that everything passes, or nothing does, measures nothing.
- **One thing per case**, and `notes` says what a weak model gets wrong there.
- **`split`**: `dev` (default) is what prompts are tuned against; `holdout` is only looked at. If a change helps dev and not holdout,
  it learned the cases.
- Prefer a `cmd` that runs the behaviour over a `contains` that matches text.

## Cassettes

`EVAL_RECORD=1` (`make eval RECORD=1`) saves every live answer in `cassettes/<case>/<backend_model>.json`. The `replay` backend plays
them back through the whole pipeline, offline and identically every time, so a change to a parser, a presenter or a judge is
tested without spending anything.

## Results

`evals/results/last.json` is git-ignored (every run overwrites it). To publish a run, pass `MD=docs/…/table.md` for the Markdown
table and commit the JSON you want as a baseline under another name.
