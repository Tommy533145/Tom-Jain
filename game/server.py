from __future__ import annotations

import asyncio
import json
import math
import os
import re
import secrets
import sqlite3
import string
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"
DATA_DIR = Path(os.environ.get("TWO_KEYS_DATA_DIR", str(ROOT / "data")))
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "two_keys.sqlite3"
CITY_W = 1600
CITY_H = 1100
CITY_BUILDINGS = [
    (55, 65, 270, 135), (430, 65, 225, 135), (790, 65, 300, 135), (1160, 65, 370, 135),
    (55, 345, 270, 255), (430, 345, 225, 255), (790, 345, 300, 255), (1160, 345, 370, 255),
    (55, 735, 270, 295), (430, 735, 225, 295), (790, 735, 300, 295), (1160, 735, 370, 295),
]
MAX_PLAYERS = 2
MOVE_SPEED = 230.0
MOVE_INTERVAL = 1 / 24
ROOM_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

JOBS = [
    {"id": "cafe", "name": "Cafe shift", "x": 250, "y": 305, "reward": 15},
    {"id": "courier", "name": "Courier desk", "x": 1320, "y": 305, "reward": 20},
    {"id": "garden", "name": "Community garden", "x": 280, "y": 670, "reward": 15},
    {"id": "music", "name": "Street music", "x": 1300, "y": 670, "reward": 20},
]
HOMES = [
    {"id": "loft", "name": "Canal Loft", "x": 715, "y": 245, "cost": 80},
    {"id": "cottage", "name": "Garden Cottage", "x": 1110, "y": 245, "cost": 120},
    {"id": "townhouse", "name": "Brick Townhouse", "x": 715, "y": 850, "cost": 160},
    {"id": "penthouse", "name": "Skyline Flat", "x": 1110, "y": 850, "cost": 220},
]
FURNITURE = [
    {"id": "sofa", "name": "Cozy sofa", "cost": 45},
    {"id": "table", "name": "Coffee table", "cost": 30},
    {"id": "plant", "name": "Leafy plant", "cost": 20},
    {"id": "lamp", "name": "Reading lamp", "cost": 25},
    {"id": "art", "name": "Framed city art", "cost": 35},
    {"id": "bed", "name": "Big shared bed", "cost": 70},
]

with sqlite3.connect(DB_PATH) as db:
    db.execute("CREATE TABLE IF NOT EXISTS couple_rooms (code TEXT PRIMARY KEY, homes_json TEXT NOT NULL, updated_at REAL NOT NULL)")
    db.execute("""CREATE TABLE IF NOT EXISTS couple_players (
        room_code TEXT NOT NULL, account_key TEXT NOT NULL, name TEXT NOT NULL, coins INTEGER NOT NULL,
        updated_at REAL NOT NULL, PRIMARY KEY (room_code, account_key)
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS couple_decor (
        room_code TEXT NOT NULL, home_id TEXT NOT NULL, items_json TEXT NOT NULL,
        PRIMARY KEY (room_code, home_id)
    )""")


@dataclass
class Player:
    id: str
    account_key: str
    name: str
    socket: WebSocket
    x: float
    y: float
    coins: int = 35
    last_move: float = 0.0
    last_work: dict[str, float] = field(default_factory=dict)
    inside: str | None = None
    yaw: float = 0.0


@dataclass
class Room:
    code: str
    players: dict[str, Player] = field(default_factory=dict)
    homes: dict[str, str] = field(default_factory=dict)
    saved_players: dict[str, dict[str, Any]] = field(default_factory=dict)
    decor: dict[str, list[str]] = field(default_factory=dict)
    recent_work: dict[str, dict[str, Any]] = field(default_factory=dict)


rooms: dict[str, Room] = {}
rooms_lock = asyncio.Lock()
app = FastAPI(title="Two Keys, One City")
app.mount("/static", StaticFiles(directory=STATIC), name="static")


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(STATIC / "index.html")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


def load_saved_room(code: str) -> Room | None:
    with sqlite3.connect(DB_PATH) as db:
        row = db.execute("SELECT homes_json FROM couple_rooms WHERE code = ?", (code,)).fetchone()
        if row is None:
            return None
        room = Room(code=code, homes=json.loads(row[0]))
        for account_key, name, coins in db.execute(
            "SELECT account_key, name, coins FROM couple_players WHERE room_code = ?", (code,)
        ):
            room.saved_players[account_key] = {"name": name, "coins": coins}
        for home_id, items_json in db.execute(
            "SELECT home_id, items_json FROM couple_decor WHERE room_code = ?", (code,)
        ):
            room.decor[home_id] = json.loads(items_json)
        return room


