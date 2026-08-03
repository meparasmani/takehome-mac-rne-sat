# MAC RNE-SAT Takehome — Worklog

Living notebook of everything we did: setup → golden RTL → analysis → spec changes → HUD evals → submission writeup.

## Setup

- Date: 2026-08-03
- GitHub user: `meparasmani`
- Problem fork: https://github.com/meparasmani/takehome-mac-rne-sat (public)
- Framework: `/home/paras_ubuntu/hud_eval` (clone of `phinitylabs/verilog-coding-template`)
- Problem clone: `/home/paras_ubuntu/takehome-mac-rne-sat`
- Branches checked out locally:
  - `mac_rne_sat_baseline` (what the agent sees)
  - `mac_rne_sat_test` (hidden cocotb testbench)
  - `mac_rne_sat_golden` (our correct RTL)
- Tools verified: git, uv, docker, iverilog
- API keys saved via `uv run hud set KEY=VALUE` to `~/.hud/.env`

## Golden RTL

- Status: **done**
- Commit on `mac_rne_sat_golden`: `13e9fd5` — Update golden RTL and add worklog
- Local pytest with golden swapped into test branch: **PASSED**
- Baseline skeleton on test branch: **FAILED** as expected (`res_valid` stuck 0)

### What the golden does (plain English)

1. Keep a 28-bit signed accumulator.
2. On each clock: if `rd`, snapshot current `acc` *before* applying `en`/`clr`.
3. Round snapshot by dropping 8 LSBs with round-half-to-even (`>>> 8` + low byte).
4. Saturate rounded value to 16-bit; update `res`/`res_valid`/`ovf` that same register edge (`res_valid <= rd`).
5. Then update `acc` (`clr&en → product`, `clr → 0`, `en → acc+product`).

## Local tests

- Golden vs hidden TB: PASS
- Baseline vs hidden TB: FAIL (expected)

## Original-20 analysis (HUD job 5b12be34…)

- Link: https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces
- Baseline pass rate ~10%

### Concrete failing run (agent_patch from HUD grade)

**What went wrong (the bug):** The agent built a **two-stage readout pipeline**:

```systemverilog
// cycle of rd: snapshot <= acc; rd_reg <= rd;
// NEXT cycle:  res_valid <= rd_reg; if (rd_reg) res <= saturated;
```

So when the testbench asserts `rd` and checks after that rising edge, `res_valid` is still 0.
Failure log: `[cyc 2] ... res_valid mismatch: exp 1 got 0`.

**Why it went wrong:** The agent over-literalized “`res_valid` is exactly one cycle after each `rd`” and added an *extra* delay flop *on top of* the output register. In cycle-exact terms, `res_valid <= rd` already *is* one register of latency; `rd_d <= rd; res_valid <= rd_d` is two.

**What it got right:** clr/en priority, snapshot before acc update (conceptually), RNE via `>>>` and low 8 bits, round-then-sat structure, sticky ovf with set-over-clr intent.

### Broader failure modes (from hidden TB FM tags)

| Tag | Mistake |
|-----|---------|
| FM-1/2 | Wrong RNE / broken negative remainder |
| FM-3 | Round every accumulate instead of at readout |
| FM-4/5/6 | Wrong same-cycle clr/en/rd ordering |
| FM-7/10 | Saturate-before-round; false ovf at exact -32768 |
| FM-8/9 | ovf not sticky; clr masks sat set |
| FM-11 | res not held / res_valid wrong width/latency |

## Spec changes log

| Date | Branch commit | What changed | Why |
|------|---------------|--------------|-----|
| 2026-08-03 | (pending push) | Added §4 per-cycle algorithm; latency anti-pattern (`rd_d`); `>>>`/low-byte RNE; ovf one-liner; extra examples; self-check list | Fix double-pipeline bug + other FMs without pasting full golden RTL |

## HUD eval iterations

| Run | Job URL | Pass rate | Notes / next fix |
|-----|---------|-----------|------------------|
| | | | |

## Final submission draft (A / B / C)

### A. Root Cause Analysis

On one failing original run, grading reported `res_valid mismatch: exp 1 got 0` on the first directed readout. The agent’s final RTL delayed `res_valid` through an intermediate `rd_reg`, producing **two** cycles of latency from sampled `rd` instead of one. The agent believed “one cycle after `rd`” required an explicit pipeline stage *plus* registered outputs.

### B. Faulty Assumptions / Missed Insights

1. Misread register latency: registering `rd` into `res_valid` already accounts for “next cycle” in hardware / TB timing.
2. Spec prose (“cycle t+1”) invited an off-by-one mental model vs. cocotb’s sample-after-edge checks.
3. Agents often self-test functional rounding but under-test **cycle-exact** `res_valid` timing.

### C. Prompt Modifications

See Spec changes log. Main lever: §4 authoritative per-cycle order + explicit ban on `rd_d <= rd; res_valid <= rd_d`, plus clearer RNE/`ovf` formulas so secondary FMs are less likely once latency is fixed.
