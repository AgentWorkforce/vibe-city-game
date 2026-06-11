# ADR 0001 — Engine choice for photorealistic VIBE CITY

Date: 2026-06-10 (decided 2026-06-11)
Status: DECIDED — staged UE5 migration. Custom engine REJECTED (final).
The human driver delegated the call to the lead with the mandate "GTA 6
quality, however best you can get there"; the lead chose the staged UE5
path per the analysis below. Perf target re-picked: fidelity-first
(1080p with TSR/DLSS-class upscaling, ~45-60fps on mid hardware) replaces
the hard 1080p60 lock.
Execution note: the UE5 spike is blocked on hardware — the dev machine
has ~13GB free disk vs the 30-60GB UE5 requires. Awaiting a resource
decision (free disk / second machine / cloud builder). Until unblocked,
Godot remains the design lab and ALL new code keeps the plain-class
portability discipline (this file, ARCHITECTURE.md).
Participants: fable-lead, claude-engine-architecture (debate in the
`#engine-architecture` relay channel), prompted by the human driver's
question and the photorealism mandate.

## Context

The human driver set the visual target to **photorealistic, GTA VI-level
graphics** (pastel blockout is placeholder, not identity) and asked whether
we should build a custom engine like Rockstar's RAGE.

## Decision 1 — Custom engine: NO (permanent)

The steelman for RAGE-class engines is about owning *simulation and
streaming* (RAGE: city-scale streaming as the architecture, euphoria
procedural animation, deterministic sim). None of it argues a small agent
team can out-build Epic/Rockstar renderers. With photorealism required, a
custom engine means building Nanite-class virtualized geometry, Lumen-class
GI, a photoreal character pipeline, AND streaming — thousands of
engineer-years. No condition reachable by this team makes it rational.

## Finding — Stock Godot 4.x cannot reach GTA-VI-class visuals

- No virtualized geometry (Nanite equivalent): photoreal density would
  require hand-authored LOD chains per asset; renderer-architecture gap,
  not a GDExtension-sized gap.
- SDFGI/VoxelGI < Lumen, and our hero look (neon wet Miami nights: many
  small emitters + glossy reflections) hits their worst artifacts.
- No MetaHuman-class photoreal character pipeline.
- Engine-independent: GTA-VI fidelity at 1080p60 on an RTX 3060 is not
  achievable on ANY engine (GTA VI targets 30fps on comparable hardware).
  Fidelity and the locked perf budget must be re-reconciled by the driver.

## Decision 2 (OPEN) — Staged Godot→UE5 gate, recommended by the architect

Keep shipping gameplay loops in Godot (gameplay/sim is engine-portable;
every loop grows migration cost, so decide early, on data):

- **Stage 1 (parallel spike):** port locomotion + one car + a wanted slice
  to UE5 with City Sample assets. Measure:
  - **G1 velocity gate:** agents ship a verified loop (UE Automation tests,
    CI green) at ≥50% of Godot cadence.
  - **G2 fidelity/perf gate:** City-Sample-class block at 1080p ≥45fps
    (TSR/DLSS allowed) on RTX 3060.
- **Stage 2 rule:** G1∧G2 → migrate immediately (~5k lines is the cheapest
  it will ever be; M3+ builds on World Partition, not custom streaming).
  G1 fails → stay Godot and re-scope fidelity to "Godot-max photoreal"
  (full PBR/photogrammetry, best-available GI, dense-but-smaller districts).

## Consequences

- Loop 7 (streaming, district tiles, pedestrians, missions, fleet)
  continues unchanged — all engine-portable design or replaceable blockout.
- `docs/ROADMAP.md` Visual Direction updated to the photoreal target.
- The 60fps@1080p/3060 performance lock needs a driver decision if GTA-VI
  fidelity stands: fidelity-first (45fps + upscaler) or perf-first.
