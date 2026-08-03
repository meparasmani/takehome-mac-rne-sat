# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

## 2. Interface

| Port        | Dir | Type              | Description                                      |
|-------------|-----|-------------------|--------------------------------------------------|
| `clk`       | in  | `logic`           | Clock. All sequential behavior on the rising edge. |
| `rst`       | in  | `logic`           | Synchronous, active-high reset.                  |
| `en`        | in  | `logic`           | Accumulate `a*b` this cycle.                     |
| `clr`       | in  | `logic`           | Clear the accumulator this cycle.                |
| `rd`        | in  | `logic`           | Request a readout snapshot this cycle.           |
| `a`         | in  | `logic signed [7:0]`  | Multiplicand.                                |
| `b`         | in  | `logic signed [7:0]`  | Multiplier.                                  |
| `res`       | out | `logic signed [15:0]` | Rounded + saturated readout result (registered). |
| `res_valid` | out | `logic`           | One-cycle pulse on the registered outputs driven by sampled `rd`. |
| `ovf`       | out | `logic`           | Sticky saturation flag (registered).             |

All control inputs (`en`, `clr`, `rd`) are sampled on every rising edge and
may be asserted in any combination. `a` and `b` are consumed only on cycles
where the accumulator takes a product (see §3).

## 3. Accumulator

The internal accumulator `acc` is a 28-bit signed two's-complement register.
The product `p = a * b` is a signed 16-bit value, sign-extended to 28 bits
before use.

Accumulator update at each rising edge (with `rst = 0`):

| `clr` | `en` | `acc` next value |
|-------|------|------------------|
| 0     | 0    | `acc` (hold)     |
| 0     | 1    | `acc + p`        |
| 1     | 0    | `0`              |
| 1     | 1    | `p` — clear-then-accumulate: the accumulator becomes the new product alone |

The grading testbench guarantees the accumulator value never exceeds the
signed 28-bit range, so accumulator wrap behavior is unspecified and need
not be handled.

## 4. Per-cycle algorithm (authoritative)

On every rising edge with `rst = 0`, perform the following **in this order**.
Implementing an *extra* pipeline stage beyond the single register update of
`res` / `res_valid` / `ovf` will fail cycle-exact grading.

1. **Snapshot.** Let `snap = acc` (the value held entering this edge —
   **before** this cycle's accumulator write). If you update `acc` with
   non-blocking assignments in the same `always_ff`, reading `acc` on the
   RHS already sees the pre-update value; you do **not** need a separate
   pipeline register for the snapshot.

2. **Round then saturate `snap` → `rres`, and compute `sat`.**
   (See §5. Do this every cycle; only apply to outputs when `rd` is 1.)

3. **Update registered outputs from this cycle's sampled controls:**
   - `res_valid <= rd`  (exactly one register of latency from sampled `rd`).
   - If `rd`: `res <= rres`; otherwise `res` holds.
   - Update `ovf` as in §6, using **this** cycle's `rd`, `sat`, and `clr`.

4. **Update the accumulator** from this cycle's `clr`/`en`/`p` (table in §3).

**Latency clarification (common failure):** when `rd` is sampled high on a
rising edge, `res_valid` and (if `rd`) the new `res` must be visible after
**that same** edge's register update — i.e. checked in that cycle by a
testbench sampling after the edge. Do **not** add a second delay flop such
as `rd_d <= rd; res_valid <= rd_d` (that is two cycles of latency and is
wrong). The phrase “one cycle after `rd`” means “after the one register that
retimes the sampled `rd`,” not “two pipeline stages.”

Same-cycle notes:

- `rd` + `en`: snapshot excludes this cycle's product; `acc` still becomes
  `acc + p` after the snapshot.
- `rd` + `clr`: snapshot is the pre-clear value; `acc` clears after.
- `rd` + `clr` + `en`: snapshot is pre-update `acc`; `acc` becomes `p`.

## 5. Rounding and saturation

Rounding happens **only on the readout path** (from `snap`), never during
accumulation.

**Hardware-friendly form of floor-divide by 256 (including negatives):**

- `q = snap >>> 8`   (arithmetic right shift — this *is* `floor(snap / 256)`)
- `r = snap[7:0]`    (this *is* the non-negative remainder `0…255`)

Do **not** use truncating signed division toward zero; that breaks negative
snapshots.

Round-half-to-even:

- `r < 128` → keep `q`
- `r > 128` → `q + 1`
- `r == 128` (tie) → keep `q` if `q` is even (`q[0]==0`), else `q + 1`

Then **saturate the rounded value** to signed 16-bit `[-32768, +32767]`.
Order matters: rounding may push past the 16-bit range (e.g. `+32767.5`
rounds to `32768`, then saturates to `32767` and sets `ovf`).
Exact rounded result `-32768` is **in range** — do **not** set `ovf`.

Worked examples (`snapshot → res`):

| snapshot | q  | r   | res | note                      |
|----------|----|-----|-----|---------------------------|
| 640      | 2  | 128 | 2   | tie, q even → stays       |
| 896      | 3  | 128 | 4   | tie, q odd → rounds up    |
| −384     | −2 | 128 | −2  | tie, q even → stays       |
| −640     | −3 | 128 | −2  | tie, q odd → `q+1`        |
| 704      | 2  | 192 | 3   | `r > 128` → round up      |
| −704     | −3 | 64  | −3  | `r < 128` → stay          |

## 6. Overflow flag

`ovf` is a registered, sticky flag updated in the **same** register edge as
`res_valid` (step 3 of §4):

- **Set** when `rd && sat` (this cycle's rounded snapshot needs clamping).
- **Clear** when `clr` is asserted and there is **no** saturating readout
  this cycle.
- Combined update that matches the rules:

  `ovf <= (clr ? 0 : ovf) | (rd && sat)`

  So a saturating readout coinciding with `clr` still leaves `ovf = 1`
  (set wins). A non-saturating readout leaves `ovf` unchanged except for
  any `clr`.

## 7. Reset

`rst` is synchronous and active-high, and overrides `en`/`clr`/`rd`. On a
rising edge with `rst = 1`: `acc`, `res`, `res_valid`, and `ovf` all clear
to 0.

## 8. Suggested self-checks

Before finishing, write a small testbench that covers at least:

1. RNE ties: snapshots 640 → 2, 896 → 4, −384 → −2, −640 → −2.
2. Same-cycle `rd`+`en`: snapshot excludes the new product.
3. Same-cycle `rd`+`clr`: snapshot is pre-clear; next readout is 0.
4. `clr`+`en`: accumulator becomes `p` alone (not 0, not old+`p`).
5. `res_valid` is high for exactly one cycle per `rd`, on the immediate
   register update — not one cycle later than that.
6. Sticky `ovf` after a saturating readout; `clr` clears it; saturating
   `rd`+`clr` still sets `ovf`.

## 9. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain. No latches.
