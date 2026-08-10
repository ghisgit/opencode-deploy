FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Optional apt mirror (hostname only, e.g. mirrors.aliyun.com).
# Replaces deb.debian.org in every apt source so the base and CPP installs
# below use the mirror. Empty = official Debian sources.
ARG APT_INSTALL_MIRROR=
RUN if [ -n "$APT_INSTALL_MIRROR" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do \
            [ -f "$f" ] && sed -i "s|deb.debian.org|${APT_INSTALL_MIRROR}|g" "$f"; \
        done; \
    fi

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gosu \
        jq \
        procps \
        ripgrep \
        tar \
        xdg-utils \
    && rm -rf /var/lib/apt/lists/*

ARG OPENCODE_VERSION=latest
ARG INSTALL_GITHUB_MIRROR=
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64) opencode_arch="x64" ;; \
        aarch64) opencode_arch="arm64" ;; \
        *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    mkdir -p /opt/opencode \
    && curl -fsSL -o /opt/opencode/opencode.tar.gz \
        "${INSTALL_GITHUB_MIRROR}https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-${opencode_arch}.tar.gz" \
    && tar -xzf /opt/opencode/opencode.tar.gz -C /opt/opencode \
    && install -m 0755 /opt/opencode/opencode /usr/local/bin/opencode \
    && rm -rf /opt/opencode \
    && opencode --version

ENV BROWSER=true

# Optional GitHub CLI (gh) and uv/uvx installs at build time.
# Values are controlled via build args from .env:
#   false | latest | pinned version (gh keeps v, uv strips leading v).
# INSTALL_GITHUB_MIRROR (prepended to download URLs) is declared above so the
# opencode download also uses it; it is re-declared here for this RUN scope.
ARG GH_INSTALL_VERSION=false
ARG UV_INSTALL_VERSION=false
ARG INSTALL_GITHUB_MIRROR=
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) gh_arch="amd64"; uv_triple="x86_64-unknown-linux-gnu" ;; \
        aarch64) gh_arch="arm64"; uv_triple="aarch64-unknown-linux-gnu" ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    if [ "$GH_INSTALL_VERSION" != "false" ]; then \
        if [ "$GH_INSTALL_VERSION" = "latest" ]; then \
            tag="$(curl -fsSL "${INSTALL_GITHUB_MIRROR}https://api.github.com/repos/cli/cli/releases/latest" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"; \
        else \
            tag="$GH_INSTALL_VERSION"; \
            case "$tag" in v*) ;; *) tag="v${tag}";; esac; \
        fi; \
        v="${tag#v}"; \
        curl -fsSL -o /tmp/gh.tgz "${INSTALL_GITHUB_MIRROR}https://github.com/cli/cli/releases/download/${tag}/gh_${v}_linux_${gh_arch}.tar.gz"; \
        tar -xzf /tmp/gh.tgz -C /tmp; \
        install -m 0755 /tmp/gh_*/bin/gh /usr/local/bin/gh; \
        rm -rf /tmp/gh.tgz /tmp/gh_*; \
    fi; \
    if [ "$UV_INSTALL_VERSION" != "false" ]; then \
        if [ "$UV_INSTALL_VERSION" = "latest" ]; then \
            tag="$(curl -fsSL "${INSTALL_GITHUB_MIRROR}https://api.github.com/repos/astral-sh/uv/releases/latest" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"; \
        else \
            tag="${UV_INSTALL_VERSION#v}"; \
        fi; \
        curl -fsSL -o /tmp/uv.tgz "${INSTALL_GITHUB_MIRROR}https://github.com/astral-sh/uv/releases/download/${tag}/uv-${uv_triple}.tar.gz"; \
        tar -xzf /tmp/uv.tgz -C /tmp; \
        install -m 0755 "/tmp/uv-${uv_triple}/uv" /usr/local/bin/uv; \
        install -m 0755 "/tmp/uv-${uv_triple}/uvx" /usr/local/bin/uvx; \
        rm -rf /tmp/uv.tgz "/tmp/uv-${uv_triple}"; \
    fi

# Optional C/C++ toolchain at build time, gated by CPP_INSTALL:
#   false | minimal | standard | full | true
ARG CPP_INSTALL=false
RUN if [ "$CPP_INSTALL" != "false" ]; then \
        case "$CPP_INSTALL" in \
            minimal)   pkgs="build-essential" ;; \
            standard)  pkgs="build-essential gdb cmake ninja-build pkg-config" ;; \
            true|full) pkgs="build-essential gdb cmake ninja-build pkg-config clang clangd llvm clang-tidy" ;; \
            *) echo "unsupported CPP_INSTALL: $CPP_INSTALL" >&2; exit 1 ;; \
        esac; \
        apt-get update \
        && apt-get install -y --no-install-recommends $pkgs \
        && rm -rf /var/lib/apt/lists/*; \
    fi

WORKDIR /workspace

# Bake the entrypoint into the image (not a runtime bind mount), so local and
# CI builds both ship the entrypoint from the current tree.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD curl -fsS "http://127.0.0.1:${PORT:-4096}/" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "4096"]
