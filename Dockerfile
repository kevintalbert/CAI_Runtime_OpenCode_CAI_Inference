# Use CML base runtime image
FROM --platform=linux/amd64 docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-jupyterlab-python3.13-standard:2025.09.1-b5

# ── System dependencies ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # editors
        vim nano \
        # terminal multiplexers
        tmux screen \
        # file & text utilities
        curl wget less tree jq unzip zip \
        ripgrep fd-find bat \
        # network utilities
        netcat-openbsd dnsutils iputils-ping \
        # process & system inspection
        pciutils htop procps lsof strace \
        # misc dev conveniences
        ssh-client rsync socat ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    # fd and bat ship under Debian alias names
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# ── Node.js 20 (required by OpenCode) ──────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── OpenCode CLI (https://github.com/anomalyco/opencode) ───────────────────
RUN npm install -g opencode-ai@latest

# ── ttyd: browser-based terminal ────────────────────────────────────────────
RUN TTYD_URL=$(curl -s https://api.github.com/repos/tsl0922/ttyd/releases/latest \
        | grep '"browser_download_url"' \
        | grep 'ttyd\.x86_64"' \
        | head -1 \
        | cut -d'"' -f4) && \
    curl -fsSL "$TTYD_URL" -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# ── Runtime directories ────────────────────────────────────────────────────
RUN mkdir -p /home/cdsw/.config/opencode && \
    chown -R cdsw:cdsw /home/cdsw/.config

# ── Shell startup script ─────────────────────────────────────────────────────
COPY scripts/startup.sh /etc/profile.d/opencode-caii.sh
RUN chmod +x /etc/profile.d/opencode-caii.sh && \
    echo '[ -f /etc/profile.d/opencode-caii.sh ] && source /etc/profile.d/opencode-caii.sh' \
        >> /etc/bash.bashrc

# ── Default environment (override in CML project / session settings) ───────
# CAII exposes an OpenAI-compatible HTTP API; set the base URL to the /v1 root
# your operator documents (often ends in .../v1).
ENV CAII_OPENAI_BASE_URL="" \
    CAII_API_TOKEN="" \
    CAII_MODEL="" \
    APP_PORT="8080"

EXPOSE 8080
WORKDIR /home/cdsw

LABEL com.cloudera.ml.runtime.edition="opencode"
LABEL com.cloudera.ml.runtime.full-version="2.0.1-opencode"
LABEL com.cloudera.ml.runtime.short-version="2.0"
LABEL com.cloudera.ml.runtime.maintenance-version="1"
LABEL com.cloudera.ml.runtime.description="OpenCode CLI for Cloudera AI Inference (OpenAI-compatible API; model is user-configured)"
