FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/liveagent \
    DISPLAY=:99 \
    XDG_RUNTIME_DIR=/tmp/runtime-liveagent \
    APPIMAGE_EXTRACT_AND_RUN=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    dbus-x11 \
    xvfb \
    xauth \
    fuse3 \
    libfuse2t64 \
    libgtk-3-0 \
    libwebkit2gtk-4.1-0 \
    libayatana-appindicator3-1 \
    libasound2 \
    libnss3 \
    libx11-xcb1 \
    libgbm1 \
    libdrm2 \
    libxkbcommon0 \
    libatspi2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 --shell /bin/sh liveagent \
    && mkdir -p /workspace /tmp/runtime-liveagent /opt/liveagent \
    && chown -R liveagent:liveagent \
        /workspace \
        /tmp/runtime-liveagent \
        /opt/liveagent

COPY --chown=liveagent:liveagent entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

USER liveagent
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
