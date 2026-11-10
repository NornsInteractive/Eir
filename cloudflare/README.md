# Eir Cloudflare Edge Deployment (Unified Web & Signaling)

本目录提供将 **Eir Flutter Web 前端应用** 与 **全功能 WebSocket WebRTC 信令服务** 统一融合并一键部署至 Cloudflare 的配置与代码。

---

## 架构优势与设计

1. **单端口 / 单域名融合**：
   - 彻底告别以往「Web 运行在 8080、信令单独占 8765」的双端口模式。
   - 静态请求走 Cloudflare Edge 静态缓存，带 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: credentialless` 头，保障 Flutter Web（CanvasKit / Wasm / 多线程）高性能运行。
   - WebSocket 升级请求（`/ws` 或根路径 `Upgrade: websocket`）直接接管，无需独立信令服务器。

2. **Durable Objects 全球一致性**：
   - 采用 Cloudflare **Durable Objects (`SignalingCoordinator`)** 保证即使放映室房主与访客分别身处不同大洲，也能路由至同一个隔离区执行原子化配对、SHA-256 令牌鉴权与 WebRTC SDP/ICE 转发。

3. **零配置自动发现**：
   - Flutter Web 客户端动态匹配当前页面 Origin（HTTPS 环境自动使用 `wss://<host>/ws`，HTTP 开发环境自动使用 `ws://<host>:<port>/ws`），开箱即用。

---

## 部署步骤

### 前置条件
已编译 Flutter Web 生产产物：
```bash
flutter build web --release
```
编译产物位于项目根目录的 `build/web/`。

---

### 方案 A：通过 Cloudflare Workers (推荐，带 Assets 支持)

1. 进入 `cloudflare` 目录：
   ```bash
   cd cloudflare
   ```

2. 首次登录 Cloudflare 账号（如未登录）：
   ```bash
   npx wrangler login
   ```

3. 一键部署：
   ```bash
   npx wrangler deploy
   ```
   Wrangler 将自动上传 `../build/web` 中的静态资源，并绑定 `SignalingCoordinator` Durable Object。

---

### 方案 B：通过 Cloudflare Pages (高级 Worker 模式)

1. 将 `_worker.js` 复制到 Web 产物根目录：
   ```bash
   cp cloudflare/_worker.js build/web/_worker.js
   ```

2. 执行 Pages 部署：
   ```bash
   npx wrangler pages deploy build/web --project-name eir
   ```

3. 在 Cloudflare Dashboard 的 Pages 项目设置中：
   - 导航至 **Settings -> Functions -> Compatibility flags**，添加 `nodejs_compat`。
   - 导航至 **Settings -> Functions -> Durable Object bindings**，添加：
     - Variable name: `ROOMS`
     - Durable Object namespace: 关联至已声明的 `SignalingCoordinator`。

---

### 本地测试与验证

- **原生 Dart 本地单端口全功能测试（推荐日常开发）**：
  ```bash
  dart run server/signaling_server.dart 8080 :: build/web
  ```
  在浏览器中打开 `http://localhost:8080` 即可同时加载 Web 页面并建立 WebSocket 信令连接。

- **使用 Wrangler 本地模拟运行**：
  ```bash
  cd cloudflare
  npx wrangler dev
  ```
