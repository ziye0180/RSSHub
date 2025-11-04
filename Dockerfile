FROM node:22-bookworm AS dep-builder
# 这里我们使用非精简镜像来提供构建时依赖（编译器和 python），因此无需稍后安装。
# 这有效加快了基于 qemu 的交叉构建。

WORKDIR /app

# 在需要 ARG 的 RUN 语句之前放置 ARG 声明以避免缓存失效
ARG USE_CHINA_NPM_REGISTRY=0
RUN \
    set -ex && \
    corepack enable pnpm && \
    if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
        echo 'use npm mirror' && \
        npm config set registry https://registry.npmmirror.com && \
        yarn config set registry https://registry.npmmirror.com && \
        pnpm config set registry https://registry.npmmirror.com ; \
    fi;

COPY ./tsconfig.json /app/
COPY ./pnpm-lock.yaml /app/
COPY ./package.json /app/

# 延迟安装 Chromium 以避免缓存失效，仅安装生产依赖以最小化镜像大小
RUN \
    set -ex && \
    export PUPPETEER_SKIP_DOWNLOAD=true && \
    pnpm install --frozen-lockfile && \
    pnpm rb

# ---------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS dep-version-parser
# 此阶段用于限制缓存失效的范围。
# 有了这个阶段，只要版本不变，package.json 的任何修改都不会破坏后续两个阶段的构建缓存。
# node:22-bookworm-slim 基于 debian:bookworm-slim，因此这个阶段不会导致额外的下载。

WORKDIR /ver
COPY ./package.json /app/
RUN \
    set -ex && \
    grep -Po '(?<="rebrowser-puppeteer": ")[^\s"]*(?=")' /app/package.json | tee /ver/.puppeteer_version && \
    grep -Po '(?<="@vercel/nft": ")[^\s"]*(?=")' /app/package.json | tee /ver/.nft_version && \
    grep -Po '(?<="fs-extra": ")[^\s"]*(?=")' /app/package.json | tee /ver/.fs_extra_version

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS docker-minifier
# 此阶段用于通过删除未使用的文件来进一步减小镜像大小。

