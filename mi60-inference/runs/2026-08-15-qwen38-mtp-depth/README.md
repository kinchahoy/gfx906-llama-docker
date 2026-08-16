# Qwen3.8 Q8_0 MTP depth comparison

Matched Docker-router A/B on build `10279` (`46b95d97e`), using the production
Qwen3.8 Q8_0 preset, three slots, native KV precision, the same 995-token
engineering prompt, greedy sampling, seed 42, prompt cache disabled, and a
1,024-token output. Each arm was a cold model load and one long screening run.

| MTP depth | Prompt tok/s | Generation tok/s | Accepted / drafted | Draft acceptance |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 202.88 | 30.04 | 582 / 879 | 66.2% |
| 4 | 254.27 | 28.32 | 675 / 1,390 | 48.6% |

Depth 2 generated 6.1% faster. Depth 4 accepted 93 additional draft tokens but
created 511 additional drafts; that extra speculative work outweighed the saved
target evaluations. Prompt rate is shown for completeness but is noisy across
cold one-run screens and is not the decision metric for MTP depth.

Keep `spec-draft-n-max = 2`. This independently confirms the earlier direct CLI
comparison (29.7 versus 28.8 generation tok/s) and preserves the existing
production choice. Re-test only if the prompt/content distribution or MTP
implementation changes.

Exact source prompt:
`/home/raistlin/infer/qwen36-gfx906-results/2026-08-12-quant-selection/qwen36-synthetic-mtp-prompt.txt`
(SHA-256 `e1140a074f250751be8d3b22c85d91e8b1a1236f11a3e0baffa52ecae229b4f7`).
