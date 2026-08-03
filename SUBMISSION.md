# Submission — mac_rne_sat takehome

Email your liaison with the three items below.

## 1. GitHub repo

https://github.com/meparasmani/takehome-mac-rne-sat

- Golden RTL: branch `mac_rne_sat_golden` → `sources/mac_rne_sat.sv`
- Final agent-facing spec: branch `mac_rne_sat_baseline` → `docs/spec.md`
- Full notebook / analysis: branch `mac_rne_sat_golden` → `TAKEHOME_WORKLOG.md`

## 2. HUD results (50–80% band)

https://hud.ai/jobs/59796d06db73464385f0cb0b149d9baa

- **7 / 10 pass (70%)** with Claude Sonnet 4.5
- Earlier iterations (too easy at 100%):
  - https://hud.ai/jobs/840542d04dee4aab801f6610b4654884
  - https://hud.ai/jobs/3121f29df79c417d906ddbf2ba7b7d58

## 3. Written analysis (A / B / C)

### A. Root Cause Analysis

On one failing run from the original ~10% job
(https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces),
grading failed on the first directed readout with:

`res_valid mismatch: exp 1 got 0`

The agent’s final RTL used a **two-stage readout pipeline** (`rd` → `rd_reg` →
`res_valid`). That created **two** cycles of latency from sampled `rd`. The
testbench expects a **single** register stage: after the rising edge that
samples `rd=1`, `res_valid` must already be 1. Much of the numeric MAC / RNE
logic looked reasonable; the run failed on **cycle-exact timing**.

### B. Faulty Assumptions / Missed Insights

1. Miscounted register latency — registering `rd` into `res_valid` already *is*
   “one cycle after.”
2. Spec prose (“cycle t+1”) invited an off-by-one vs. cocotb’s after-edge checks.
3. Self-tests often checked rounding numbers but not `res_valid` timing.
4. Other known trap modes: negative RNE remainder, same-cycle `rd`+`en`/`clr`,
   sticky `ovf` set-over-clear, exact −32768 not overflow.

### C. Prompt Modifications

Final `docs/spec.md` (pushed to baseline/test/golden):

1. Ask for a **single register stage** on the readout path (addresses double
   pipeline without pasting golden code).
2. Give hardware RNE form: `q = snapshot >>> 8`, `r = snapshot[7:0]`.
3. Add negative tie example (−640 → −2).
4. Note exact rounded −32768 must not set `ovf`.

We first tried stronger hints (assignment-level formulas / explicit `rd_d` ban)
and got **100%** pass rate — too easy. Softening to the wording above landed at
**70%**.