def save_room(room: Room) -> None:
    now = time.time()
    with sqlite3.connect(DB_PATH) as db:
        db.execute(
            "INSERT INTO couple_rooms(code, homes_json, updated_at) VALUES(?, ?, ?) "
            "ON CONFLICT(code) DO UPDATE SET homes_json=excluded.homes_json, updated_at=excluded.updated_at",
            (room.code, json.dumps(room.homes), now),
        )
        for key, record in room.saved_players.items():
            db.execute(
                "INSERT INTO couple_players(room_code, account_key, name, coins, updated_at) VALUES(?, ?, ?, ?, ?) "
                "ON CONFLICT(room_code, account_key) DO UPDATE SET name=excluded.name, coins=excluded.coins, updated_at=excluded.updated_at",
                (room.code, key, record["name"], record["coins"], now),
            )
        for home_id, items in room.decor.items():
            db.execute(
                "INSERT INTO couple_decor(room_code, home_id, items_json) VALUES(?, ?, ?) "
                "ON CONFLICT(room_code, home_id) DO UPDATE SET items_json=excluded.items_json",
                (room.code, home_id, json.dumps(items)),
            )
        for player in room.players.values():
            db.execute(
                "INSERT INTO couple_players(room_code, account_key, name, coins, updated_at) VALUES(?, ?, ?, ?, ?) "
                "ON CONFLICT(room_code, account_key) DO UPDATE SET name=excluded.name, coins=excluded.coins, updated_at=excluded.updated_at",
                (room.code, player.account_key, player.name, player.coins, now),
            )


def make_code() -> str:
    return "".join(secrets.choice(ROOM_ALPHABET) for _ in range(8))


def collides_with_building(x: float, y: float, radius: float = 15.0) -> bool:
    return any(
        x + radius > bx and x - radius < bx + bw and y + radius > by and y - radius < by + bh
        for bx, by, bw, bh in CITY_BUILDINGS
    )


def room_snapshot(room: Room) -> dict[str, Any]:
    return {
        "type": "state",
        "room": room.code,
        "players": [
            {"id": player.id, "name": player.name, "x": player.x, "y": player.y, "coins": player.coins, "inside": player.inside, "yaw": player.yaw}
            for player in room.players.values()
        ],
        "homes": room.homes,
        "decor": room.decor,
        "furniture": FURNITURE,
        "jobs": JOBS,
        "properties": HOMES,
    }


async def send_error(socket: WebSocket, message: str) -> None:
    await socket.send_json({"type": "error", "message": message})


async def broadcast(room: Room, extra: dict[str, Any] | None = None) -> None:
    payload = room_snapshot(room)
    if extra:
        payload["notice"] = extra
    stale: list[str] = []
    for player in list(room.players.values()):
        try:
            await player.socket.send_json(payload)
        except Exception:
            stale.append(player.id)
    for player_id in stale:
        room.players.pop(player_id, None)


async def find_or_create_room(request: dict[str, Any], socket: WebSocket) -> tuple[Room | None, Player | None, str | None]:
    action = request.get("type")
    name = str(request.get("name", "Player")).strip()[:20] or "Player"
    account_key = str(request.get("account", ""))
    account_key = re.sub(r"[^a-zA-Z0-9_-]", "", account_key)[:80]
    if len(account_key) < 20:
        return None, None, "Refresh the game and try again."

    async with rooms_lock:
        if action == "create":
            code = make_code()
            with sqlite3.connect(DB_PATH) as db:
                while code in rooms or db.execute("SELECT 1 FROM couple_rooms WHERE code = ?", (code,)).fetchone():
                    code = make_code()
            room = Room(code=code)
            rooms[code] = room
            save_room(room)
        elif action == "join":
            code = str(request.get("room", "")).strip().upper()
            room = rooms.get(code)
            if room is None:
                room = load_saved_room(code)
                if room is None:
                    return None, None, "Room code not found. Ask your partner to create a city first."
                rooms[code] = room
            if len(room.players) >= MAX_PLAYERS:
                return None, None, "This room already has two players."
        else:
            return None, None, "Choose create room or join with a room code."

        if any(existing.account_key == account_key for existing in room.players.values()):
            return None, None, "This browser is already connected to this city."
        saved = room.saved_players.pop(account_key, None)
        player_id = secrets.token_urlsafe(8)
        player = Player(
            id=player_id,
            account_key=account_key,
            name=name,
            socket=socket,
            x=len(room.players) * 54 + 770,
            y=305,
            coins=35 if saved is None else int(saved["coins"]),
        )
        room.players[player_id] = player
        save_room(room)
        return room, player, None


