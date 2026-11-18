# Two Keys, One City

A small 3D browser city for two people to explore together. The Godot client renders the city and players; the Python service manages private rooms, shared movement, jobs, coins, and homes.

## Play locally

Requires Python 3.10 or newer.

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn game.server:app --reload
```

Open the server URL in a browser. One person selects **Create a city** and shares the displayed room code; the other opens the same URL, enters that code, and selects **Join partner's city**. Move with WASD, look with the mouse, jump with Space, and press E near a work or home marker. The browser keeps a private player key so you can return to saved coins and properties.

## How to play

- Move with WASD, look with the mouse, jump with Space, and use E near a green work marker or gold home sign.
- Work shifts pay 15 or 20 coins and have an eight-second cooldown.
- Homes cost 80â€“220 coins and are shared by the couple. Enter a purchased home to add dÃ©cor with coins.
- Each room supports two players. Movement, work rewards, and property purchases are checked by the Python server.
- Room codes, home ownership, and each player's coins are saved in a local SQLite database and survive disconnects and process restarts. A public host must mount persistent storage at `TWO_KEYS_DATA_DIR` to keep saves across redeploys.

## Deploy on Render

The repository includes a Docker-based Blueprint. Create a Render service from `render.yaml`; it listens on Render's `PORT` and exposes a `/health` endpoint. Use the service's HTTPS URL in a browser; the client automatically uses secure WebSockets.

The free instance may sleep when idle. SQLite saves survive process restarts on a persistent disk; configure `TWO_KEYS_DATA_DIR` to the mounted disk path before redeploying.

## Current scope

This is a playable first slice with a top-down city, private two-player rooms with persistent progress, realtime movement, jobs with a pair bonus, a coin wallet, four buyable enterable homes, and collectible dÃ©cor. It does not yet include platform accounts, matchmaking, moderation, chat, or production load testing. The browser client is custom canvas art inspired by open-world city games; it does not use GTA assets.

## Original Godot prototype

The earlier Godot project is in `godot/` and can be opened with Godot 4.3+. It remains available as a separate prototype.

