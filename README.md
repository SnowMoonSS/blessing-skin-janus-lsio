# Janus - LinuxServer.io Image

基于 [LinuxServer.io](https://linuxserver.io/) 基础镜像构建的 [Janus](https://github.com/bs-community/janus) Docker 镜像——Blessing Skin Server 的外挂 [Yggdrasil Connect](https://github.com/yushijinhun/authlib-injector/issues/268) 服务端。

Janus 是一个独立的 Node.js（NestJS）服务，需要与 [Blessing Skin Server](https://github.com/bs-community/blessing-skin-server) 使用**同一个 MySQL/MariaDB 数据库**，为皮肤站提供基于 OAuth 2.0 / OpenID Connect 的外置登录（Yggdrasil Connect）能力。

本项目将 Janus 的容器化方案迁移到 LinuxServer.io 基础镜像之上，复用 LinuxServer 社区多年打磨的容器最佳实践。

## 关于 Janus

* 代码仓库：[github.com/bs-community/janus](https://github.com/bs-community/janus)
* 部署指南：[Wiki - 部署指南](https://github.com/bs-community/janus/wiki/%E9%83%A8%E7%BD%B2%E6%8C%87%E5%8D%97)
* 前提：你需要一个 Blessing Skin Server ≥ 6，并已安装 [Yggdrasil Connect](https://github.com/bs-community/blessing-skin-plugins/blob/master/plugins/yggdrasil-connect) 插件。

## 本项目提供什么

| | |
| --- | --- |
| 基础镜像 | `ghcr.io/linuxserver/baseimage-debian:trixie` |
| 内置 init 系统 | `s6-overlay` 进程监督 |
| 运行时 | Node.js ≥ 22.12（经 NodeSource apt 仓库安装，默认 Node 24） |
| 应用 | NestJS（`node dist/main`），默认监听 `3000` |
| 数据库 | MySQL / MariaDB（与 Blessing Skin 共享，不支持 SQLite / PostgreSQL） |
| 运行用户 | `abc`（非 root，通过 `PUID`/`PGID` 映射） |

## LinuxServer Base Image 提供的功能

1. **s6-overlay 进程监督系统** — 作为 PID 1，提供僵尸回收、服务依赖管理、优雅终止、自动重启与就绪通知。本仓库的 s6 配置位于：
   * `root/etc/s6-overlay/s6-rc.d/init-janus-config/` — 配置初始化
   * `root/etc/s6-overlay/s6-rc.d/svc-janus/` — Node 服务
2. **PUID / PGID 用户映射** — 通过 `PUID=1000`、`PGID=1000` 指定宿主机用户，容器内应用以该用户身份运行。
3. **TZ 时区环境变量** — 通过 `TZ=Asia/Shanghai` 设定容器时区。
4. **自定义脚本（Custom Scripts）** — 挂载目录到 `/custom-cont-init.d`，放入可执行脚本即可在每次启动时、所有服务启动前执行。
5. **自定义服务（Custom Services）** — 挂载目录到 `/custom-services.d`，放入可执行脚本即可作为独立服务并行运行。
6. **Docker Mods 扩展生态** — 通过 `DOCKER_MODS` 环境变量引用 LinuxServer 社区扩展层。
7. **标准化的 `/config`** — 配置与密钥分离：
   * `/config/.env` — Janus 运行配置（软链到 `/app/.env`）。
   * `/config/oauth-private.key` — 从 Blessing Skin Server 复制的令牌签名密钥。

## ⚠️ 关于 HTTPS / 反向代理

**本镜像不做任何 HTTPS / 反向代理功能。** 出于安全与兼容性考虑（`ISSUER` 与 `BS_SITE_URL` 必须是 `https://` 地址，`trust proxy` 已启用），你需要自行在 Janus 之前部署一个反向代理（如 Nginx / HAProxy / Cloudflared）并在其上配置 HTTPS 证书，将请求转发到本容器（默认 `3000` 端口）。镜像内不含、也不默认启用任何代理组件。

## 快速开始

### 前置准备

1. 确认你的 Blessing Skin Server 已安装并配置好 Yggdrasil Connect 插件。
2. 从你的 Blessing Skin Server 复制签名密钥到本项目的 `./config` 目录：

   ```bash
   mkdir -p config
   cp /path/to/blessing-skin/storage/oauth-private.key config/oauth-private.key
   ```

   > 如果该密钥是 PKCS#1 格式（以 `-----BEGIN RSA PRIVATE KEY-----` 开头），容器启动时会自动转换为 PKCS#8。
   > 请**确保密钥是 PKCS#8** 格式（以 `-----BEGIN PRIVATE KEY-----` 开头），否则 Janus 无法启动。若不是，可先用 OpenSSL 转换：
   >
   > ```bash
   > openssl pkcs8 -topk8 -inform PEM -outform PEM -in oauth-private.key -out oauth-private-pkcs8.key -nocrypt
   > mv oauth-private-pkcs8.key oauth-private.key
   > ```

### Docker Compose

```yaml
services:
  janus:
    image: ghcr.io/snowmoonss/janus:latest
    container_name: janus
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - PORT=3000
      - DB_HOST=mariadb                        # 与 Blessing Skin 共享的数据库地址
      - DB_PORT=3306
      - DB_USERNAME=blessingskin
      - DB_PASSWORD=change-me-db-password
      - DB_NAME=blessingskin
      - ISSUER=https://auth.example.com        # Janus 对外地址（HTTPS）
      - BS_SITE_URL=https://skin.example.com   # 皮肤站地址（HTTPS）
      - SHARED_CLIENT_ID=
      # - DB_PREFIX=bs_                        # 若皮肤站配置了表前缀则打开
      - TOKEN_EXPIRES_IN_1=259200
      - TOKEN_EXPIRES_IN_2=604800
      - DEVICE_CODE_EXPIRES_IN=600
      - GRANT_EXPIRES_IN=25920000
    ports:
      - "3000:3000"
    volumes:
      - ./config:/config       # .env 及 oauth-private.key
    restart: unless-stopped
```

> **重要**：`ISSUER` 与 `BS_SITE_URL` 必须是 `https://` 或 `http://localhost`，**不得以 `/` 结尾**，不得包含 query string 或 fragment，否则 Janus 会因配置校验失败而退出。

### 手动运行

```bash
docker run -d \
  --name janus \
  -p 3000:3000 \
  -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
  -e DB_HOST=mariadb -e DB_PORT=3306 \
  -e DB_USERNAME=blessingskin -e DB_PASSWORD=change-me-db-password -e DB_NAME=blessingskin \
  -e ISSUER=https://auth.example.com \
  -e BS_SITE_URL=https://skin.example.com \
  -v ./config:/config \
  ghcr.io/snowmoonss/janus:latest
```

### 完成安装

启动后，Janus 会在启动时自动执行数据库迁移（创建 `yggc_*` 表）。随后在你的 Blessing Skin Server 的 Yggdrasil Connect 插件配置页面填写你的 Janus `ISSUER`（OpenID 提供者标识符）即可。

## 环境变量

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `PUID` / `PGID` | 宿主机用户 UID/GID | `1000` |
| `TZ` | 容器时区 | 未设置 |
| `PORT` | Janus HTTP 监听端口 | `3000` |
| `DB_HOST` | 数据库地址 | 未设置 |
| `DB_PORT` | 数据库端口 | `3306` |
| `DB_USERNAME` | 数据库用户名 | 未设置 |
| `DB_PASSWORD` | 数据库密码 | 未设置 |
| `DB_NAME` | 数据库名 | 未设置 |
| `DB_PREFIX` | 数据表前缀（同 Blessing Skin 的 `DB_PREFIX`） | 未设置 |
| `ISSUER` | OpenID 提供者标识符（必须 HTTPS、无尾部 `/`） | 未设置 |
| `BS_SITE_URL` | 皮肤站地址（必须 HTTPS、无尾部 `/`） | 未设置 |
| `SHARED_CLIENT_ID` | 公用应用的应用 ID（可留空） | 未设置 |
| `TOKEN_EXPIRES_IN_1` | Access Token / ID Token 过期时间（秒） | `259200` |
| `TOKEN_EXPIRES_IN_2` | Refresh Token 过期时间（秒） | `604800` |
| `DEVICE_CODE_EXPIRES_IN` | 设备代码过期时间（秒） | `600` |
| `GRANT_EXPIRES_IN` | 单次授权过期时间（秒） | `25920000` |
| `JANUS_ENV` | 直接提供完整 `.env` 内容（多行），覆盖默认生成 | 未设置 |

> 数据库相关变量会在容器启动时写入 `/config/.env`；`JANUS_ENV` 会整体写入 `.env`（适用于需要自定义更多配置项的进阶场景）。

## 开发与构建

```bash
docker build -f Dockerfile \
  --build-arg BUILDPLATFORM=linux/amd64 \
  --build-arg JANUS_VERSION=master \
  -t janus:local .
```

### 构建参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `BUILDPLATFORM` | 构建平台 | `linux/amd64` |
| `NODE_MAJOR` | Node.js 主版本（构建与运行时，经 NodeSource `setup_${NODE_MAJOR}.x` 安装） | `24` |
| `JANUS_REPO` | Janus 源码仓库 | `https://github.com/bs-community/janus.git` |
| `JANUS_VERSION` | 版本（git 分支/tag） | `master` |
| `JANUS_SOURCE` | 源码来源（仅支持 `git`） | `git` |

## 许可证

* 本项目 Docker 构建文件与配置：MIT License
* [Janus](https://github.com/bs-community/janus)：MIT License
* [LinuxServer.io](https://linuxserver.io/) 基础镜像：GPL-3.0
* [s6-overlay](https://github.com/just-containers/s6-overlay)：ISC

## 致谢

* [Janus](https://github.com/bs-community/janus) — Yggdrasil Connect 服务端
* [Blessing Skin](https://github.com/bs-community/blessing-skin-server) — 优秀的皮肤托管应用
* [LinuxServer.io](https://linuxserver.io/) — 业界领先的 Docker 基础镜像与运维实践
