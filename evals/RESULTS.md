# Eval results

Measured by `make eval` on the cases in this folder, from the baselines in `evals/baselines/`. Regenerate with `make eval-table`.
pass@1 = the share of single tries that passed; pass@k = the share of cases with at least one passing sample; usable = the output
could be read at all; tries = calls per sample (repairs and steps included); per pass = what one passing answer cost.

## claude-haiku

31 cases × up to 3 sample(s) · claude/haiku

| action | model | cases | samples | pass@1 | pass@k | flaky | usable | tries | tokens in→out | cost | per pass | time |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| docs | claude/haiku | 5 | 15 | 93% | 100% | 1 | 100% | 1.0 | 1086→359 | $0.0043 | $0.0003 | 7.4s |
| fix | claude/haiku | 8 | 24 | 100% | 100% | 0 | 100% | 1.0 | 1166→59 | $0.0035 | $0.0001 | 5.0s |
| refactor | claude/haiku | 7 | 21 | 100% | 100% | 0 | 100% | 1.0 | 1035→134 | $0.0036 | $0.0002 | 4.1s |
| review | claude/haiku | 11 | 33 | 100% | 100% | 0 | 100% | 1.0 | 1084→150 | $0.0061 | $0.0002 | 5.1s |

Failed:

- docs/py-raises · claude/haiku · preserves

## claude-sonnet

31 cases × up to 1 sample(s) · claude/sonnet

| action | model | cases | samples | pass@1 | pass@k | usable | tries | tokens in→out | cost | per pass | time |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| docs | claude/sonnet | 5 | 5 | 100% | 100% | 100% | 1.0 | 1088→205 | $0.0212 | $0.0042 | 8.4s |
| fix | claude/sonnet | 8 | 8 | 100% | 100% | 100% | 1.0 | 1168→18 | $0.0201 | $0.0025 | 4.3s |
| refactor | claude/sonnet | 7 | 7 | 100% | 100% | 100% | 1.0 | 1037→59 | $0.0187 | $0.0027 | 4.6s |
| review | claude/sonnet | 11 | 11 | 100% | 100% | 100% | 1.0 | 1086→76 | $0.0323 | $0.0029 | 5.4s |

