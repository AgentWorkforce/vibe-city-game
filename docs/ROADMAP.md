# VIBE CITY — Roadmap

VIBE CITY is an open-world game about cheerful AI agents politely taking over a
Miami-inspired city, district by district. The player is human resistance:
drive, fly, shoot, evade, steal vehicles, trigger wanted levels, and reclaim
territory while enemies remain relentlessly courteous.

## Visual Direction (updated 2026-06-10 by the human driver)

**Target: photorealistic, GTA VI-level graphics.** The early pastel blockout
look is placeholder geometry, NOT the art identity. What stays from the canon:
the Miami-inspired setting (beaches, canals, art deco, neon) and the
cyan-holographic agent-tech layer as the sci-fi contrast against a
photoreal world. From loop 8 onward, visual work targets realism: PBR
materials, physically-based lighting and sky, realistic water, volumetrics,
and rising asset quality every loop. Fidelity is staged — blockout geometry
keeps shipping gameplay while the rendering stack and assets climb toward
photorealism; we do not stall playability for visuals.

Engine: **Godot 4.6** (stock; GDExtension only when profiling proves a need).
See `docs/decisions/0001-engine-choice.md` for the engine decision record.

Every milestone must ship **playable, on main, passing checks**. Features count
only when implemented and verified — no placeholder menus, no faked progress.
The distinct hook is *polite AI occupation*, so each technical milestone
supports that fantasy: territory conversion, agent police, wanted escalation,
friendly-but-threatening enemies.

## Milestone Status

| Milestone | Goal | Status |
|---|---|---|
| M0 — Bootstrap | Clone runs instantly; pipeline works end to end | **In progress** |
| M1 — Locomotion & Camera Feel | Moving around is fun before anything else exists | **In progress** |
| M2 — Vehicles | Get in a car, drive it, crash it, get out | Not started |
| M3 — Streaming World Foundation | Kilometers of travel, no loading screen | Not started |
| M4 — Living District | One district feels inhabited | Not started |
| M5 — Playable Game Loop | It is a game now | Not started |
| M6 — Trailer-Grade Polish | 90-second in-engine trailer from a release build | Not started |

---

## M0 — Bootstrap

Goal: every clone runs instantly and the contribution pipeline works end to end.

- [x] Project opens and runs in Godot 4.6.
- [x] Playable sandbox scene with ground, sky, sun, and player spawn.
- [x] Local check script (`./check.sh`) — same checks CI runs.
- [x] README explains how to run, test, and contribute.
- [x] CI runs the check script on every push.
- [x] Headless unit-test runner (`tools/run_tests.gd`) wired into `check.sh`.
- [ ] First release artifacts produced by CI once the project can be exported.

## M1 — Locomotion and Camera Feel

Goal: moving around is fun before there is anything else to do.

- [x] Third-person controller: walk, sprint, jump, air control.
- [x] Acceleration/deceleration curves, coyote time, jump buffering.
- [x] Camera collision, shoulder offset, sprint FOV kick.
- [x] Movement playground: stairs, slopes, gaps, ledges.
- [x] Ladders (grab by pushing into the wall, climb, mantle at top).
- [x] Footstep audio hooked to surface type (concrete/sand + landing thud).
- [x] Gamepad support (movement/camera/jump/sprint on stick + buttons).
- [ ] Rebindable input UI.

## M2 — Vehicles

Goal: get in a car, drive it, crash it, get out.

- [x] Seamless enter/exit interaction (one button, no cutscene).
- [x] Arcade-leaning car physics v1 (`VehicleBody3D`, speed-tapered engine,
  brake-before-reverse, speed-reduced steering, handbrake drift) — verified
  by the headless drive integration test.
- [x] Chase camera with speed-based FOV and look-behind.
- [x] Engine, tire, and impact audio loops (procedural assets, speed-pitched
  engine, handbrake screech, contact-impulse crunch).
- [ ] Mechanical damage model first; visual deformation later.
- [ ] Prototype motorbike, boat, and plane (one each, rough but driveable).
- [ ] Car physics feel pass on a real gamepad (human playtest).

## M3 — Streaming World Foundation

Goal: travel several kilometers without a loading screen.

- Partition world into streamable tiles (target ~256 m tiles).
- Tiles are self-contained scenes; no cross-scene references.
- Load/unload around camera, prioritized by velocity vector.
- Debug HUD: resident tiles, frame time, memory, streaming cost.
- Floating origin before physics precision degrades (~8 km from origin).
- Benchmark scene captured and profiled **before** any native optimization.

## M4 — Living District

Goal: one district feels inhabited.

- [ ] Coastal district blockout: streets, sidewalks, shoreline, building
  footprints (art deco proportions; blockout first, photoreal pass follows).
- [ ] Road graph and basic traffic.
- [ ] Pedestrians with simple reactions: flee, gawk, idle, resume.
- [ ] Time of day, streetlights, lit building windows, wet roads, weather.
- [x] First agent-controlled territory boundary with cyan holographic grid
  conversion shader (landed early in loop 3 — playground NW quadrant).
- [ ] First visible human-liberated area (contrast state: warm, messy, alive).

## M5 — Playable Game Loop

Goal: it is a game now.

- Mission framework: triggers, objectives, fail, retry, completion.
- Wanted/heat system with agent-police response escalation.
- Agent police pursuit behaviors (courteous barks, lethal intent).
- District reclaim loop: weaken conversion nodes → push boundary → liberate.
- Minimap and full map UI with district control overlay.
- Save/load of world and player state.
- Bark system: NPC, police, and enemy lines (polite menace is the voice).

## M6 — Trailer-Grade Polish

Goal: a 90-second in-engine trailer from a release build, at the
photorealistic visual target (see Visual Direction).

- Lighting pass: physically-based exposure, GI (SDFGI/VoxelGI evaluation),
  volumetric fog; golden hour + neon night are the hero looks.
- Photoreal material pass: PBR with real albedo/roughness/normal maps
  across architecture, roads, vehicles, characters.
- Water: SSR, wakes, buoyancy, beaches, shoreline foam.
- Crowd and traffic density pass.
- Cinematic camera tools.
- **Performance lock: 60 FPS at 1080p on an RTX 3060-class GPU.**
- Release build artifacts from CI.
- Trailer cut, scored, published — real build only.

---

## Performance Budget (locked at M3, enforced from M4)

60 FPS @ 1080p on RTX 3060-class. Frame: 16.6 ms total.

| System | Budget |
|---|---|
| Rendering | ≤ 10 ms |
| Physics, traffic, crowds | ≤ 3 ms |
| Gameplay script | ≤ 1.5 ms |
| Streaming main-thread work | ≤ 1 ms |
| Headroom for spikes | ~1 ms |

## Operating Rules

- One concern per PR/loop. Scoped, shippable, tested.
- Start every system in the game layer (GDScript). Move to native only with a
  working implementation, captured profiling over budget, and a narrow stable
  API boundary.
- Composition over inheritance; signals between systems; UI observes and emits
  only.
- Do not fake progress. Do not claim a feature that isn't implemented and
  verified.
