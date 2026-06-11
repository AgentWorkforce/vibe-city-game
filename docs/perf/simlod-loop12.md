# Loop 12 Simulation LOD Results

Captured on 2026-06-11 with Godot 4.6.3 stable using
`tools/bench_report.sh`, seed `11011`, 120 warmup physics frames, and 1800
measured physics frames. Sim LOD ships default-enabled after this loop because
the final matrix showed a small repeatable 2x p50 win without default-density
p50 regression. It did not reach the temporary 40% density-reduction target.

## Shipping Behavior

- `SimLODManager` registers pedestrians, agents, police, and traffic cars.
- NEAR remains full per-frame behavior below 35 m.
- MID runs behavior every 2nd or 3rd physics frame with accumulated delta and
  scales horizontal solver velocity so `move_and_slide()` covers the accumulated
  displacement.
- FAR pedestrians/agents avoid `move_and_slide()` and drift along intent with
  collision disabled; FAR traffic stays on the road graph without obstacle
  raycasts or wheel animation.
- Signal-driven reactions promote FAR actors to MID so flee/damage/wanted
  reactions still run.
- Entering back from FAR restores collision immediately and requests a ground
  snap before normal physics resumes.
- `SIM_LOD_DISABLE=1`, `SIM_LOD_FORCE_MID_NEAR=1`, and
  `SIM_LOD_FORCE_FAR_NEAR=1` are retained as benchmark diagnostics.

## Default Density No-Regression

Default density is 60 pedestrians, 16 traffic cars, 12 agents, and 4 police.
Loop 11 default median physics p50 was 8.856 ms; this session's before median
was 8.790 ms.

| Run Set | Physics p50s | Median | Notes |
|---|---:|---:|---|
| Loop 11 baseline | 8.851 / 8.934 / 8.856 ms | 8.856 ms | `docs/perf/baseline-loop11.md` |
| Loop 12 before | 10.176 / 8.790 / 8.719 ms | 8.790 ms | Same seed and counts |
| Final enabled LOD | 8.904 / 8.500 / 8.254 ms | 8.500 ms | No p50 regression |
| R1 shipped-tree recheck | 7.818 / 9.105 / 8.256 ms | 8.256 ms | After MID solver-displacement fix |

Final default JSON reports:

- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-after3-run1_p60_c16_a12_pol4_f1800_seed11011_1781185019.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-after3-run2_p60_c16_a12_pol4_f1800_seed11011_1781185062.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-after3-run3_p60_c16_a12_pol4_f1800_seed11011_1781185104.json`

R1 shipped-tree default JSON reports:

- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-r1-default-run1_p60_c16_a12_pol4_f1800_seed11011_1781186534.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-r1-default-run2_p60_c16_a12_pol4_f1800_seed11011_1781186609.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-r1-default-run3_p60_c16_a12_pol4_f1800_seed11011_1781186645.json`

## Attempt History

| Attempt | Default Physics p50 | 2x Physics p50 | Outcome |
|---|---:|---:|---|
| Tick-skip only | 8.420 / 9.556 ms | Not run | Noise-level default result; no clear win |
| Near-path cleanup | 10.907 / 9.174 ms | Not run | Default no-regression failed, stopped early |
| Final enabled pass | 8.904 / 8.500 / 8.254 ms | 30.458 ms | Default passed; 2x outlier triggered diagnostics |
| Diagnostic current repeat | Not rerun | 21.885 / 21.254 ms | 30.458 ms did not reproduce |

The 30.458 ms 2x result was a host/session artifact. It was not reproduced by
the diagnostic current-path runs on the same code path.

## 2x Diagnostic Matrix

2x density is 120 pedestrians, 32 traffic cars, 24 agents, and 4 police. The
Loop 11 2x anchor was physics p50 22.045 ms.

| Variant | Physics p50 | Physics p95 | Read |
|---|---:|---:|---|
| Current enabled LOD | 21.885 ms | 44.661 ms | Small p50 win vs anchor |
| Current enabled repeat | 21.254 ms | 30.588 ms | Confirms p50 neutrality/win |
| MID forced NEAR | 24.259 ms | 38.387 ms | MID skipping helps p50 |
| FAR forced NEAR | 22.030 ms | 53.360 ms | FAR traffic is p50-neutral |
| Manager disabled | 22.692 ms | 58.640 ms | Anchor-like p50; p95 tail is session-wide noise |

Diagnostic JSON reports:

- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-diag-current_p120_c32_a24_pol4_f1800_seed11011_1781185508.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-diag-mid-near_p120_c32_a24_pol4_f1800_seed11011_1781185569.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-diag-far-near_p120_c32_a24_pol4_f1800_seed11011_1781185614.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-diag-disabled_p120_c32_a24_pol4_f1800_seed11011_1781185667.json`
- `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/simlod-loop12-diag-current-repeat_p120_c32_a24_pol4_f1800_seed11011_1781185708.json`

Current enabled diagnostics at 2x:

| Counter | Value |
|---|---|
| Final tier counts | NEAR 97, MID 67, FAR 16 |
| Assignment counts | NEAR 6471, MID 4259, FAR 982 |
| Transitions | NEAR>MID 100, NEAR>FAR 33, MID>NEAR 26, MID>FAR 28, FAR>NEAR 12, FAR>MID 21 |

## Spawn Distribution

The density harness clusters most pedestrians and agents inside NEAR/MID, so a
FAR-only crowd optimization cannot produce the expected city-scale win here.
The 2x population still has zero FAR pedestrians, zero FAR agents, and zero FAR
police.

| Population | Default NEAR / MID / FAR | 2x NEAR / MID / FAR |
|---|---:|---:|
| Pedestrians | 44 / 16 / 0 | 88 / 32 / 0 |
| Agents | 4 / 8 / 0 | 9 / 15 / 0 |
| Police | 0 / 4 / 0 | 0 / 4 / 0 |
| Traffic cars | 1 / 4 / 11 | 3 / 7 / 22 |

This explains the final result: MID tick skipping contributes the small p50
gain, while FAR pedestrian/agent drift has almost no benchmark population to
harvest.

## Tier Cost Reading

| Tier | Loop 12 Cost Shape |
|---|---|
| NEAR | Full behavior and `move_and_slide()` every frame; this remains the dominant cost at both densities |
| MID | Behavior runs every 2nd or 3rd frame with delta compensation; it improved 2x p50 by about 2.4 ms versus forcing MID to NEAR |
| FAR pedestrians/agents | No `move_and_slide()`, collision disabled, cheap drift and occasional ground snap; not represented in the current density harness |
| FAR traffic | No obstacle raycast and snap-to-graph movement; p50-neutral in the diagnostic matrix |

## Measurement Lessons

- Use median-of-three for any headline number. A single 2x sample reported
  30.458 ms p50, but repeat current-path samples were 21.885 ms and 21.254 ms.
- p95 tails were noisy across enabled, forced, and disabled variants. The
  manager-disabled run had the highest p95 of the diagnostic set, so those
  tails were not attributable to one LOD subsystem.
- The benchmark is useful for density pressure, but its spatial distribution
  does not represent city-scale FAR crowds.

## Loop 13+ Levers

1. Native batched movement in T1/GDExtension, per ADR-0001 triggers, because
   `CharacterBody3D.move_and_slide()` multiplied by population is the core cost.
2. Active-NPC radius budgets: cap or pool full-physics NPCs around the player,
   which is the genre-standard design lever.
3. A widened city-scale benchmark that intentionally places FAR pedestrians and
   agents if the team wants to validate FAR-tier drift separately from the
   current near-intersection density harness.
