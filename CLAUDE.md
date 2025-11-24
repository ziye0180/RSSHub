# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 项目概述

RSSHub 是全球最大的 RSS 网络，拥有 5,000+ 个全球实例，聚合来自各种来源的数百万内容。基于 Node.js 22+ (ESM)、Hono Web 框架和 pnpm 构建。

## 核心命令

### 开发
```bash
pnpm dev                    # 启动开发服务器（热更新，端口 1200）
pnpm test                   # 运行格式检查 + vitest 覆盖率测试
pnpm vitest                 # 仅运行单元测试
pnpm vitest:watch           # 测试监听模式
pnpm format                 # 自动修复代码格式（Prettier + ESLint）
```

### 构建与生产
```bash
pnpm build                  # 构建路由元数据 + tsdown 打包
pnpm start                  # 启动生产服务器（node dist/index.js）
```

### Docker（自定义环境）
```bash
make dev-start              # 启动开发环境（docker/docker-compose.dev.yaml）
make test-start             # 启动测试环境
make prod-start             # 启动生产环境（docker/docker-compose.yaml）
make docker-build           # 构建指定版本镜像
make logs-dev               # 查看开发容器日志
```

## 架构基础

### 应用启动流程

```
lib/index.ts（入口）
  → lib/app-bootstrap.tsx（Hono 应用初始化）
    → 中间件栈（13 个中间件）
    → lib/registry.ts（路由注册）
    → lib/api/（API 路由）
```

### 路由注册机制

**核心文件**：`lib/registry.ts`

**三种基于环境的加载策略**：
- **开发环境**（`NODE_ENV=dev`）：通过 `directory-import` 从 `lib/routes/**/*.ts` 动态导入
- **生产环境**（`NODE_ENV=production`）：从预构建的 `assets/build/routes.js` 加载，handler 懒加载
- **测试环境**（`NODE_ENV=test`）：从 `assets/build/routes.json` 加载元数据

**路由组织结构**：
```
lib/routes/<namespace>/
├── namespace.ts           # 命名空间元数据（名称、URL、分类）
├── <route-file1>.ts      # 导出 route 对象和 handler
└── <route-file2>.ts
```

**路由排序**：字面量路径优先于参数化路径（`:param`），确保精确匹配的优先级。

### 中间件栈（加载顺序）

1. `trimTrailingSlash` - 移除尾部斜杠
2. `compress` - Gzip 压缩
3. `jsxRenderer` - RSS XML 渲染
4. `mLogger` - 请求日志
5. `trace` - OpenTelemetry 追踪
6. `sentry` - 错误监控
7. `accessControl` - ACCESS_KEY 验证
8. `debug` - 调试信息注入
9. `template` - RSS 模板渲染
10. `header` - 响应头设置
11. `anti-hotlink` - 防盗链
12. `parameter` - 查询参数处理（filter/limit/format/mode）
13. `cache` - Redis/内存缓存（带并发保护）

**缓存中间件**（`lib/middleware/cache.ts`）：
- 使用 XXH64 哈希缩短缓存键
- 默认路由缓存 5 分钟，内容缓存 10 分钟
- 防并发请求锁机制
- 格式：`rsshub:koa-redis-cache:<hash>`

### 构建系统

**构建脚本**：`scripts/workflow/build-routes.ts`

**生成文件**：
- `assets/build/routes.json` - 路由元数据（测试用）
- `assets/build/routes.js` - 生产路由（带懒加载导入）
- `assets/build/radar-rules.json` - 浏览器扩展规则
- `assets/build/maintainers.json` - 维护者信息

**生产打包器**：`tsdown`（压缩代码，静态资源复制到 `dist/`）

### 配置系统

**核心文件**：`lib/config.ts`（700+ 行）

**配置来源**：`.env` 文件 → 环境变量 → 默认值

**主要配置项**：
```typescript
{
  cache: { type, routeExpire, contentExpire },
  redis: { url },
  proxy: { protocol, host, port, strategy },
  feature: { filter_regex_engine, disable_nsfw },
  openai: { apiKey, model },
  puppeteerWSEndpoint,
  <namespace>: { access_token, ... }  // 命名空间特定配置
}
```

## 添加新路由

### 步骤 1：创建命名空间（如果是新的）

**文件**：`lib/routes/<namespace>/namespace.ts`

```typescript
import type { Namespace } from '@/types';

export const namespace: Namespace = {
    name: '站点名称',
    url: 'example.com',
    categories: ['blog'],  // 参考其他命名空间中的现有分类
    lang: 'zh-CN'
};
```

### 步骤 2：实现路由

**文件**：`lib/routes/<namespace>/<feature>.ts`

