# Two Keys, One City

A small third-person 3D city for two partners. Explore together, take local jobs, earn coins, buy homes, go inside, and decorate a shared place. Godot renders the game; Python runs the room server and saves couple progress.

## Run the game locally

Requirements: Godot 4.3+ and Python 3.10+.

Start the Python server from the repository root:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn game.server:app --host 0.0.0.0 --port 8000
```

In another terminal, launch the Godot project:

```powershell
godot --path godot
```

In the game, keep the server URL as `ws://127.0.0.1:8000/ws`. One partner selects **Create our city** and shares the eight-character code; the other enters that code and selects **Join with code**.

## Play

- WASD: walk
- Mouse: look around
- E: take a nearby job, buy or enter a home, add décor, or leave the interior
- Esc: release the mouse; click to capture it again

Jobs pay coins, and completing the same kind of job together grants a couple bonus. Homes and décor are shared by the room. The Python server checks purchases, job rewards, movement rate, and city collisions.

## Play online

Run the Python service on a public WebSocket host and set the Godot URL to `wss://your-host/ws`. Render's Docker Blueprint is included as a starting point. For saves to survive redeploys, mount persistent storage and set `TWO_KEYS_DATA_DIR` to its path.

A temporary public demo may use a Cloudflare Quick Tunnel, but the URL only works while the host computer and tunnel process remain online.

## Saves

SQLite stores room codes, player coin balances, home ownership, and décor in `game/data/two_keys.sqlite3` by default. Set `TWO_KEYS_DATA_DIR` to move the database to a persistent volume.

## Current scope

This is a playable 3D vertical slice with a procedural city, third-person movement, two-player rooms, jobs, a coin wallet, enterable homes, and shared décor. It is an original small prototype, not a recreation of GTA 6; it still needs richer character and city art, more activities, platform accounts, moderation, and production load testing.
