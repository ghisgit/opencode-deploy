#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
HOME_DIR="/data"
WORKSPACE="/workspace"
MISE_DATA_DIR="${MISE_DATA_DIR:-/mise}"
mkdir -p \
    "$HOME_DIR" \
    "$HOME_DIR/.config/opencode" \
    "$HOME_DIR/.local/share/opencode" \
    "$HOME_DIR/.local/state/opencode" \
    "$HOME_DIR/.cache/opencode"

# The image sets no global HOME; export it here so both paths below run with
# HOME=/data. gosu would fall back to the passwd entry, but an explicit value
# also covers arbitrary `--user <uid>` starts with no passwd entry.
export HOME="$HOME_DIR"

if [ "$(id -u)" != "0" ]; then
    exec opencode "$@"
fi

if ! getent group "$PGID" > /dev/null 2>&1; then
    if getent group "$OPENCODE_USER" > /dev/null 2>&1; then
        groupmod -o -g "$PGID" "$OPENCODE_USER"
    else
        groupadd -o -g "$PGID" "$OPENCODE_USER"
    fi
fi

if id "$OPENCODE_USER" > /dev/null 2>&1; then
    usermod -o -u "$PUID" -g "$PGID" -d "$HOME_DIR" "$OPENCODE_USER"
else
    useradd -o -u "$PUID" -g "$PGID" -d "$HOME_DIR" -s /bin/bash "$OPENCODE_USER"
fi

chown -R "$PUID:$PGID" "$HOME_DIR" "$WORKSPACE" || \
    echo "warning: chown failed for some paths under $HOME_DIR or $WORKSPACE (read-only mounts?)"

# Hand the mise dir (tools installed at build time as root) to the runtime
# user so `mise install` works without sudo.
chown -R "$PUID:$PGID" "$MISE_DATA_DIR"

exec gosu "$PUID:$PGID" /usr/local/bin/opencode "$@"
