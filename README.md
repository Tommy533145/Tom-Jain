# Tom&Jain

A separate Godot 4 open-world multiplayer starter. Tom&Grace is not modified.

## First milestone
- Procedural low-poly city block and central plaza
- Third-person player controller (WASD, mouse, Space)
- WebSocket multiplayer transport for desktop and Godot Web exports
- Server-mediated player join/leave and position relay
- Simple join screen

## Requirements
Godot 4.3+.

## Local multiplayer test
1. Open `godot/project.godot` in Godot 4.
2. Start a headless host: `godot --headless --path godot -- --server`
3. Run two client instances from the editor or exported builds.
4. Connect each client to `ws://127.0.0.1:9080`.
5. For LAN testing, use the host computer's LAN IP instead.

The headless server listens on port 9080. For public internet access, deploy it on a persistent server and configure WSS/TLS at a reverse proxy. Browser exports require secure-context-compatible WSS when hosted over HTTPS.

## Controls
- WASD: move
- Mouse: look
- Space: jump
- Esc: release mouse; click to capture again

## Prototype limitations
This is an early networking foundation, not a production public-world service. It has no accounts, anti-cheat, persistence, matchmaking, moderation, rate limiting, voice chat, or authoritative physics yet. Do not expose it to the public until those are implemented. The city uses procedural placeholder geometry; realistic art assets are a later milestone.
