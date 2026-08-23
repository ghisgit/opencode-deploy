FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bash-completion \
        ca-certificates \
        curl \
        git \
        gosu \
        sudo \
        jq \
        procps \
        ripgrep \
        tar \
        xdg-utils \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV MISE_DATA_DIR="/mise"
ENV MISE_CONFIG_DIR="/mise"
ENV MISE_CACHE_DIR="/mise/cache"
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
ENV PATH="/mise/shims:$PATH"
RUN curl -fsSL https://mise.run | sh
RUN mise trust -a && mise install

# Bake the opencode user/group (1000:1000, bash shell, home /data) so dev
# containers ("remoteUser": "opencode") and `docker run --user opencode` work
# out of the box. entrypoint.sh still remaps PUID/PGID at runtime, so no
# build args are needed. Passwordless sudo lets the agent escalate when needed.
RUN groupadd -o -g 1000 opencode \
    && useradd -o -u 1000 -g 1000 -d /data -s /bin/bash opencode \
    && mkdir -p /data \
    && chown opencode:opencode /data \
    && usermod -aG sudo opencode \
    && echo "opencode ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/opencode \
    && chmod 0440 /etc/sudoers.d/opencode

ARG OPENCODE_VERSION=latest
# Pick the release asset matching the build arch (buildx/QEMU sets uname -m
# per platform), so the same Dockerfile builds amd64 and arm64 images.
RUN mkdir -p /tmp/opencode \
    && case "$(uname -m)" in \
        x86_64) opencode_arch="x64" ;; \
        aarch64) opencode_arch="arm64" ;; \
        *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /tmp/opencode/opencode.tar.gz \
        "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-${opencode_arch}.tar.gz" \
    && tar -xzf /tmp/opencode/opencode.tar.gz -C /tmp/opencode \
    && install -m 0755 /tmp/opencode/opencode /usr/local/bin/opencode \
    && rm -rf /tmp/opencode \
    && opencode --version

# No global HOME: gosu resolves the dropped-privileges user's home from
# /etc/passwd (/data), and the entrypoint exports HOME for both of its paths.
ENV BROWSER=true

WORKDIR /workspace

# Bake the entrypoint into the image (not a runtime bind mount), so local
# builds ship the entrypoint from the current tree.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD curl -fsS "http://127.0.0.1:${PORT:-4096}/" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "4096"]
