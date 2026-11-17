# Tom&Jain

A separate Godot 4 open-world multiplayer starter. Tom&Grace is not modified.

## First milestone
- Procedural city block and central plaza
- Third-person player controller (WASD, mouse, Space)
- WebSocket multiplayer transport for Windows and Godot Web exports
- Server-mediated player join/leave and position relay
- Player display names and a simple join screen

## Requirements
Godot 4.3+.

## Local multiplayer test
1. Open `godot/project.godot` in Godot 4.
2. Start a headless host: `godot --headless --path godot -- --server`
3. Run two client instances from the editor or exported builds.
4. Connect each client to `ws://127.0.0.1:9080`.
5. For LAN testing, use the host computer's LAN IP instead.

The server reads the `PORT` environment variable when present and otherwise listens on port 9080.

## Public server deployment (Render)
This repository includes a Docker-based Render Blueprint. Create the service from the repository's `render.yaml`; the server binds to Render's assigned `PORT`. Render terminates public TLS, so browser and desktop clients should connect using the service's `wss://` URL. The default Render free instance may spin down after inactivity and is not suitable for guaranteed always-on public multiplayer.

## Controls
- WASD: move
- Mouse: look
- Space: jump
- Esc: release mouse; click to capture again

## Prototype limitations
This is an early networking foundation, not a production public-world service. It still needs accounts, authoritative movement/physics, persistence, matchmaking, moderation, rate limiting, monitoring, and load testing before being opened to a large public audience. The city currently uses procedural placeholder geometry; realistic art assets and richer gameplay systems are later milestones.
