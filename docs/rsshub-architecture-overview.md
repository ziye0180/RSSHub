# RSSHub 架构导览

本文面向需要二次开发和自定义路由的开发者，梳理 RSSHub 在运行态与构建态的关键流程，帮助快速定位扩展点。

## 技术栈快照

- **运行框架**：[`Hono`](https://hono.dev/)（`lib/app-bootstrap.tsx`），支持中间件链式扩展。
- **服务入口**：`lib/index.ts` 负责集群模式与 HTTP Server 启动。
- **配置体系**：`lib/config.ts` 解析环境变量并生成统一配置对象，贯穿中间件与路由。
- **路由注册**：`lib/registry.ts` 动态加载 `lib/routes/**` 中的命名空间与路由定义。
- **模板渲染**：`lib/middleware/template.tsx` 将路由返回的通用数据结构渲染为 RSS/Atom/JSON/RSS3。
- **缓存层**：`lib/utils/cache/**` 抽象 Redis/内存缓存，`cache` 中间件负责请求级缓存控制。

## 请求生命周期

```mermaid
graph LR
    subgraph 启动流程
        A[lib/index.ts<br/>入口] --> B[lib/app.ts<br/>加载 request-rewriter]
        B --> C[lib/app-bootstrap.tsx<br/>实例化 Hono]
    end
    C --> M[中间件链<br/>logger → trace → sentry → ... → cache]
    M --> R[lib/registry.ts<br/>动态路由注册]
    R --> H[路由 Handler<br/>lib/routes/<namespace>/*.ts]
    H --> D[(Data 对象)]
    D --> T[template 中间件<br/>规范化数据/渲染]
    T --> O[输出 RSS / Atom / JSON]
    M --> API[/api 子路由<br/>OpenAPIHono]
```

### 中间件栈（执行顺序）

1. `trimTrailingSlash` / `compress`：URL 规范化与响应压缩。
2. 自研中间件（`lib/middleware/*`）：
   - `logger`、`trace`、`sentry`：观测与调试。
   - `access-control`、`header`、`anti-hotlink`：访问控制与头部处理。
   - `parameter`：统一解析 query，补齐默认值。
   - `cache`：基于 `cache.tryGet` 和路由返回数据实现请求缓存与同一路径抖动抑制。
3. `template`：根据返回数据和 `format` 参数渲染最终响应。

### 路由匹配

- `lib/registry.ts` 使用 `directory-import` 扫描 `lib/routes/<namespace>`，加载 `namespace.ts` 与各 `route.ts`/`apiRoute.ts` 文件。
- 每个 `Route` 定义 handler 时返回结构化 `Data`（见 `lib/types.ts`），模板中间件会补齐 `ttl`、`lastBuildDate` 等字段。
- 生产构建使用 `scripts/workflow/build-routes.ts` 预编译路由元数据到 `assets/build/routes.*`，启动时直接加载，避免运行时遍历。

## 插件（路由）结构约定

以 `lib/routes/github` 为例：

- `namespace.ts`：提供命名空间元信息（名称、站点 URL、描述、语言）。
- `*.ts` 路由文件：导出 `route` 常量，包含 `path`、`parameters`、`radar`、`handler` 等。
- `templates/`（可选）：存放自定义 art-template 模板。
- `apiRoute`（可选）：导出 `apiRoute` 供 `/api/<namespace>` 使用，返回原始 JSON。

> **返回结构统一**：`handler` 必须返回符合 `lib/types.ts` 中 `Data`/`DataItem` 的对象，确保模板中间件能够渲染至 RSS/Atom/JSON。

## 缓存与并发控制

- `lib/utils/cache/index.ts` 根据配置选择 Redis 或内存缓存，实现 `globalCache`（请求级别）与 `tryGet`（数据级别）。
- `cache` 中间件通过 `xxhash` 缩短 Key，将同一路径的并发请求串行化：首个请求生成标记，其余请求轮询等待；可避免目标站点被瞬时打爆。
- 路由可通过设置 `ctx.res.headers['Cache-Control'] = 'no-cache'` 来跳过缓存写入。

## 自定义路由开发步骤

1. **命名空间**：在 `lib/routes/<namespace>` 新建目录，补充 `namespace.ts`。
2. **路由定义**：创建 `<name>.ts`，导出 `route: Route`，实现 `handler` 并返回 `Data`。
3. **本地调试**：运行已有服务，访问 `/v2/<namespace>/<path>` 验证；附加 `?format=json` 检查数据结构。
4. **雷达规则**（可选）：在 `route` 的 `radar` 字段中添加 source/target，以便浏览器插件自动生成订阅链接。
5. **构建产物**：若需要部署生产，可执行 `pnpm build:routes`（或等价脚本）生成 `assets/build/routes.*` 静态索引。

## 与自研采集服务的集成建议

- **定义统一 Schema**：在你方服务中定义标准 JSON Schema，对接时让每个 RSSHub 插件返回的 `Data` 先转为内部格式，再推送到消息队列/数据库。
- **解耦拉取与分发**：利用 RSSHub 作为数据抓取器，调度服务通过定时任务或 MCP 调用 `/v2/...` / `/api/...` 接口获取数据，完成去重与推送。
- **敏感源隔离**：对需要鉴权或反爬的来源，可在路由内使用自定义 `ofetch` 配置（代理、UA、Cookie）。建议在插件目录内集中管理此类配置，避免污染全局。

---

以上结构为后续二次开发的基础，可据此梳理新插件、扩展缓存策略或接入额外输出格式。
