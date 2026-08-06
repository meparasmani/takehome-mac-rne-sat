# Submission — mac_rne_sat takehome

Email your liaison with: (1) this repo link, (2) the HUD results link,
(3) the written analysis (Sections A–C below).

---

## 1. GitHub repo

https://github.com/meparasmani/takehome-mac-rne-sat

| Branch | What to look at |
|--------|-----------------|
| `mac_rne_sat_baseline` | Agent-facing `docs/spec.md` + empty skeleton |
| `mac_rne_sat_test` | Hidden cocotb grader (`tests/test_mac_rne_sat.py`) |
| `mac_rne_sat_golden` | Correct RTL (`sources/mac_rne_sat.sv`), this file, worklog |

---

## 2. HUD results (target band 50–80%)

**Final result: 7 / 10 = 70%**

https://hud.ai/jobs/59796d06db73464385f0cb0b149d9baa

Model: Claude Sonnet 4.5 · `group-size 10` · `max-steps 100`

### Iteration history

| Spec version | Pass rate | Job |
|--------------|-----------|-----|
| Original (upstream) | ~10% (20 runs) | https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces |
| v1 (heavy hints) | 10/10 = 100% | https://hud.ai/jobs/840542d04dee4aab801f6610b4654884 |
| v2 (softened, but still banned `rd_d` explicitly) | 10/10 = 100% | https://hud.ai/jobs/3121f29df79c417d906ddbf2ba7b7d58 |
| **v3 (final)** | **7/10 = 70%** | https://hud.ai/jobs/59796d06db73464385f0cb0b149d9baa |

---

## 3. Written analysis

### A. Root Cause Analysis (one failing original run)

**Source.** A failing rollout from the original ~10% evaluation
(https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces).
The grade junit showed an immediate directed-corner failure:

```text
[cyc 2] RNE +2.5 -> 2 (even quotient stays) res_valid mismatch: exp 1 got 0
```

So grading never even reached deep overflow / sticky-flag corners; the
implementation failed on **cycle-exact `res_valid` timing** on the first real
readout.

#### What the agent wrote (bug)

The agent built a **two-stage readout pipeline**:

```systemverilog
// Stage 1 — on the edge where rd is sampled:
always_ff @(posedge clk) begin
    if (rd) snapshot <= acc;
    rd_reg <= rd;                 // delay flop #1
end

// Stage 2 — one edge later:
always_ff @(posedge clk) begin
    res_valid <= rd_reg;          // delay flop #2  ← TOO LATE
    if (rd_reg) res <= saturated;
end
```

#### What the testbench / golden expect

The cocotb model advances one clock as:

1. Drive `rd=1` before/at the rising edge.
2. On that rising edge, registered outputs update.
3. On the falling edge of the **same** cycle, assert `res_valid == 1`.

Correct hardware is a **single** register stage:

```systemverilog
always_ff @(posedge clk) begin
    res_valid <= rd;              // exactly one register of latency
    if (rd) res <= rres;          // rres from pre-update acc snapshot
    // then update acc from clr/en
end
```

#### Concrete timing example

Suppose `acc` already holds `640` (from a prior `clr+en` load of `64×10`).
The directed test then asserts `rd=1` for one cycle.

| Time | Input `rd` | Correct `res_valid` | Agent's `res_valid` | Correct `res` | Agent's `res` |
|------|------------|---------------------|---------------------|---------------|---------------|
| Rising edge T (sample `rd=1`) | 1 | becomes **1** after this edge | still **0** (`rd_reg` just captured) | becomes **2** | unchanged |
| Falling edge T (TB check) | 1 | **1** ✓ | **0** ✗ fail | **2** | old value |
| Rising edge T+1 | 0 | 0 | becomes 1 (too late) | holds 2 | becomes 2 |

Numerically the agent often computed RNE correctly (`640 → q=2, r=128,
even → stay 2`). The failure was latency, not rounding math.

#### Why the agent went wrong

The original spec said `res_valid` is “exactly one cycle after each `rd`”
and described outputs appearing in cycle *t+1*. The agent interpreted that
as “add a pipeline register, *then* register the outputs,” counting the
narrative cycle and the hardware register as two delays. In RTL + this TB,
registering sampled `rd` into `res_valid` **already is** the one cycle of
latency.

---

### B. Faulty Assumptions / Missed Insights

Beyond the latency bug on the examined run, the same original-failure
landscape (hidden TB tags FM-1…FM-11) shows recurring misconceptions:

#### B1. Register latency miscount (primary, this run)

**Assumption:** “One cycle after” needs an explicit extra flop.
**Reality:** `res_valid <= rd` is already one flip-flop of delay.

#### B2. Spec prose vs. cocotb sampling

**Assumption:** Cycle *t* with `rd`, results only at some abstract *t+1*
that requires an idle cycle in between.
**Reality:** TB samples after the sampling edge; there is no spare dead
cycle for a second pipeline stage.

#### B3. Underspecified self-tests

Agents often write a unit test that loads a product and prints `res` after
several clocks, but do not lockstep-check `res_valid` on the *immediate*
post-`rd` edge. Rounding can look “correct” in a waveform while grading
still fails.

#### B4. Negative remainder / floor vs. trunc (FM-1/2)

