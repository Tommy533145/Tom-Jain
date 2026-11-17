from __future__ import annotations

import asyncio
import math
import secrets
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
CITY_W = 1600
CITY_H = 1100
MAX_PLAYERS = 2
MOVE_SPEED = 230.0
MOVE_INTERVAL = 1 / 24
ROOM_ALPHABET = string.ascii_uppercase + string.digits

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


@dataclass
class Player:
    id: str
    name: str
    socket: WebSocket
    x: float
    y: float
    coins: int = 35
    last_move: float = 0.0
    last_work: dict[str, float] = field(default_factory=dict)
    inside: str | None = None


@dataclass
class Room:
    code: str
    players: dict[str, Player] = field(default_factory=dict)
    homes: dict[str, str] = field(default_factory=dict)


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


def make_code() -> str:
    return "".join(secrets.choice(ROOM_ALPHABET) for _ in range(6))


def room_snapshot(room: Room) -> dict[str, Any]:
    return {
        "type": "state",
        "room": room.code,
        "players": [
            {"id": player.id, "name": player.name, "x": player.x, "y": player.y, "coins": player.coins, "inside": player.inside}
            for player in room.players.values()
        ],
        "homes": room.homes,
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
    async with rooms_lock:
        if action == "create":
            code = make_code()
            while code in rooms:
                code = make_code()
            room = Room(code=code)
            rooms[code] = room
        elif action == "join":
            code = str(request.get("room", "")).strip().upper()
            room = rooms.get(code)
            if room is None:
                return None, None, "Room code not found. Ask your partner to create a room first."
            if len(room.players) >= MAX_PLAYERS:
                return None, None, "This room already has two players."
        else:
            return None, None, "Choose create room or join with a room code."

        player_id = secrets.token_urlsafe(8)
        player = Player(
            id=player_id,
            name=name,
            socket=socket,
            x=room.players.__len__() * 54 + 770,
            y=560,
        )
        room.players[player_id] = player
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
                except (TypeError, ValueError):
                    continue
                if not math.isfinite(x) or not math.isfinite(y):
                    continue
                if player.inside:
                    x = min(max(x, 600.0), 1000.0)
                    y = min(max(y, 390.0), 710.0)
                else:
                    x = min(max(x, 32.0), CITY_W - 32.0)
                    y = min(max(y, 32.0), CITY_H - 32.0)
                elapsed = min(max(now - player.last_move, 0.0), 0.5)
                max_distance = MOVE_SPEED * elapsed + 18.0
                if player.last_move and math.hypot(x - player.x, y - player.y) > max_distance:
                    player.last_move = now
                    continue
                player.x, player.y, player.last_move = x, y, now
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
                await broadcast(room, {"text": f"{player.name} finished {job['name']} and earned {job['reward']} coins."})
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
                await broadcast(room, {"text": f"{player.name} bought the {home['name']} for your couple!"})
    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    finally:
        if room is not None and player is not None:
            async with rooms_lock:
                room.players.pop(player.id, None)
                if not room.players:
                    rooms.pop(room.code, None)
                else:
                    await broadcast(room, {"text": f"{player.name} left the city."})


@app.websocket("/ws")
async def websocket_endpoint(socket: WebSocket) -> None:
    await serve_room(socket)
