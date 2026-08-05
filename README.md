# Docker LiveAgent（无桌面服务器 / Gateway 模式）

在 Linux 服务器上通过 Docker 运行 [Stack-Cairn/LiveAgent](https://github.com/Stack-Cairn/LiveAgent) Agent，并从远程 Gateway WebUI 使用。

本项目适用于**不需要在服务器本地查看图形界面**的场景：容器仍使用 WebKitGTK 和 Xvfb 启动官方 LiveAgent AppImage，但会在启动后取消映射本地窗口，使 WebKit 进入后台节流状态，从而显著降低空闲 CPU 和内存占用。

> 本项目不是 LiveAgent 官方仓库，仅提供第三方 Docker 部署方案。目前官方桌面端的 Agent 运行时仍依赖 WebView JavaScript，因此不能彻底删除 WebKit；本项目实现的是“保留运行时、隐藏本地窗口、通过 Gateway 操作”的轻量化方案。

## 主要特性

- Debian 13 + Xvfb + WebKitGTK，无需安装 XFCE、xrdp 或宿主机桌面；
- 启动后自动取消映射本地 LiveAgent 窗口，仅通过 Gateway 使用；
- 禁用无显示环境中不必要的 WebKit 合成、DMA-BUF 渲染和 GTK 辅助功能；
- 默认限制每个实例使用 `0.75 CPU / 1 GiB RAM`；
- 内置健康检查、日志轮转和优雅停止；
- 自动下载官方 Linux x86_64 AppImage，支持固定版本或跟随 latest；
- 配置、历史、Skills、WebKit UI 状态、AppImage 和工作区使用宿主机目录持久化；
- 默认以非 root 用户运行，不挂载 Docker Socket 或宿主机系统目录；
- 将仓库复制或 clone 到不同目录即可运行多个相互隔离的 Agent。

## 优化效果参考

以下数据来自一台 6 核 Linux 服务器上两个空闲 Agent 实例的实测，实际占用会随版本、模型请求和任务负载变化：

| 状态 | 单实例 WebKit CPU | 单实例内存 |
|---|---:|---:|
| 优化前（窗口持续映射） | 约 130% | 约 470–600 MiB |
| 优化后（窗口取消映射） | 通常约 1–4% | 约 285–305 MiB |

任务执行期间 CPU 和内存会临时升高，Compose 中的资源限制会防止单实例长期占满服务器。

## 目录结构

```text
Docker-LiveAgent/
├── docker-compose.yml              # 默认安全、无桌面 Gateway 模式
├── docker-compose.full-access.yml  # 可选：完整宿主机权限（极高风险）
├── Dockerfile                      # Debian、WebKitGTK、Xvfb 运行环境
├── entrypoint.sh                   # AppImage 下载、Gateway 配置和窗口隐藏
├── .env.example                    # 环境变量示例
├── .env                            # 私密配置，不应提交 Git
├── data/                           # 配置、Provider、历史、Memory、Skills
├── webview-data/                   # WebKit localStorage（Skills 启用状态等）
├── appimage/                       # AppImage 与版本标记
└── workspace/                      # 默认唯一可读写的宿主机工作目录
```

容器内挂载关系：

```text
./data/         → /home/liveagent/.liveagent
./webview-data/ → /home/liveagent/.local/share/com.xiaofei.liveagent
./appimage/     → /opt/liveagent
./workspace/    → /workspace
```

删除或重建容器不会删除上述目录中的数据。

## 系统要求

- Linux x86_64；
- Docker Engine；
- Docker Compose v2（`docker compose`）；
- 容器能够访问 `api.github.com`、`github.com` 和你的 Gateway HTTPS/WSS 地址。

建议启用 Docker 开机启动：

```bash
sudo systemctl enable --now docker containerd
```

## 快速部署

### 1. Clone 仓库并创建持久化目录

```bash
git clone https://github.com/HCARX/Docker-LiveAgent.git /opt/liveagent
cd /opt/liveagent

mkdir -p data webview-data appimage workspace
sudo chown -R 1000:1000 data webview-data appimage workspace
chmod 700 data webview-data appimage workspace

cp .env.example .env
chmod 600 .env
```

容器内 LiveAgent 默认使用 UID/GID `1000`。若目录不可写，可能出现 SQLite 无法打开、AppImage 无法下载或工作区权限错误。

### 2. 配置 Gateway

先按照 LiveAgent 官方文档部署 Gateway：

- [LiveAgent 官方仓库](https://github.com/Stack-Cairn/LiveAgent)
- [远程 Gateway 部署说明](https://github.com/Stack-Cairn/LiveAgent/blob/main/README.zh-CN.md#需要远程访问-部署-gateway)

生成当前 Agent 的唯一 UUID：

```bash
echo "agent-$(cat /proc/sys/kernel/random/uuid)"
```

在 Gateway 的多客户端管理中注册该 UUID，并签发与其绑定的 `agt_...` Agent Token。然后编辑 `.env`：

```ini
LIVEAGENT_GATEWAY_URL=https://your-gateway.example.com
LIVEAGENT_AGENT_ID=agent-REPLACE-WITH-YOUR-UUID
LIVEAGENT_AGENT_TOKEN=agt_REPLACE-WITH-TOKEN-BOUND-TO-THE-UUID

# 资源限制
MEMORY_LIMIT=1024m
MEMORY_RESERVATION=512m
CPU_LIMIT=0.75

# 建议生产环境固定经过验证的版本；留空表示每次启动查询 latest
LIVEAGENT_VERSION=v1.2.3

# 虚拟显示参数，一般无需修改
XVFB_SCREEN=1200x720x16
```

| 变量 | 默认值 | 说明 |
|---|---|---|
| `LIVEAGENT_GATEWAY_URL` | 空 | Gateway HTTPS 地址，不要以 `/` 结尾 |
| `LIVEAGENT_AGENT_ID` | 空 | 当前实例唯一的 `agent-...` UUID |
| `LIVEAGENT_AGENT_TOKEN` | 空 | 与该 UUID 绑定的 `agt_...` Token |
| `MEMORY_LIMIT` | `1024m` | 容器内存硬限制 |
| `MEMORY_RESERVATION` | `512m` | 容器内存软预留 |
| `CPU_LIMIT` | `0.75` | 容器可用 CPU 核数 |
| `LIVEAGENT_VERSION` | `v1.2.3` | 固定官方 Release；设为空则跟随 latest |
| `XVFB_SCREEN` | `1200x720x16` | Xvfb 虚拟屏幕尺寸与色深 |

> WebUI 登录使用 Gateway 的共享管理 Token；Agent 连接 Gateway 使用绑定 UUID 的 `agt_...` 专属 Token，两者不能混用。

### 3. 构建并启动

```bash
docker compose up -d --build
```

查看状态：

```bash
docker compose ps
docker compose logs --tail=100 liveagent
```

正常启动日志应包含类似内容：

```text
[LiveAgent] Using cached AppImage: v1.2.3
[LiveAgent] Local window unmapped; Gateway mode remains active.
```

约 30 秒后，容器状态应显示 `healthy`。

## 工作原理

启动流程：

```text
读取 .env
→ 获取指定版本或 latest Release 信息
→ 下载/复用官方 Linux x86_64 AppImage
→ 将 Gateway 设置写入持久化 SQLite
→ 启动 Xvfb
→ 启动 LiveAgent AppImage
→ 等待 Tauri 创建本地窗口
→ 使用 xdotool 取消窗口映射
→ 保留 WebView JavaScript 与 Gateway WebSocket 运行
```

关键优化环境变量：

```text
WEBKIT_DISABLE_COMPOSITING_MODE=1
WEBKIT_DISABLE_DMABUF_RENDERER=1
GTK_A11Y=none
NO_AT_BRIDGE=1
GDK_BACKEND=x11
```

窗口隐藏后，WebKit 会降低动画、重绘和部分计时器开销；LiveAgent Rust 侧仍会维持 Gateway 状态心跳和连接。

## 日常管理

### 查看状态、日志和资源

```bash
docker compose ps
docker compose logs --tail=200 liveagent
docker stats
```

### 停止、启动和重启

```bash
docker compose stop
docker compose start
docker compose restart
```

配置使用 `restart: unless-stopped`：异常退出、Docker 重启或服务器重启后会自动恢复，但被管理员明确停止的容器不会在 Docker 重启后自行启动。

### 重建容器但保留数据

```bash
docker compose up -d --build --force-recreate
```

### 删除容器但保留数据

```bash
docker compose down
docker compose up -d --build
```

只要不删除 `data/`、`webview-data/`、`appimage/` 和 `workspace/`，配置、历史及 Skills 启用状态就不会丢失。

### 从旧版部署升级：保留 Skills 启用状态

旧版 Compose 只挂载了 `~/.liveagent`，但 LiveAgent 会将 Skills 总开关、已选择的 Skills、当前模型、主题和部分 UI 设置保存在 WebKit localStorage：

```text
/home/liveagent/.local/share/com.xiaofei.liveagent
```

这个目录不在 `data/` 内。旧版部署执行 `docker compose up -d --build --force-recreate` 时，旧容器被删除，未挂载的 localStorage 也会随之删除，因此已安装的 Skill 文件仍然存在，但启用状态会恢复默认。

首次升级到包含 `webview-data` 挂载的新版本前，建议停止容器并迁移现有 WebKit 数据：

```bash
cd /path/to/liveagent
docker compose stop liveagent
mkdir -p webview-data
docker cp "$(docker compose ps -aq liveagent)":/home/liveagent/.local/share/com.xiaofei.liveagent/. ./webview-data/
sudo chown -R 1000:1000 webview-data
chmod 700 webview-data
docker compose up -d --build --force-recreate
```

如果旧容器已经被删除，则无法从旧容器恢复该 localStorage；直接创建目录并启动，然后在 WebUI 中重新启用一次 Skills 即可：

```bash
mkdir -p webview-data
sudo chown -R 1000:1000 webview-data
chmod 700 webview-data
docker compose up -d --build --force-recreate
```

此后重建容器会继续使用 `webview-data/` 中的 Skills 和 UI 状态。

## 版本更新策略

### 固定版本（推荐生产环境）

在 `.env` 中设置：

```ini
LIVEAGENT_VERSION=v1.2.3
```

修改版本号后执行：

```bash
docker compose up -d --build --force-recreate
```

入口脚本会下载相应官方 Release 的 AppImage。

### 自动跟随 latest

将 `.env` 中该项留空：

```ini
LIVEAGENT_VERSION=
```

此后每次容器启动都会检查官方 latest；仅版本变化时重新下载：

```bash
docker compose restart
```

> 自动跟随 latest 可能引入未经验证的版本变化。生产服务器更建议先测试，再手动更新固定版本号。

## 健康检查与日志

Compose 每 30 秒检查：

- `liveagent` 主进程存在；
- `WebKitWebProcess` 存在。

查看健康状态：

```bash
docker inspect --format '{{.State.Health.Status}}' "$(docker compose ps -q liveagent)"
```

Docker JSON 日志默认轮转：

```text
单文件最大 10 MiB
最多保留 3 个文件
```

容器停止时提供 30 秒优雅退出时间，以降低 SQLite 状态未写完的风险。

## 备份与迁移

### 仅备份配置和历史

```bash
tar -czf liveagent-data-$(date +%F).tar.gz data/
```

### 备份完整实例

```bash
tar -czf liveagent-backup-$(date +%F).tar.gz \
  data/ webview-data/ appimage/ workspace/ .env
```

备份中可能包含 API Key、Gateway Token、聊天记录和工作文件，请加密保存，不要上传至公开仓库。

### 迁移

在旧服务器停止实例，将仓库目录连同 `.env`、`data/`、`webview-data/`、`appimage/` 和 `workspace/` 复制到新服务器，然后执行：

```bash
cd /path/to/liveagent
sudo chown -R 1000:1000 data webview-data appimage workspace
chmod 700 data webview-data appimage workspace
chmod 600 .env
docker compose up -d --build
```

## 运行多个 Agent

为每个实例使用独立目录、UUID 和 Token：

```bash
git clone https://github.com/HCARX/Docker-LiveAgent.git /opt/liveagent-1
git clone https://github.com/HCARX/Docker-LiveAgent.git /opt/liveagent-2
```

分别在两个目录中创建 `.env` 和持久化目录，再运行：

```bash
docker compose up -d --build
```

Compose 会根据目录名自动隔离项目和容器。各容器内部都可使用 `DISPLAY=:99`，不会相互冲突。

## 默认安全边界

默认配置包括：

- 非 root 用户 `liveagent`（UID 1000）；
- `cap_drop: ALL`；
- `no-new-privileges:true`；
- 不映射任何入站端口；
- 不挂载 Docker Socket；
- 不挂载 `/root`、`/etc`、`/` 或 `~/.ssh`；
- Agent 默认只能读写当前实例的 `workspace/` 和自身持久化目录。

不要把以下内容加入默认配置：

```text
privileged: true
/var/run/docker.sock
/:/host
/root
/etc
~/.ssh
```

## 完整宿主机访问模式（极高风险）

仓库中的 `docker-compose.full-access.yml` 可让 Agent 获得接近宿主机 root 的权限：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.full-access.yml \
  up -d --build
```

该模式会启用：

```text
/:/host:rw,rshared
/var/run/docker.sock
pid: host
network_mode: host
privileged: true
```

容器中通过 `/host/...` 操作真实服务器文件。此模式可能让模型、MCP、Skill 或恶意提示直接控制整台服务器，除非完全理解风险，否则不要启用。

切回默认隔离模式：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.full-access.yml \
  down

docker compose up -d
```

## 故障排查

### 容器启动失败或持续重启

```bash
docker compose ps
docker compose logs --tail=300 liveagent
```

### SQLite、AppImage 或工作区权限错误

```bash
sudo chown -R 1000:1000 data webview-data appimage workspace
chmod 700 data webview-data appimage workspace
docker compose restart
```

### 无法下载 AppImage

```bash
docker compose exec liveagent curl -I https://api.github.com
docker compose exec liveagent curl -I https://github.com
```

如固定版本不存在，日志会显示 GitHub Release API 返回错误。请检查 `LIVEAGENT_VERSION` 是否与官方标签完全一致。

### Agent 在 Gateway 中离线

确认 `.env` 中三项均填写且 Token 与 UUID 对应：

```bash
docker compose logs --tail=300 liveagent
```

还应确认反向代理正确支持 WebSocket：

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto https;
proxy_read_timeout 300s;
proxy_send_timeout 300s;
proxy_buffering off;
```

### 容器 healthy，但 WebKit CPU 再次持续过高

```bash
docker stats
docker compose top
```

建议依次检查：

1. 是否仍有 `Local window unmapped` 日志；
2. 是否误将 `LIVEAGENT_HEADLESS` 改为 `0`；
3. 当前 AppImage 版本是否发生变化；
4. 临时将 `CPU_LIMIT` 降低后重建；
5. 回退到已验证的 `LIVEAGENT_VERSION`。

### 恢复本地虚拟窗口映射（仅调试）

默认服务器部署无需查看窗口。如需在X11调试，可临时在 Compose 中设置：

```yaml
LIVEAGENT_HEADLESS: "0"
```

然后重建容器。该模式可能显著提高空闲CPU占用，不建议长期启用。

## GitHub 发布前的安全检查

以下内容绝对不能提交到公开仓库：

```text
.env
data/
webview-data/
appimage/
workspace/
*.sqlite
*.sqlite-wal
*.sqlite-shm
```

`.gitignore` 只会忽略**尚未被Git跟踪**的文件。如果旧版本曾经提交过 `.env`，需执行：

```bash
git rm --cached .env
```

这只会取消Git跟踪，不会删除服务器上的 `.env`。提交前务必检查：

```bash
git status
git diff --cached
```

推荐只提交：

```text
README.md
.env.example
.gitignore
Dockerfile
docker-compose.yml
docker-compose.full-access.yml
entrypoint.sh
```

若Token曾经被提交到Git历史或公开页面，应立即在Gateway中吊销并重新签发；仅从最新提交删除并不能消除历史泄露。

## 彻底重置（危险）

```bash
docker compose down
rm -rf data webview-data appimage workspace
```

该操作会删除Provider/API Key、聊天记录、Memory、Skills、Skills 启用状态、其他本地 UI 设置、Remote设置、下载的AppImage和工作文件。执行前请先备份。

## 许可证与致谢

- LiveAgent：<https://github.com/Stack-Cairn/LiveAgent>
- 本仓库仅封装官方发布的Linux AppImage；LiveAgent本体遵循其上游项目许可证。
