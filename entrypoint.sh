#!/bin/sh
set -eu

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-liveagent}"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

APP_DIR="/opt/liveagent"
APPIMAGE="$APP_DIR/LiveAgent.AppImage"
VERSION_FILE="$APP_DIR/version"
mkdir -p "$APP_DIR"

# 每次启动均检查 Stack-Cairn 官方最新 Release；仅在版本变化时下载 AppImage。
LATEST_JSON="$(curl -fsSL --retry 5 --retry-delay 2 \
  -H 'Accept: application/vnd.github+json' \
  -H 'User-Agent: LiveAgent-Docker-Updater' \
  https://api.github.com/repos/Stack-Cairn/LiveAgent/releases/latest)"

LATEST_VERSION="$(printf '%s' "$LATEST_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"

DOWNLOAD_URL="$(printf '%s' "$LATEST_JSON" | python3 -c '
import json, sys
release = json.load(sys.stdin)
for asset in release.get("assets", []):
    if asset.get("name", "").endswith("Linux-x86_64.AppImage"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("Latest release has no Linux-x86_64 AppImage asset")
')"

CURRENT_VERSION=""
if [ -f "$VERSION_FILE" ]; then
  CURRENT_VERSION="$(cat "$VERSION_FILE" 2>/dev/null || true)"
fi

if [ ! -x "$APPIMAGE" ] || [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
  echo "[LiveAgent] Downloading official latest AppImage: $LATEST_VERSION"
  curl -fL --retry 5 --retry-delay 2 -o "$APPIMAGE.new" "$DOWNLOAD_URL"
  chmod 0755 "$APPIMAGE.new"
  mv "$APPIMAGE.new" "$APPIMAGE"
  printf '%s' "$LATEST_VERSION" > "$VERSION_FILE"
else
  echo "[LiveAgent] Using cached AppImage: $CURRENT_VERSION"
fi

# 三项都提供时，写入专属 Agent 的 Gateway 连接设置。
# agt_ 令牌仅用于Agent链路；WebUI 登录应使用 Gateway 共享Token。
if [ -n "${LIVEAGENT_GATEWAY_URL:-}" ] \
  && [ -n "${LIVEAGENT_AGENT_ID:-}" ] \
  && [ -n "${LIVEAGENT_AGENT_TOKEN:-}" ]; then

  python3 -c '
import json, os, sqlite3, time
path = "/home/liveagent/.liveagent/config.sqlite"
os.makedirs(os.path.dirname(path), exist_ok=True)
conn = sqlite3.connect(path)
conn.execute("""CREATE TABLE IF NOT EXISTS remote_settings (
  config_id TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)""")
row = conn.execute("SELECT payload_json FROM remote_settings WHERE config_id = ?", ("default",)).fetchone()
settings = json.loads(row[0]) if row else {}
settings.update({
  "enabled": True,
  "gatewayUrl": os.environ["LIVEAGENT_GATEWAY_URL"].rstrip("/"),
  "gatewayPort": 443,
  "token": os.environ["LIVEAGENT_AGENT_TOKEN"],
  "agentId": os.environ["LIVEAGENT_AGENT_ID"],
  "autoReconnect": True,
  "heartbeatInterval": 30,
  "enableWebTerminal": False,
  "enableWebSshTerminal": False,
  "enableWebGit": False,
  "enableWebTunnels": False,
})
conn.execute("""INSERT INTO remote_settings(config_id, payload_json, updated_at)
VALUES (?, ?, ?)
ON CONFLICT(config_id) DO UPDATE SET
  payload_json = excluded.payload_json,
  updated_at = excluded.updated_at""", ("default", json.dumps(settings, separators=(",", ":")), int(time.time() * 1000)))
conn.commit()
conn.close()
'
fi

# 每个容器独立使用 :99，不会与其他容器或宿主机桌面冲突。
Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp -ac &
XVFB_PID="$!"
cleanup() { kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup INT TERM EXIT
sleep 1

# 以前台运行保证 Docker 可观测；异常退出会由 restart: always 自动恢复。
exec dbus-run-session -- "$APPIMAGE"
