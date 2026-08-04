# LiveAgent Docker运行 仅测试Debian 13 
将本仓库 clone 到任意 Linux 服务器目录后，可用 Docker 运行一个低资源、持久化的 Stack-Cairn LiveAgent Agent。
用于无桌面环境的一键部署（并且实现后续更新AppImage）
## 注意
本教程在AI辅助下完成，并且只包含Agent部署，**需要搭配作者的网关WEBUI使用哦！**
作者项目地址：https://github.com/Stack-Cairn/LiveAgent

容器内部通过 Xvfb 虚拟显示器运行 LiveAgent；不需要宿主机安装 XFCE、xrdp 或图形桌面。

## 当前目录结构

```text
当前 clone 目录/
├── docker-compose.yml              # 默认隔离模式
├── docker-compose.full-access.yml  # 可选：完整宿主机权限（高风险）
├── Dockerfile                      # 运行时镜像定义
├── entrypoint.sh                   # 自动更新 AppImage、启动 Xvfb 与 LiveAgent
├── .env.example                    # 环境变量模板
├── .env                            # 私密配置；由 .gitignore 排除
├── README.md
├── data/                           # 配置、Provider、历史、Memory、Skills；由 .gitignore 排除
├── appimage/                       # 自动下载的 AppImage 和 version；由 .gitignore 排除
└── workspace/                      # Agent 默认唯一可写的宿主机工作目录；由 .gitignore 排除
```

`data/`、`appimage/`、`workspace/` 都是当前 clone 目录下的 bind mount，不是隐藏的 Docker named volume。因此可直接查看、备份或整体迁移当前目录。

默认结构：

```text
Docker 容器
├─ Debian 13 + Xvfb + WebKitGTK
├─ /opt/liveagent       ← 当前目录 ./appimage/
├─ ~/.liveagent         ← 当前目录 ./data/
└─ /workspace           ← 当前目录 ./workspace/
```

> Compose 未固定 `name`、`container_name` 和 volume name。不同 clone 目录会自动形成独立 Compose 项目与容器；同时每个目录的 `data/`、`appimage/`、`workspace/` 也天然独立。

## 前置要求

- Linux x86_64；
- Docker Engine 与 Docker Compose；
- Docker 开机启动：

```bash
sudo systemctl enable --now docker containerd
```

- 容器可访问 `api.github.com` 与 `github.com`；
- 如需远程管理，容器还应能访问 Gateway 的 HTTPS/WSS 域名。

## 首次部署

### 1. 创建运行目录与权限

```bash
git clone https://github.com/HCARX/Docker-LiveAgent /www/wwwroot/AI
```

```bash
cd /www/wwwroot/AI
mkdir -p data appimage workspace

# 容器内 Agent 使用 UID/GID 1000（liveagent）。
# 这三项必须可被 UID 1000 写入，否则会出现配置数据库、AppImage 下载或工作区权限错误。
chown -R 1000:1000 data appimage workspace
chmod 700 data appimage workspace

cp .env.example .env
chmod 600 .env
```

> 如使用 root 执行 Docker，仍应保留上述 `1000:1000` 权限，因为容器内程序默认以非 root 的 `liveagent` 用户运行。

### 2. 配置 Gateway（可选）

生成新 Agent UUID：

```bash
echo "agent-$(cat /proc/sys/kernel/random/uuid)"
```

在 Gateway 中注册这个 UUID，并签发**绑定此 UUID**的 Agent 专属 Token：

```text
agt_...
```

编辑 `.env`：

```bash
nano .env
```

示例：

```ini
LIVEAGENT_GATEWAY_URL=https://your-gateway.example.com
LIVEAGENT_AGENT_ID=agent-你的UUID
LIVEAGENT_AGENT_TOKEN=agt_绑定该UUID的专属令牌

MEMORY_LIMIT=1500m
CPU_LIMIT=1.5
```

若暂时不接 Gateway，将前三项留空；Agent 仍会在容器中运行，但不会出现在 Gateway WebUI 中。

| 变量 | 含义 |
|---|---|
| `LIVEAGENT_GATEWAY_URL` | Gateway HTTPS 地址 |
| `LIVEAGENT_AGENT_ID` | 当前实例唯一的 `agent-...` UUID |
| `LIVEAGENT_AGENT_TOKEN` | 绑定此 UUID 的 `agt_...` 专属 Token |
| `MEMORY_LIMIT` | 单实例内存限制，建议 1500m，不建议低于 800m |
| `CPU_LIMIT` | 单实例 CPU 核数限制 |

> WebUI 登录使用 Gateway **共享管理 Token**；Agent 容器连接 Gateway 使用绑定 UUID 的 **`agt_...` 专属 Token**。两者不能混用。

### 3. 构建与启动

```bash
docker compose up -d --build
```

首次启动会：

```text
构建 Debian + GTK/WebKit/Xvfb 镜像
→ 使用当前目录的 data/、appimage/、workspace/
→ 查询 Stack-Cairn/LiveAgent 官方 Latest Release
→ 下载最新 Linux x86_64 AppImage 到 ./appimage/
→ 启动 Xvfb 和 LiveAgent
→ 若 .env 三项齐全，自动连接 Gateway
```

查看状态和日志：

```bash
docker compose ps
docker compose logs -f liveagent
```

## 日常操作

### 查看状态、日志与资源

```bash
docker compose ps
docker compose logs --tail=200 liveagent
docker stats
```

### 停止和恢复（保留全部数据）

```bash
docker compose stop
docker compose start
```

### 重启并检查官方新版 AppImage

```bash
docker compose restart
```