WORKDIR /minifier
COPY --from=dep-version-parser /ver/* /minifier/

ARG USE_CHINA_NPM_REGISTRY=0
RUN \
    set -ex && \
    if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
        npm config set registry https://registry.npmmirror.com && \
        yarn config set registry https://registry.npmmirror.com && \
        pnpm config set registry https://registry.npmmirror.com ; \
    fi; \
    npm install -g corepack@latest && \
    corepack enable pnpm && \
    pnpm add @vercel/nft@$(cat .nft_version) fs-extra@$(cat .fs_extra_version) --save-prod

COPY . /app
COPY --from=dep-builder /app /app

WORKDIR /app
RUN \
    set -ex && \
    pnpm build && \
    rm -rf /app/lib && \
    cp /app/scripts/docker/minify-docker.js /minifier/ && \
    export PROJECT_ROOT=/app && \
    node /minifier/minify-docker.js && \
    rm -rf /app/node_modules /app/scripts && \
    mv /app/app-minimal/node_modules /app/ && \
    rm -rf /app/app-minimal && \
    ls -la /app && \
    du -hd1 /app

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS chromium-downloader
# 此阶段用于提高构建并发性并最小化镜像大小。
# 是的，下载 Chromium 从不需要下面的那些依赖。

WORKDIR /app
COPY ./.puppeteerrc.cjs /app/
COPY --from=dep-version-parser /ver/.puppeteer_version /app/.puppeteer_version

ARG TARGETPLATFORM
ARG USE_CHINA_NPM_REGISTRY=0
ARG PUPPETEER_SKIP_DOWNLOAD=1
# 官方推荐在 x86(_64) 上使用 Puppeteer 的方式是使用 Puppeteer 捆绑的 Chromium：
# https://pptr.dev/faq#q-why-doesnt-puppeteer-vxxx-workwith-chromium-vyyy
RUN \
    set -ex ; \
    if [ "$PUPPETEER_SKIP_DOWNLOAD" = 0 ] && [ "$TARGETPLATFORM" = 'linux/amd64' ]; then \
        if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
            npm config set registry https://registry.npmmirror.com && \
            yarn config set registry https://registry.npmmirror.com && \
            pnpm config set registry https://registry.npmmirror.com ; \
        fi; \
        echo 'Downloading Chromium...' && \
        unset PUPPETEER_SKIP_DOWNLOAD && \
        corepack enable pnpm && \
        pnpm --allow-build=rebrowser-puppeteer add rebrowser-puppeteer@$(cat /app/.puppeteer_version) --save-prod && \
        pnpm rb && \
        pnpx rebrowser-puppeteer browsers install chrome ; \
    else \
        mkdir -p /app/node_modules/.cache/puppeteer ; \
    fi;

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS app

LABEL org.opencontainers.image.authors="https://github.com/DIYgod/RSSHub"

ENV NODE_ENV=production
ENV TZ=Asia/Shanghai

WORKDIR /app

# 首先安装依赖以避免缓存失效或干扰 buildkit 并发构建
ARG TARGETPLATFORM
ARG PUPPETEER_SKIP_DOWNLOAD=1
# https://pptr.dev/troubleshooting#chrome-headless-doesnt-launch-on-unix
# https://github.com/puppeteer/puppeteer/issues/7822
# https://www.debian.org/releases/bookworm/amd64/release-notes/ch-information.en.html#noteworthy-obsolete-packages
# 官方推荐在 arm/arm64 上使用 Puppeteer 的方式是从发行版仓库安装 Chromium：
# https://github.com/puppeteer/puppeteer/blob/07391bbf5feaf85c191e1aa8aa78138dce84008d/packages/puppeteer-core/src/node/BrowserFetcher.ts#L128-L131
RUN \
    set -ex && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        dumb-init git curl \
    ; \
    if [ "$PUPPETEER_SKIP_DOWNLOAD" = 0 ]; then \
        if [ "$TARGETPLATFORM" = 'linux/amd64' ]; then \
            apt-get install -yq --no-install-recommends \
                ca-certificates fonts-liberation wget xdg-utils \
                libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libdrm2 \
                libexpat1 libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
                libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
            ; \
        else \
            apt-get install -yq --no-install-recommends \
                chromium \
            && \
            echo "CHROMIUM_EXECUTABLE_PATH=$(which chromium)" | tee /app/.env ; \
        fi; \
    fi; \
    rm -rf /var/lib/apt/lists/*

COPY --from=chromium-downloader /app/node_modules/.cache/puppeteer /app/node_modules/.cache/puppeteer

RUN \
    set -ex && \
    if [ "$PUPPETEER_SKIP_DOWNLOAD" = 0 ] && [ "$TARGETPLATFORM" = 'linux/amd64' ]; then \
        echo '正在验证 Chromium 安装...' && \
        if ldd $(find /app/node_modules/.cache/puppeteer/ -name chrome -type f) | grep "not found"; then \
            echo "!!! Chromium 有未满足的共享库依赖 !!!" && \
            exit 1 ; \
        else \
            echo "太棒了！所有共享库依赖都已满足！" ; \
        fi; \
    fi;

COPY --from=docker-minifier /app /app

EXPOSE 1200
ENTRYPOINT ["dumb-init", "--"]

CMD ["npm", "run", "start"]

# ---------------------------------------------------------------------------------------------------------------------

# 如果 Chromium 有未满足的共享库依赖，这里有一些魔法可以找到并安装它们所属的包：
# 在大多数情况下，你只需在 `grep ^lib` 处停止，然后将这些包添加到上面的阶段。
#
# set -ex && \
# apt-get update && \
# apt install -yq --no-install-recommends \
#     apt-file \
# && \
# apt-file update && \
# ldd $(find /app/node_modules/.cache/puppeteer/ -name chrome -type f) | grep -Po "\S+(?= => not found)" | \
# sed 's/\./\\./g' | awk '{print $1"$"}' | apt-file search -xlf - | grep ^lib | \
# xargs -d '\n' -- \
#     apt-get install -yq --no-install-recommends \
# && \
# apt purge -yq --auto-remove \
#     apt-file \
# rm -rf /tmp/.chromium_path /var/lib/apt/lists/*

# !!! 如果你手动构建 Docker 镜像但禁用了 buildx/BuildKit，请自行设置 TARGETPLATFORM !!!
