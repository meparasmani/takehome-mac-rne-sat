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
| `res_valid` | out | `logic`           | One-cycle pulse produced by registering sampled `rd`. |
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

## 4. Readout path and timing

Asserting `rd` requests a snapshot readout of the accumulator.

**Snapshot value.** The snapshot is the accumulator value as it stood
**before** any accumulator update (`en`/`clr`) on that same rising edge.
An `en` asserted with `rd` still updates the accumulator normally; it is
simply not part of that snapshot. A `clr` with `rd` clears after the
snapshot (the readout returns the pre-clear value).

**Registered-output latency (important).** `res`, `res_valid`, and `ovf`
are ordinary registers updated from the controls sampled on the current
edge. That single register stage *is* the “one cycle” of latency: after
the rising edge where `rd` is sampled high, the updated `res_valid` (and
updated `res` when `rd` is high) are already present for checks in that
cycle. Do **not** insert an *additional* delay flop on `rd` before driving
`res_valid` (for example capturing `rd` into `rd_d` and then registering
`rd_d` into `res_valid`). That creates two cycles of latency and is wrong.

Between readouts, `res` **holds** its last value. `res_valid` is high for
exactly one cycle per accepted `rd`. Back-to-back `rd` cycles are allowed.

**Rounding — round-half-to-even at the 8 LSBs.** Rounding is applied only
on the readout snapshot, never during accumulation. Prefer computing:

- `q` = arithmetic right shift of the snapshot by 8 (`>>> 8`), which is
  `floor(snapshot / 256)` for two's-complement values;
- `r` = the low 8 bits of the snapshot (a non-negative remainder `0…255`).

Then:

- `r < 128` → keep `q`;
- `r > 128` → `q + 1`;
- on a tie (`r == 128`): `q` if `q` is even, else `q + 1`.

Do not use truncating-toward-zero signed division for negative snapshots.

**Saturation — applied after rounding.** Clamp the rounded value to the
signed 16-bit range `[−32768, +32767]`. Rounding may carry past that range
first (e.g. `+32767.5` → round to `32768` → saturate to `32767`). Exact
rounded result `−32768` is in range and must **not** set `ovf`.

Worked examples (`snapshot → res`):

| snapshot | q  | r   | res | note                      |
|----------|----|-----|-----|---------------------------|
| 640      | 2  | 128 | 2   | tie, q even → stays       |
| 896      | 3  | 128 | 4   | tie, q odd → rounds up    |
| −384     | −2 | 128 | −2  | tie, q even → stays       |
| −640     | −3 | 128 | −2  | tie, q odd → `q+1`        |

## 5. Overflow flag

`ovf` is a registered, sticky flag updated together with the readout
registers (same edge as `res_valid`):

- **Set** whenever a readout saturates (rounded snapshot outside
  `[−32768, 32767]`).
- **Cleared** only by `clr` (or `rst`).
- **Same-cycle priority:** if a saturating readout coincides with `clr`,
  the set wins — `ovf` remains/becomes 1. `clr` clears only when no
  saturating readout lands that same cycle.
- A non-saturating readout leaves `ovf` unchanged. `res` always carries
  the clamped value; saturation is signaled only via `ovf`.

## 6. Reset

`rst` is synchronous and active-high, and overrides `en`/`clr`/`rd`. On a
rising edge with `rst = 1`: `acc`, `res`, `res_valid`, and `ovf` all clear
to 0.

## 7. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain. No latches.
