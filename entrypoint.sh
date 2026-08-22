#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
HOME_DIR="/data"
WORKSPACE="/workspace"

mkdir -p \
    "$HOME_DIR" \
    "$HOME_DIR/.config/opencode" \
    "$HOME_DIR/.local/share/opencode" \
    "$HOME_DIR/.local/state/opencode" \
    "$HOME_DIR/.cache/opencode"

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
    usermod -o -u "$PUID" -g "$PGID" -d "$HOME_DIR" -s /bin/bash "$OPENCODE_USER"
else
    useradd -o -u "$PUID" -g "$PGID" -d "$HOME_DIR" -s /bin/bash "$OPENCODE_USER"
fi

chown -R "$PUID:$PGID" "$HOME_DIR" "$WORKSPACE"

exec gosu "$PUID:$PGID" /usr/local/bin/opencode "$@"