async def serve_room(socket: WebSocket) -> None:
    await socket.accept()
    room: Room | None = None
    player: Player | None = None
    try:
        hello = await asyncio.wait_for(socket.receive_json(), timeout=20)
        if not isinstance(hello, dict):
            await send_error(socket, "Send a create or join request first.")
            return
        room, player, error = await find_or_create_room(hello, socket)
        if error:
            await send_error(socket, error)
            return
        await socket.send_json({"type": "welcome", "room": room.code, "player": player.id})
        await broadcast(room, {"text": f"{player.name} joined your city."})
        while True:
            message = await socket.receive_json()
            if not isinstance(message, dict):
                continue
            kind = message.get("type")
            if kind == "move":
                now = time.monotonic()
                if now - player.last_move < MOVE_INTERVAL:
                    continue
                try:
                    x = float(message.get("x"))
                    y = float(message.get("y"))
                    yaw = float(message.get("yaw", player.yaw))
                except (TypeError, ValueError):
                    continue
                if not math.isfinite(x) or not math.isfinite(y) or not math.isfinite(yaw):
                    continue
                if player.inside:
                    x = min(max(x, 600.0), 1000.0)
                    y = min(max(y, 390.0), 710.0)
                else:
                    x = min(max(x, 32.0), CITY_W - 32.0)
                    y = min(max(y, 32.0), CITY_H - 32.0)
                elapsed = min(max(now - player.last_move, 0.0), 0.5)
                max_distance = MOVE_SPEED * elapsed + 18.0
                if not player.inside and collides_with_building(x, y):
                    continue
                if player.last_move and math.hypot(x - player.x, y - player.y) > max_distance:
                    player.last_move = now
                    continue
                player.x, player.y, player.yaw, player.last_move = x, y, yaw, now
                await broadcast(room)
            elif kind == "enter":
                home = next((item for item in HOMES if item["id"] == message.get("home")), None)
                if home is None or home["id"] not in room.homes or math.hypot(player.x - home["x"], player.y - home["y"]) > 86:
                    await send_error(socket, "Walk up to a home your couple owns.")
                    continue
                player.inside = home["id"]
                player.x, player.y, player.last_move = 800.0, 550.0, time.monotonic()
                await broadcast(room, {"text": f"{player.name} went inside the {home['name']}."})
            elif kind == "exit":
                home = next((item for item in HOMES if item["id"] == player.inside), None)
                if home is None:
                    await send_error(socket, "You are already outside.")
                    continue
                player.inside = None
                player.x, player.y, player.last_move = float(home["x"]), float(home["y"] + 62), time.monotonic()
                await broadcast(room, {"text": f"{player.name} stepped back onto the street."})
            elif kind == "work":
                if player.inside:
                    await send_error(socket, "Head outside to pick up a shift.")
                    continue
                job = next((item for item in JOBS if item["id"] == message.get("job")), None)
                if job is None or math.hypot(player.x - job["x"], player.y - job["y"]) > 62:
                    await send_error(socket, "Walk up to a job spot first.")
                    continue
                now = time.monotonic()
                if now - player.last_work.get(job["id"], 0.0) < 8.0:
                    await send_error(socket, "Take a short break before doing that job again.")
                    continue
                player.last_work[job["id"]] = now
                player.coins += job["reward"]
                notice = f"{player.name} finished {job['name']} and earned {job['reward']} coins."
                previous = room.recent_work.get(job["id"])
                if previous and previous["account"] != player.account_key and now - previous["at"] <= 180:
                    partner = next((p for p in room.players.values() if p.account_key == previous["account"]), None)
                    if partner:
                        partner.coins += 12
                    else:
                        record = room.saved_players.get(previous["account"])
                        if record:
                            record["coins"] += 12
                    player.coins += 12
                    notice += " You completed it together: both earned a 12 coin couple bonus!"
                    room.recent_work.pop(job["id"], None)
                else:
                    room.recent_work[job["id"]] = {"account": player.account_key, "at": now}
                save_room(room)
                await broadcast(room, {"text": notice})
            elif kind == "decorate":
                if not player.inside or math.hypot(player.x - 940, player.y - 650) > 82:
                    await send_error(socket, "Walk over to the décor stand inside your home.")
                    continue
                item = next((entry for entry in FURNITURE if entry["id"] == message.get("item")), None)
                if item is None:
                    await send_error(socket, "That décor item is not available.")
                    continue
                items = room.decor.setdefault(player.inside, [])
                if item["id"] in items:
                    await send_error(socket, "Your home already has that item.")
                    continue
                if player.coins < item["cost"]:
                    await send_error(socket, f"You need {item['cost'] - player.coins} more coins.")
                    continue
                player.coins -= item["cost"]
                items.append(item["id"])
                save_room(room)
                await broadcast(room, {"text": f"{player.name} added a {item['name']} to your home."})
            elif kind == "buy":
                if player.inside:
                    await send_error(socket, "Head outside to browse homes.")
                    continue
                home = next((item for item in HOMES if item["id"] == message.get("home")), None)
                if home is None or math.hypot(player.x - home["x"], player.y - home["y"]) > 76:
                    await send_error(socket, "Walk up to a home sign to buy that property.")
                    continue
                if home["id"] in room.homes:
                    await send_error(socket, "That home already belongs to your couple.")
                    continue
                if player.coins < home["cost"]:
                    await send_error(socket, f"You need {home['cost'] - player.coins} more coins.")
                    continue
                player.coins -= home["cost"]
                room.homes[home["id"]] = player.name
                room.decor.setdefault(home["id"], [])
                save_room(room)
                await broadcast(room, {"text": f"{player.name} bought the {home['name']} for your couple!"})
    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    finally:
        if room is not None and player is not None:
            async with rooms_lock:
                room.players.pop(player.id, None)
                room.saved_players[player.account_key] = {"name": player.name, "coins": player.coins}
                save_room(room)
                if not room.players:
                    rooms.pop(room.code, None)
                else:
                    await broadcast(room, {"text": f"{player.name} left the city."})


@app.websocket("/ws")
async def websocket_endpoint(socket: WebSocket) -> None:
    await serve_room(socket)
