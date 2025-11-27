import { Route, ViewType } from '@/types';
import cache from '@/utils/cache';
import parser from '@/utils/rss-parser';
import ofetch from '@/utils/ofetch';
import { load } from 'cheerio';
import { parseDate } from '@/utils/parse-date';
import { config } from '@/config';
import Parser from '@postlight/parser';

export const route: Route = {
    path: '/',
    categories: ['program-update'],
    view: ViewType.Articles,
    example: '/rssproxy?url=https://example.com/feed.xml',
    parameters: {},
    features: {
        requireConfig: false,
        requirePuppeteer: false,
        antiCrawler: false,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
    radar: [],
    name: 'RSS 代理服务',
    maintainers: [],
    handler,
    description: `
通用 RSS 代理服务，支持解析和转发任意 RSS/Atom 订阅源。

### 查询参数

| 参数 | 说明 | 示例 |
|------|------|------|
| \`url\` | RSS 订阅源地址（必需） | \`https://example.com/feed.xml\` |
| \`fulltext\` | 是否抓取全文内容 | \`true\` / \`false\`（默认） |
| \`ttl\` | 缓存时间（秒） | \`3600\`（默认 300） |

### 使用示例

\`\`\`
# 基础代理
/rssproxy?url=https://example.com/feed.xml

# 输出 JSON 格式
/rssproxy?url=https://example.com/feed.xml&format=json

# 全文抓取
/rssproxy?url=https://example.com/feed.xml&fulltext=true

# 限制条数 + 过滤
/rssproxy?url=https://example.com/feed.xml&limit=10&filter=keyword

# 自定义缓存时间
/rssproxy?url=https://example.com/feed.xml&ttl=3600

# 组合使用
/rssproxy?url=https://example.com/feed.xml&format=json&fulltext=true&limit=20
\`\`\`

### 安全说明

为防止 SSRF 攻击，默认禁止访问以下域名：
- 本地地址：localhost, 127.0.0.1
- 内网地址：192.168.*, 10.*, 172.16.*~172.31.*
- 可通过环境变量 \`RSSPROXY_BLOCKED_DOMAINS\` 自定义黑名单
    `,
};

async function handler(ctx) {
    // 获取查询参数
    const feedUrl = ctx.req.query('url');
    const fulltext = ctx.req.query('fulltext') === 'true';
    const ttl = Number(ctx.req.query('ttl')) || config.rssproxy?.defaultTtl || 300;

    // 参数验证
    if (!feedUrl) {
        throw new Error('缺少必需参数: url');
    }

    // URL 格式验证
    let urlObj: URL;
    try {
        urlObj = new URL(feedUrl);
    } catch {
        throw new Error('无效的 URL 格式');
    }

    // 安全检查：域名黑名单
    const blockedDomains = config.rssproxy?.blockedDomains || [
        'localhost',
        '127.0.0.1',
        '0.0.0.0',
        // IPv4 内网地址范围
        // 将在下面的函数中检查
    ];

    const isBlockedDomain = (hostname: string): boolean => {
        // 完全匹配检查
        if (blockedDomains.includes(hostname)) {
            return true;
        }

        // IPv4 内网地址检查
        const ipv4Regex = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
        const match = hostname.match(ipv4Regex);
        if (match) {
            const [, a, b] = match.map(Number);
            // 10.0.0.0/8
            if (a === 10) {
                return true;
            }
            // 172.16.0.0/12
            if (a === 172 && b >= 16 && b <= 31) {
                return true;
            }
            // 192.168.0.0/16
            if (a === 192 && b === 168) {
                return true;
            }
            // 127.0.0.0/8 (loopback)
            if (a === 127) {
                return true;
            }
        }

        // 通配符匹配（如 192.168.*）
        for (const blocked of blockedDomains) {
            if (blocked.includes('*')) {
                const regex = new RegExp(`^${blocked.replaceAll('.', String.raw`\.`).replaceAll('*', '.*')}$`);
                if (regex.test(hostname)) {
                    return true;
                }
            }
        }

        return false;
    };

    if (isBlockedDomain(urlObj.hostname)) {
        throw new Error(`域名 ${urlObj.hostname} 被禁止访问`);
    }

    // 使用缓存包装整个解析过程
    const feedData = await cache.tryGet(
        `rssproxy:${feedUrl}:${fulltext}`,
        async () => {
            // 解析 RSS
            const feed = await parser.parseURL(feedUrl);

            // 转换为标准格式
            let items = feed.items.map((item) => ({
                title: item.title || '',
                link: item.link || '',
                description: item['content:encoded'] || item.content || item.contentSnippet || item.description || '',
                pubDate: item.pubDate ? parseDate(item.pubDate) : undefined,
                author: item.creator || item.author || '',
                category: item.categories || [],
                guid: item.guid || item.link,
            }));

            // 全文抓取
            if (fulltext) {
                items = await Promise.all(
                    items.map((item) =>
                        cache.tryGet(`rssproxy:fulltext:${item.link}`, async () => {
                            if (!item.link) {
                                return item;
                            }

                            try {
                                // 使用 @postlight/parser 提取全文
                                const response = await ofetch(item.link);
                                const $ = load(response);
                                const result = await Parser.parse(item.link, {
                                    html: $.html(),
                                });

                                if (result && result.content && result.content.length > 40) {
                                    item.description = result.content;
                                    if (!item.author && result.author) {
                                        item.author = result.author;
                                    }
                                }
                            } catch {
                                // 全文抓取失败时保留原始 description
                                // 不抛出错误，继续处理其他项目
                            }

                            return item;
                        })
                    )
                );
            }

            return {
                title: feed.title || 'RSS Proxy',
                link: feed.link || feedUrl,
                description: feed.description || '',
                language: feed.language,
                item: items,
            };
        },
        ttl
    );

    return feedData;
}
