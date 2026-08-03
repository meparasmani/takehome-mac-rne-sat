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
- Tools verified earlier: git, uv, docker, iverilog

## Golden RTL

- Status: in progress
- Notes: Implement signed 8×8 MAC with RNE round, saturate, sticky ovf. Match hidden `MacModel`.

## Local tests

- Status: pending

## Original-20 analysis (HUD job 5b12be34…)

- Link: https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces
- Baseline pass rate ~10%
- Findings: pending (fill after reading failing traces + FM tags from TB)

## Spec changes log

| Date | Commit | What changed | Why |
|------|--------|--------------|-----|
| | | | |

## HUD eval iterations

| Run | Job URL | Pass rate | Notes / next fix |
|-----|---------|-----------|------------------|
| | | | |

## Final submission draft (A / B / C)

### A. Root Cause Analysis
(pending)

### B. Faulty Assumptions / Missed Insights
(pending)

### C. Prompt Modifications
(pending)
