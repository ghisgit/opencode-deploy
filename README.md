# opencode — Docker Compose deployment

Debian-based Docker deployment of [opencode](https://github.com/anomalyco/opencode)
running in web mode, with persistent data on the host.

## Directory layout

| Local path | Container path | Purpose |
|---|---|---|
| `opencode/` | `/data/.config/opencode`, `/data/.local/share/opencode`, `/data/.local/state/opencode`, `/data/.cache/opencode` | opencode's own persisted data (config, sessions, logs, cache) |
| `data/` | file-by-file mounts (see below) | other project files you want available in the container home |
| `workspace/` | `/workspace` | working directory for the web session |
| `entrypoint.sh` | `/entrypoint.sh` | creates home dirs, maps `PUID`/`PGID` user, fixes ownership, drops privileges (baked into the image at build time — changing it requires a rebuild) |
| `docker-compose.override.example.yml` | — | template for `docker-compose.override.yml` (git-ignored): local `build` block + per-file data mounts |

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
      # Writable config under /data (no :ro suffix — required by entrypoint).
      - ./data/.gitconfig:/data/.gitconfig
      # Read-only files: mount outside /data, never under it.
      - ./data/global-ignores:/etc/gitconfig.d/ignores:ro
```

Add one volume line per file.

> **Warning — do not mount read-only (`:ro`) files into `/data`.** The
> `entrypoint.sh` runs `chown -R` over `/data` on every start. A read-only bind
> mount there makes that `chown` fail, the entrypoint exits non-zero, and
> because `docker-compose.yml` sets `restart: unless-stopped`, the container
> restarts, fails again, and loops forever. Mount files the container only
> needs to read elsewhere (e.g. under `/etc` or `/opt`) instead of under
> `/data`; anything mounted under `/data` must remain writable.

`docker-compose.override.yml` is git-ignored (it references personal files such
as `data/.gitconfig`, which are not tracked), so adjust it locally. Create the
source file in `data/` first — the bind mount fails to start if it does not
exist.

Files in `data/` are committed to git (only `.gitkeep` is tracked by default),
while runtime state under `opencode/` is git-ignored.

## Optional tools baked into the image

Set `GH_INSTALL_VERSION`, `UV_INSTALL_VERSION` and/or `FNM_INSTALL_VERSION` in
`.env` to install the GitHub CLI (`gh`), `uv`/`uvx`, and the Fast Node Manager
(`fnm`) into the image at build time (`/usr/local/bin`, so they are on `PATH`).
Each accepts `false` (skip, the default), `latest`, or a pinned version such as
`v2.97.0` or `0.12.2`. `gh` and `fnm` keep the `v` prefix; `uv` strips it.
`INSTALL_GITHUB_MIRROR` prefixes the download URLs for opencode, gh, uv and fnm
(e.g. `https://ghproxy.com/`); leave empty for direct GitHub.
`APT_INSTALL_MIRROR` (hostname only, e.g. `mirrors.aliyun.com`) replaces
`deb.debian.org` in the apt sources so the base and C/C++ installs use that
mirror; empty keeps the official Debian sources.

`CPP_INSTALL` chooses how much of a C/C++ toolchain is baked in: `false` (none,
default), `minimal` (gcc/g++/make), `standard` (plus gdb/cmake/ninja/pkg-config),
or `full`/`true` (plus clang/clangd/llvm/clang-tidy). Unknown values fail the build.

Because these are build-time, set them **before** `docker compose build` /
`Dev Containers: Rebuild Container`. They only apply when building locally via
the `docker-compose.override.yml` build block (see below) — the prebuilt GHCR
image is already baked with `latest`/`latest`/`latest`/`latest`/`full`.

## Prebuilt images (GitHub Actions)

The image is built by a GitHub Actions workflow (`.github/workflows/build-image.yml`)
and published to GHCR as `ghcr.io/ghisgit/opencode-deploy`:

- **Architectures**: `amd64` and `arm64`. The `latest` tag is a multi-arch
  manifest, so Docker/`docker compose` automatically pulls the variant matching
  your host (an amd64 host gets the amd64 image — the default — an arm64 host
  gets the arm64 one). Single-arch tags are also published for explicit use:
  `latest-amd64` and `latest-arm64`.
- **Baked defaults**: `OPENCODE_VERSION=latest`, `GH_INSTALL_VERSION=latest`,
  `UV_INSTALL_VERSION=latest`, `FNM_INSTALL_VERSION=latest`, `CPP_INSTALL=full`.
  apt/GitHub mirrors are left empty (direct official sources).
- **Baked user**: an `opencode` user/group (`1000:1000`, bash shell, home
  `/data`) ships with the image, so dev containers (`"remoteUser": "opencode"`)
  and `docker run --user opencode` work out of the box. Runtime `PUID`/`PGID`
  still remap the ids via `entrypoint.sh` when they differ.
- **Triggers**: every push to `main`, a daily check at **02:00 UTC** (schedule),
  plus a manual **Run workflow** button on the Actions page (where you can
  override any of the five build variables). Each run also tags `sha-<commit>` so
  you can pin to a specific build.
- **Version tags**: the multi-arch build is tagged with the resolved opencode
  version without the `v` prefix (e.g. `1.18.15`), so you can pin an image to a
  specific opencode release. The version is resolved deterministically before
  building: `latest` is looked up via the GitHub API, and a pinned input missing
  the `v` prefix gets one added, so the download URL
  `/releases/download/vX/` stays correct.
- **Scheduled runs skip if already published**: the 02:00 UTC check first inspects
  GHCR for the resolved version tag and, if it already exists, skips the build
  (no new opencode release → no new image). Push/manual runs always build.

The default `docker-compose.yml` pulls `ghcr.io/ghisgit/opencode-deploy:latest`,
so a plain `docker compose up -d` needs no local build.

To use a different prebuilt build (e.g. an arm64-only or a pinned version),
point the image at it in `docker-compose.override.yml`:

```yaml
services:
  opencode:
    image: ghcr.io/ghisgit/opencode-deploy:latest-amd64
```

and run `docker compose up -d`. Remove the `build` block from
`docker-compose.override.yml` (or don't copy it from the template) so no local
build happens.

## Getting started

1. Copy and adjust the environment file:

   ```sh
   cp .env.example .env
   ```

   Set `PUID`/`PGID` to match your host user (`id -u` / `id -g`) so persisted
   files keep the right ownership.

2. Start (pulls the prebuilt GHCR image — no local build):

   ```sh
   docker compose up -d
   ```

   To build locally with your custom `.env` build args instead (e.g. a different
   toolchain tier), copy the override template (`cp docker-compose.override.example.yml
   docker-compose.override.yml`, which includes the local `build` block) and run
   `docker compose up -d --build`.

3. Open `http://localhost:4096`.

The container healthcheck probes the web server; the status is shown as
`(healthy)` in `docker ps`.

## VS Code Dev Container

A `.devcontainer/devcontainer.json` is provided so you can develop inside the
same container with VS Code:

1. Copy and adjust `.env` as above.
2. Make sure `docker-compose.override.yml` exists — `.devcontainer/devcontainer.json`
   now lists it in `dockerComposeFile`, so its mounts (your `data/` files) are
   merged into the dev container too. Create it from the template if you have not:
   `cp docker-compose.override.example.yml docker-compose.override.yml`. If the
   file is missing, reopening in a container fails.
3. Do **not** run `docker compose up` yourself — `docker-compose.yml` fixes the
   container name (`container_name: opencode`), which would conflict with the
   Dev Containers-managed instance. If a manual stack is running, stop it first
   with `docker compose down`.
4. The override includes the local `build` block, so the dev container builds the
   image from `./Dockerfile` with your `.env` build args on first start
   (i.e. it uses your local settings, not the prebuilt GHCR image).
5. Run **Dev Containers: Reopen in Container** from a VS Code window opened on
   this folder.

The devcontainer reuses `docker-compose.yml` and `docker-compose.override.yml`
directly, so `PUID`/`PGID`, the `data/` mount points and the entrypoint are
identical. VS Code attaches as the `opencode` user (baked into the image at
build time; `entrypoint.sh` remaps its uid/gid when `PUID`/`PGID` differ),
which writes to `/data` and `/workspace` with the mapped ownership instead of
running as `root`.

## Configuration (`.env`)

`PORT`, `PUID`/`PGID`, `DATA_DIR`, `WORKSPACE` and the auth vars are used at
runtime by every deployment. The build-time vars (`OPENCODE_VERSION`,
`GH_INSTALL_VERSION`, `UV_INSTALL_VERSION`, `FNM_INSTALL_VERSION`,
`INSTALL_GITHUB_MIRROR`, `APT_INSTALL_MIRROR`, `CPP_INSTALL`) only affect
**local** builds via `docker-compose.override.yml` — they are ignored when using
the prebuilt image.

| Variable | Default | Description |
|---|---|---|
| `PORT` | `4096` | Web server port (host:container) |
| `OPENCODE_VERSION` | `latest` | opencode version to install, e.g. `v1.18.14` |
| `PUID` / `PGID` | `1000` | Host user/group id the container runs as |
| `DATA_DIR` | `./opencode` | Host directory holding opencode's persisted data |
| `WORKSPACE` | `./workspace` | Host directory mounted at `/workspace` |
| `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` | `opencode` / empty | Web server auth (empty password = unsecured) |
| `GH_INSTALL_VERSION` | `false` | Bake GitHub CLI into the image: `false`, `latest`, or a pinned version like `v2.97.0` |
| `UV_INSTALL_VERSION` | `false` | Bake `uv`/`uvx` into the image: `false`, `latest`, or a pinned version like `0.12.2` |
| `FNM_INSTALL_VERSION` | `false` | Bake the Fast Node Manager into the image: `false`, `latest`, or a pinned version like `v1.39.0` |
| `INSTALL_GITHUB_MIRROR` | empty | Prefix prepended to the opencode/gh/uv/fnm download URLs (e.g. `https://ghproxy.com/`); empty = direct GitHub |
| `APT_INSTALL_MIRROR` | empty | apt mirror hostname replacing `deb.debian.org` (e.g. `mirrors.aliyun.com`); empty = official sources |
| `CPP_INSTALL` | `false` | C/C++ toolchain tier at build time: `false`, `minimal`, `standard`, or `full`/`true` |