每次容器启动均查询 GitHub latest release。只有发现版本变化时才下载新版，下载文件与 `version` 标记均可直接在当前目录查看：

```bash
ls -lh appimage/
cat appimage/version
```

### 删除容器再重建（保留所有配置和文件）

```bash
docker compose rm -sf liveagent
docker compose up -d
```

因为运行数据都在当前目录的 `data/`、`appimage/`、`workspace/`，删除容器不会丢失它们。

## 自动启动与稳定性

`docker-compose.yml` 使用：

```yaml
restart: always
```

Docker 服务启用后，服务器重启、Docker 重启、LiveAgent 异常退出后，容器都会自动恢复。Gateway 或网络晚于容器恢复时，Agent 的自动重连会持续尝试上线。

## 更新、备份和迁移

### 更新 AppImage

官方发新版本后只需：

```bash
docker compose restart
```

脚本会自动查询最新版本并下载。无需手动替换 AppImage，也无需重建基础镜像。

### 备份

仅备份 Agent 配置与历史：

```bash
tar czf liveagent-data-$(date +%F).tar.gz data/
```

备份完整实例（配置、缓存 AppImage、工作文件）：

```bash
tar czf liveagent-backup-$(date +%F).tar.gz data/ appimage/ workspace/ .env
```

备份中可能含有 API Key、对话记录和 Token，请妥善加密保存。

### 迁移到另一台服务器

停止旧实例后，复制当前 clone 目录（包括隐藏的 `.env`）到新服务器，确保 Docker 已安装，然后执行：

```bash
chown -R 1000:1000 data appimage workspace
chmod 700 data appimage workspace
chmod 600 .env
docker compose up -d --build
```

### 危险：彻底重置

```bash
docker compose down
rm -rf data appimage workspace
```

这会删除 Agent 的 Provider/API Key、聊天记录、Memory、Skills、Remote 配置、下载的 AppImage 和工作文件。执行前请先备份。

## 运行多个 Agent

将仓库 clone 到不同目录，每个目录使用独立的 `.env`、`data/`、`appimage/` 与 `workspace/`：

```bash
git clone <仓库地址> /opt/liveagent-1
git clone <仓库地址> /opt/liveagent-2

cd /opt/liveagent-1
mkdir -p data appimage workspace
chown -R 1000:1000 data appimage workspace
cp .env.example .env
# 填 Agent 1 的 UUID / agt_ Token
docker compose up -d --build

cd /opt/liveagent-2
mkdir -p data appimage workspace
chown -R 1000:1000 data appimage workspace
cp .env.example .env
# 填 Agent 2 的 UUID / agt_ Token
docker compose up -d --build
```

两个 Agent 必须使用不同的 UUID 和不同的 `agt_` 专属 Token。无需修改 YAML；容器内都可使用 `DISPLAY=:99`，因为容器之间隔离，不会冲突。

## 默认隔离权限

默认配置为：

```text
容器内非 root 用户 liveagent（UID 1000）
无 Linux capabilities
no-new-privileges
无 Docker Socket
无宿主机系统目录挂载
仅当前目录 ./workspace 可写
```

不要在基础配置中添加：

```text
privileged: true
/var/run/docker.sock
/:/host
/root
/etc
~/.ssh
```

## 完整宿主机访问模式（极高风险）

仓库提供 `docker-compose.full-access.yml`。需要明确授予完整服务器运维能力时，执行：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.full-access.yml \
  up -d --build
```

它会授予：

```text
/host                 → 宿主机根目录读写
/var/run/docker.sock  → 宿主机全部 Docker 管理权限
pid: host             → 查看宿主机进程
network_mode: host    → 直接使用宿主机网络
privileged: true      → 高权限设备和 Linux capabilities
```

容器中操作真实服务器文件请使用 `/host/...`：

```bash
ls -la /host/www
cat /host/etc/os-release
```

`/:/host` 是 bind mount，只呈现同一份宿主机文件，**不会复制文件或使磁盘空间翻倍**。

此模式几乎等同于将 root 级服务器权限交给 Agent；只有在你信任模型、Skills/MCP、外部输入与 Gateway 访问控制时才使用。

### 切回默认隔离模式

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.full-access.yml \
  down

docker compose up -d
```

这不会删除当前目录的 `data/`、`appimage/` 或 `workspace/`。

## 故障排查

### 容器未启动或持续重启

```bash
docker compose ps
docker compose logs --tail=300 liveagent
```

### `Permission denied` / SQLite 无法写入 / 无法下载 AppImage

在当前目录重新修复容器用户权限：

```bash
chown -R 1000:1000 data appimage workspace
chmod 700 data appimage workspace
```

然后重启：

```bash
docker compose restart
```

### 无法下载最新 AppImage

检查容器是否可访问 GitHub：

```bash
docker compose exec liveagent curl -I https://api.github.com
docker compose exec liveagent curl -I https://github.com
```

### Agent 在 Gateway 显示离线

检查 `.env` 中的 URL、UUID、`agt_` Token 是否全部填写，且 Token 确实绑定对应 UUID：

```bash
docker compose logs --tail=300 liveagent
```

### Gateway WebUI 显示 `1006 clean=false`

这通常是浏览器到 Gateway 的 WebSocket/Nginx 代理问题，不一定是容器 Agent 的问题。Gateway 前的 Nginx 通常需透传：

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

## 安全提醒

- `.env`、`data/`、`appimage/`、`workspace/` 已由 `.gitignore` 排除，不要手动提交到 Git；
- 不要把 Gateway 共享管理 Token 填给 Agent；
- 高权限模式下，对 `/host/...` 的删除和改动会直接作用于真实服务器；
- 不要无意执行彻底重置命令；更新前建议备份。
