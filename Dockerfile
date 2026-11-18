FROM barichello/godot-ci:4.4.1 AS game-export

WORKDIR /src
COPY godot ./godot

RUN mkdir -p "$HOME/.local/share/godot/export_templates/4.4.1.stable" \
    && wget -q https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz -O /tmp/godot-templates.tpz \
    && mkdir -p /tmp/godot-templates \
    && unzip -q /tmp/godot-templates.tpz -d /tmp/godot-templates \
    && cp -R /tmp/godot-templates/templates/. "$HOME/.local/share/godot/export_templates/4.4.1.stable/" \
    && godot --headless --editor --path godot --quit \
    && mkdir -p /build \
    && godot --headless --path godot --export-release "Web" /build/index.html

FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY game ./game
COPY --from=game-export /build ./game/static/game

ENV PYTHONUNBUFFERED=1
EXPOSE 10000

CMD ["sh", "-c", "uvicorn game.server:app --host 0.0.0.0 --port ${PORT:-10000}"]
