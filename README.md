# Two Keys, One City

A tiny browser city for two people to explore together. Create a private room, share its six-character code, pick up work around town, earn coins, and buy homes for your couple.

The Python browser game lives in `game/`. The original Godot prototype remains in `godot/`.

## Play locally

Requires Python 3.10 or newer.

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn game.server:app --reload
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000) in two browser windows. One person creates a city and shares the room code; the other joins with that code. For a second person on another computer, expose the local service securely or deploy it to Render.

## How to play

- Move with WASD; use E near a green work marker or gold home sign.
- Work shifts pay 15 or 20 coins and have an eight-second cooldown.
- Homes cost 80–220 coins and are shared by the couple.
- Each room supports two players. Movement, work rewards, and property purchases are checked by the Python server.
- Rooms and progress live in server memory in this prototype. They reset when the room empties or the service restarts; persistent accounts and saved homes are a next milestone.

## Deploy on Render

The repository includes a Docker-based Blueprint. Create a Render service from `render.yaml`; it listens on Render's `PORT` and exposes a `/health` endpoint. Use the service's HTTPS URL in a browser; the client automatically uses secure WebSockets.

The free instance may sleep when idle, and in-memory rooms reset on restart. Use a persistent database and an always-on service plan before treating this as a permanent shared world.

## Current scope

This is a playable first slice with a top-down city, private two-player rooms, realtime movement, work spots, a coin wallet, and four buyable homes. It does not yet include user accounts, durable saving, interior scenes/furnishing, matchmaking, moderation, chat, mobile touch controls, or production load testing. The browser client is custom canvas art inspired by open-world city games; it does not use GTA assets.

## Original Godot prototype

The earlier Godot project is in `godot/` and can be opened with Godot 4.3+. It remains available as a separate prototype.
