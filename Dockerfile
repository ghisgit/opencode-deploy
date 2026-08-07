FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

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
RUN mkdir -p /opt/opencode \
    && curl -fsSL -o /opt/opencode/opencode.tar.gz \
        "https://github.com/anomalyco/opencode/releases/${OPENCODE_VERSION}/download/opencode-linux-x64.tar.gz" \
    && tar -xzf /opt/opencode/opencode.tar.gz -C /opt/opencode \
    && install -m 0755 /opt/opencode/opencode /usr/local/bin/opencode \
    && rm -rf /opt/opencode \
    && opencode --version

ENV BROWSER=true

WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD curl -fsS "http://127.0.0.1:${PORT:-4096}/" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "4096"]
