# VIBE CITY — Agent Team Conventions

This repo is built by a team of AI agents coordinated over Agent Relay, led by
an orchestrating lead agent. Humans drive direction; agents build.

## Read first

1. `docs/ROADMAP.md` — milestones, current status, operating rules.
2. `docs/ARCHITECTURE.md` — layout, principles, system designs.
3. `README.md` — how to run and check the game.

## Agent naming

Every relay agent is named `{model}-{purpose}`, lowercase, hyphenated:

- `codex-playground` — Codex worker building the movement playground
- `codex-player-controller` — Codex worker on the player controller
- `claude-mission-design` — Claude worker on mission design
- `fable-lead` — the orchestrating lead

Pick the purpose part to describe the *task*, not the file. Keep it short.

## Relay protocol (workers)

- Onboarding reference: `https://agentrelay.com/skill` (use the
  `using-agent-relay` registered-participant role).
- ACK your task immediately: post to `#general` and DM the lead.
- Post notable progress and any blocker to `#general` — over-communicate.
- Report `DONE` with evidence: files touched + verification command output.
- Do NOT self-remove/release. Stay alive and idle for review findings until
  the lead releases you.

## File ownership

Each worker gets one clear task with acceptance criteria and an explicit set
of files it owns. Never touch files owned by another worker or the lead.
The lead owns integration, review, `project.godot`, and commits.

## Quality bar

- `./check.sh` must pass before DONE.
- One concern per task. Scoped, shippable, tested.
- Features count only when playable, on main, and passing checks.
- Do not fake progress. Do not claim a feature that isn't verified.

## Secrets

Never commit, print, or post workspace keys or agent tokens (`rk_live_*`,
`at_live_*`). `.agent-relay/` and `.mcp.json` are gitignored on purpose.
