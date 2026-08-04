#!/bin/sh
set -eu

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-liveagent}"
export XVFB_SCREEN="${XVFB_SCREEN:-1200x720x16}"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

APP_DIR=/opt/liveagent
APPIMAGE="$APP_DIR/LiveAgent.AppImage"
VERSION_FILE="$APP_DIR/version"
mkdir -p "$APP_DIR"

# 可选固定版本。生产环境建议在 .env 设置 LIVEAGENT_VERSION=v1.2.3，
# 避免容器重启时未经验证地自动升级；留空则使用 latest。
RELEASE_API=https://api.github.com/repos/Stack-Cairn/LiveAgent/releases
if [ -n "${LIVEAGENT_VERSION:-}" ]; then
  RELEASE_URL="$RELEASE_API/tags/$LIVEAGENT_VERSION"
else
  RELEASE_URL="$RELEASE_API/latest"
fi

LATEST_JSON="$(curl -fsSL --retry 5 --retry-delay 2 \
  -H 'Accept: application/vnd.github+json' \
  -H 'User-Agent: LiveAgent-Docker-Updater' \
  "$RELEASE_URL")"

LATEST_VERSION="$(printf '%s' "$LATEST_JSON" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
DOWNLOAD_URL="$(printf '%s' "$LATEST_JSON" | python3 -c '
import json, sys
release = json.load(sys.stdin)
for asset in release.get("assets", []):
    if asset.get("name", "").endswith("Linux-x86_64.AppImage"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit("Release has no Linux-x86_64 AppImage asset")
')"

CURRENT_VERSION=""
[ ! -f "$VERSION_FILE" ] || CURRENT_VERSION="$(cat "$VERSION_FILE" 2>/dev/null || true)"
if [ ! -x "$APPIMAGE" ] || [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
  echo "[LiveAgent] Downloading AppImage: $LATEST_VERSION"
  curl -fL --retry 5 --retry-delay 2 -o "$APPIMAGE.new" "$DOWNLOAD_URL"
  chmod 0755 "$APPIMAGE.new"
  mv "$APPIMAGE.new" "$APPIMAGE"
  printf '%s' "$LATEST_VERSION" > "$VERSION_FILE"
else
  echo "[LiveAgent] Using cached AppImage: $CURRENT_VERSION"
fi

# 仅在三项齐全时写入 Gateway 设置；不输出令牌。
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
row = conn.execute("SELECT payload_json FROM remote_settings WHERE config_id=?", ("default",)).fetchone()
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
conn.execute("""INSERT INTO remote_settings(config_id,payload_json,updated_at)
VALUES (?,?,?) ON CONFLICT(config_id) DO UPDATE SET
payload_json=excluded.payload_json, updated_at=excluded.updated_at""",
("default", json.dumps(settings,separators=(",",":")), int(time.time()*1000)))
conn.commit(); conn.close()
'
fi

Xvfb "$DISPLAY" -screen 0 "$XVFB_SCREEN" -nolisten tcp -ac -noreset &
XVFB_PID=$!
APP_PID=""
cleanup() {
  [ -z "$APP_PID" ] || kill "$APP_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT
sleep 1

# 后台运行以便在服务器模式下移除窗口映射。WebKit 本身不能删除：
# Gateway 的 Agent 运行时仍在 WebView JavaScript 中执行。
dbus-run-session -- "$APPIMAGE" &
APP_PID=$!

if [ "${LIVEAGENT_HEADLESS:-1}" = "1" ]; then
  # 等待 Tauri 创建窗口，再 unmap。窗口隐藏后 document.visibilityState=hidden，
  # WebKit 可对动画/计时器节流，同时 Gateway WebSocket 与任务仍保持运行。
  i=0
  while [ "$i" -lt 100 ]; do
    WINDOWS="$(xwininfo -root -tree 2>/dev/null | awk '/LiveAgent|liveagent/ {print $1}')"
    if [ -n "$WINDOWS" ]; then
      for wid in $WINDOWS; do xdotool windowunmap "$wid" 2>/dev/null || true; done
      echo "[LiveAgent] Local window unmapped; Gateway mode remains active."
      break
    fi
    kill -0 "$APP_PID" 2>/dev/null || break
    i=$((i + 1))
    sleep 0.1
  done
fi

wait "$APP_PID"
