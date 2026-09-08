# Janus - LinuxServer.io Image

基于 [LinuxServer.io](https://linuxserver.io/) 基础镜像构建的 [Janus](https://github.com/bs-community/janus) Docker 镜像——Blessing Skin Server 的外挂 [Yggdrasil Connect](https://github.com/MUAlliance/yggdrasil-connect) 服务端。

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
7. **标准化的配置 / 数据目录**：
   * `/config/.env` — Janus 运行配置（软链到 `/app/.env`），由容器从 `/app/.env.example` 复制并叠加 compose 环境变量生成。
   * `/server-storage/oauth-private.key` — 只读挂载 Blessing Skin Server 的 storage 目录后自动读取的令牌签名密钥。
   * `/data` — 迁移前自动生成的数据库备份目录（`backup-*.sql`）。

## ⚠️ 关于 HTTPS / 反向代理

**本镜像不做任何 HTTPS / 反向代理功能。** 出于安全与兼容性考虑（`ISSUER` 与 `BS_SITE_URL` 必须是 `https://` 地址，`trust proxy` 已启用），你需要自行在 Janus 之前部署一个反向代理（如 Nginx / HAProxy / Cloudflared）并在其上配置 HTTPS 证书，将请求转发到本容器（默认 `3000` 端口）。镜像内不含、也不默认启用任何代理组件。

## 启用 Yggdrasil Connect

Janus 本身只提供 OpenID 服务端；要真正启用 Yggdrasil Connect，还需要在 Blessing Skin Server 中配置 [Yggdrasil Connect 插件](https://github.com/MUAlliance/yggdrasil-connect)。请按以下步骤操作（摘自该插件 README）：

> 说明：第 3、4 步是 Blessing Skin Server（Laravel）的 artisan 命令，需要在 **Blessing Skin 容器** 内执行（容器名 `blessing-skin`）；Janus 容器本身不含 PHP/artisan。

1. **禁用旧版插件**：如果你已安装基于原版 Yggdrasil API 插件修改的旧版插件，请务必在下载新版插件前禁用旧版插件，否则可能出现 `Invalid version string` 错误。
2. **安装插件**：在插件市场安装 Yggdrasil Connect 插件。
3. **创建个人访问客户端**：在 Blessing Skin Server 的容器内执行：
   ```bash
   docker exec -it -w /app blessing-skin-server php artisan yggc:create-personal-access-client
   ```
   创建完成后，在 Blessing Skin Server 的 `.env` 中新增 `PASSPORT_PERSONAL_ACCESS_CLIENT_ID`，将其值设为命令返回的个人访问客户端的 Client ID。
   > Yggdrasil Connect 不会自动写入 OAuth2 的回调 URL，所以这里直接选择 `yes` 。之后去`用户中心/高级功能/OAuth2 应用`自行设置回调 URL。示例：`https://auth.example.com/callback`
4. **（仅当从原版 Yggdrasil API 迁移时）修复 uuid 表**：在 Blessing Skin Server 的容器内执行
   ```bash
   docker exec -it -w /app blessing-skin-server php artisan yggc:fix-uuid-table
   ```
   以清除原版插件 `uuid` 表中可能存在的异常数据并修改表结构。
   > ⚠️ **该命令会直接删除 `uuid` 表中的部分记录，执行前请务必先备份 `uuid` 表！** 若你未安装过原版 Yggdrasil API 而直接安装本插件，则无需执行此命令。
5. **填写 OpenID 提供者标识符**：部署好 Janus 后，在本插件的配置页面填写你的 Janus 实例的 OpenID 提供者标识符（即本文档中的 `ISSUER`）。

> **已知问题**：在部分情况下，用户通过传统 Auth Server 登录可能遇到 HTTP 500，或请求 OAuth 授权时在 scope 正确的情况下仍遇到 `invalid_scopes` 错误。可在插件管理中重启（禁用再启用）该插件，或将 Blessing Skin Server 升级至最新开发版以解决。详见 [bs-community/blessing-skin-server#661](https://github.com/bs-community/blessing-skin-server/pull/661#issuecomment-3008486580)。

## 快速开始

### 前置准备

1. 确认你的 Blessing Skin Server 已安装并配置好 Yggdrasil Connect 插件。
2. **挂载 Blessing Skin 的 storage 目录**：容器启动时会自动从只读挂载点 `/server-storage/oauth-private.key` 读取令牌签名密钥（无需手动复制）。将你 Blessing Skin 的 `./data`（即其 `storage` 内容）目录挂载到 Janus 的 `/server-storage:ro` 即可。

   ```bash
   # 在 docker-compose.yml 的 janus 服务中：
   volumes:
     - ./data:/server-storage:ro     # ./data 是 Blessing Skin 的 storage 目录
   ```

   > 如果该密钥是 PKCS#1 格式（以 `-----BEGIN RSA PRIVATE KEY-----` 开头），容器启动时会自动转换为 PKCS#8。
   > 请**确保密钥是 PKCS#8** 格式（以 `-----BEGIN PRIVATE KEY-----` 开头），否则 Janus 无法启动。若你的 Blessing Skin 密钥不符合，可先用 OpenSSL 转换：
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
    ports:
      - "3000:3000"
    volumes:
      - ./janus-config:/config      # .env（由模板 + 环境变量生成）
      - ./data:/server-storage:ro   # 只读读取 Blessing Skin 的 oauth-private.key
      - ./janus-data:/data          # 迁移前数据库自动备份
    restart: unless-stopped
```

> **重要**：`ISSUER` 与 `BS_SITE_URL` 必须是 `https://` 或 `http://localhost`，**不得以 `/` 结尾**，不得包含 query string 或 fragment，否则 Janus 会因配置校验失败而退出。
>
> **`.env` 的生成规则**：容器启动时若 `/config/.env` 不存在，会从镜像内的 `/app/.env.example` 复制一份；随后用 docker-compose 中设置的环境变量（`DB_*`、`ISSUER`、`BS_SITE_URL`、`TOKEN_*` 等）覆盖 `/config/.env` 中对应项。优先级为：
> **docker-compose 环境变量 > 已存在的 `/config/.env` > `.env.example` 默认值**。

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
  -v ./janus-config:/config \
  -v ./data:/server-storage:ro \
  -v ./janus-data:/data \
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

> 数据库相关变量（`DB_*`）、`ISSUER`、`BS_SITE_URL`、`TOKEN_*` 等会在容器启动时写入 `/config/.env`（由 `.env.example` 复制，并在这些环境变量非空时覆盖对应项）。

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
