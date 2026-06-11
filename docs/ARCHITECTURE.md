# VIBE CITY — Architecture

Engine: **Godot 4.6**, stock. GDScript for all gameplay. GDExtension modules
are allowed only when a system has a working GDScript implementation, captured
profiling shows it exceeds its frame budget, and the native API boundary is
narrow and stable. We do not fork or patch the engine.

## Project Layout

```
project.godot           # Godot project file (root of the runnable project)
check.sh                # Local check script — identical to CI
scenes/
  playground/           # M0/M1 movement playground (sandbox world)
  player/               # Player scene (controller + camera rig)
  vehicles/             # M2+: car, bike, boat, plane scenes
  world/                # M3+: streamable tiles, district scenes
  ui/                   # HUD, menus, map
scripts/
  player/               # Movement, camera logic (plain scripts, testable)
  core/                 # Events bus, game state, save/load
  systems/              # Wanted, districts, traffic, missions (M4+)
tests/                  # GUT or gdUnit4 unit tests for plain scripts
docs/                   # This file, ROADMAP.md, design notes
.github/workflows/      # CI — runs check.sh on a headless Godot image
```

## Core Principles

1. **Game layer first.** Every system starts in GDScript. Native comes later,
   if ever, with profiling evidence.
2. **Composition over inheritance.** A player is a `CharacterBody3D` with
   movement, camera-target, health, and interaction components — not a deep
   class tree. Vehicles, pedestrians, and agent police reuse the same
   component pieces.
3. **Signals between systems.** Systems communicate through signals or a thin
   autoload event bus (`scripts/core/events.gd`). No system reaches into
   another's scene tree. No `get_node("../../..")`.
4. **UI observes and emits only.** HUD/map/menus subscribe to signals and emit
   intents. Zero game logic in UI scripts.
5. **Thin scenes, testable scripts.** Scene scripts wire nodes and forward to
   plain logic classes (e.g., movement math lives in a class that takes inputs
   and returns velocities) so unit tests don't need a running scene tree.
6. **Self-contained scenes.** Especially world tiles (M3+): a tile scene must
   load with zero references into other tiles or global scenes.

## Player & Camera (M1)

- `Player` is a `CharacterBody3D` with a `MovementController` script.
  Movement parameters (max speed, acceleration/deceleration curves, jump
  height, coyote time, jump buffer window, air control factor) are exported
  and tunable in-editor.
- Coyote time and jump buffering are timers in the movement logic, not
  animation hacks.
- `CameraRig` is a separate node hierarchy (yaw pivot → pitch pivot →
  `SpringArm3D` → `Camera3D`): shoulder offset on the spring arm, collision
  via the spring arm's shape cast, sprint FOV kick driven by player speed.
  The rig follows the player by reference set at spawn — it is not a child of
  the player body, so camera motion can be smoothed independently.
- Input map defines `move_*`, `jump`, `sprint`, `camera_*` actions with both
  keyboard/mouse and gamepad bindings. Rebinding UI comes later; actions are
  the contract.

## World & Streaming (M3 sketch — build M1/M2 with this in mind)

- World partitioned into ~256 m square tile scenes under `scenes/world/`.
- A `WorldStreamer` autoload loads/unloads tiles around the camera,
  prioritized by velocity vector; loading happens via
  `ResourceLoader.load_threaded_request`.
- Floating origin: when the player passes ~8 km from origin, shift the world.
  All systems must use relative positions or subscribe to the origin-shift
  signal. This lands before scale forces it, not after physics jitters.
- Debug HUD (toggleable) shows resident tiles, frame time, memory, streaming
  cost per frame.

## Occupation Systems (M4/M5 sketch)

- `DistrictControl` autoload owns a graph of districts with a control value
  (agent ↔ human). Conversion is rendered as a cyan holographic grid shader
  blended by control value; liberated areas get the warm/messy human pass.
- `WantedSystem` autoload tracks heat; emits escalation tiers. Agent police
  respond per tier (courteous warnings → polite pursuit → apologetic lethal
  force). Barks are data-driven (CSV/JSON of lines keyed by context).
- Missions are scenes implementing a small `Mission` contract: triggers,
  objectives, fail, retry, complete — driven by signals from world systems.

## Checks & CI

- `./check.sh` is the single source of truth; CI runs exactly it.
- Checks: project imports headlessly (`godot --headless --import`), GDScript
  parses/lints, unit tests pass, main scene loads headlessly.
- A change is done only when `./check.sh` passes locally and in CI.

## Performance

Target: 60 FPS @ 1080p on RTX 3060-class. Budgets in `docs/ROADMAP.md`.
Profile with Godot's profiler + captured benchmark scenes (M3) before any
optimization work. Optimization PRs must include before/after captures.