```typescript
import { Route } from '@/types';
import got from '@/utils/got';
import { load } from 'cheerio';
import { parseDate } from '@/utils/parse-date';

export const route: Route = {
    path: '/posts/:category?',
    categories: ['blog'],
    example: '/mysite/posts/tech',
    parameters: {
        category: {
            description: '分类名称',
            options: [
                { value: 'tech', label: '科技' },
                { value: 'life', label: '生活' }
            ]
        }
    },
    features: {
        requireConfig: false,           // 如需环境变量则设为 true
        requirePuppeteer: false,
        antiCrawler: false,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false
    },
    name: '文章',
    maintainers: ['github-username'],
    handler,
    url: 'example.com/posts'
};

async function handler(ctx) {
    const category = ctx.req.param('category') || 'all';
    const url = `https://example.com/posts/${category}`;

    // 1. 获取数据
    const response = await got(url);
    const $ = load(response.data);

    // 2. 解析并生成 items
    const items = $('.post').toArray().map((elem) => ({
        title: $(elem).find('h2').text(),
        link: new URL($(elem).find('a').attr('href'), url).href,  // 转换为绝对 URL
        pubDate: parseDate($(elem).find('.date').text()),         // 必须是 Date 或 UTC 字符串
        description: $(elem).find('.excerpt').html(),
        author: $(elem).find('.author').text()
    }));

    // 3. 返回 Data 对象
    return {
        title: `站点 - ${category}`,
        link: url,
        item: items
    };
}
```

### 步骤 3：测试与验证

```bash
# 开发模式
pnpm dev
# 访问：http://localhost:1200/<namespace>/<path>

# 运行测试
pnpm vitest

# 构建以验证路由注册
pnpm build
cat assets/build/routes.json | jq '.<namespace>'
```

## 关键开发规则

### 路由 Handler 要求

1. **返回 Data 对象**，包含 `title`、`link`、`item` 字段
2. **转换日期**为 `Date` 对象或通过 `parseDate()` 转为 UTC 字符串
3. **使用绝对 URL** - 将相对链接转换为绝对路径
4. **声明必需配置**在 `features.requireConfig` 数组中
5. **优雅处理错误** - 不要有未处理的 Promise rejection

### 常用工具库

**网络请求**：
- `@/utils/got` - 带代理支持的 HTTP 客户端（推荐）
- `@/utils/ofetch` - 备选 fetch 封装

**HTML 解析**：
- `cheerio` - 类 jQuery API（最常用）
- `jsdom` - 完整 DOM 实现

**浏览器自动化**：
- `rebrowser-puppeteer` - 用于 JavaScript 密集型网站
- 生产环境需要 `PUPPETEER_WS_ENDPOINT` 环境变量

**日期解析**：
- `@/utils/parse-date` - 智能多格式解析器

**缓存工具**：
- `cache.tryGet(key, fetchFunc, ttl)` - 自动缓存包装器
- TTL 单位为秒，默认值来自配置

### 路径别名

```typescript
'@/*' → 'lib/*'
```

示例：`import got from '@/utils/got'`

## Docker 架构

**多阶段 Dockerfile**（`docker/Dockerfile`）：
1. `dep-builder` - 安装依赖和构建工具
2. `dep-version-parser` - 解析版本用于缓存
3. `docker-minifier` - 使用 `@vercel/nft` 构建和 tree-shake
4. `chromium-downloader` - 下载 Chromium（条件性）
5. `app` - 最终精简镜像

**服务**（根目录 `docker-compose.yml`）：
- `rsshub` - 主应用
- `browserless` - Puppeteer 远程浏览器
- `redis` - 缓存存储

## 代码质量

**Pre-commit 钩子**（Husky）：
- ESLint + Prettier 自动修复
- TypeScript 类型检查

**测试**：
- `vitest` 用于单元测试
- `vitest routes` 用于路由特定测试
- 覆盖率指标排除 `lib/routes/**`

## 性能优化

1. **路由级缓存** - 默认 5 分钟，Redis 支持
2. **代码分割** - 生产环境动态导入
3. **并发保护** - 防止重复获取
4. **Cluster 模式** - 多核 CPU 利用（通过 `ENABLE_CLUSTER`）

## 常见陷阱

1. 忘记将相对 URL 转换为绝对 URL
2. 没有使用 `parseDate()` 处理日期字符串
3. 遗漏 `features.requireConfig` 声明
4. 没有处理分页（使用 `limit` 参数）
5. 硬编码 URL 而不是使用 `ctx.req.param()`

## 参考文档

- 官方文档：https://docs.rsshub.app
- 贡献指南：https://docs.rsshub.app/joinus/
- 部署指南：https://docs.rsshub.app/deploy/
