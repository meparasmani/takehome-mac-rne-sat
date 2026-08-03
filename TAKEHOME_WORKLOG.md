# MAC RNE-SAT Takehome — Worklog

Living notebook: setup → golden RTL → analysis → spec changes → HUD evals → submission writeup.

**Keep this file on `mac_rne_sat_golden` only** (not baseline/test — those are agent-visible).

## Setup

- Date: 2026-08-03
- GitHub: https://github.com/meparasmani/takehome-mac-rne-sat (public fork)
- Framework: `/home/paras_ubuntu/hud_eval`
- Problem clone: `/home/paras_ubuntu/takehome-mac-rne-sat`
- Branches: `mac_rne_sat_baseline`, `mac_rne_sat_test`, `mac_rne_sat_golden`
- Tools: git, uv, docker, iverilog
- API keys via `uv run hud set KEY=VALUE` → `~/.hud/.env`

## Golden RTL

- Status: **done**
- Commit: `13e9fd5` on `mac_rne_sat_golden`
- Local pytest (golden into test branch): **PASSED**
- Baseline skeleton: **FAILED** as expected
- Image validation (`imagectl3 -v`): all 6 patch checks **PASSED**

### Plain-English golden behavior

1. 28-bit signed accumulator.
2. On each clock with `rd`: snapshot current `acc` before applying `en`/`clr`.
3. Round snapshot: `q = snap >>> 8`, `r = snap[7:0]`, round-half-to-even; then saturate to 16-bit.
4. Update `res`/`res_valid`/`ovf` on that same edge (`res_valid` registers `rd` — one register of latency only).
5. Then update `acc` (`clr&en→p`, `clr→0`, `en→acc+p`).

## Original-20 analysis (~10% pass)

- Job: https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces

### Concrete failing run (from grading `agent_patch`)

**Bug:** Two-stage readout pipeline:

```systemverilog
// edge with rd: snapshot <= acc; rd_reg <= rd;
// next edge:    res_valid <= rd_reg; if (rd_reg) res <= saturated;
```

Test failed immediately: `res_valid mismatch: exp 1 got 0` on the first directed readout.

**Cause:** Over-literal reading of “one cycle after `rd`.” The agent added an extra delay flop *plus* registered outputs → two cycles of latency. Correct is a **single** register stage (`res_valid` updated from sampled `rd` on that edge).

**What was already right:** clr/en priority, pre-update snapshot idea, RNE via `>>>`/low 8 bits, round-then-sat, sticky ovf intent.

### Other common failure modes (hidden TB FM-1…FM-11)

Wrong RNE / negatives; rounding during accumulate; wrong same-cycle clr/en/rd; saturate-before-round; ovf stickiness / clr masking set; exact -32768 false ovf; `res` hold / `res_valid` width.

## Spec changes log

| Version | Commit (baseline) | Change | Result |
|---------|-------------------|--------|--------|
| v1 heavy | `27e7d0f` | Full per-cycle algo, `res_valid<=rd`, `ovf` one-liner, ban `rd_d`, self-checks | Eval1: **100%** (too easy) |
| v2 soft | `e61df23` | Removed formulas/self-checks; kept explicit `rd_d` ban | Eval2: **100%** (still too easy) |
| v3 target | `a654a1b` | Soft “single register stage” wording; keep `>>>`/extra negative example; no `rd_d` example | Eval3: **70%** ✓ |

Also removed `TAKEHOME_WORKLOG.md` from baseline/test so agents cannot read analysis (`55bb299`).

## HUD eval iterations

| Run | Job URL | Pass rate | Notes |
|-----|---------|-----------|-------|
| 1 | https://hud.ai/jobs/840542d04dee4aab801f6610b4654884 | 10/10 = 100% | v1 too helpful |
| 2 | https://hud.ai/jobs/3121f29df79c417d906ddbf2ba7b7d58 | 10/10 = 100% | v2 still too helpful |
| 3 | https://hud.ai/jobs/59796d06db73464385f0cb0b149d9baa | 7/10 = **70%** | In target band 50–80% |

## Final submission draft (A / B / C)

### A. Root Cause Analysis

On one failing original run, grading reported `res_valid mismatch: exp 1 got 0` on the first directed readout (“RNE +2.5 → 2”). The agent’s final RTL delayed `res_valid` through an intermediate `rd_reg`, producing **two** cycles of latency from sampled `rd` instead of one. Numerically, much of the MAC/RNE logic looked reasonable; the implementation was rejected on **cycle-exact timing** before later corners were fully exercised.

### B. Faulty Assumptions / Missed Insights

1. **Register latency miscount:** Registering sampled `rd` into `res_valid` already *is* one cycle of latency relative to the input. Adding another pipeline register doubles it.
2. **Prose vs. TB timing:** Spec language “cycle *t+1*” invited an off-by-one mental model vs. cocotb checking outputs after the sampling edge.
3. **Self-test gap:** Agents often validate rounding numbers but under-test whether `res_valid` asserts on the same edge the TB expects.
4. Secondary risks: negative remainder/`floor` vs truncating divide; same-cycle `rd`+`clr`/`en`; sticky `ovf` set-over-clear.

### C. Prompt Modifications

Final `docs/spec.md` (v3) changes vs. original, and why:

1. **Single-register-stage guidance** on the readout path — addresses the double-pipeline failure mode without pasting RTL or naming the `rd_d` anti-pattern (that version hit 100%).
2. **Hardware RNE form** (`>>> 8` + low 8 bits) and warning against truncating-toward-zero — helps FM-1/2 negative rounding.
3. **Extra negative tie example** (−640 → −2) — reinforces odd-quotient tie toward +∞ on negatives.
4. **Clarify exact −32768 is not overflow** — helps FM-10.
5. Left ovf/clr priority and snapshot-before-update largely as original prose (still some natural failure rate).

We deliberately **removed** assignment-level pseudocode (`res_valid <= rd`, `ovf <= …`) and the explicit `rd_d` ban after seeing 100% pass rates, to land in the 50–80% band.

## Submission checklist

1. **Repo:** https://github.com/meparasmani/takehome-mac-rne-sat
2. **HUD results (target band):** https://hud.ai/jobs/59796d06db73464385f0cb0b149d9baa (70%)
3. **Analysis:** sections A/B/C above
4. Email liaison with those three items
