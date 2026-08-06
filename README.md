# opencode — Docker Compose deployment

Debian-based Docker deployment of [opencode](https://github.com/anomalyco/opencode)
running in web mode, with persistent data on the host.

## Directory layout

| Local path | Container path | Purpose |
|---|---|---|
| `opencode/` | `/data/.config/opencode`, `/data/.local/share/opencode`, `/data/.local/state/opencode`, `/data/.cache/opencode` | opencode's own persisted data (config, sessions, logs, cache) |
| `data/` | file-by-file mounts (see below) | other project files you want available in the container home |
| `workspace/` | `/workspace` | working directory for the web session |
| `entrypoint.sh` | `/entrypoint.sh` | creates home dirs, maps `PUID`/`PGID` user, fixes ownership, drops privileges |
| `docker-compose.override.example.yml` | — | template for `docker-compose.override.yml` (git-ignored) |

## Persisting files into the container home (`/data`)

opencode runs with `HOME=/data`. The local `data/` directory is used to persist
other project files into the container home directory, such as `.gitconfig` or
`.ssh`.

Do **not** mount the whole `data/` directory over `/data` — it would shadow the
container home and interfere with the opencode data mounts below it. Mount
individual files instead, via `docker-compose.override.yml` (so
`docker-compose.yml` stays untouched — Compose auto-merges the override file).

Start from the tracked template:

```sh
cp docker-compose.override.example.yml docker-compose.override.yml
```

```yaml
services:
  opencode:
    volumes:
      - ./data/.gitconfig:/data/.gitconfig:ro
```

Add one volume line per file. Drop the `:ro` suffix for files the container
must be able to write.

`docker-compose.override.yml` is git-ignored (it references personal files such
as `data/.gitconfig`, which are not tracked), so adjust it locally. Create the
source file in `data/` first — the bind mount fails to start if it does not
exist.

Files in `data/` are committed to git (only `.gitkeep` is tracked by default),
while runtime state under `opencode/` is git-ignored.

## Getting started

1. Copy and adjust the environment file:

   ```sh
   cp .env.example .env
   ```

   Set `PUID`/`PGID` to match your host user (`id -u` / `id -g`) so persisted
   files keep the right ownership.

2. Build and start:

   ```sh
   docker compose up -d
   ```

3. Open `http://localhost:4096`.

The container healthcheck probes the web server; the status is shown as
`(healthy)` in `docker ps`.

## Configuration (`.env`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `4096` | Web server port (host:container) |
| `OPENCODE_VERSION` | `latest` | opencode version to install, e.g. `v1.18.14` |
| `PUID` / `PGID` | `1000` | Host user/group id the container runs as |
| `DATA_DIR` | `./opencode` | Host directory holding opencode's persisted data |
| `WORKSPACE` | `./workspace` | Host directory mounted at `/workspace` |
| `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` | `opencode` / empty | Web server auth (empty password = unsecured) |
