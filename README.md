# opencode — Docker Compose deployment

Debian-based Docker deployment of [opencode](https://github.com/anomalyco/opencode)
running in web mode, with persistent data on the host.

## Directory layout

| Local path | Container path | Purpose |
|---|---|---|
| `opencode/` | `/data/.config/opencode`, `/data/.local/share/opencode`, `/data/.local/state/opencode`, `/data/.cache/opencode` | opencode's own persisted data (config, sessions, logs, cache) |
| `data/` | file-by-file mounts (see below) | other project files you want available in the container home |
| `workspace/` | `/workspace` | working directory for the web session |
| `entrypoint.sh` | `/entrypoint.sh` (baked into the image) | creates home dirs, maps `PUID`/`PGID` user, fixes ownership, drops privileges |
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

## Baked-in user and sudo

The image ships a default `opencode` user (UID/GID `1000`, bash shell,
`HOME=/data`) that is a member of the `sudo` group with passwordless sudo
(`/etc/sudoers.d/opencode`, `NOPASSWD: ALL`). This makes devcontainers
(`"remoteUser": "opencode"`) and `docker run --user opencode` work out of the
box, and lets the agent escalate with `sudo` when needed.

At startup the entrypoint still remaps the user/group to `PUID`/`PGID`
(defaulting to `1000`) so persisted files on the host keep the right
ownership — no build args required.

## Getting started

1. (Optional) Copy and adjust the environment file:

   ```sh
   cp .env.example .env
   ```

   `.env` is optional — sensible defaults apply when it is absent. If present,
   set `PUID`/`PGID` to match your host user (`id -u` / `id -g`) so persisted
   files keep the right ownership.

   Note: the optional `env_file` requires Docker Compose v2.24+.

2. Start:

   ```sh
   docker compose up -d
   ```

   By default this pulls the prebuilt image from GHCR (see below). To build
   the image locally instead, copy `docker-compose.override.example.yml` to
   `docker-compose.override.yml` — its template includes the build block.
   Local builds are tagged `opencode-deploy:local` (override via
   `LOCAL_IMAGE`) so they never collide with the published GHCR image.

3. Open `http://localhost:4096`.

The container healthcheck probes the web server; the status is shown as
`(healthy)` in `docker ps`.

## Prebuilt images (GHCR)

GitHub Actions publishes multi-arch images (`linux/amd64`, `linux/arm64`) to
`ghcr.io/ghisgit/opencode-deploy`. Tags:

| Tag | Meaning |
|---|---|
| `latest` | Most recent build |
| `<version>` (e.g. `1.18.15`) | Pinned opencode release; stable for rollbacks |
| `sha-<short>` | Exact git commit the image was built from |

When builds run:

- on every push to `main`
- manually via **Run workflow**, optionally pinning `OPENCODE_VERSION`
- daily at 02:00 UTC — skipped when the resolved opencode version is already
  published

Pull a specific version manually:

```sh
docker pull ghcr.io/ghisgit/opencode-deploy:<version>
```

## Developing with VS Code (Dev Containers)

The repo ships a `.devcontainer/devcontainer.json` that attaches VS Code to
the same compose project used for deployment — same image, volumes, and
`.env` settings.

Prerequisites:

- [VS Code](https://code.visualstudio.com/) with the
  [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  extension
- Docker Compose v2.24+ (for the optional `env_file`, as above)

Usage:

1. (Optional) Create `.env` as described in [Getting started](#getting-started).
2. Open this folder in VS Code and run **Dev Containers: Reopen in Container**
   from the command palette (`F1`).

What you get:

- A shell/editor session in `/workspace` as the baked `opencode` user, with
  passwordless `sudo` available.
- The running opencode web server is reachable directly at
  `http://localhost:${PORT:-4096}` via compose's own port publishing — no
  VS Code port forwarding needed.
- Your `docker-compose.override.yml` is applied too — Dev Containers does not
  load it automatically, so it is referenced explicitly in
  `.devcontainer/devcontainer.json`. The file is git-ignored; a cross-platform
  `initializeCommand` (shell script on Linux/macOS hosts, `.cmd` batch file on
  Windows) creates an empty stub on a fresh clone so the dev container opens
  out of the box.
- UID/GID mapping is handled by `PUID`/`PGID` exactly as in normal operation;
  Dev Containers' own UID rewrite is disabled to avoid double remapping.

Note: stopping the dev container (e.g. **Dev Containers: Stop Container**)
stops the web server too — it is the same service.

## Configuration (`.env`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `4096` | Web server port (host:container) |
| `OPENCODE_VERSION` | `latest` | opencode version for local image builds, e.g. `v1.18.14` |
| `PUID` / `PGID` | `1000` | Host user/group id the container runs as |
| `DATA_DIR` | `./opencode` | Host directory holding opencode's persisted data |
| `WORKSPACE` | `./workspace` | Host directory mounted at `/workspace` |
| `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` | `opencode` / `opencode` | Web server auth (change the password before exposing the port) |
