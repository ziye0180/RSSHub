# RSSProxy 环境变量配置说明

## 可选配置项

### RSSPROXY_DEFAULT_TTL
- **说明**：默认缓存时间（秒）
- **默认值**：300（5 分钟）
- **示例**：`RSSPROXY_DEFAULT_TTL=3600`

### RSSPROXY_BLOCKED_DOMAINS
- **说明**：禁止访问的域名黑名单，用逗号分隔
- **默认值**：空（内置了本地地址和内网地址的检查）
- **示例**：`RSSPROXY_BLOCKED_DOMAINS=example.com,test.com`

## 内置安全保护

即使不配置黑名单，rssproxy 路由也会自动阻止以下地址：
- `localhost`
- `127.0.0.1` 及所有 127.x.x.x
- `0.0.0.0`
- `10.0.0.0/8` (私有网络)
- `172.16.0.0/12` (私有网络)
- `192.168.0.0/16` (私有网络)

## 配置示例

在 `.env` 文件中添加：

```env
# RSSProxy 配置
RSSPROXY_DEFAULT_TTL=3600
RSSPROXY_BLOCKED_DOMAINS=example.com,internal.company.com
```

## 使用示例

```bash
# 基础代理
curl "http://localhost:1200/rssproxy?url=https://example.com/feed.xml"

# 输出 JSON 格式
curl "http://localhost:1200/rssproxy?url=https://example.com/feed.xml&format=json"

# 全文抓取
curl "http://localhost:1200/rssproxy?url=https://example.com/feed.xml&fulltext=true"

# 自定义缓存时间
curl "http://localhost:1200/rssproxy?url=https://example.com/feed.xml&ttl=7200"

# 限制条数并过滤
curl "http://localhost:1200/rssproxy?url=https://example.com/feed.xml&limit=10&filter=keyword"
```
