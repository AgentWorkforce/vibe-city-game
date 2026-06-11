# Loop 11 Density Benchmark Baseline

Captured on 2026-06-11 with Godot 4.6.3 stable using
`tools/bench_report.sh`. This is a measurement-only M3 baseline before any
native or gameplay optimization work.

Tree state: HEAD was `88ece0e`, with uncommitted loop-11 floating-origin
changes present in shared gameplay/world files, including the approved R1
production wiring that adds a live `FloatingOrigin` node to `city.tscn` and
`playground.tscn`.

## Harness

- Scene: `res://scenes/bench/benchmark_city.tscn`
- Script: `res://scripts/bench/bench_harness.gd`
- Seed: `11011`
- Warmup policy: 120 requested physics frames; reported runs settled after
  119 warmup frames before sampling.
- Sample count: 1800 measured physics frames per full run.
- Default density: 60 pedestrians, 16 traffic cars, 12 agents, 4 police.
- Headless mode uses Godot's dummy display server. It records
  `Performance.TIME_PROCESS` and `Performance.TIME_PHYSICS_PROCESS`, object
  count, and node count. These numbers cover script/physics monitor time, not
  GPU rendering cost. Rendering budget compliance still needs a real windowed
  or capture build profile.
- The harness removes HUD/map/banner UI in all modes. In headless mode it also
  avoids dummy-renderer tile mesh noise and uses a collision benchmark block
  around the fixed focus point. Windowed mode keeps the streamed city visuals
  and records FPS.
- Because the headless path removes `WorldStreamer` and substitutes a synthetic
  collision block, the headless baseline excludes real streamed tile-collision
  cost.

## ROADMAP Budget Comparison

The ROADMAP locks these M3/M4 budgets:

| System | Budget |
|---|---:|
| Gameplay script | <= 1.5 ms |
| Physics, traffic, crowds | <= 3 ms |

Headless median-of-three default-density results. Budget reads below use p50
because p95 tails vary materially between sessions; p95 is retained as spike
context.

| Metric | p50 | p95 | max | Budget Read |
|---|---:|---:|---:|---|
| Process monitor | 0.137 ms | 0.433 ms | 3.226 ms | p50 under 1.5 ms gameplay-script budget |
| Physics monitor | 8.856 ms | 13.675 ms | 14.874 ms | p50 is about 3x over 3 ms physics/traffic/crowds budget |
| Process + physics | 9.007 ms | 13.803 ms | 15.176 ms | p50 is about 2x over combined 4.5 ms script+physics target |
| Object count | 2784 | 2785 | 2785 | reference only |
| Node count | 790 | 790 | 790 | reference only |

Interpretation: script `_process` cost is currently small in headless, while
physics/crowd/traffic work is already well above the future M4 physics budget
at the default density. This is a baseline capture, not a gating failure.

Session variance note: default-density p50s reproduced tightly across the
reviewer counter-capture (`review-loop11`, physics p50 8.859 ms, combined p50
9.043 ms) and these post-R1 captures (median physics p50 8.856 ms, combined
p50 9.007 ms). p95 tails were much noisier: the reviewer counter-capture
recorded physics/combined p95 of 10.019/11.881 ms, while post-R1 captures here
recorded physics p95 from 10.915 to 14.122 ms and combined p95 from 12.427 to
14.277 ms. Earlier same-seed captures in the loop reached roughly 19.6 ms
physics p95, so p95 is treated as spike context rather than the budget anchor.
Reviewer JSON:
`/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/review-loop11_p60_c16_a12_pol4_f1800_seed11011_1781182340.json`

## Default Density Runs

| Run | JSON | Process p50 | Physics p50 | Combined p50 | Physics p95 | Combined p95 | Nodes |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/baseline-loop11-post-r1-run1_p60_c16_a12_pol4_f1800_seed11011_1781182473.json` | 0.136 ms | 8.851 ms | 9.000 ms | 14.122 ms | 14.277 ms | 790 |
| 2 | `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/baseline-loop11-post-r1-run2_p60_c16_a12_pol4_f1800_seed11011_1781182509.json` | 0.137 ms | 8.934 ms | 9.074 ms | 13.675 ms | 13.803 ms | 790 |
| 3 | `/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/baseline-loop11-post-r1-run3_p60_c16_a12_pol4_f1800_seed11011_1781182546.json` | 0.144 ms | 8.856 ms | 9.007 ms | 10.915 ms | 12.427 ms | 790 |

The three runs are deterministic in population setup: same seed, same counts,
same node count, and stable object count. Timing still varies by scheduler and
host load.

## 2x Population Breaking Point

2x run: 120 pedestrians, 32 traffic cars, 24 agents, 4 police, same seed and
1800-frame sample window.

| Metric | p50 | p95 | max |
|---|---:|---:|---:|
| Process monitor | 0.121 ms | 0.172 ms | 3.965 ms |
| Physics monitor | 22.045 ms | 25.408 ms | 33.402 ms |
| Process + physics | 22.158 ms | 27.039 ms | 33.509 ms |
| Object count | 3692 | 3713 | 3713 |
| Node count | 1410 | 1410 | 1410 |

JSON:
`/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/baseline-loop11-post-r1-2x_p120_c32_a24_pol4_f1800_seed11011_1781182591.json`

The 2x case is clearly past the current breaking point for the future physics
budget: physics p50 increases from 8.856 ms to 22.045 ms.

## Windowed Probe

Short sanity run only: 300 measured frames, default density, 1280x720,
vsync disabled.

| Metric | p50 | p95 | max |
|---|---:|---:|---:|
| Process monitor | 1.515 ms | 6.993 ms | 6.993 ms |
| Physics monitor | 18.793 ms | 19.310 ms | 19.310 ms |
| Process + physics | 20.698 ms | 25.421 ms | 25.421 ms |
| FPS monitor | 7 | 23 | 23 |
| Object count | 4987 | 4990 | 4990 |
| Node count | 2299 | 2300 | 2300 |

JSON:
`/Users/will/Library/Application Support/Godot/app_userdata/VIBE CITY/bench/windowed-post-r1-probe_p60_c16_a12_pol4_f300_seed11011_1781182663.json`

Windowed numbers are not directly comparable to the headless baseline because
the streamed city visuals are active and rendering is present.

## Hot-System Reading

1. Pedestrian and agent `CharacterBody3D.move_and_slide()` loops dominate the
   scaling curve. Doubling pedestrians and agents raises physics p50 by about
   13.2 ms in the post-R1 headless captures.
2. Traffic cars run per-frame obstacle raycasts in `TrafficCar._is_forward_blocked()`;
   doubling cars from 16 to 32 contributes directly to the physics spike.
3. Police agents inherit the agent wander/pursuit physics path and also scan
   player/wanted state each physics frame. They are a smaller count here, but
   will matter once wanted escalation increases police density.

No optimization was done in this loop. Recommendations are to add per-system
instrumentation before changing behavior, then evaluate crowd update throttling,
traffic raycast cadence, and cheaper idle actor collision/update modes.