For snapshot `-384`:

- Floor divide by 256: `q = -2`, remainder `r = 128` (non-negative).
- Tie, `q` even → `res = -2`.

Agents that use truncating signed `/` toward zero get `q = -1` and a signed
remainder, then RNE ties go wrong (e.g. `-640` should become `-2`, not
`-3`).

**Hardware form that matches the reference model:**

```text
q = snapshot >>> 8          // arithmetic right shift = floor(/256)
r = snapshot[7:0]           // always 0..255
```

Example walk-through for `-640` (`0xFFFFFD80` in wider two's complement):

```text
>>> 8  →  q = -3  (odd)
low 8  →  r = 0x80 = 128 (tie)
odd tie → q+1 = -2
```

#### B5. Same-cycle control priority (FM-4/5/6)

Agents sometimes:

- On `clr+en`: clear to `0` instead of loading `p` alone.
- On `rd+en`: include this cycle's product in the snapshot.
- On `rd+clr`: return 0 instead of the pre-clear accumulator.

Example (`acc=512`, same cycle `rd=1, en=1, a=64, b=8` → product 512):

| Part | Correct |
|------|---------|
| Snapshot for this read | **512** → `res=2` |
| Next `acc` | 512+512=**1024** |
| Next read | **1024** → `res=4` |

If the agent snapshots post-update `acc`, the first read wrongly returns 4.

#### B6. Round-then-saturate and exact −32768 (FM-7/10)

Rounding can create a value outside 16-bit range that then clamps:

```text
snapshot = 0x7FFF80   // +32767.5 in Q8
q = 32767 (odd), r = 128 → round to 32768 → saturate to 32767, ovf=1
```

Conversely, exact rounded `-32768` is **in range** — `ovf` must stay 0
(FM-10: `acc = -2^23`).

#### B7. Sticky `ovf` vs. same-cycle `clr` (FM-8/9)

Correct combined update:

```text
ovf_next = (clr ? 0 : ovf) | (rd && sat)
```

So saturating `rd` + `clr` in one cycle still leaves `ovf=1` (set wins).
Agents that write `if (clr) ovf<=0; else if (rd&&sat) ovf<=1` with wrong
order / wrong cycle alignment clear the flag when they should not.

---

### C. Prompt Modifications (what we changed and why)

We only changed `docs/spec.md` (and kept the hidden testbench behavior).
No golden RTL was pasted into the agent-facing prompt.

#### C1. Single-register-stage readout guidance → addresses A / B1 / B2

Added that grading is cycle-exact and the readout path must stay a
**single** register stage from sampled controls (`res` / `res_valid` /
`ovf` updated on the same edge that samples `rd`). Extra pipeline stages
fail even if rounding math is right.

This directly targets the observed `rd → rd_reg → res_valid` bug without
handing over golden code.

#### C2. Hardware RNE formulation (`>>>` + low byte) → addresses B4

Original prose used `floor(snapshot/256)` and `0 ≤ r ≤ 255`, which is
correct but easy for agents to implement with truncating `/` and `%`.
We added the equivalent hardware form and an explicit warning against
truncating-toward-zero on negatives.

#### C3. Extra negative tie example (−640 → −2) → addresses B4

Original examples included `−384 → −2` (even tie stays) but not an odd
negative tie. We added:

| snapshot | q | r | res | note |
|----------|---|---|-----|------|
| −640 | −3 | 128 | −2 | tie, q odd → `q+1` |

#### C4. Exact −32768 is not overflow → addresses B6 / FM-10

One sentence: rounded exact `-32768` is in range and must not assert `ovf`.

#### C5. Calibration: why not the stronger draft?

| Draft | Content | Pass rate |
|-------|---------|-----------|
| v1 | Full numbered per-cycle algorithm, `res_valid <= rd`, `ovf <= (clr?0:ovf)\|(rd&&sat)`, explicit “do not do `rd_d<=rd; res_valid<=rd_d`”, self-check checklist | **100%** — too easy |
| v2 | Removed formulas/checklist but kept the explicit `rd_d` anti-pattern | **100%** — still too easy |
| **v3 (shipped)** | Soft “single register stage” wording + `>>>` + −640 example + −32768 note; no assignment-level pseudocode | **70%** — in band |

Lesson: for this model, naming the exact anti-pattern or pasting
assignment-level updates collapses remaining difficulty. Soft structural
guidance plus better RNE mechanics was enough to lift ~10% → ~70% without
solving the problem for the agent.

#### C6. What we deliberately left for the agent

We did **not** simplify or remove:

- Same-cycle `clr`/`en`/`rd` snapshot rules (still require careful NBA
  ordering).
- Sticky `ovf` set-over-clear priority (still easy to get wrong).
- Round-then-saturate carry into clamp (still need FM-7 style care).

Those remaining soft spots explain why 3/10 runs still fail at 70%.

---

## Quick reference for the liaison

- **Repo:** https://github.com/meparasmani/takehome-mac-rne-sat  
- **Final HUD (70%):** https://hud.ai/jobs/59796d06db73464385f0cb0b149d9baa  
- **Original hard baseline (~10%):** https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces  
- **DIY notebook:** `TAKEHOME_WORKLOG.md` on `mac_rne_sat_golden`
